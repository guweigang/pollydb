# Memory Schema Capabilities

This note proposes the schema-level declaration model for memory-specific
capabilities in `pollydb`.

The guiding question is:

- just as a field can declare FTS capability today, how should a field declare:
  - vectorization capability
  - reflection / retrospective capability

The answer should be explicit at schema definition time, not left to ad hoc
application conventions.

## Problem

Today a table can already declare lexical retrieval capability through
`SchemaIndexDef.fts(...)` and `SchemaIndexDef.fts_markdown(...)`.

That gives a good model for:

- which fields are indexed
- how source text is derived
- which query path should operate on them

Memory-oriented capabilities need the same level of explicitness.

Without that, applications will end up with hidden assumptions such as:

- "this markdown field should be embedded"
- "that summary field may be distilled"
- "this content field supports replay"

Those rules belong in schema, not in ingest glue.

## Design Goal

Split memory capability declarations into two layers:

1. index-like declarations for retrieval surfaces
2. reflection-capability declarations for derived memory behavior

This preserves a clean separation:

- indexes answer "how is this queried?"
- reflection capabilities answer "how may this be distilled, linked, and replayed?"

## Layer 1: Embedding as a Schema Index Capability

Vectorization should be declared similarly to FTS: through `SchemaIndexDef`.

This is the right layer because vectorization is:

- derived
- rebuildable
- tied to one source field
- one of several query surfaces over that field

### Proposed API Shape

```v
pub fn SchemaIndexDef.embedding_text(name string, column string, profile string) !SchemaIndexDef

pub fn SchemaIndexDef.embedding_markdown(name string, column string, scope MarkdownEmbeddingScope, profile string) !SchemaIndexDef
```

Where:

- `name` is the index name
- `column` is the source field
- `profile` selects an embedding profile such as model family or dimensions
- markdown scope is one of:
  - `.block`
  - `.path`

### Example

```v
storage.TypedTableSpec.new(
	storage.TableDef.new('memory_entries', [
		storage.ColumnDef.new('entry_id', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('content_md', .markdown_, true)!,
		storage.ColumnDef.new('summary_text', .string_, true)!,
	], ['entry_id'])!,
	[
		storage.SchemaIndexDef.fts_markdown('content_md_fts_idx', 'content_md', .visible_text)!,
		storage.SchemaIndexDef.embedding_markdown('content_md_block_vec_idx', 'content_md', .block, 'bge-small-zh-v1.5')!,
		storage.SchemaIndexDef.embedding_markdown('content_md_path_vec_idx', 'content_md', .path, 'bge-small-zh-v1.5')!,
		storage.SchemaIndexDef.embedding_text('summary_text_vec_idx', 'summary_text', 'bge-small-zh-v1.5')!,
	],
)!
```

### Why IndexDef Is The Right Fit

Embedding declarations are close to FTS declarations because both mean:

- source data stays elsewhere
- an index sidecar is derived from it
- the sidecar may be rebuilt later
- query APIs should discover capability from schema

So embedding should feel like:

- `fts_*` for lexical retrieval
- `embedding_*` for semantic retrieval

## Layer 2: Reflection as a Memory Capability

Reflection is not just an index.

It controls whether a field may participate in:

- background distillation
- reflection-node generation
- semantic link creation
- retrospective replay

That makes it a better fit for a separate schema capability layer.

## Proposed API Shape

```v
pub struct ReflectionOptions {
pub:
	enabled               bool = true
	embedding_index       string
	reflection_kind       string = 'summary'
	replay_anchor         bool = true
	link_evidence_blocks  bool = true
	link_semantic_neighbors bool = true
}

pub struct MemoryCapabilityDef {
pub:
	table_name string
	column_name string
	options ReflectionOptions
}

pub fn MemoryCapabilityDef.reflective_field(table_name string, column_name string, options ReflectionOptions) !MemoryCapabilityDef
```

This can later grow into a table-level registry:

```v
pub fn (mut db PersistentDatabase) register_memory_capability(def MemoryCapabilityDef) !
```

### Example

```v
db.register_memory_capability(storage.MemoryCapabilityDef.reflective_field(
	'memory_entries',
	'content_md',
	storage.ReflectionOptions{
		embedding_index: 'content_md_path_vec_idx'
		reflection_kind: 'summary'
		replay_anchor: true
		link_evidence_blocks: true
		link_semantic_neighbors: true
	},
)!)!
```

