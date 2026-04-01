# Field Capability Plugins

This document proposes a refactor of `pollydb` typed storage so complex field types can be added as capability-backed plugins instead of requiring changes across `types.v`, `database.v`, `projector.v`, `markdown_store.v`, and sidecar query code.

The immediate motivation is `markdown_`. What looked like "one more column type" turned out to require:

- inline row encoding via `MarkdownRef`
- external side-store ingest/load
- semantic diff and merge
- derived projector support
- derived secondary indexes
- transaction-time query compensation
- sidecar query and reporting adapters

That is a strong signal that the current abstraction is still centered on scalar columns, while `markdown_` behaves like a structured document field with its own storage and compute lifecycle.

## Problem

Today `ColumnType` mixes three concerns:

- physical inline encoding
- logical value semantics
- derived capabilities such as merge, indexing, and query projection

This works well for scalar fields:

- `string_`
- `bool_`
- `i64_`
- `datetime_`

It becomes expensive for document-like fields because each new feature gets wired separately:

- row codec special cases
- commit/merge special cases
- projector special cases
- index special cases
- transaction query special cases
- sidecar API special cases

The result is correct, but expensive to extend.

## Goal

Keep the current typed-table model, but split field extensibility into a small set of explicit capabilities. A complex field should register handlers once, and the rest of the engine should call capability interfaces instead of hard-coding `markdown_`.

## Design

Introduce a registry of field capability plugins.

```v
pub struct FieldCapabilityRegistry {
pub mut:
	handlers map[string]FieldCapabilityPlugin
}
```

Each plugin is keyed by a logical capability name, not by the entire storage subsystem.

```v
pub interface FieldCapabilityPlugin {
	name() string
	supports(column ColumnDef) bool
	inline_codec() InlineValueCodec
	external_storage() ?ExternalFieldStorage
	merge_strategy() ?FieldMergeStrategy
	projection_strategy() ?FieldProjectionStrategy
	index_strategy() ?FieldIndexStrategy
	query_strategy() ?FieldQueryStrategy
}
```

`ColumnType` remains useful, but becomes the low-level inline value category. Complex behavior lives in the plugin.

## Capability Surfaces

### 1. Inline Value Codec

Handles row-local encoding and decoding.

```v
pub interface InlineValueCodec {
	encode(value ColumnValue) ![]u8
	decode(data []u8) !ColumnValue
}
```

For scalar fields this is enough.

For `markdown_`, the inline codec just encodes and decodes `MarkdownRef`.

### 2. External Field Storage

Handles side-store ingest/load for fields whose real payload is not stored inline.

```v
pub interface ExternalFieldStorage {
	ingest(mut db PersistentDatabase, column ColumnDef, raw ColumnValue, cfg ChunkConfig, meta CommitMeta) !ColumnValue
	load(mut db PersistentDatabase, column ColumnDef, stored ColumnValue) !ColumnValue
	diff(mut db PersistentDatabase, column ColumnDef, base ColumnValue, target ColumnValue) !FieldDiff
}
```

This is the layer where `markdown_` side-store belongs.

### 3. Field Merge Strategy

Handles semantic 3-way merge for one field.

```v
pub interface FieldMergeStrategy {
	try_merge(mut db PersistentDatabase, column ColumnDef, base ColumnValue, ours ColumnValue, theirs ColumnValue, cfg ChunkConfig, meta CommitMeta) !FieldMergeResult
}

pub struct FieldMergeResult {
pub:
	merged    bool
	value     ColumnValue
	conflict  string
}
```

This removes `markdown_`-specific merge branches from row merge orchestration. The row merge engine only needs to ask, "does this field have a merge strategy?"

### 4. Field Projection Strategy

Handles projector-compatible derived metrics.

```v
pub interface FieldProjectionStrategy {
	validate_selector(selector string, expected ColumnType) !
	compute_projection(mut db PersistentDatabase, branch_name string, table_name string, column ColumnDef, selector string) !ColumnValue
}
```

This turns Markdown projector support into a generic "field-derived projection" feature.

### 5. Field Index Strategy

Handles derived secondary indexes from one field.

```v
pub interface FieldIndexStrategy {
	validate_selector(selector string, expected ColumnType) !
	expand_index_values(mut db PersistentDatabase, column ColumnDef, stored ColumnValue, selector string, expected ColumnType) ![]ColumnValue
}
```

This is the key abstraction that removes most current `markdown_selector` branches.

It also generalizes well to future fields:

- `jsondoc_` path indexes
- `html_` tag or link host indexes
- `notebook_` code-cell language indexes
- `embedding_` bucket or family indexes

### 6. Field Query Strategy

Handles ad-hoc field-native queries that are not naturally expressed as ordinary secondary index lookups.

