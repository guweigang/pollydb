module storage

import memory

fn test_parse_yaml_ddl_text_builds_sessions_spec() {
	ddl := '
schema_version: 1
tables:
  - name: sessions
    primary_key: [id]
    columns:
      - name: id
        type: string
        nullable: false
      - name: title
        type: string
        nullable: false
      - name: updated_at
        type: datetime
        nullable: false
      - name: archived
        type: bool
        nullable: false
      - name: entry_count
        type: i64
        nullable: false
    indexes:
      - name: updated_at_idx
        kind: column
        column: updated_at
      - name: updated_at_cover_idx
        kind: covering
        column: updated_at
'
	file := parse_yaml_ddl_text(ddl) or { panic(err) }
	assert file.schema_version == 1
	assert file.tables.len == 1
	spec := file.table_spec('sessions') or { panic(err) }
	assert spec.name() == 'sessions'
	assert spec.table.primary_key == ['id']
	assert spec.table.columns.len == 5
	assert spec.indexes.len == 2
	assert spec.indexes[0].name == 'updated_at_idx'
	assert spec.indexes[0].column == 'updated_at'
	assert !spec.indexes[0].stores_row
	assert spec.indexes[1].name == 'updated_at_cover_idx'
	assert spec.indexes[1].stores_row
}

fn test_parse_yaml_ddl_text_builds_projections_and_memory_capabilities() {
	ddl := '
schema_version: 1
tables:
  - name: docs
    primary_key: [id]
    columns:
      - name: id
        type: string
        nullable: false
      - name: body
        type: markdown
        nullable: false
    indexes:
      - name: body_vec_idx
        kind: embedding_markdown
        column: body
        scope: path
        profile: bge-small
aggregate_projections:
  - name: count(docs.body.links)
    table_name: docs
    column_name: body
    kind: count_field_selector
    plugin: markdown
    selector: links
    priority: 120
    cost_hint: low
memory_capabilities:
  - table_name: docs
    column_name: body
    embedding_index: body_vec_idx
    reflection_kind: summary
    replay_anchor: true
    link_evidence_blocks: true
    link_semantic_neighbors: false
'
	file := parse_yaml_ddl_text(ddl) or { panic(err) }
	assert file.aggregate_projections.len == 1
	assert file.memory_capabilities.len == 1

	projections := file.aggregate_projection_defs() or { panic(err) }
	assert projections.len == 1
	assert projections[0].name == 'count(docs.body.links)'
	assert projections[0].table_name == 'docs'
	assert projections[0].column_name == 'body'
	assert projections[0].field_projection_plugin() == 'markdown'
	assert projections[0].field_projection_selector() == 'links'
	assert projections[0].priority == 120
	assert projections[0].cost_hint == .low

	capabilities := file.memory_capability_defs() or { panic(err) }
	assert capabilities.len == 1
	assert capabilities[0].table_name == 'docs'
	assert capabilities[0].column_name == 'body'
	assert capabilities[0].options.embedding_index == 'body_vec_idx'
	assert capabilities[0].options.reflection_kind == 'summary'
	assert capabilities[0].options.replay_anchor
	assert capabilities[0].options.link_evidence_blocks
	assert !capabilities[0].options.link_semantic_neighbors

	spec := file.table_spec('docs') or { panic(err) }
	assert spec.indexes.len == 1
	assert spec.indexes[0].is_embedding()
	assert spec.indexes[0].embedding_scope == memory.MarkdownEmbeddingScope.path.str()
}
