module storage

import crypto.sha256
import math
import memory
import os

pub struct VectorSearchQuery {
pub:
	branch_name string
	limit       int = 10
	scope       memory.MarkdownEmbeddingScope
	scope_set   bool
}

pub struct VectorSearchHit {
pub:
	int_id        i64
	target_id     string
	branch_name   string
	table_name    string
	column_name   string
	primary_key   []u8
	score         f64
	scope         memory.MarkdownEmbeddingScope
	kind          string
	content_id    string
	occurrence_id string
	parent_id     string
	anchor        string
	order         int
	path_hint     string
	text          string
	dimensions    int
}

pub enum VectorIndexBackendKind {
	polly_scan
	usearch
}

struct VectorSidecarRow {
	int_id        i64
	target_id     string
	branch_name   string
	table_name    string
	column_name   string
	primary_key   []u8
	scope         memory.MarkdownEmbeddingScope
	kind          string
	content_id    string
	occurrence_id string
	parent_id     string
	anchor        string
	order         int
	path_hint     string
	text          string
	vector        []f32
}

const vector_target_ids_table_name = 'pollydb_vector_target_ids'
const vector_id_lookup_table_name = 'pollydb_vector_id_lookup'
const vector_records_table_name = 'pollydb_vector_records'

fn vector_sidecar_dir(root_dir string) string {
	return os.join_path(repository_layout_dir(root_dir), 'vectors')
}

fn usearch_sidecar_dir(root_dir string) string {
	return os.join_path(vector_sidecar_dir(root_dir), 'usearch')
}

fn usearch_sidecar_scope_key(query VectorSearchQuery) string {
	if query.scope_set {
		return query.scope.str()
	}
	return 'all'
}

fn usearch_sidecar_index_path(root_dir string, query VectorSearchQuery, dimensions int) string {
	branch_key := query.branch_name.bytes().hex()
	scope_key := usearch_sidecar_scope_key(query).bytes().hex()
	return os.join_path(usearch_sidecar_dir(root_dir), '${branch_key}-${scope_key}-${dimensions}.usearch')
}

fn usearch_sidecar_meta_path(index_path string) string {
	return '${index_path}.meta'
}

pub fn vector_target_ids_spec() !TypedTableSpec {
	return TypedTableSpec.new(TableDef.new(vector_target_ids_table_name, [
		ColumnDef.new('target_id', .string_, false)!,
		ColumnDef.new('int_id', .i64_, false)!,
		ColumnDef.new('content_id', .string_, false)!,
		ColumnDef.new('occurrence_id', .string_, false)!,
		ColumnDef.new('scope', .string_, false)!,
		ColumnDef.new('anchor', .string_, false)!,
	], ['target_id'])!, [
		SchemaIndexDef.new('int_id_idx', 'int_id')!,
	])!
}

pub fn vector_id_lookup_spec() !TypedTableSpec {
	return TypedTableSpec.new(TableDef.new(vector_id_lookup_table_name, [
		ColumnDef.new('int_id_key', .string_, false)!,
		ColumnDef.new('int_id', .i64_, false)!,
		ColumnDef.new('target_id', .string_, false)!,
		ColumnDef.new('content_id', .string_, false)!,
		ColumnDef.new('occurrence_id', .string_, false)!,
		ColumnDef.new('scope', .string_, false)!,
		ColumnDef.new('anchor', .string_, false)!,
	], ['int_id_key'])!, [
		SchemaIndexDef.new('target_id_idx', 'target_id')!,
	])!
}

pub fn vector_records_spec() !TypedTableSpec {
	return TypedTableSpec.new(TableDef.new(vector_records_table_name, [
		ColumnDef.new('target_id', .string_, false)!,
		ColumnDef.new('int_id', .i64_, false)!,
		ColumnDef.new('source_table_name', .string_, false)!,
		ColumnDef.new('source_column_name', .string_, false)!,
		ColumnDef.new('source_primary_key', .bytes_, false)!,
		ColumnDef.new('scope', .string_, false)!,
		ColumnDef.new('kind', .string_, false)!,
		ColumnDef.new('content_id', .string_, false)!,
		ColumnDef.new('occurrence_id', .string_, false)!,
		ColumnDef.new('parent_id', .string_, false)!,
		ColumnDef.new('anchor', .string_, false)!,
		ColumnDef.new('sort_order', .i64_, false)!,
		ColumnDef.new('path_hint', .string_, false)!,
		ColumnDef.new('text_body', .string_, false)!,
		ColumnDef.new('dims', .i64_, false)!,
		ColumnDef.new('vector_text', .string_, false)!,
	], ['target_id'])!, [
		SchemaIndexDef.new('int_id_idx', 'int_id')!,
		SchemaIndexDef.new('scope_idx', 'scope')!,
	])!
}