This means:

- `content_md` is allowed to enter Reflector pipelines
- the preferred semantic surface for clustering is `content_md_path_vec_idx`
- resulting reflections should preserve replay anchors

## Capability Taxonomy

It helps to distinguish four field roles.

### 1. Raw Field

Stores factual source material.

Examples:

- `content_md`
- `content_text`
- `tool_output_md`

### 2. Embedding-Enabled Field

May produce PollyDB-native vector records and derived ANN index material.

Examples:

- `content_md`
- `summary_text`

Declared by:

- `SchemaIndexDef.embedding_*`

### 3. Reflectable Field

May participate in Reflector clustering and distillation.

Examples:

- `content_md`
- `summary_md`
- `decision_md`

Declared by:

- `MemoryCapabilityDef.reflective_field(...)`

### 4. Replayable Field

May serve as an anchor-aware target for retrospective navigation.

Examples:

- markdown-backed content with stable anchors

This is best modeled as an option under reflection capability rather than as a
separate index kind.

## Suggested Runtime Semantics

### During Ingest

If a field has embedding capability:

- build or refresh vector targets for that field

If a field has reflection capability:

- enqueue it as a candidate for Reflector policy evaluation

### During Reflection

Reflector should only draw from fields that explicitly opt in.

This prevents:

- accidental summarization of volatile/system-only fields
- hidden coupling between application logic and field naming

### During Replay Query

Replay/query code should inspect capability metadata to decide:

- which field to semantically search
- whether anchor-aware replay is possible
- whether a hit can be expanded into evidence blocks

## Discovery API

Just as FTS capability should be discoverable from schema, memory capability
should also be discoverable.

Suggested shape:

```v
pub fn (spec TypedTableSpec) embedding_indexes_for_column(column string) []SchemaIndexDef
pub fn (spec TypedTableSpec) reflection_capabilities() []MemoryCapabilityDef
pub fn (spec TypedTableSpec) reflection_capability(column string) ?MemoryCapabilityDef
```

This lets:

- CLI tools inspect capabilities
- `agentview` or future memory UIs adapt without hard-coded table knowledge
- replay/query layers choose the right retrieval surfaces automatically

## Compatibility With Field Capability Plugins

This design should fit the broader plugin direction in
[docs/field_capability_plugins.md](/Users/guweigang/Source/pollytree/docs/field_capability_plugins.md).

The intended split is:

- field plugins own how a field emits derived materials
- schema capability defs own whether a table/column chooses to use them

For example:

- the `markdown` field plugin knows how to emit block/path embedding targets
- `SchemaIndexDef.embedding_markdown(...)` declares that one table column wants
  that capability active
- `MemoryCapabilityDef.reflective_field(...)` declares that Reflector may
  consume that field

## Why Not Put Reflection Into SchemaIndexDef?

Because reflection is broader than indexing.

An index declaration answers:

- where does the searchable derivative live?

A reflection declaration answers:

- may this field be distilled?
- how should it cluster?
- should replay anchors be preserved?
- should semantic links be written?

Those are higher-level memory behaviors, not just access paths.

So the cleaner split is:

- `SchemaIndexDef` for retrieval/index surfaces
- `MemoryCapabilityDef` for reflective/derived memory behavior

## Recommended First Implementation

The first implementation should stay narrow.

### Step 1

Add schema declarations for:

- `embedding_text(...)`
- `embedding_markdown(...)`

No reflection capability yet.

### Step 2

Add a minimal `MemoryCapabilityDef.reflective_field(...)` registry with:

- `embedding_index`
- `reflection_kind`
- `replay_anchor`

### Step 3

Teach the future Reflector to use only registered reflective fields.

This gets the benefits of explicit schema semantics without overbuilding the
entire memory framework in one pass.

## Recommended Direction

If we want memory to become a first-class capability in `pollydb`, the schema
should eventually let a user say:

- this field is lexically searchable
- this field is semantically searchable
- this field may be reflected on
- this field supports retrospective replay

That is the memory equivalent of how FTS made lexical retrieval explicit.