```v
pub interface FieldQueryStrategy {
	exact(mut db PersistentDatabase, branch_name string, table_name string, column ColumnDef, selector string, value ColumnValue, limit int) ![]TypedSchemaRow
	prefix(mut db PersistentDatabase, branch_name string, table_name string, column ColumnDef, selector string, value ColumnValue, limit int) ![]TypedSchemaRow
	metric(mut db PersistentDatabase, branch_name string, table_name string, column ColumnDef, selector string) !ColumnValue
}
```

Most fields may not implement this. `markdown_` benefits from it because it already supports both metric-like and derived-index-like access paths.

## Schema Shape

Instead of baking `json_field` and `markdown_selector` directly into one index struct forever, move toward a generic derived-selector shape.

Current:

```v
SchemaIndexDef {
	column            string
	json_field        string
	json_field_type   ColumnType
	markdown_selector string
}
```

Target:

```v
pub enum DerivedSelectorKind {
	none
	json_path
	field_selector
}

pub struct DerivedSelector {
pub:
	kind          DerivedSelectorKind
	plugin_name   string
	selector      string
	value_type    ColumnType
}
```

Then:

```v
pub struct SchemaIndexDef {
pub:
	name       string
	column     string
	covering   bool
	selector   DerivedSelector
}
```

This keeps JSON indexes working while giving complex fields a general hook.

`markdown_` would use:

- `kind = .field_selector`
- `plugin_name = 'markdown'`
- `selector = 'link_host'`

## Runtime Flow

### Write Path

1. typed row write reaches table schema
2. for each column, look up plugin by column definition
3. if plugin has `external_storage`, ingest raw value before row encoding
4. inline codec writes stored inline representation
5. row commit path asks `index_strategy` for derived index values
6. projector refresh later asks `projection_strategy` for derived metrics

### Merge Path

1. typed row merge detects field-level divergence
2. for each changed column, check plugin `merge_strategy`
3. if no strategy exists, keep current scalar behavior
4. if strategy exists, plugin returns merged value or conflict
5. merge report may optionally ask plugin external storage for a human summary

### Query Path

1. normal scalar indexes continue as-is
2. derived indexes use the plugin `index_strategy`
3. ad-hoc field-native queries use plugin `query_strategy`
4. sidecar only routes requests; it does not know Markdown-specific logic

## What Moves Out Of Markdown Special Cases

The following current `markdown_` branches should become plugin calls over time:

- typed index validation for markdown selectors
- persistent reindex expansion for Markdown fields
- transaction-time Markdown index compensation
- Markdown-specific index cursor population
- row merge special handling for Markdown columns
- sidecar Markdown metric and Markdown query routing logic

After refactor, the generic engine should only ask:

- does this column have external storage?
- does this column have a merge strategy?
- does this index use a field-derived selector?
- does this field support ad-hoc query?

## Migration Plan

### Phase 1: Capability Registry Without Behavior Change

Add registry types and register built-in scalar handlers plus one `markdown` handler, but keep current code paths intact.

Success criteria:

- no behavior changes
- tests stay green
- registry can answer "which plugin owns this column?"

### Phase 2: Move Derived Index Expansion Behind Plugin API

Refactor:

- persistent markdown index expansion
- transaction markdown index compensation
- markdown cursor entry generation

to call `FieldIndexStrategy`.

Success criteria:

- `database.v` no longer branches on `markdown_selector` for index value extraction
- Markdown value and metric index tests still pass

### Phase 3: Move Merge Behind Plugin API

Refactor typed row merge to dispatch via `FieldMergeStrategy`.

Success criteria:

- row merge engine becomes field-agnostic
- Markdown merge tests still pass

### Phase 4: Move Projections Behind Plugin API

Refactor projector markdown selector support to call `FieldProjectionStrategy`.

Success criteria:

- `projector.v` no longer imports Markdown extraction details directly
- aggregate projector behavior remains unchanged

### Phase 5: Unify Query Entry Points

Build one generic derived query endpoint and one sidecar/query API that dispatches via `FieldQueryStrategy`.

Success criteria:

- sidecar stops carrying Markdown-specific query semantics
- future document-like fields can add ad-hoc query support without new endpoints

## Why This Is Better

This refactor keeps the current strengths of `pollydb`:

- typed rows
- content-addressed storage
- secondary indexes
- projector-managed derived state

But it changes the extension model from:

- "add a type, then patch every subsystem"

to:

- "register one field capability plugin, then let the engine call it"

That is the right direction if `pollydb` is going to support more rich fields after Markdown.

## Recommendation

Do not remove the current Markdown implementation first. Treat it as the proving ground.

Recommended next engineering step:

1. add `FieldCapabilityRegistry`
2. wrap existing Markdown index expansion behind `FieldIndexStrategy`
3. only after that, move merge and projection dispatch

That sequence gives the highest architectural payoff with the lowest immediate rewrite risk.