pub fn (mut database PersistentDatabase) ensure_vector_binding_tables() ! {
	if !database.has_table(vector_target_ids_table_name) {
		database.register_table(vector_target_ids_spec()!)!
	}
	if !database.has_table(vector_id_lookup_table_name) {
		database.register_table(vector_id_lookup_spec()!)!
	}
	if !database.has_table(vector_records_table_name) {
		database.register_table(vector_records_spec()!)!
	}
}

pub fn (mut database PersistentDatabase) vector_int_id_for_target(branch_name string, target_id string) !i64 {
	database.ensure_vector_binding_tables()!
	session := database.open_session(branch_name)!
	row := session.get_row(mut database, vector_target_ids_table_name, target_id.bytes())!
	return required_typed_row_i64(row, 'int_id')
}

pub fn (mut database PersistentDatabase) vector_target_id_for_int(branch_name string, int_id i64) !string {
	database.ensure_vector_binding_tables()!
	session := database.open_session(branch_name)!
	row := session.get_row(mut database, vector_id_lookup_table_name, vector_int_id_key(int_id).bytes())!
	return required_typed_row_string(row, 'target_id')
}

pub fn (mut database PersistentDatabase) ensure_vector_target_bindings(branch_name string, targets []memory.MarkdownEmbeddingTarget) !map[string]i64 {
	if targets.len == 0 {
		return map[string]i64{}
	}
	database.ensure_vector_binding_tables()!
	mut ids_by_target := map[string]i64{}
	mut missing := []memory.MarkdownEmbeddingTarget{}
	mut next_id := i64(1)
	mut branch_exists := false
	mut session := DatabaseSession{}
	if _ := database.checkout(branch_name) {
		branch_exists = true
		session = database.open_session(branch_name)!
		for target in targets {
			row := session.get_row(mut database, vector_target_ids_table_name, target.id.bytes()) or {
				missing << target
				continue
			}
			ids_by_target[target.id] = required_typed_row_i64(row, 'int_id')
		}
		existing_rows := session.scan_table(mut database, vector_target_ids_table_name,
			0) or { []TypedSchemaRow{} }
		for row in existing_rows {
			current := required_typed_row_i64(row, 'int_id')
			if current >= next_id {
				next_id = current + 1
			}
		}
	} else {
		missing = targets.clone()
	}
	if missing.len == 0 {
		return ids_by_target
	}
	mut writes := TypedWriteSet.new()
	mut assigned := next_id
	for target in missing {
		int_id := assigned
		assigned++
		ids_by_target[target.id] = int_id
		mut target_row := TypedRowData.new()
		target_row.set('target_id', target.id)
		target_row.set('int_id', int_id)
		target_row.set('content_id', target.content_id)
		target_row.set('occurrence_id', target.occurrence_id)
		target_row.set('scope', target.scope.str())
		target_row.set('anchor', target.anchor)
		writes.put(vector_target_ids_table_name, target.id.bytes(), target_row)
		mut id_row := TypedRowData.new()
		id_row.set('int_id_key', vector_int_id_key(int_id))
		id_row.set('int_id', int_id)
		id_row.set('target_id', target.id)
		id_row.set('content_id', target.content_id)
		id_row.set('occurrence_id', target.occurrence_id)
		id_row.set('scope', target.scope.str())
		id_row.set('anchor', target.anchor)
		writes.put(vector_id_lookup_table_name, vector_int_id_key(int_id).bytes(), id_row)
	}
	if !branch_exists {
		cfg := ChunkConfig.default()
		specs := database.registered_specs()
		mut items := []KVPair{}
		for op in writes.operations() {
			if op.delete {
				continue
			}
			spec := database.table_spec(op.table_name)!
			codec := TypedRowCodec.new(spec.table)
			table_view := TableView.new(Tree{}, spec.table.name)
			items << KVPair{
				key:   table_view.key_for(op.primary_key)
				value: codec.encode(op.row)!
			}
		}
		mut tree := Tree.build(items, cfg)!
		tree = rebuild_typed_indexes_for_specs(tree, specs, cfg)!
		tree = rebuild_typed_aggregates_for_specs(tree, specs, cfg)!
		_ = database.commit_to_branch(branch_name, tree, CommitMeta{
			author:  'pollydb/vector'
			message: 'seed vector target ids'
		})!
		return ids_by_target
	}
	database.apply_typed_write_set(branch_name, writes, ChunkConfig.default(), CommitMeta{
		author:  'pollydb/vector'
		message: 'assign vector target ids'
	})!
	return ids_by_target
}

