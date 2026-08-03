# Typed DDL YAML

`pollydb` already has a typed-table schema model in code:

- `storage.TableDef`
- `storage.ColumnDef`
- `storage.SchemaIndexDef`
- `storage.TypedTableSpec`

This document defines a small YAML format that compiles into those runtime
types. The goal is not to replace SQL DDL, but to provide a declarative schema
source for:

- typed table registration
- sidecar and CLI tooling
- future `vsql` schema discovery

## Scope

The first version intentionally stays narrow:

- tables
- primary keys
- columns
- secondary indexes

It does not yet cover:

- migrations
- computed columns

It now also supports:

- aggregate projectors
- memory capabilities

## Example

```yaml
schema_version: 1

tables:
  - name: sessions
    primary_key: [id]
    columns:
      - name: id
        type: string
        nullable: false
      - name: updated_at
        type: datetime
        nullable: false
    indexes:
      - name: updated_at_idx
        kind: column
        column: updated_at
      - name: updated_at_cover_idx
        kind: covering
        column: updated_at
```

## Column fields

- `name`
- `type`
- `nullable`

Supported `type` values:

- `bool`
- `i64`
- `string`
- `text`
- `bytes`
- `enum`
- `json`
- `datetime`
- `markdown`

Optional fields:

- `aggregate: sum`
- `enum_values: [active, draft, done]`
- `default_current_timestamp: true`
- `auto_update_current_timestamp: true`

## Index fields

- `name`
- `kind`
- `column`

Supported `kind` values in the first implementation:

- `column`
- `covering`
- `covering_projected`
- `json_path`
- `json_path_covering`
- `fts_text`
- `fts_markdown`
- `embedding_text`
- `embedding_markdown`

Additional fields depend on kind:

- `stored_columns`
- `json_field`
- `json_field_type`
- `mode`
- `tokenizer`
- `prefix_lengths`
- `profile`
- `scope`

## Current status

The first live consumer is:

- [agentview/codex_schema.v](/Users/guweigang/Source/pollytree/agentview/codex_schema.v)

The `sessions` table is now loaded from:

- [agentview/codex_schema.yml](/Users/guweigang/Source/pollytree/agentview/codex_schema.yml)

This keeps the rollout small while proving that YAML DDL can compile into the
existing typed runtime model without changing storage semantics.

## Aggregate Projections

Example:

```yaml
aggregate_projections:
  - name: count(docs.body.links)
    table_name: docs
    column_name: body
    kind: count_field_selector
    plugin: markdown
    selector: links
    priority: 120
    cost_hint: low
```

Supported `kind` values in the current YAML compiler:

- `sum_i64`
- `sum_json_i64`
- `count_field_selector`

Extra fields by kind:

- `json_path` for `sum_json_i64`
- `plugin` and `selector` for `count_field_selector`
- `priority`
- `cost_hint`

## Memory Capabilities

Example:

```yaml
memory_capabilities:
  - table_name: docs
    column_name: body
    embedding_index: body_vec_idx
    reflection_kind: summary
    replay_anchor: true
    link_evidence_blocks: true
    link_semantic_neighbors: false
```

Supported fields:

- `table_name`
- `column_name`
- `embedding_index`
- `reflection_kind`
- `enabled`
- `replay_anchor`
- `link_evidence_blocks`
- `link_semantic_neighbors`

## CLI workflow

The current CLI loop is:

1. validate or describe one YAML file
2. preview the schema update against one repository catalog
3. plan the concrete catalog/index actions
4. register it only when the preview is clean

Examples:

```bash
pollydb validate-schema ./agentview/codex_schema.yml
pollydb describe-schema ./agentview/codex_schema.yml entries
pollydb preview-schema-update ./agentview/codex_schema.yml
pollydb plan-schema-update ./agentview/codex_schema.yml
pollydb register-schema ./agentview/codex_schema.yml
```

`register-schema` now runs a preflight preview first. If any table would hit
`schema_mismatch`, the command aborts before mutating the catalog. This avoids
partial multi-table updates where early tables were already registered before a
later mismatch was discovered.

When `aggregate_projections` and `memory_capabilities` are present, `register-schema`
will also register them after the referenced tables are in place. Re-running the
same YAML is idempotent: matching projector/capability definitions are skipped,
while conflicting re-definitions still fail fast.

`plan-schema-update` goes one step further than preview and lists the concrete
actions that apply would attempt, such as:

- `create_table`
- `add_index`
- `noop`
- `blocked`
