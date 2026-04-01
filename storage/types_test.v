module storage

import time

fn test_table_def_requires_columns_and_primary_key() {
	id_col := ColumnDef.new('id', .i64_, false) or { panic(err) }
	name_col := ColumnDef.new('name', .string_, false) or { panic(err) }
	def := TableDef.new('users', [id_col, name_col], ['id']) or { panic(err) }

	assert def.name == 'users'
	assert def.has_column('name')
	assert (def.column('id') or { panic(err) }).typ == .i64_
	assert (def.primary_key_columns() or { panic(err) }).len == 1
}

fn test_column_def_sum_aggregate_requires_i64() {
	sum_col := ColumnDef.sum_i64('score', false) or { panic(err) }
	assert sum_col.aggregate == .sum
	assert sum_col.typ == .i64_
	if _ := ColumnDef.new_with_aggregate('name', .string_, false, .sum) {
		assert false
	} else {
		assert err.msg().contains('aggregate sum requires i64 column')
	}
}

fn test_typed_row_codec_roundtrip_preserves_types_and_nulls() {
	table := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('name', .string_, false) or { panic(err) },
		ColumnDef.new('email', .string_, true) or { panic(err) },
		ColumnDef.new('active', .bool_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	codec := TypedRowCodec.new(table)
	mut row := TypedRowData.new()
	row.set('id', i64(42))
	row.set('name', 'ada')
	row.set_null('email')
	row.set('active', true)

	encoded := codec.encode(row) or { panic(err) }
	decoded := codec.decode(encoded) or { panic(err) }

	id_value := decoded.get('id') or { panic(err) }
	name_value := decoded.get('name') or { panic(err) }
	email_value := decoded.get('email') or { panic(err) }
	active_value := decoded.get('active') or { panic(err) }

	assert id_value is i64 && id_value == i64(42)
	assert name_value is string && name_value == 'ada'
	assert email_value is NullValue
	assert active_value is bool && active_value == true
}

fn test_typed_row_codec_rejects_type_mismatch() {
	table := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	codec := TypedRowCodec.new(table)
	mut row := TypedRowData.new()
	row.set('id', 'not-an-int')

	if _ := codec.encode(row) {
		assert false
	} else {
		assert err.msg().contains('expects i64')
	}
}

fn test_typed_row_codec_decode_projected_reads_only_selected_columns() {
	table := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('name', .string_, false) or { panic(err) },
		ColumnDef.new('email', .string_, true) or { panic(err) },
		ColumnDef.new('active', .bool_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	codec := TypedRowCodec.new(table)
	mut row := TypedRowData.new()
	row.set('id', i64(42))
	row.set('name', 'ada')
	row.set_null('email')
	row.set('active', true)

	encoded := codec.encode(row) or { panic(err) }
	projected := codec.decode_projected(encoded, ['id', 'email']) or { panic(err) }

	assert projected.has('id')
	assert !projected.has('name')
	assert projected.has('email')
	id_value := projected.get('id') or { panic(err) }
	email_value := projected.get('email') or { panic(err) }
	assert id_value is i64 && id_value == i64(42)
	assert email_value is NullValue
}

fn test_typed_row_codec_decode_i64_column_reads_scalar_without_full_decode() {
	table := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('name', .string_, false) or { panic(err) },
		ColumnDef.new('active', .bool_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	codec := TypedRowCodec.new(table)
	mut row := TypedRowData.new()
	row.set('id', i64(42))
	row.set('name', 'ada')
	row.set('active', true)

	encoded := codec.encode(row) or { panic(err) }
	value := codec.decode_i64_column(encoded, 'id') or { panic(err) }
	assert value == i64(42)
}

fn test_typed_value_encoder_orders_i64_values_for_indexes() {
	column := ColumnDef.new('id', .i64_, false) or { panic(err) }
	neg := TypedValueEncoder.encode_index_value(i64(-10), column) or { panic(err) }
	zero := TypedValueEncoder.encode_index_value(i64(0), column) or { panic(err) }
	pos := TypedValueEncoder.encode_index_value(i64(10), column) or { panic(err) }

	assert compare_key_bytes(neg, zero) < 0
	assert compare_key_bytes(zero, pos) < 0
}

fn test_typed_value_encoder_orders_bool_and_handles_null() {
	bool_col := ColumnDef.new('active', .bool_, false) or { panic(err) }
	nullable_col := ColumnDef.new('email', .string_, true) or { panic(err) }
	false_encoded := TypedValueEncoder.encode_index_value(false, bool_col) or { panic(err) }
	true_encoded := TypedValueEncoder.encode_index_value(true, bool_col) or { panic(err) }
	null_encoded := TypedValueEncoder.encode_index_value(NullValue{}, nullable_col) or { panic(err) }
	value_encoded := TypedValueEncoder.encode_index_value('ada@example.com', nullable_col) or { panic(err) }

	assert compare_key_bytes(false_encoded, true_encoded) < 0
	assert compare_key_bytes(null_encoded, value_encoded) < 0
}

fn test_datetime_column_def_and_codec_roundtrip() {
	table := TableDef.new('events', [
		ColumnDef.new('id', .string_, false) or { panic(err) },
		ColumnDef.datetime_with_current_timestamp('created_at', false, false) or { panic(err) },
		ColumnDef.datetime_with_current_timestamp('updated_at', false, true) or { panic(err) },
	], ['id']) or { panic(err) }
	assert table.columns[1].typ == .datetime_
	assert table.columns[1].default_current_timestamp
	assert table.columns[2].auto_update_current_timestamp
	codec := TypedRowCodec.new(table)
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('created_at', current_datetime_string())
	row.set('updated_at', current_datetime_string())
	encoded := codec.encode(row) or { panic(err) }
	decoded := codec.decode(encoded) or { panic(err) }
	created_at := decoded.get('created_at') or { panic(err) }
	match created_at {
		string { _ := time.parse_rfc3339(created_at) or { panic(err) } }
		else { panic('expected datetime string') }
	}
}

fn test_markdown_ref_encode_decode_roundtrip() {
	ref := MarkdownRef{
		version: 1
		doc_root_id: 'doc:abc123'
		source_hash: 'src:def456'
		source_len: 1024
		ast_version: 3
		parse_flags: u32(7)
	}
	encoded := ref.encode()
	decoded := decode_markdown_ref(encoded) or { panic(err) }
	assert decoded == ref
}

fn test_typed_row_codec_roundtrip_preserves_markdown_ref() {
	table := TableDef.new('notes', [
		ColumnDef.new('id', .string_, false) or { panic(err) },
		ColumnDef.new('body', .markdown_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	codec := TypedRowCodec.new(table)
	mut row := TypedRowData.new()
	row.set('id', 'note-1')
	row.set('body', MarkdownRef{
		doc_root_id: 'doc:root-1'
		source_hash: 'src:hash-1'
		source_len: 2048
		ast_version: 1
		parse_flags: u32(0)
	})

	encoded := codec.encode(row) or { panic(err) }
	decoded := codec.decode(encoded) or { panic(err) }
	body := decoded.get('body') or { panic(err) }
	match body {
		MarkdownRef {
			assert body.doc_root_id == 'doc:root-1'
			assert body.source_hash == 'src:hash-1'
			assert body.source_len == 2048
			assert body.ast_version == 1
		}
		else {
			panic('expected markdown ref')
		}
	}
}

fn test_typed_value_encoder_rejects_invalid_markdown_ref() {
	column := ColumnDef.new('body', .markdown_, false) or { panic(err) }
	if _ := TypedValueEncoder.validate(column, MarkdownRef{
		doc_root_id: ''
		source_hash: 'src:hash-1'
		source_len: 1
		ast_version: 1
	}) {
		assert false
	} else {
		assert err.msg().contains('doc_root_id')
	}
}

fn test_typed_schema_view_put_and_get_roundtrip() {
	cfg := ChunkConfig{min_size: 64, max_size: 128, mask: 0}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('name', .string_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut seed := TypedRowData.new()
	seed.set('id', i64(1))
	seed.set('name', 'ada')
	base := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut view := TypedSchemaView.new(TableView.new(base, 'users'), codec)
	mut row := TypedRowData.new()
	row.set('id', i64(2))
	row.set('name', 'grace')
	view = view.put('002'.bytes(), row, cfg) or { panic(err) }

	got := view.get('002'.bytes()) or { panic(err) }
	assert got.primary_key.bytestr() == '002'
	name := got.data.get('name') or { panic(err) }
	assert name is string && name == 'grace'
}

fn test_typed_indexed_schema_view_put_updates_index() {
	cfg := ChunkConfig{min_size: 64, max_size: 128, mask: 0}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('email', .string_, false) or { panic(err) },
		ColumnDef.new('active', .bool_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut seed := TypedRowData.new()
	seed.set('id', i64(1))
	seed.set('email', 'ada@example.com')
	seed.set('active', true)
	base := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	schema := TypedSchemaView.new(TableView.new(base, 'users'), codec)
	mut indexed := TypedIndexedSchemaView.new(schema, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }

	mut inserted := TypedRowData.new()
	inserted.set('id', i64(2))
	inserted.set('email', 'grace@example.com')
	inserted.set('active', false)
	indexed = indexed.put('002'.bytes(), inserted, cfg) or { panic(err) }
	rows := indexed.find_by_index('email', 'grace@example.com', 0) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '002'

	mut updated := TypedRowData.new()
	updated.set('id', i64(2))
	updated.set('email', 'grace+new@example.com')
	updated.set('active', false)
	indexed = indexed.put('002'.bytes(), updated, cfg) or { panic(err) }
	old_rows := indexed.find_by_index('email', 'grace@example.com', 0) or { panic(err) }
	new_rows := indexed.find_by_index('email', 'grace+new@example.com', 0) or { panic(err) }
	assert old_rows.len == 0
	assert new_rows.len == 1
}

fn test_rebuild_typed_aggregates_for_specs_persists_sum_keys() {
	cfg := ChunkConfig{min_size: 64, max_size: 128, mask: 0}
	table_def := TableDef.new('metrics', [
		ColumnDef.sum_i64('id', false) or { panic(err) },
		ColumnDef.new('name', .string_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	spec := TypedTableSpec.new(table_def, []) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut row1 := TypedRowData.new()
	row1.set('id', i64(1))
	row1.set('name', 'a')
	mut row2 := TypedRowData.new()
	row2.set('id', i64(5))
	row2.set('name', 'b')
	base := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'metrics').key_for('001'.bytes())
			value: codec.encode(row1) or { panic(err) }
		},
		KVPair{
			key: TableView.new(Tree{}, 'metrics').key_for('005'.bytes())
			value: codec.encode(row2) or { panic(err) }
		},
	], cfg) or { panic(err) }
	rebuilt := rebuild_typed_aggregates_for_specs(base, [spec], cfg) or { panic(err) }
	item := rebuilt.get(encode_table_sum_aggregate_key('metrics', 'id')) or { panic(err) }
	value := TypedValueEncoder.decode_value(item.value, .i64_) or { panic(err) }
	match value {
		i64 { assert value == i64(6) }
		else { panic('expected i64 aggregate value') }
	}
}

fn test_typed_transaction_apply_write_set_handles_put_and_delete() {
	cfg := ChunkConfig{min_size: 64, max_size: 128, mask: 0}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('email', .string_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	spec := TypedTableSpec.new(table_def, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut seed := TypedRowData.new()
	seed.set('id', i64(1))
	seed.set('email', 'ada@example.com')
	base := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut tx := TypedTransaction.new(base)
	tx.register_table(spec) or { panic(err) }

	mut writes := TypedWriteSet.new()
	mut inserted := TypedRowData.new()
	inserted.set('id', i64(2))
	inserted.set('email', 'grace@example.com')
	writes.put('users', '002'.bytes(), inserted)
	writes.delete('users', '001'.bytes())

	result := tx.apply_write_set(writes, cfg) or { panic(err) }
	view := result.tx.indexed_view('users') or { panic(err) }
	old_rows := view.find_by_index('email', 'ada@example.com', 0) or { panic(err) }
	new_rows := view.find_by_index('email', 'grace@example.com', 0) or { panic(err) }

	assert result.diff.added_cids.len > 0
	assert old_rows.len == 0
	assert new_rows.len == 1
	assert new_rows[0].primary_key.bytestr() == '002'
}

fn test_typed_indexed_schema_view_fast_update_preserves_indexes_for_fixed_width_non_index_columns() {
	cfg := ChunkConfig{min_size: 64, max_size: 128, mask: 0}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('email', .string_, false) or { panic(err) },
		ColumnDef.new('active', .bool_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut seed := TypedRowData.new()
	seed.set('id', i64(1))
	seed.set('email', 'ada@example.com')
	seed.set('active', true)
	base := Tree.build([
		KVPair{
			key: 't|users|001'.bytes()
			value: codec.encode(seed) or { panic(err) }
		},
		KVPair{
			key: 'i|users|email|\x01ada@example.com|001'.bytes()
			value: []u8{}
		},
	], cfg) or { panic(err) }
	schema := TypedSchemaView.new(TableView.new(base, 'users'), codec)
	mut indexed := TypedIndexedSchemaView.new(schema, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }

	mut updated := TypedRowData.new()
	updated.set('id', i64(1))
	updated.set('email', 'ada@example.com')
	updated.set('active', false)
	indexed = indexed.put('001'.bytes(), updated, cfg) or { panic(err) }

	row := indexed.get('001'.bytes()) or { panic(err) }
	active := row.data.get('active') or { panic(err) }
	assert active is bool && active == false
	rows := indexed.find_by_index('email', 'ada@example.com', 0) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '001'
}

fn test_fts_query_validation_accepts_single_term_and_scoped_prefix() {
	validate_fts_query(FtsQuery{
		table_name: 'notes'
		column_name: 'body'
		scope: .heading
		kind: .prefix
		terms: ['Road']
		limit: 10
	}) or { panic(err) }
	assert fts_scope_name(.heading) == 'heading'
	assert fts_query_kind_name(.prefix) == 'prefix'
	assert fts_normalize_term('  RoadMap ') == 'roadmap'
}

fn test_fts_query_validation_rejects_empty_and_multi_term_prefix() {
	if _ := validate_fts_query(FtsQuery{
		table_name: 'notes'
		column_name: 'body'
		kind: .term
		terms: []string{}
	}) {
		panic('expected empty term list to fail')
	} else {
		assert err.msg().contains('at least one term')
	}
	if _ := validate_fts_query(FtsQuery{
		table_name: 'notes'
		column_name: 'body'
		kind: .prefix
		terms: ['road', 'map']
	}) {
		panic('expected multi-term prefix query to fail')
	} else {
		assert err.msg().contains('exactly one term')
	}
}

fn test_fts_tokenize_text_splits_and_normalizes_ascii_words() {
	tokens := fts_tokenize_text('Road-map v1 docs.example.com')
	assert tokens == ['road', 'map', 'v1', 'docs', 'example', 'com']
}

fn test_emit_markdown_fts_tokens_collects_scoped_terms() {
	tokens := emit_markdown_fts_tokens('# Intro\n\nParagraph about PollyDB.\n\n- list item\n\n```v\nprintln(\"ok\")\n```\n') or {
		panic(err)
	}
	assert tokens.len > 0
	assert tokens.any(it.scope == .heading && it.term == 'intro')
	assert tokens.any(it.scope == .paragraph && it.term == 'pollydb')
	assert tokens.any(it.scope == .list_item && it.term == 'list')
	assert tokens.any(it.scope == .code_block && it.term == 'println')
}

fn test_fts_distinct_keys_adds_scope_specific_and_any_scope_terms() {
	keys := fts_markdown_derived_keys('# Intro\n\nParagraph about PollyDB.\n') or { panic(err) }
	assert keys.any(it.scope == .heading && it.term == 'intro')
	assert keys.any(it.scope == .paragraph && it.term == 'pollydb')
	assert keys.any(it.scope == .any && it.term == 'intro')
	assert keys.any(it.scope == .any && it.term == 'pollydb')
}

fn test_fts_matches_query_supports_term_prefix_all_and_any() {
	keys := fts_markdown_derived_keys('# Intro\n\nParagraph about PollyDB merge.\n\n## Roadmap\n\nShip agent sync.\n') or {
		panic(err)
	}
	assert fts_matches_query(keys, FtsQuery{
		table_name: 'notes'
		column_name: 'body'
		scope: .heading
		kind: .term
		terms: ['roadmap']
	}) or { panic(err) }
	assert fts_matches_query(keys, FtsQuery{
		table_name: 'notes'
		column_name: 'body'
		scope: .heading
		kind: .prefix
		terms: ['road']
	}) or { panic(err) }
	assert fts_matches_query(keys, FtsQuery{
		table_name: 'notes'
		column_name: 'body'
		scope: .paragraph
		kind: .all
		terms: ['pollydb', 'merge']
	}) or { panic(err) }
	assert fts_matches_query(keys, FtsQuery{
		table_name: 'notes'
		column_name: 'body'
		scope: .any
		kind: .any
		terms: ['agent', 'missing']
	}) or { panic(err) }
	assert !(fts_matches_query(keys, FtsQuery{
		table_name: 'notes'
		column_name: 'body'
		scope: .paragraph
		kind: .term
		terms: ['roadmap']
	}) or { panic(err) })
}