pub fn (mut database PersistentDatabase) upsert_markdown_embedding_targets(branch_name string, targets []memory.MarkdownEmbeddingTarget, vectors [][]f32) ! {
	return database.upsert_markdown_embedding_targets_for_source(branch_name, '', []u8{},
		'', targets, vectors)
}

pub fn (mut database PersistentDatabase) upsert_markdown_embedding_targets_for_source(branch_name string, table_name string, primary_key []u8, column_name string, targets []memory.MarkdownEmbeddingTarget, vectors [][]f32) ! {
	if targets.len != vectors.len {
		return error('embedding targets and vectors length mismatch')
	}
	backend_kind := database.vector_index_backend_kind()
	if backend_kind == .usearch {
		database.ensure_vector_index_backend_ready(backend_kind)!
	}
	int_ids_by_target := database.ensure_vector_target_bindings(branch_name, targets)!
	mut writes := TypedWriteSet.new()
	for idx, target in targets {
		vector := vectors[idx]
		int_id := int_ids_by_target[target.id] or {
			return error('missing vector int id binding for target ${target.id}')
		}
		mut row := TypedRowData.new()
		row.set('target_id', target.id)
		row.set('int_id', int_id)
		row.set('source_table_name', table_name)
		row.set('source_column_name', column_name)
		row.set('source_primary_key', primary_key.clone())
		row.set('scope', target.scope.str())
		row.set('kind', target.kind)
		row.set('content_id', target.content_id)
		row.set('occurrence_id', target.occurrence_id)
		row.set('parent_id', target.parent_id)
		row.set('anchor', target.anchor)
		row.set('sort_order', i64(target.order))
		row.set('path_hint', target.path_hint)
		row.set('text_body', target.text)
		row.set('dims', i64(vector.len))
		row.set('vector_text', encode_vector_text(vector))
		writes.put(vector_records_table_name, target.id.bytes(), row)
	}
	database.apply_typed_write_set(branch_name, writes, ChunkConfig.default(), CommitMeta{
		author:  'pollydb/vector'
		message: 'upsert vector records'
	})!
	database.upsert_vector_index(branch_name, targets, vectors, backend_kind)!
}

pub fn (mut database PersistentDatabase) index_markdown_ref_embeddings(branch_name string, ref MarkdownRef, mut engine memory.EmbeddingEngine) ![]memory.MarkdownEmbeddingTarget {
	return database.index_markdown_ref_embeddings_for_source(branch_name, '', []u8{},
		'', ref, mut engine)
}

pub fn (mut database PersistentDatabase) index_markdown_ref_embeddings_for_source(branch_name string, table_name string, primary_key []u8, column_name string, ref MarkdownRef, mut engine memory.EmbeddingEngine) ![]memory.MarkdownEmbeddingTarget {
	targets := markdown_embedding_targets_from_ref(database, ref)!
	vectors := engine.embed_batch(memory.markdown_embedding_texts(targets))!
	dims := engine.dimensions()
	for vector in vectors {
		if vector.len != dims {
			return error('embedding engine returned inconsistent dimensions')
		}
	}
	database.upsert_markdown_embedding_targets_for_source(branch_name, table_name, primary_key,
		column_name, targets, vectors)!
	return targets
}

pub fn (mut database PersistentDatabase) query_markdown_text_embeddings(mut engine memory.EmbeddingEngine, text string, query VectorSearchQuery) ![]VectorSearchHit {
	query_vector := engine.embed(text)!
	return database.query_markdown_embedding_vector(query_vector, query)
}

pub fn (mut database PersistentDatabase) query_markdown_embedding_vector(query_vector []f32, query VectorSearchQuery) ![]VectorSearchHit {
	if query.branch_name.len == 0 {
		return error('vector search branch_name is required')
	}
	backend_kind := database.vector_index_backend_kind()
	database.ensure_vector_index_backend_ready(backend_kind)!
	matches := database.query_vector_index(query_vector, query, backend_kind)!
	if matches.len == 0 {
		return []VectorSearchHit{}
	}
	rows := database.vector_rows_by_int_ids(query, matches.map(it.int_id))!
	row_by_int_id := vector_rows_by_int_id(rows)
	mut hits := []VectorSearchHit{cap: matches.len}
	for item in matches {
		row := row_by_int_id[item.int_id] or { continue }
		hits << VectorSearchHit{
			int_id:        row.int_id
			target_id:     row.target_id
			branch_name:   row.branch_name
			table_name:    row.table_name
			column_name:   row.column_name
			primary_key:   row.primary_key.clone()
			score:         item.score
			scope:         row.scope
			kind:          row.kind
			content_id:    row.content_id
			occurrence_id: row.occurrence_id
			parent_id:     row.parent_id
			anchor:        row.anchor
			order:         row.order
			path_hint:     row.path_hint
			text:          row.text
			dimensions:    row.vector.len
		}
	}
	if query.limit > 0 && hits.len > query.limit {
		return hits[..query.limit].clone()
	}
	return hits
}

fn (mut database PersistentDatabase) vector_rows(query VectorSearchQuery) ![]VectorSidecarRow {
	database.ensure_vector_binding_tables()!
	session := database.open_session(query.branch_name)!
	rows := session.scan_table(mut database, vector_records_table_name, 0) or { []TypedSchemaRow{} }
	mut out := []VectorSidecarRow{cap: rows.len}
	for row in rows {
		vector_row := vector_row_from_typed(query.branch_name, row)!
		if query.scope_set && vector_row.scope != query.scope {
			continue
		}
		out << vector_row
	}
	out.sort_with_compare(fn (a &VectorSidecarRow, b &VectorSidecarRow) int {
		if a.order < b.order {
			return -1
		}
		if a.order > b.order {
			return 1
		}
		if a.target_id < b.target_id {
			return -1
		}
		if a.target_id > b.target_id {
			return 1
		}
		return 0
	})
	return out
}

fn (mut database PersistentDatabase) vector_rows_by_int_ids(query VectorSearchQuery, int_ids []i64) ![]VectorSidecarRow {
	if int_ids.len == 0 {
		return []VectorSidecarRow{}
	}
	id_set := int_id_lookup_set(int_ids)
	rows := database.vector_rows(query)!
	mut out := []VectorSidecarRow{cap: rows.len}
	for row in rows {
		if row.int_id in id_set {
			out << row
		}
	}
	return out
}

fn vector_row_from_typed(branch_name string, row TypedSchemaRow) !VectorSidecarRow {
	scope_raw := required_typed_row_string(row, 'scope')
	scope := match scope_raw {
		'path' { memory.MarkdownEmbeddingScope.path }
		else { memory.MarkdownEmbeddingScope.block }
	}
	vector := decode_vector_text(required_typed_row_string(row, 'vector_text'))!
	dims := required_typed_row_i64(row, 'dims')
	if dims != i64(vector.len) {
		return error('stored vector dimensions do not match vector payload')
	}
	return VectorSidecarRow{
		int_id:        required_typed_row_i64(row, 'int_id')
		target_id:     required_typed_row_string(row, 'target_id')
		branch_name:   branch_name
		table_name:    required_typed_row_string(row, 'source_table_name')
		column_name:   required_typed_row_string(row, 'source_column_name')
		primary_key:   required_typed_row_bytes(row, 'source_primary_key')
		scope:         scope
		kind:          required_typed_row_string(row, 'kind')
		content_id:    required_typed_row_string(row, 'content_id')
		occurrence_id: required_typed_row_string(row, 'occurrence_id')
		parent_id:     required_typed_row_string(row, 'parent_id')
		anchor:        required_typed_row_string(row, 'anchor')
		order:         int(required_typed_row_i64(row, 'sort_order'))
		path_hint:     required_typed_row_string(row, 'path_hint')
		text:          required_typed_row_string(row, 'text_body')
		vector:        vector
	}
}

fn int_id_lookup_set(int_ids []i64) map[i64]bool {
	mut out := map[i64]bool{}
	for int_id in int_ids {
		out[int_id] = true
	}
	return out
}

fn vector_rows_by_int_id(rows []VectorSidecarRow) map[i64]VectorSidecarRow {
	mut out := map[i64]VectorSidecarRow{}
	for row in rows {
		out[row.int_id] = row
	}
	return out
}

fn vector_rows_to_index_records(rows []VectorSidecarRow) []memory.VectorIndexRecord {
	mut records := []memory.VectorIndexRecord{cap: rows.len}
	for row in rows {
		records << memory.VectorIndexRecord{
			branch_name: row.branch_name
			int_id:      row.int_id
			vector:      row.vector.clone()
		}
	}
	return records
}

fn vector_rows_signature(rows []VectorSidecarRow) string {
	mut material := []u8{}
	for row in rows {
		material << row.int_id.str().bytes()
		material << `\x00`
		material << row.target_id.bytes()
		material << `\x00`
		material << row.scope.str().bytes()
		material << `\x00`
		material << encode_vector_text(row.vector).bytes()
		material << `\x1f`
	}
	return sha256.sum(material).hex()
}

fn usearch_sidecar_meta(query VectorSearchQuery, rows []VectorSidecarRow, dimensions int) string {
	return [
		'schema_version=usearch-v1',
		'branch=${query.branch_name}',
		'scope=${usearch_sidecar_scope_key(query)}',
		'dimensions=${dimensions}',
		'rows=${rows.len}',
		'signature=${vector_rows_signature(rows)}',
	].join('\n')
}

fn vector_search_backend_kind_from_env() VectorIndexBackendKind {
	raw := os.getenv_opt('POLLYDB_VECTOR_BACKEND') or { '' }
	return match raw.trim_space().to_lower() {
		'usearch' { .usearch }
		else { .polly_scan }
	}
}

pub fn (database PersistentDatabase) vector_index_backend_kind() VectorIndexBackendKind {
	return vector_search_backend_kind_from_env()
}

fn (database PersistentDatabase) ensure_vector_index_backend_ready(kind VectorIndexBackendKind) ! {
	match kind {
		.polly_scan {}
		.usearch {
			$if usearch ? {
				return
			} $else {
				return error('USearch vector backend requires compiling with -d usearch')
			}
		}
	}
}

fn (database PersistentDatabase) upsert_vector_index(branch_name string, targets []memory.MarkdownEmbeddingTarget, vectors [][]f32, kind VectorIndexBackendKind) ! {
	match kind {
		.polly_scan {}
		.usearch {
			$if usearch ? {
				usearch_index_path := usearch_sidecar_index_path(database.root_dir, VectorSearchQuery{
					branch_name: branch_name
				}, if vectors.len > 0 { vectors[0].len } else { 0 })
				os.rm(usearch_index_path) or {}
				os.rm(usearch_sidecar_meta_path(usearch_index_path)) or {}
			} $else {
				return error('USearch vector backend requires compiling with -d usearch')
			}
		}
	}
	_ = branch_name
	_ = targets
	_ = vectors
}

fn (mut database PersistentDatabase) query_vector_index(query_vector []f32, query VectorSearchQuery, kind VectorIndexBackendKind) ![]memory.VectorIndexMatch {
	match kind {
		.polly_scan {
			rows := database.vector_rows(query)!
			mut matches := []memory.VectorIndexMatch{cap: rows.len}
			for row in rows {
				matches << memory.VectorIndexMatch{
					int_id: row.int_id
					score:  vector_cosine_similarity(query_vector, row.vector)
				}
			}
			matches.sort_with_compare(fn (a &memory.VectorIndexMatch, b &memory.VectorIndexMatch) int {
				if a.score > b.score {
					return -1
				}
				if a.score < b.score {
					return 1
				}
				if a.int_id < b.int_id {
					return -1
				}
				if a.int_id > b.int_id {
					return 1
				}
				return 0
			})
			if query.limit > 0 && matches.len > query.limit {
				return matches[..query.limit].clone()
			}
			return matches
		}
		.usearch {
			$if usearch ? {
				rows := database.vector_rows(query)!
				if rows.len == 0 {
					return []memory.VectorIndexMatch{}
				}
				mut backend := database.ensure_usearch_sidecar_index(query, rows, query_vector.len)!
				defer {
					backend.close() or {}
				}
				return backend.query(query_vector, memory.VectorIndexQuery{
					limit: if query.limit > 0 { query.limit } else { rows.len }
				})!
			} $else {
				return error('USearch vector backend requires compiling with -d usearch')
			}
		}
	}
}

$if usearch ? {
	fn (database PersistentDatabase) ensure_usearch_sidecar_index(query VectorSearchQuery, rows []VectorSidecarRow, dimensions int) !memory.USearchVectorBackend {
		if dimensions <= 0 {
			return error('USearch query vector dimensions must be positive')
		}
		os.mkdir_all(usearch_sidecar_dir(database.root_dir))!
		index_path := usearch_sidecar_index_path(database.root_dir, query, dimensions)
		meta_path := usearch_sidecar_meta_path(index_path)
		expected_meta := usearch_sidecar_meta(query, rows, dimensions)
		mut backend := memory.new_usearch_vector_backend(memory.USearchVectorBackendConfig{
			dimensions: dimensions
			capacity:   rows.len
		})!
		if os.exists(index_path) && os.exists(meta_path) {
			current_meta := os.read_file(meta_path) or { '' }
			if current_meta == expected_meta {
				backend.load(index_path) or {
					backend.close() or {}
					backend = memory.new_usearch_vector_backend(memory.USearchVectorBackendConfig{
						dimensions: dimensions
						capacity:   rows.len
					})!
					database.rebuild_usearch_sidecar_index(mut backend, index_path, meta_path,
						expected_meta, rows)!
					return backend
				}
				return backend
			}
		}
		database.rebuild_usearch_sidecar_index(mut backend, index_path, meta_path, expected_meta,
			rows)!
		return backend
	}

	fn (database PersistentDatabase) rebuild_usearch_sidecar_index(mut backend memory.USearchVectorBackend, index_path string, meta_path string, meta string, rows []VectorSidecarRow) ! {
		_ = database
		backend.upsert(vector_rows_to_index_records(rows))!
		backend.save(index_path)!
		os.write_file(meta_path, meta)!
	}
}

fn required_typed_row_i64(row TypedSchemaRow, field string) i64 {
	value := row.data.get(field) or { panic(err) }
	return match value {
		i64 { value }
		else { panic('expected i64 field: ${field}') }
	}
}

fn required_typed_row_string(row TypedSchemaRow, field string) string {
	value := row.data.get(field) or { panic(err) }
	return match value {
		string { value }
		else { panic('expected string field: ${field}') }
	}
}

fn required_typed_row_bytes(row TypedSchemaRow, field string) []u8 {
	value := row.data.get(field) or { panic(err) }
	return match value {
		[]u8 { value.clone() }
		else { panic('expected bytes field: ${field}') }
	}
}

fn vector_int_id_key(int_id i64) string {
	raw := int_id.str()
	if raw.len >= 20 {
		return raw
	}
	return '0'.repeat(20 - raw.len) + raw
}

fn encode_vector_text(vector []f32) string {
	if vector.len == 0 {
		return ''
	}
	mut parts := []string{cap: vector.len}
	for value in vector {
		parts << value.str()
	}
	return parts.join(',')
}

fn decode_vector_text(raw string) ![]f32 {
	if raw.len == 0 {
		return []f32{}
	}
	parts := raw.split(',')
	mut vector := []f32{cap: parts.len}
	for part in parts {
		vector << f32(part.f64())
	}
	return vector
}

pub fn vector_cosine_similarity(a []f32, b []f32) f64 {
	limit := if a.len < b.len { a.len } else { b.len }
	if limit == 0 {
		return 0.0
	}
	mut dot := f64(0)
	mut a_norm := f64(0)
	mut b_norm := f64(0)
	for idx in 0 .. limit {
		av := f64(a[idx])
		bv := f64(b[idx])
		dot += av * bv
		a_norm += av * av
		b_norm += bv * bv
	}
	if a_norm == 0 || b_norm == 0 {
		return 0.0
	}
	return dot / (math.sqrt(a_norm) * math.sqrt(b_norm))
}
