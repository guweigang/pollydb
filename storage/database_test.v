module storage

import os
import time

fn database_users_spec() !TypedTableSpec {
	table := TableDef.new('users', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('name', .string_, false)!,
		ColumnDef.new('email', .string_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.new('email', 'email')!,
	])
}

fn database_users_no_index_spec() !TypedTableSpec {
	table := TableDef.new('users', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('name', .string_, false)!,
		ColumnDef.new('email', .string_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [])
}

fn database_users_covering_spec() !TypedTableSpec {
	table := TableDef.new('users', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('name', .string_, false)!,
		ColumnDef.new('email', .string_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.covering('email', 'email')!,
	])
}

fn database_metrics_spec() !TypedTableSpec {
	table := TableDef.new('metrics', [
		ColumnDef.sum_i64('id', false)!,
		ColumnDef.new('name', .string_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [])
}

fn database_metrics_plain_spec() !TypedTableSpec {
	table := TableDef.new('metrics', [
		ColumnDef.new('id', .i64_, false)!,
		ColumnDef.new('name', .string_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [])
}

fn database_items_spec() !TypedTableSpec {
	table := TableDef.new('items', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.enum_string('status', ['active', 'draft', 'done'], false)!,
		ColumnDef.new('meta', .json_, false)!,
		ColumnDef.new('enabled', .bool_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.new('status_idx', 'status')!,
		SchemaIndexDef.json_path('kind_idx', 'meta', 'kind', .string_)!,
		SchemaIndexDef.json_path_covering('kind_cover', 'meta', 'kind', .string_)!,
		SchemaIndexDef.json_path_covering('enabled_idx', 'meta', 'enabled', .bool_)!,
	])
}

fn database_events_datetime_spec() !TypedTableSpec {
	table := TableDef.new('events', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.datetime_with_current_timestamp('created_at', false, false)!,
		ColumnDef.datetime_with_current_timestamp('updated_at', false, true)!,
	], ['id'])!
	return TypedTableSpec.new(table, [])
}

fn database_events_datetime_indexed_spec() !TypedTableSpec {
	table := TableDef.new('events', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.datetime('created_at', false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.new('created_at_idx', 'created_at')!,
	])
}

fn database_notes_spec() !TypedTableSpec {
	table := TableDef.new('notes', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [])
}

fn database_notes_indexed_spec() !TypedTableSpec {
	table := TableDef.new('notes', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.markdown_metric('body_link_count_idx', 'body', 'links')!,
		SchemaIndexDef.markdown_metric_covering('body_h2_count_cover', 'body', 'headings:2')!,
	])
}

fn database_notes_value_indexed_spec() !TypedTableSpec {
	table := TableDef.new('notes', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.markdown_value('body_link_host_idx', 'body', 'link_host')!,
		SchemaIndexDef.markdown_value_covering('body_code_lang_cover', 'body', 'code_block_lang')!,
		SchemaIndexDef.markdown_value('body_heading_text_idx', 'body', 'heading_text:2')!,
	])
}

fn database_notes_value_and_fts_indexed_spec() !TypedTableSpec {
	table := TableDef.new('notes', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.markdown_value('body_link_host_idx', 'body', 'link_host')!,
		SchemaIndexDef.markdown_value_covering('body_code_lang_cover', 'body', 'code_block_lang')!,
		SchemaIndexDef.markdown_value('body_heading_text_idx', 'body', 'heading_text:2')!,
		SchemaIndexDef.markdown_value('body_fts_any_idx', 'body', 'fts')!,
		SchemaIndexDef.markdown_value('body_fts_heading_idx', 'body', 'fts:heading')!,
	])
}

fn database_notes_fts_indexed_spec() !TypedTableSpec {
	table := TableDef.new('notes', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('title', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.markdown_value('body_fts_any_idx', 'body', 'fts')!,
		SchemaIndexDef.markdown_value('body_fts_heading_idx', 'body', 'fts:heading')!,
	])
}

fn database_docs_general_fts_spec() !TypedTableSpec {
	table := TableDef.new('docs', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('content_text', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!
	return TypedTableSpec.new(table, [
		SchemaIndexDef.fts_with_options('content_text_fts_idx', 'content_text', FtsIndexOptions{
			tokenizer:      'unicode61 remove_diacritics 2'
			prefix_lengths: [2, 3, 4]
		})!,
		SchemaIndexDef.fts_markdown_with_options('body_fts_idx', 'body', .visible_text_with_code,
			FtsIndexOptions{
			prefix_lengths: [2, 4]
		})!,
	])
}

fn database_seed_tree(spec TypedTableSpec, primary_key string, name string, email string, cfg ChunkConfig) !Tree {
	codec := TypedRowCodec.new(spec.table)
	mut row := TypedRowData.new()
	row.set('id', primary_key)
	row.set('name', name)
	row.set('email', email)
	return Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for(primary_key.bytes())
			value: codec.encode(row)!
		},
	], cfg)
}

fn test_persistent_database_typed_roundtrip() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-roundtrip')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('name', 'ada')
	row.set('email', 'ada@example.com')
	writes.put('users', '001'.bytes(), row)
	result := db.apply_typed_write_set('main', writes, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }
	assert result.update.branch.name == 'main'
	db.close() or { panic(err) }

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	assert reopened.branch_names() == ['main']
	assert reopened.table_names() == ['users']
	tx := reopened.begin_transaction('main') or { panic(err) }
	view := tx.indexed_view('users') or { panic(err) }
	found := view.get('001'.bytes()) or { panic(err) }
	name := found.data.get('name') or { panic(err) }
	match name {
		string { assert name == 'ada' }
		else { panic('expected string name') }
	}
	rows := view.find_by_index('email', 'ada@example.com', 0) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '001'
}

fn test_persistent_database_catalog_preserves_column_aggregates() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-catalog-aggregates')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_metrics_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.close() or { panic(err) }

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	loaded := reopened.table_spec('metrics') or { panic(err) }
	assert loaded.table.supports_sum_aggregate('id')
	assert !(loaded.table.supports_sum_aggregate('name'))
}

fn test_persistent_database_register_or_update_table_adds_indexes() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-update-table-indexes')
	defer {
		os.rmdir_all(dir) or {}
	}
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	spec_without_index := database_users_no_index_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec_without_index) or { panic(err) }
	seed_tree := database_seed_tree(spec_without_index, '001', 'ada', 'ada@example.com',
		cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }
	changed := db.register_or_update_table(database_users_spec() or { panic(err) }) or {
		panic(err)
	}
	assert changed
	_ = db.rebuild_indexes_at_branch('main', ['users'], cfg) or { panic(err) }
	db.close() or { panic(err) }

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	spec := reopened.table_spec('users') or { panic(err) }
	assert spec.indexes.len == 1
	assert spec.indexes[0].name == 'email'
	session := reopened.begin_session(SessionOptions.for_branch('main')) or { panic(err) }
	rows := session.lookup_index(mut reopened, 'users', 'email', 'ada@example.com', 10) or {
		panic(err)
	}
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '001'
}

fn test_database_session_lookup_index_ordered_projected_uses_covering_reader_path() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-ordered-projected')
	defer {
		os.rmdir_all(dir) or {}
	}
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	mut writes := TypedWriteSet.new()
	for triple in [
		['001', 'ada', 'ada@example.com'],
		['002', 'bea', 'bea@example.com'],
		['003', 'cy', 'cy@example.com'],
	] {
		mut row := TypedRowData.new()
		row.set('id', triple[0])
		row.set('name', triple[1])
		row.set('email', triple[2])
		writes.put('users', triple[0].bytes(), row)
	}
	_ = db.apply_typed_write_set('main', writes, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	rows := session.lookup_index_ordered_projected(mut db, 'users', 'email', ColumnValue(NullValue{}),
		false, []u8{}, 2, ['id', 'email'], true) or { panic(err) }
	assert rows.len == 2
	assert rows[0].primary_key.bytestr() == '003'
	assert rows[1].primary_key.bytestr() == '002'
	assert rows[0].data.has('id')
	assert rows[0].data.has('email')
	assert !rows[0].data.has('name')
	db.close() or { panic(err) }
}

fn test_persistent_database_can_begin_split_working_set() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-split-working-set')
	defer {
		os.rmdir_all(dir) or {}
	}
	cfg := ChunkConfig{
		min_size:                   64
		max_size:                   128
		mask:                       0
		enable_partitioned_rebuild: true
	}
	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('name', 'ada')
	row.set('email', 'ada@example.com')
	writes.put('users', '001'.bytes(), row)
	_ = db.apply_typed_write_set('main', writes, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }
	mut split_set := db.begin_split_working_set_with_specs('main', [spec], cfg) or { panic(err) }
	assert !split_set.has_changes(cfg)
	view := split_set.indexed_view('users') or { panic(err) }
	assert view.is_split_backed()
	found := view.get('001'.bytes()) or { panic(err) }
	assert found.primary_key.bytestr() == '001'
	rows := view.find_by_index('email', 'ada@example.com', 0) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '001'
	db.close() or { panic(err) }
}

fn test_persistent_database_split_backed_apply_matches_mixed_apply() {
	dir_mixed := os.join_path(os.vtmp_dir(), 'pollydb-database-split-apply-mixed')
	dir_split := os.join_path(os.vtmp_dir(), 'pollydb-database-split-apply-split')
	defer {
		os.rmdir_all(dir_mixed) or {}
		os.rmdir_all(dir_split) or {}
	}
	cfg := ChunkConfig{
		min_size:                   64
		max_size:                   128
		mask:                       0
		enable_partitioned_rebuild: true
	}
	spec := database_users_spec() or { panic(err) }
	mut db_mixed := PersistentDatabase.init(dir_mixed, 'main') or { panic(err) }
	mut db_split := PersistentDatabase.init(dir_split, 'main') or { panic(err) }
	db_mixed.register_table(spec) or { panic(err) }
	db_split.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db_mixed.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	_ = db_split.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut row_001 := TypedRowData.new()
	row_001.set('id', '001')
	row_001.set('name', 'ada')
	row_001.set('email', 'ada@example.com')
	mut row_002 := TypedRowData.new()
	row_002.set('id', '002')
	row_002.set('name', 'grace')
	row_002.set('email', 'grace@example.com')
	writes.put('users', '001'.bytes(), row_001)
	writes.put('users', '002'.bytes(), row_002)
	_ = db_mixed.apply_typed_write_set('main', writes, cfg, CommitMeta{
		author:    'gwg'
		message:   'mixed apply'
		timestamp: 1
	}) or { panic(err) }
	_ = db_split.apply_typed_write_set_split_backed('main', writes, cfg, CommitMeta{
		author:    'gwg'
		message:   'split apply'
		timestamp: 1
	}) or { panic(err) }
	tx_mixed := db_mixed.begin_transaction('main') or { panic(err) }
	tx_split := db_split.begin_transaction('main') or { panic(err) }
	view_mixed := tx_mixed.indexed_view('users') or { panic(err) }
	view_split := tx_split.indexed_view('users') or { panic(err) }
	assert view_mixed.get('001'.bytes()) or { panic(err) } == view_split.get('001'.bytes()) or {
		panic(err)
	}
	mixed_rows := view_mixed.find_by_index('email', 'grace@example.com', 0) or { panic(err) }
	split_rows := view_split.find_by_index('email', 'grace@example.com', 0) or { panic(err) }
	assert mixed_rows.len == split_rows.len
	assert split_rows.len == 1
	assert split_rows[0].primary_key.bytestr() == '002'
	db_mixed.close() or { panic(err) }
	db_split.close() or { panic(err) }
}

fn test_persistent_database_cfg_routed_split_backed_apply_matches_mixed_apply() {
	dir_mixed := os.join_path(os.vtmp_dir(), 'pollydb-database-cfg-split-apply-mixed')
	dir_split := os.join_path(os.vtmp_dir(), 'pollydb-database-cfg-split-apply-split')
	defer {
		os.rmdir_all(dir_mixed) or {}
		os.rmdir_all(dir_split) or {}
	}
	base_cfg := ChunkConfig{
		min_size:                   64
		max_size:                   128
		mask:                       0
		enable_partitioned_rebuild: true
	}
	split_cfg := base_cfg.with_split_backed_working_set(true)
	spec := database_users_spec() or { panic(err) }
	mut db_mixed := PersistentDatabase.init(dir_mixed, 'main') or { panic(err) }
	mut db_split := PersistentDatabase.init(dir_split, 'main') or { panic(err) }
	db_mixed.register_table(spec) or { panic(err) }
	db_split.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', base_cfg) or {
		panic(err)
	}
	_ = db_mixed.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	_ = db_split.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut row_001 := TypedRowData.new()
	row_001.set('id', '001')
	row_001.set('name', 'ada')
	row_001.set('email', 'ada@example.com')
	writes.put('users', '001'.bytes(), row_001)
	_ = db_mixed.apply_typed_write_set('main', writes, base_cfg, CommitMeta{
		author:    'gwg'
		message:   'mixed routed apply'
		timestamp: 1
	}) or { panic(err) }
	_ = db_split.apply_typed_write_set('main', writes, split_cfg, CommitMeta{
		author:    'gwg'
		message:   'split routed apply'
		timestamp: 1
	}) or { panic(err) }
	tx_mixed := db_mixed.begin_transaction('main') or { panic(err) }
	tx_split := db_split.begin_transaction('main') or { panic(err) }
	view_mixed := tx_mixed.indexed_view('users') or { panic(err) }
	view_split := tx_split.indexed_view('users') or { panic(err) }
	assert view_mixed.get('001'.bytes()) or { panic(err) } == view_split.get('001'.bytes()) or {
		panic(err)
	}
	db_mixed.close() or { panic(err) }
	db_split.close() or { panic(err) }
}

fn test_persistent_database_split_group_commit_roundtrip() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-split-group-commit')
	defer {
		os.rmdir_all(dir) or {}
	}
	cfg := ChunkConfig{
		min_size:                        64
		max_size:                        128
		mask:                            0
		enable_partitioned_rebuild:      true
		enable_split_backed_working_set: true
	}
	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	mut session := db.begin_default_split_group_commit_session(GroupCommitOptions{
		checkpoint_every: 1
		checkpoint_mode:  .data_only
	}, cfg) or { panic(err) }
	mut rows := map[string]TypedRowData{}
	mut row_001 := TypedRowData.new()
	row_001.set('id', '001')
	row_001.set('name', 'ada')
	row_001.set('email', 'ada@example.com')
	rows['001'] = row_001
	mut row_002 := TypedRowData.new()
	row_002.set('id', '002')
	row_002.set('name', 'grace')
	row_002.set('email', 'grace@example.com')
	rows['002'] = row_002
	_ = session.put_rows(mut db, 'users', rows, cfg, CommitMeta{
		author:    'gwg'
		message:   'split group commit'
		timestamp: 1
	}) or { panic(err) }
	session.finish(mut db) or { panic(err) }
	tx := db.begin_transaction('main') or { panic(err) }
	view := tx.indexed_view('users') or { panic(err) }
	assert (view.get('001'.bytes()) or { panic(err) }).primary_key.bytestr() == '001'
	assert (view.find_by_index('email', 'grace@example.com', 0) or { panic(err) }).len == 1
	db.close() or { panic(err) }
}

fn test_persistent_database_catalog_preserves_enum_json_and_json_path_indexes() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-catalog-enum-json')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_items_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.close() or { panic(err) }

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	loaded := reopened.table_spec('items') or { panic(err) }
	assert loaded.table.columns[1].typ == .enum_
	assert loaded.table.columns[1].enum_values == ['active', 'draft', 'done']
	assert loaded.table.columns[2].typ == .json_
	assert loaded.indexes.len == 4
	assert loaded.indexes[1].is_json_path()
	assert loaded.indexes[1].json_field == 'kind'
	assert loaded.indexes[1].json_field_type == .string_
	assert !loaded.indexes[1].stores_row
	assert loaded.indexes[2].is_json_path()
	assert loaded.indexes[2].json_field == 'kind'
	assert loaded.indexes[2].json_field_type == .string_
	assert loaded.indexes[2].stores_row
	assert loaded.indexes[3].is_json_path()
	assert loaded.indexes[3].json_field == 'enabled'
	assert loaded.indexes[3].json_field_type == .bool_
	assert loaded.indexes[3].stores_row
}

fn test_persistent_database_catalog_preserves_markdown_selector_indexes() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-catalog-markdown-indexes')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.close() or { panic(err) }

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	loaded := reopened.table_spec('notes') or { panic(err) }
	assert loaded.indexes.len == 2
	assert loaded.indexes[0].is_markdown_selector()
	assert loaded.indexes[0].markdown_selector == 'links'
	assert !loaded.indexes[0].stores_row
	assert loaded.indexes[1].is_markdown_selector()
	assert loaded.indexes[1].markdown_selector == 'headings:2'
	assert loaded.indexes[1].stores_row
}

fn test_persistent_database_catalog_preserves_markdown_value_indexes() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-catalog-markdown-value-indexes')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.close() or { panic(err) }

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	loaded := reopened.table_spec('notes') or { panic(err) }
	assert loaded.indexes.len == 3
	assert loaded.indexes[0].markdown_selector == 'link_host'
	assert loaded.indexes[0].json_field_type == .string_
	assert loaded.indexes[1].markdown_selector == 'code_block_lang'
	assert loaded.indexes[1].stores_row
	assert loaded.indexes[2].markdown_selector == 'heading_text:2'
}

fn test_persistent_database_catalog_preserves_general_fts_indexes() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-catalog-general-fts')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_docs_general_fts_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.close() or { panic(err) }

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	loaded := reopened.table_spec('docs') or { panic(err) }
	assert loaded.indexes.len == 2
	assert loaded.indexes[0].is_fts()
	assert loaded.indexes[0].fts_source_plugin == ''
	assert loaded.indexes[0].fts_text_mode == FtsTextMode.plain_text.str()
	assert loaded.indexes[0].fts_tokenizer == 'unicode61 remove_diacritics 2'
	assert loaded.indexes[0].fts_prefix_lengths == [2, 3, 4]
	assert loaded.indexes[1].is_fts()
	assert loaded.indexes[1].fts_source_plugin == 'markdown'
	assert loaded.indexes[1].fts_text_mode == FtsTextMode.visible_text_with_code.str()
	assert loaded.indexes[1].fts_tokenizer == 'unicode61'
	assert loaded.indexes[1].fts_prefix_lengths == [2, 4]
}

fn test_persistent_database_catalog_preserves_datetime_behaviors() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-catalog-datetime')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_events_datetime_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	db.close() or { panic(err) }

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	loaded := reopened.table_spec('events') or { panic(err) }
	assert loaded.table.columns[2].typ == .datetime_
	assert loaded.table.columns[2].default_current_timestamp
	assert !loaded.table.columns[2].auto_update_current_timestamp
	assert loaded.table.columns[3].default_current_timestamp
	assert loaded.table.columns[3].auto_update_current_timestamp
}

fn test_persistent_database_datetime_current_timestamp_and_auto_update() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-datetime-auto')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_events_datetime_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', '000')
	seed_row.set('title', 'seed')
	seed_row.set('created_at', current_datetime_string())
	seed_row.set('updated_at', current_datetime_string())
	mut seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }

	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('title', 'draft')
	_ = session.put_row(mut db, 'events', '001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert event'
		timestamp: 1
	}) or { panic(err) }
	inserted := session.get_row(mut db, 'events', '001'.bytes()) or { panic(err) }
	created_at := inserted.data.get('created_at') or { panic(err) }
	updated_at := inserted.data.get('updated_at') or { panic(err) }
	mut created_at_text := ''
	mut updated_at_text := ''
	match created_at {
		string {
			created_at_text = created_at
			_ := time.parse_rfc3339(created_at_text) or { panic(err) }
		}
		else {
			panic('expected created_at datetime string')
		}
	}
	match updated_at {
		string {
			updated_at_text = updated_at
			_ := time.parse_rfc3339(updated_at_text) or { panic(err) }
		}
		else {
			panic('expected updated_at datetime string')
		}
	}
	time.sleep(2 * time.millisecond)
	mut patch := TypedRowData.new()
	patch.set('title', 'published')
	_ = session.put_row(mut db, 'events', '001'.bytes(), patch, cfg, CommitMeta{
		author:    'gwg'
		message:   'update event'
		timestamp: 2
	}) or { panic(err) }
	updated := session.get_row(mut db, 'events', '001'.bytes()) or { panic(err) }
	next_created_at := updated.data.get('created_at') or { panic(err) }
	next_updated_at := updated.data.get('updated_at') or { panic(err) }
	match next_created_at {
		string { assert next_created_at == created_at_text }
		else { panic('expected created_at datetime string after update') }
	}
	match next_updated_at {
		string {
			assert next_updated_at != updated_at_text
			_ := time.parse_rfc3339(next_updated_at) or { panic(err) }
		}
		else {
			panic('expected updated_at datetime string after update')
		}
	}
	title := updated.data.get('title') or { panic(err) }
	match title {
		string { assert title == 'published' }
		else { panic('expected updated title') }
	}
}

fn test_persistent_database_datetime_index_between_lookup() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-datetime-between')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_events_datetime_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row1 := TypedRowData.new()
	row1.set('id', '001')
	row1.set('title', 'a')
	row1.set('created_at', '2026-03-30T10:00:00.000000Z')
	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('title', 'b')
	row2.set('created_at', '2026-03-30T11:00:00.000000Z')
	mut row3 := TypedRowData.new()
	row3.set('id', '003')
	row3.set('title', 'c')
	row3.set('created_at', '2026-03-30T12:00:00.000000Z')
	mut seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('001'.bytes())
			value: codec.encode(row1)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('002'.bytes())
			value: codec.encode(row2)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('003'.bytes())
			value: codec.encode(row3)!
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed events'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	rows := session.lookup_index_between(mut db, 'events', 'created_at_idx', '2026-03-30T10:30:00.000000Z',
		'2026-03-30T12:00:00.000000Z', 10) or { panic(err) }
	assert rows.len == 2
	assert rows[0].primary_key.bytestr() == '002'
	assert rows[1].primary_key.bytestr() == '003'
}

fn test_persistent_database_datetime_index_after_lookup() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-datetime-after')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_events_datetime_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row1 := TypedRowData.new()
	row1.set('id', '001')
	row1.set('title', 'a')
	row1.set('created_at', '2026-03-30T10:00:00.000000Z')
	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('title', 'b')
	row2.set('created_at', '2026-03-30T11:00:00.000000Z')
	mut row3 := TypedRowData.new()
	row3.set('id', '003')
	row3.set('title', 'c')
	row3.set('created_at', '2026-03-30T12:00:00.000000Z')
	mut seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('001'.bytes())
			value: codec.encode(row1)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('002'.bytes())
			value: codec.encode(row2)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('003'.bytes())
			value: codec.encode(row3)!
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed events'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	rows := session.lookup_index_after(mut db, 'events', 'created_at_idx', '2026-03-30T11:00:00.000000Z',
		10) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '003'
}

fn test_persistent_database_datetime_index_before_lookup() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-datetime-before')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_events_datetime_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row1 := TypedRowData.new()
	row1.set('id', '001')
	row1.set('title', 'a')
	row1.set('created_at', '2026-03-30T10:00:00.000000Z')
	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('title', 'b')
	row2.set('created_at', '2026-03-30T11:00:00.000000Z')
	mut row3 := TypedRowData.new()
	row3.set('id', '003')
	row3.set('title', 'c')
	row3.set('created_at', '2026-03-30T12:00:00.000000Z')
	mut seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('001'.bytes())
			value: codec.encode(row1)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('002'.bytes())
			value: codec.encode(row2)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('003'.bytes())
			value: codec.encode(row3)!
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed events'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	rows := session.lookup_index_before(mut db, 'events', 'created_at_idx', '2026-03-30T11:00:00.000000Z',
		10) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '001'
}

fn test_persistent_database_json_path_indexes_lookup() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-json-path-index')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_items_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', '000')
	seed_row.set('status', 'draft')
	seed_row.set('meta', '{"kind":"seed","enabled":false}')
	seed_row.set('enabled', false)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('status', 'active')
	row.set('meta', '{"kind":"alpha","enabled":true}')
	row.set('enabled', true)
	_ = session.put_row(mut db, 'items', '001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'put item'
		timestamp: 1
	}) or { panic(err) }

	status_rows := session.lookup_index(mut db, 'items', 'status_idx', 'active', 10) or {
		panic(err)
	}
	assert status_rows.len == 1
	kind_rows := session.lookup_index(mut db, 'items', 'kind_idx', 'alpha', 10) or { panic(err) }
	assert kind_rows.len == 1
	enabled_rows := session.lookup_index(mut db, 'items', 'enabled_idx', true, 10) or { panic(err) }
	assert enabled_rows.len == 1
	loaded_status := enabled_rows[0].data.get('status') or { panic(err) }
	match loaded_status {
		string { assert loaded_status == 'active' }
		else { panic('expected decoded row from covering json-path index') }
	}
}

fn test_persistent_database_nested_json_path_indexes_lookup() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-nested-json-path-index')
	defer {
		os.rmdir_all(dir) or {}
	}

	table := TableDef.new('items', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.enum_string('status', ['active', 'draft'], false)!,
		ColumnDef.new('meta', .json_, false)!,
	], ['id'])!
	spec := TypedTableSpec.new(table, [
		SchemaIndexDef.json_path('kind_code_idx', 'meta', 'kind.code', .string_)!,
		SchemaIndexDef.json_path_covering('kind_code_cover', 'meta', 'kind.code', .string_)!,
	]) or { panic(err) }

	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut seed_row := TypedRowData.new()
	seed_row.set('id', '000')
	seed_row.set('status', 'draft')
	seed_row.set('meta', '{"kind":{"code":"seed.zero"}}')
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: TypedRowCodec.new(spec.table).encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row1 := TypedRowData.new()
	row1.set('id', '001')
	row1.set('status', 'active')
	row1.set('meta', '{"kind":{"code":"alpha.one"}}')
	_ = session.put_row(mut db, 'items', '001'.bytes(), row1, cfg, CommitMeta{
		author:    'gwg'
		message:   'put first item'
		timestamp: 1
	}) or { panic(err) }
	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('status', 'draft')
	row2.set('meta', '{"kind":{"code":"alpha.two"}}')
	_ = session.put_row(mut db, 'items', '002'.bytes(), row2, cfg, CommitMeta{
		author:    'gwg'
		message:   'put second item'
		timestamp: 2
	}) or { panic(err) }

	exact_rows := session.lookup_index(mut db, 'items', 'kind_code_idx', 'alpha.one',
		10) or { panic(err) }
	assert exact_rows.len == 1
	assert exact_rows[0].primary_key.bytestr() == '001'

	projected_rows := session.lookup_index_prefix_projected(mut db, 'items', 'kind_code_cover',
		'alpha.', 10, [
		'status',
	]) or { panic(err) }
	assert projected_rows.len == 2
	assert projected_rows[0].data.has('status')
	assert !projected_rows[0].data.has('meta')
	assert !projected_rows[0].data.has('id')
}

fn test_database_session_set_json_path_updates_json_indexes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-set-json-path')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_items_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut seed_row := TypedRowData.new()
	seed_row.set('id', '000')
	seed_row.set('status', 'draft')
	seed_row.set('meta', '{"kind":"seed.zero","enabled":false}')
	seed_row.set('enabled', false)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: TypedRowCodec.new(spec.table).encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('status', 'active')
	row.set('meta', '{"kind":"alpha","enabled":true}')
	row.set('enabled', true)
	_ = session.put_row(mut db, 'items', '001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'put item'
		timestamp: 1
	}) or { panic(err) }

	before := session.lookup_index(mut db, 'items', 'kind_idx', 'alpha', 10) or { panic(err) }
	assert before.len == 1
	_ = session.set_json_path(mut db, 'items', '001'.bytes(), 'meta', 'kind', 'beta',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'set json path'
		timestamp: 2
	}) or { panic(err) }
	after_old := session.lookup_index(mut db, 'items', 'kind_idx', 'alpha', 10) or { panic(err) }
	after_new := session.lookup_index(mut db, 'items', 'kind_idx', 'beta', 10) or { panic(err) }
	assert after_old.len == 0
	assert after_new.len == 1
	loaded := session.get_row(mut db, 'items', '001'.bytes()) or { panic(err) }
	meta := loaded.data.get('meta') or { panic(err) }
	match meta {
		string { assert meta.contains('"kind":"beta"') }
		else { panic('expected updated json payload') }
	}
}

fn test_database_session_patch_delete_and_null_json_paths() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-patch-json-path')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_items_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut seed_row := TypedRowData.new()
	seed_row.set('id', '000')
	seed_row.set('status', 'draft')
	seed_row.set('meta', '{"kind":"seed.zero","enabled":false}')
	seed_row.set('enabled', false)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: TypedRowCodec.new(spec.table).encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('status', 'active')
	row.set('meta', '{"kind":"alpha","enabled":true,"legacy":"old"}')
	row.set('enabled', true)
	_ = session.put_row(mut db, 'items', '001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'put item'
		timestamp: 1
	}) or { panic(err) }

	_ = session.set_json_path_null(mut db, 'items', '001'.bytes(), 'meta', 'kind', cfg,
		CommitMeta{
		author:    'gwg'
		message:   'null kind'
		timestamp: 2
	}) or { panic(err) }
	null_lookup := session.lookup_index(mut db, 'items', 'kind_idx', NullValue{}, 10) or {
		panic(err)
	}
	assert null_lookup.len == 1

	_ = session.delete_json_path(mut db, 'items', '001'.bytes(), 'meta', 'legacy', cfg,
		CommitMeta{
		author:    'gwg'
		message:   'delete legacy'
		timestamp: 3
	}) or { panic(err) }

	_ = session.patch_json_paths(mut db, 'items', '001'.bytes(), 'meta', [
		JsonPathUpdate{
			path:  'kind'
			op:    .set
			value: 'gamma'
		},
		JsonPathUpdate{
			path:  'enabled'
			op:    .set
			value: false
		},
	], cfg, CommitMeta{
		author:    'gwg'
		message:   'patch json'
		timestamp: 4
	}) or { panic(err) }

	old_kind := session.lookup_index(mut db, 'items', 'kind_idx', 'alpha', 10) or { panic(err) }
	new_kind := session.lookup_index(mut db, 'items', 'kind_idx', 'gamma', 10) or { panic(err) }
	enabled_false := session.lookup_index(mut db, 'items', 'enabled_idx', false, 10) or {
		panic(err)
	}
	assert old_kind.len == 0
	assert new_kind.len == 1
	assert enabled_false.len == 1

	loaded := session.get_row(mut db, 'items', '001'.bytes()) or { panic(err) }
	meta := loaded.data.get('meta') or { panic(err) }
	match meta {
		string {
			assert meta.contains('"kind":"gamma"')
			assert meta.contains('"enabled":false')
			assert !meta.contains('"legacy"')
		}
		else {
			panic('expected patched json payload')
		}
	}
}

fn test_persistent_database_commit_typed_working_set() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-working-set')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or {
		panic(err)
	}
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	defer {
		db.close() or {}
	}
	mut set := db.begin_working_set('main') or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	writes.put('users', '002'.bytes(), row)
	_ = set.apply_write_set(writes, cfg) or { panic(err) }
	assert set.has_changes()
	update := db.commit_typed_working_set(mut set, CommitMeta{
		author:    'gwg'
		message:   'commit working set'
		timestamp: 2
	}) or { panic(err) }
	assert update.update.branch.name == 'main'
	assert !set.has_changes()

	tx := db.begin_transaction('main') or { panic(err) }
	view := tx.indexed_view('users') or { panic(err) }
	row2 := view.get('002'.bytes()) or { panic(err) }
	email := row2.data.get('email') or { panic(err) }
	match email {
		string { assert email == 'grace@example.com' }
		else { panic('expected string email') }
	}
}

fn test_persistent_database_session_roundtrip() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-session')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or {
		panic(err)
	}
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	assert session.table_names() == ['users']
	mut tx_session := session.begin_working_set(mut db) or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut row := TypedRowData.new()
	row.set('id', '003')
	row.set('name', 'linus')
	row.set('email', 'linus@example.com')
	writes.put('users', '003'.bytes(), row)
	_ = tx_session.apply_write_set(writes, cfg) or { panic(err) }
	assert tx_session.has_changes()
	status := tx_session.status() or { panic(err) }
	assert status.tables.len == 1
	assert status.tables[0].row_changes.len == 1
	_ = tx_session.commit(mut db, CommitMeta{
		author:    'gwg'
		message:   'session commit'
		timestamp: 2
	}) or { panic(err) }

	tx := session.begin_transaction(mut db) or { panic(err) }
	view := tx.indexed_view('users') or { panic(err) }
	loaded := view.get('003'.bytes()) or { panic(err) }
	name := loaded.data.get('name') or { panic(err) }
	match name {
		string { assert name == 'linus' }
		else { panic('expected string name') }
	}
}

fn test_persistent_database_session_put_rows_roundtrip() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-session-put-rows')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or {
		panic(err)
	}
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut rows := map[string]TypedRowData{}
	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('name', 'grace')
	row2.set('email', 'grace@example.com')
	rows['002'] = row2
	mut row3 := TypedRowData.new()
	row3.set('id', '003')
	row3.set('name', 'linus')
	row3.set('email', 'linus@example.com')
	rows['003'] = row3
	_ = session.put_rows(mut db, 'users', rows, cfg, CommitMeta{
		author:    'gwg'
		message:   'bulk session put rows'
		timestamp: 2
	}) or { panic(err) }

	tx := db.begin_transaction('main') or { panic(err) }
	view := tx.indexed_view('users') or { panic(err) }
	found := view.find_by_index('email', 'grace@example.com', 10) or { panic(err) }
	assert found.len == 1
	assert found[0].primary_key.bytestr() == '002'
	loaded := view.get('003'.bytes()) or { panic(err) }
	name := loaded.data.get('name') or { panic(err) }
	match name {
		string { assert name == 'linus' }
		else { panic('expected string name') }
	}
}

fn test_persistent_database_markdown_ref_helpers_roundtrip() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-markdown-session')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Seed')
	seed.set('body', MarkdownRef{
		doc_root_id: 'doc:seed'
		source_hash: 'src:seed'
		source_len:  12
		ast_version: 1
		parse_flags: u32(0)
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	current := session.get_markdown_ref(mut db, 'notes', 'note-1'.bytes(), 'body') or { panic(err) }
	assert current.doc_root_id == 'doc:seed'

	updated := MarkdownRef{
		doc_root_id: 'doc:next'
		source_hash: 'src:next'
		source_len:  48
		ast_version: 1
		parse_flags: u32(3)
	}
	_ = session.put_markdown_ref(mut db, 'notes', 'note-1'.bytes(), 'body', updated, cfg,
		CommitMeta{
		author:    'gwg'
		message:   'update markdown ref'
		timestamp: 2
	}) or { panic(err) }

	reloaded := session.get_markdown_ref(mut db, 'notes', 'note-1'.bytes(), 'body') or {
		panic(err)
	}
	assert reloaded.doc_root_id == 'doc:next'
	assert reloaded.source_hash == 'src:next'
	assert reloaded.source_len == 48
}

fn test_persistent_database_put_markdown_persists_source_and_ref() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-markdown-ingest')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Seed')
	seed.set('body', MarkdownRef{
		doc_root_id: 'doc:seed'
		source_hash: 'src:seed'
		source_len:  4
		ast_version: 1
		parse_flags: u32(0)
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	raw := '# Hello\n\nThis is **markdown**.\n'
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', raw, cfg, CommitMeta{
		author:    'gwg'
		message:   'store markdown'
		timestamp: 2
	}) or { panic(err) }

	ref := session.get_markdown_ref(mut db, 'notes', 'note-1'.bytes(), 'body') or { panic(err) }
	assert ref.doc_root_id.starts_with('doc:')
	assert ref.source_len == raw.len
	loaded := session.get_markdown(mut db, 'notes', 'note-1'.bytes(), 'body') or { panic(err) }
	assert loaded == raw
}

fn test_external_field_storage_helpers_roundtrip_markdown() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-external-field-markdown')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	column := ColumnDef.new('body', .markdown_, false) or { panic(err) }
	raw := ColumnValue('# Hello\n\nPlugin-backed markdown.\n')
	stored := ingest_external_field_value(mut db, column, raw) or { panic(err) }
	assert stored is MarkdownRef
	loaded := load_external_field_value(db, column, stored) or { panic(err) }
	assert loaded is string
	assert loaded as string == '# Hello\n\nPlugin-backed markdown.\n'
	assert db.field_plugin_names() == ['markdown']
}

fn test_aggregate_projection_def_exposes_field_projection_metadata() {
	def := AggregateProjectionDef.count_field_selector('count(notes.body.links)', 'notes',
		'body', 'markdown', 'links') or { panic(err) }
	assert def.is_field_projection_selector()
	assert def.field_projection_plugin() == 'markdown'
	assert def.field_projection_selector() == 'links'
	selector_ref := def.field_projection_selector_ref() or {
		panic('expected field projection selector ref')
	}
	assert selector_ref.plugin_name == 'markdown'
	assert selector_ref.selector == 'links'
	selector_meta := def.field_projection_meta() or { panic('expected field projection meta') }
	assert selector_meta.plugin_name == 'markdown'
	assert selector_meta.selector == 'links'
	assert selector_meta.value_type == .i64_
	assert !selector_meta.stores_row
	assert def.source_markdown_selector == 'links'
}

fn test_persistent_database_accepts_explicit_field_capability_registry() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-field-registry-explicit')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	mut registry := FieldCapabilityRegistry.new()
	registry.install_markdown_defaults()
	db.set_field_capability_registry(registry)
	assert db.field_plugin_names() == ['markdown']
	column := ColumnDef.new('body', .markdown_, false) or { panic(err) }
	stored := ingest_external_field_value(mut db, column, ColumnValue('# Explicit registry\n')) or {
		panic(err)
	}
	assert stored is MarkdownRef
}

fn test_persistent_database_diff_markdown_refs_reports_structural_changes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-markdown-diff')
	defer {
		os.rmdir_all(dir) or {}
	}

	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	left := db.ingest_markdown('# Title\n\nFirst paragraph.\n') or { panic(err) }
	right := db.ingest_markdown('# Title\n\nFirst paragraph changed.\n\n## Next\n\nMore text.\n') or {
		panic(err)
	}
	diff := db.diff_markdown_refs(left, right) or { panic(err) }
	assert diff.left_root_id == left.doc_root_id
	assert diff.right_root_id == right.doc_root_id
	assert diff.entries.len > 0
	assert diff.entries.any(it.op == .edited || it.op == .added)
	_ = cfg
}

fn test_persistent_database_markdown_selector_indexes_lookup_after_commit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-markdown-selector-indexes-lookup')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row := TypedRowData.new()
	row.set('id', 'note-1')
	row.set('title', 'Doc')
	row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Intro\n\n[docs](https://example.com)\n\n## Details\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'insert markdown'
		timestamp: 2
	}) or { panic(err) }

	link_rows := session.lookup_index(mut db, 'notes', 'body_link_count_idx', i64(1),
		10) or { panic(err) }
	assert link_rows.len == 1
	assert link_rows[0].primary_key.bytestr() == 'note-1'

	h2_rows := session.lookup_index(mut db, 'notes', 'body_h2_count_cover', i64(1), 10) or {
		panic(err)
	}
	assert h2_rows.len == 1
	title := h2_rows[0].data.get('title') or { panic(err) }
	match title {
		string { assert title == 'Doc' }
		else { panic('expected title in covering markdown index row') }
	}
}

fn test_transaction_session_markdown_selector_indexes_are_live_before_commit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-markdown-selector-indexes-transaction-live')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row := TypedRowData.new()
	row.set('id', 'note-1')
	row.set('title', 'Draft')
	row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut tx := session.begin_working_set(mut db) or { panic(err) }
	_ = tx.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Intro\n\n[docs](https://example.com)\n\n## Details\n',
		cfg) or { panic(err) }

	link_rows := tx.lookup_index('notes', 'body_link_count_idx', i64(1), 10) or { panic(err) }
	assert link_rows.len == 1
	assert link_rows[0].primary_key.bytestr() == 'note-1'

	before_rows := tx.lookup_index_before('notes', 'body_h2_count_cover', i64(2), 10) or {
		panic(err)
	}
	assert before_rows.len == 1

	between_rows := tx.lookup_index_between('notes', 'body_h2_count_cover', i64(1), i64(1),
		10) or { panic(err) }
	assert between_rows.len == 1
}

fn test_transaction_session_lookup_index_prefix() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-tx-index-prefix')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or {
		panic(err)
	}
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut tx := session.begin_working_set(mut db) or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = tx.put_row('users', '002'.bytes(), row, cfg) or { panic(err) }

	rows := tx.lookup_index_prefix('users', 'email', 'gr', 10) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '002'
}

fn test_persistent_database_lookup_index_before_reverse() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-index-before-reverse')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_events_datetime_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row1 := TypedRowData.new()
	row1.set('id', '001')
	row1.set('title', 'a')
	row1.set('created_at', '2026-03-30T10:00:00.000000Z')
	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('title', 'b')
	row2.set('created_at', '2026-03-30T11:00:00.000000Z')
	mut row3 := TypedRowData.new()
	row3.set('id', '003')
	row3.set('title', 'c')
	row3.set('created_at', '2026-03-30T12:00:00.000000Z')
	mut seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('001'.bytes())
			value: codec.encode(row1)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('002'.bytes())
			value: codec.encode(row2)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('003'.bytes())
			value: codec.encode(row3)!
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	rows := session.lookup_index_before_reverse(mut db, 'events', 'created_at_idx', '2026-03-30T12:00:00.000000Z',
		10) or { panic(err) }
	assert rows.len == 2
	assert rows[0].primary_key.bytestr() == '002'
	assert rows[1].primary_key.bytestr() == '001'
	title := rows[0].data.get('title') or { panic(err) }
	match title {
		string { assert title == 'b' }
		else { panic('expected string title') }
	}
}

fn test_transaction_session_markdown_selector_index_cursor_supports_iteration() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-markdown-selector-index-cursor')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row1 := TypedRowData.new()
	row1.set('id', 'note-1')
	row1.set('title', 'One')
	row1.set('body', MarkdownRef{
		doc_root_id: 'seed-1'
		source_hash: 'seed-1'
		source_len:  0
	})
	mut row2 := TypedRowData.new()
	row2.set('id', 'note-2')
	row2.set('title', 'Two')
	row2.set('body', MarkdownRef{
		doc_root_id: 'seed-2'
		source_hash: 'seed-2'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(row1)!
		},
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-2'.bytes())
			value: codec.encode(row2)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut tx := session.begin_working_set(mut db) or { panic(err) }
	_ = tx.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Intro\n\n[one](https://example.com/1)\n',
		cfg) or { panic(err) }
	_ = tx.put_markdown(mut db, 'notes', 'note-2'.bytes(), 'body', '# Intro\n\n[two](https://example.com/2)\n',
		cfg) or { panic(err) }

	mut cursor := tx.index_cursor('notes', 'body_link_count_idx', i64(1), []u8{}, 10) or {
		panic(err)
	}
	peeked := cursor.peek() or { panic(err) }
	assert peeked.primary_key.bytestr() == 'note-1'
	first := cursor.next() or { panic(err) }
	assert first.primary_key.bytestr() == 'note-1'
	second := cursor.next() or { panic(err) }
	assert second.primary_key.bytestr() == 'note-2'

	mut seeked := tx.index_cursor('notes', 'body_link_count_idx', i64(1), []u8{}, 10) or {
		panic(err)
	}
	seek_key := TypedValueEncoder.encode_index_value(i64(1), ColumnDef.new('markdown_metric',
		.i64_, false) or { panic(err) }) or { panic(err) }
	seeked.seek(seek_key, 'note-2'.bytes()) or { panic(err) }
	current := seeked.current() or { panic(err) }
	assert current.primary_key.bytestr() == 'note-2'

	mut collected_cursor := tx.index_cursor('notes', 'body_link_count_idx', i64(1), []u8{},
		10) or { panic(err) }
	collected := collected_cursor.collect(10) or { panic(err) }
	assert collected.len == 2
}

fn test_persistent_database_markdown_value_indexes_lookup_and_prefix_after_commit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-markdown-value-indexes-lookup')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row := TypedRowData.new()
	row.set('id', 'note-1')
	row.set('title', 'Doc')
	row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '## Roadmap\n\n[docs](https://docs.example.com/a)\n\n```v\nprintln("ok")\n```\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'insert markdown'
		timestamp: 2
	}) or { panic(err) }

	host_rows := session.lookup_index(mut db, 'notes', 'body_link_host_idx', 'docs.example.com',
		10) or { panic(err) }
	assert host_rows.len == 1
	assert host_rows[0].primary_key.bytestr() == 'note-1'

	heading_rows := session.lookup_index_prefix(mut db, 'notes', 'body_heading_text_idx',
		'Road', 10) or { panic(err) }
	assert heading_rows.len == 1

	lang_rows := session.lookup_index(mut db, 'notes', 'body_code_lang_cover', 'v', 10) or {
		panic(err)
	}
	assert lang_rows.len == 1
	title := lang_rows[0].data.get('title') or { panic(err) }
	match title {
		string { assert title == 'Doc' }
		else { panic('expected covering value index row') }
	}
}

fn test_transaction_session_markdown_value_index_cursor_supports_iteration() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-markdown-value-index-cursor')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row1 := TypedRowData.new()
	row1.set('id', 'note-1')
	row1.set('title', 'One')
	row1.set('body', MarkdownRef{
		doc_root_id: 'seed-1'
		source_hash: 'seed-1'
		source_len:  0
	})
	mut row2 := TypedRowData.new()
	row2.set('id', 'note-2')
	row2.set('title', 'Two')
	row2.set('body', MarkdownRef{
		doc_root_id: 'seed-2'
		source_hash: 'seed-2'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(row1)!
		},
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-2'.bytes())
			value: codec.encode(row2)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut tx := session.begin_working_set(mut db) or { panic(err) }
	_ = tx.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '[one](https://docs.example.com/1)\n',
		cfg) or { panic(err) }
	_ = tx.put_markdown(mut db, 'notes', 'note-2'.bytes(), 'body', '[two](https://docs.example.com/2)\n',
		cfg) or { panic(err) }

	mut cursor := tx.index_cursor('notes', 'body_link_host_idx', 'docs.example.com', []u8{},
		10) or { panic(err) }
	assert (cursor.peek() or { panic(err) }).primary_key.bytestr() == 'note-1'
	assert (cursor.next() or { panic(err) }).primary_key.bytestr() == 'note-1'
	assert (cursor.next() or { panic(err) }).primary_key.bytestr() == 'note-2'
}

fn test_persistent_database_preview_markdown_merge_refs_returns_merged_source() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-preview-markdown-merge-refs')
	defer {
		os.rmdir_all(dir) or {}
	}

	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	base := db.ingest_markdown('# Title\n\nOne.\n\nTwo.\n') or { panic(err) }
	ours := db.ingest_markdown('# Title\n\nOne updated.\n\nTwo.\n') or { panic(err) }
	theirs := db.ingest_markdown('# Title\n\nOne.\n\nTwo updated.\n') or { panic(err) }
	preview := db.preview_markdown_merge_refs(base, ours, theirs) or { panic(err) }
	assert preview.mergeable
	assert preview.base_to_ours.entries.len > 0
	assert preview.base_to_theirs.entries.len > 0
	assert preview.merged_ref.doc_root_id.starts_with('doc:')
	assert preview.merged_source.contains('One updated.')
	assert preview.merged_source.contains('Two updated.')
	_ = cfg
}

fn test_persistent_database_merge_markdown_refs_returns_new_ref() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-markdown-refs')
	defer {
		os.rmdir_all(dir) or {}
	}

	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	base := db.ingest_markdown('# Title\n\nAlpha.\n\nBeta.\n') or { panic(err) }
	ours := db.ingest_markdown('# Title\n\nAlpha main.\n\nBeta.\n') or { panic(err) }
	theirs := db.ingest_markdown('# Title\n\nAlpha.\n\nBeta feature.\n') or { panic(err) }
	merged := db.merge_markdown_refs(base, ours, theirs) or { panic(err) }
	assert merged.doc_root_id.starts_with('doc:')
	merged_raw := db.load_markdown(merged) or { panic(err) }
	assert merged_raw.contains('Alpha main.')
	assert merged_raw.contains('Beta feature.')
	_ = cfg
}

fn test_persistent_database_merge_auto_resolves_distinct_row_columns_with_markdown() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-markdown-row-columns')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	initial_body := db.ingest_markdown('# Seed\n\nBase body.\n') or { panic(err) }
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Original')
	seed.set('body', initial_body)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_update := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed_update.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	mut main_row := TypedRowData.new()
	main_row.set('id', 'note-1')
	main_row.set('title', 'Main Title')
	main_row.set('body', initial_body)
	_ = main_session.put_row(mut db, 'notes', 'note-1'.bytes(), main_row, cfg, CommitMeta{
		author:    'gwg'
		message:   'main title update'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	_ = feature_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Seed\n\nFeature body update.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'feature body update'
		timestamp: 3
	}) or { panic(err) }

	mut merge_session := main_session.begin_working_set(mut db) or { panic(err) }
	result := merge_session.merge_from(mut db, 'feature', [], cfg) or { panic(err) }
	assert result.resolution.resolved_keys.len == 1
	merged_row := merge_session.get_row('notes', 'note-1'.bytes()) or { panic(err) }
	title := merged_row.data.get('title') or { panic(err) }
	match title {
		string { assert title == 'Main Title' }
		else { panic('expected merged title string') }
	}
	merged_ref := merge_session.get_markdown_ref('notes', 'note-1'.bytes(), 'body') or {
		panic(err)
	}
	merged_markdown := db.load_markdown(merged_ref) or { panic(err) }
	assert merged_markdown.contains('Feature body update.')
}

fn test_persistent_database_merge_auto_resolves_markdown_field_disjoint_top_level_blocks() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-markdown-field-top-level')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	initial_body := db.ingest_markdown('# Title\n\nFirst paragraph.\n\nSecond paragraph.\n') or {
		panic(err)
	}
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Original')
	seed.set('body', initial_body)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_update := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed_update.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	_ = main_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Title\n\nFirst paragraph updated on main.\n\nSecond paragraph.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'main markdown update'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	_ = feature_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Title\n\nFirst paragraph.\n\nSecond paragraph updated on feature.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'feature markdown update'
		timestamp: 3
	}) or { panic(err) }

	mut merge_session := main_session.begin_working_set(mut db) or { panic(err) }
	result := merge_session.merge_from(mut db, 'feature', [], cfg) or { panic(err) }
	assert result.resolution.resolved_keys.len == 1
	merged_ref := merge_session.get_markdown_ref('notes', 'note-1'.bytes(), 'body') or {
		panic(err)
	}
	merged_markdown := db.load_markdown(merged_ref) or { panic(err) }
	assert merged_markdown.contains('First paragraph updated on main.')
	assert merged_markdown.contains('Second paragraph updated on feature.')
}

fn test_persistent_database_merge_auto_resolves_markdown_nested_blockquote_list_changes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-markdown-nested-blockquote-list')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	base_raw := '> intro\n>\n> - alpha\n> - beta\n'
	initial_body := db.ingest_markdown(base_raw) or { panic(err) }
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Original')
	seed.set('body', initial_body)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_update := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed markdown'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed_update.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	_ = main_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '> intro updated on main\n>\n> - alpha\n> - beta\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'main nested markdown update'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	_ = feature_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '> intro\n>\n> - alpha\n> - beta updated on feature\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'feature nested markdown update'
		timestamp: 3
	}) or { panic(err) }

	mut merge_session := main_session.begin_working_set(mut db) or { panic(err) }
	_ = merge_session.merge_from(mut db, 'feature', [], cfg) or { panic(err) }
	merged_ref := merge_session.get_markdown_ref('notes', 'note-1'.bytes(), 'body') or {
		panic(err)
	}
	merged_markdown := db.load_markdown(merged_ref) or { panic(err) }
	assert merged_markdown.contains('intro updated on main')
	assert merged_markdown.contains('beta updated on feature')
}

fn test_persistent_database_merge_auto_resolves_markdown_multiblock_list_item_changes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-markdown-multiblock-list-item')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	base_raw := '- item intro\n\n  ```v\n  println("base")\n  ```\n'
	initial_body := db.ingest_markdown(base_raw) or { panic(err) }
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Original')
	seed.set('body', initial_body)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_update := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed markdown'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed_update.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	_ = main_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '- item intro updated on main\n\n  ```v\n  println("base")\n  ```\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'main list item paragraph update'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	_ = feature_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '- item intro\n\n  ```v\n  println("feature")\n  ```\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'feature list item code update'
		timestamp: 3
	}) or { panic(err) }

	mut merge_session := main_session.begin_working_set(mut db) or { panic(err) }
	_ = merge_session.merge_from(mut db, 'feature', [], cfg) or { panic(err) }
	merged_ref := merge_session.get_markdown_ref('notes', 'note-1'.bytes(), 'body') or {
		panic(err)
	}
	merged_markdown := db.load_markdown(merged_ref) or { panic(err) }
	assert merged_markdown.contains('item intro updated on main')
	assert merged_markdown.contains('println("feature")')
}

fn test_persistent_database_merge_auto_resolves_markdown_reorder_plus_edit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-markdown-reorder-plus-edit')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	base_raw := '# Title\n\nAlpha paragraph.\n\nBeta paragraph.\n'
	initial_body := db.ingest_markdown(base_raw) or { panic(err) }
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Original')
	seed.set('body', initial_body)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_update := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed markdown'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed_update.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	_ = main_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Title\n\nBeta paragraph.\n\nAlpha paragraph.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'main reorder'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	_ = feature_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Title\n\nAlpha paragraph updated on feature.\n\nBeta paragraph.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'feature edit'
		timestamp: 3
	}) or { panic(err) }

	mut merge_session := main_session.begin_working_set(mut db) or { panic(err) }
	_ = merge_session.merge_from(mut db, 'feature', [], cfg) or { panic(err) }
	merged_ref := merge_session.get_markdown_ref('notes', 'note-1'.bytes(), 'body') or {
		panic(err)
	}
	merged_markdown := db.load_markdown(merged_ref) or { panic(err) }
	assert merged_markdown.contains('Beta paragraph.')
	assert merged_markdown.contains('Alpha paragraph updated on feature.')
	beta_idx := merged_markdown.index('Beta paragraph.') or { panic(err) }
	alpha_idx := merged_markdown.index('Alpha paragraph updated on feature.') or { panic(err) }
	assert beta_idx < alpha_idx
}

fn test_persistent_database_merge_auto_resolves_markdown_list_reorder_plus_edit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-markdown-list-reorder-plus-edit')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	base_raw := '- alpha\n- beta\n'
	initial_body := db.ingest_markdown(base_raw) or { panic(err) }
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Original')
	seed.set('body', initial_body)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_update := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed markdown'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed_update.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	_ = main_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '- beta\n- alpha\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'main list reorder'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	_ = feature_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '- alpha updated on feature\n- beta\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'feature list edit'
		timestamp: 3
	}) or { panic(err) }

	mut merge_session := main_session.begin_working_set(mut db) or { panic(err) }
	_ = merge_session.merge_from(mut db, 'feature', [], cfg) or { panic(err) }
	merged_ref := merge_session.get_markdown_ref('notes', 'note-1'.bytes(), 'body') or {
		panic(err)
	}
	merged_markdown := db.load_markdown(merged_ref) or { panic(err) }
	assert merged_markdown.contains('- beta')
	assert merged_markdown.contains('- alpha updated on feature')
	beta_idx := merged_markdown.index('- beta') or { panic(err) }
	alpha_idx := merged_markdown.index('- alpha updated on feature') or { panic(err) }
	assert beta_idx < alpha_idx
}

fn test_persistent_database_merge_auto_resolves_markdown_repeated_block_reorder_plus_edit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-markdown-repeated-blocks')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	base_raw := '# Title\n\nRepeat.\n\nRepeat.\n'
	initial_body := db.ingest_markdown(base_raw) or { panic(err) }
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Original')
	seed.set('body', initial_body)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_update := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed markdown'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed_update.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	_ = main_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Title\n\nRepeat.\n\nRepeat.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'main noop normalize'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	_ = feature_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Title\n\nRepeat updated on feature.\n\nRepeat.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'feature repeated edit'
		timestamp: 3
	}) or { panic(err) }

	mut merge_session := main_session.begin_working_set(mut db) or { panic(err) }
	_ = merge_session.merge_from(mut db, 'feature', [], cfg) or { panic(err) }
	merged_ref := merge_session.get_markdown_ref('notes', 'note-1'.bytes(), 'body') or {
		panic(err)
	}
	merged_markdown := db.load_markdown(merged_ref) or { panic(err) }
	assert merged_markdown.contains('Repeat updated on feature.')
}

fn test_persistent_database_merge_auto_resolves_markdown_repeated_list_item_reorder_plus_edit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-markdown-repeated-list-items')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	base_raw := '- repeat\n- repeat\n'
	initial_body := db.ingest_markdown(base_raw) or { panic(err) }
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Original')
	seed.set('body', initial_body)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_update := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed markdown'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed_update.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	_ = main_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '- repeat\n- repeat\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'main noop normalize'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	_ = feature_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '- repeat updated on feature\n- repeat\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'feature repeated list edit'
		timestamp: 3
	}) or { panic(err) }

	mut merge_session := main_session.begin_working_set(mut db) or { panic(err) }
	_ = merge_session.merge_from(mut db, 'feature', [], cfg) or { panic(err) }
	merged_ref := merge_session.get_markdown_ref('notes', 'note-1'.bytes(), 'body') or {
		panic(err)
	}
	merged_markdown := db.load_markdown(merged_ref) or { panic(err) }
	assert merged_markdown.contains('- repeat updated on feature')
}

fn test_persistent_database_merge_auto_resolves_markdown_repeated_blocks_by_heading_context() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-markdown-repeated-heading-context')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	base_raw := '# A\n\nRepeat.\n\n# B\n\nRepeat.\n'
	initial_body := db.ingest_markdown(base_raw) or { panic(err) }
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Original')
	seed.set('body', initial_body)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_update := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed markdown'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed_update.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	_ = main_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# B\n\nRepeat.\n\n# A\n\nRepeat.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'main section reorder'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	_ = feature_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# A\n\nRepeat.\n\n# B\n\nRepeat updated under B.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'feature context edit'
		timestamp: 3
	}) or { panic(err) }

	mut merge_session := main_session.begin_working_set(mut db) or { panic(err) }
	_ = merge_session.merge_from(mut db, 'feature', [], cfg) or { panic(err) }
	merged_ref := merge_session.get_markdown_ref('notes', 'note-1'.bytes(), 'body') or {
		panic(err)
	}
	merged_markdown := db.load_markdown(merged_ref) or { panic(err) }
	b_idx := merged_markdown.index('# B') or { panic(err) }
	updated_idx := merged_markdown.index('Repeat updated under B.') or { panic(err) }
	a_idx := merged_markdown.index('# A') or { panic(err) }
	assert b_idx < updated_idx
	assert updated_idx < a_idx
}

fn test_persistent_database_open_local_backends() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-backends')
	defer {
		os.rmdir_all(dir) or {}
	}

	mut database := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		database.close() or {}
	}
	paths := database.backend_paths()
	assert paths.catalog_meta.ends_with('.pollydb/catalog.meta')
	mut backends := database.open_local_backends() or { panic(err) }
	defer {
		backends.close()
	}
	repo := backends.repository_meta_backend.load_repository() or { panic(err) }
	assert repo.default_branch == 'main'
	catalog, projectors := backends.catalog_backend.load_catalog() or { panic(err) }
	assert catalog.len == 0
	assert projectors.len == 0
}

fn test_persistent_database_backend_provider() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-provider')
	defer {
		os.rmdir_all(dir) or {}
	}

	mut database := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		database.close() or {}
	}
	provider := database.backend_provider()
	assert provider.default_branch() == 'main'
	assert provider.paths().catalog_meta.ends_with('.pollydb/catalog.meta')
	mut backends := provider.open_backends() or { panic(err) }
	defer {
		backends.close()
	}
	assert backends.paths.root_dir == dir
}

fn test_persistent_database_open_with_provider() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-open-with-provider')
	defer {
		os.rmdir_all(dir) or {}
	}

	provider := LocalDatabaseBackendProvider.new(dir, 'main')
	mut database := PersistentDatabase.init_with_provider(provider) or { panic(err) }
	database.close() or { panic(err) }
	mut reopened := PersistentDatabase.open_with_provider(provider) or { panic(err) }
	defer {
		reopened.close() or {}
	}
	assert reopened.backend_provider().default_branch() == 'main'
}

fn test_database_status_report_distinguishes_data_only_durability() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-status-data-only')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'put row'
		timestamp: 2
	}) or { panic(err) }
	db.checkpoint_mode(.data_only) or { panic(err) }

	report := db.status_report() or { panic(err) }
	assert report.data_durable
	assert !report.index_snapshots_fresh
	assert report.node_index_snapshot_pending || report.commit_index_snapshot_pending
	assert !report.durable
	assert report.format().contains('data_durable=true')
	assert report.format().contains('index_snapshots_fresh=false')
	assert report.format().contains('node_index_snapshot_pending=')

	db.refresh_index_snapshots() or { panic(err) }
	refreshed := db.status_report() or { panic(err) }
	assert refreshed.data_durable
	assert refreshed.index_snapshots_fresh
	assert !refreshed.node_index_snapshot_pending
	assert !refreshed.commit_index_snapshot_pending
	assert refreshed.durable
}

fn test_database_refresh_index_snapshots_async_for() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-async-refresh')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'put row'
		timestamp: 2
	}) or { panic(err) }
	db.checkpoint_mode(.data_only) or { panic(err) }
	report := db.status_report() or { panic(err) }
	assert report.data_durable
	assert !report.index_snapshots_fresh

	mut handle := PersistentDatabase.refresh_index_snapshots_async_for(dir, 'main')
	handle.wait() or { panic(err) }
	inspected := PersistentDatabase.inspect(dir, 'main') or { panic(err) }
	assert inspected.data_durable
	assert inspected.index_snapshots_fresh
	assert inspected.durable

	db.engine.repository.close_without_checkpoint()
}

fn test_group_commit_high_throughput_profile() {
	profile := GroupCommitOptions.high_throughput()
	assert profile.checkpoint_every == 8
	assert profile.checkpoint_mode == .data_only
	assert profile.auto_refresh_index_snapshots
	tuned := profile.with_checkpoint_every(16)
	assert tuned.checkpoint_every == 16
	assert tuned.checkpoint_mode == .data_only
	assert tuned.auto_refresh_index_snapshots

	durable := GroupCommitOptions.durable_default()
	assert durable.checkpoint_every == 8
	assert durable.checkpoint_mode == .full
	assert !durable.auto_refresh_index_snapshots
}

fn test_snapshot_read_scheduler_queries_multiple_commit_versions_in_parallel() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-snapshot-read-scheduler')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	db.checkpoint() or { panic(err) }
	v1 := db.branch('main') or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut updated := TypedRowData.new()
	updated.set('id', '001')
	updated.set('name', 'grace')
	updated.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '001'.bytes(), updated, cfg, CommitMeta{
		author:    'gwg'
		message:   'update row'
		timestamp: 2
	}) or { panic(err) }
	db.checkpoint() or { panic(err) }
	v2 := db.branch('main') or { panic(err) }

	scheduler := db.snapshot_read_scheduler()
	mut h1 := scheduler.get_row_async(v1.commit_cid, 'users', '001'.bytes())
	mut h2 := scheduler.get_row_async(v2.commit_cid, 'users', '001'.bytes())
	row1 := h1.wait() or { panic(err) }
	row2 := h2.wait() or { panic(err) }
	name1 := row1.row.data.get('name') or { panic(err) }
	name2 := row2.row.data.get('name') or { panic(err) }
	match name1 {
		string { assert name1 == 'ada' }
		else { panic('expected string name') }
	}
	match name2 {
		string { assert name2 == 'grace' }
		else { panic('expected string name') }
	}
}

fn test_snapshot_read_scheduler_scans_multiple_commit_versions_in_parallel() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-snapshot-scan-scheduler')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	db.checkpoint() or { panic(err) }
	v1 := db.branch('main') or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'add grace'
		timestamp: 2
	}) or { panic(err) }
	db.checkpoint() or { panic(err) }
	v2 := db.branch('main') or { panic(err) }

	scheduler := db.snapshot_read_scheduler()
	mut h1 := scheduler.scan_table_async(v1.commit_cid, 'users', 10)
	mut h2 := scheduler.scan_table_async(v2.commit_cid, 'users', 10)
	rows1 := h1.wait() or { panic(err) }
	rows2 := h2.wait() or { panic(err) }
	assert rows1.rows.len == 1
	assert rows1.rows[0].primary_key.bytestr() == '001'
	assert rows2.rows.len == 2
	assert rows2.rows[0].primary_key.bytestr() == '001'
	assert rows2.rows[1].primary_key.bytestr() == '002'
}

fn test_snapshot_read_scheduler_prefix_index_lookup_async() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-snapshot-prefix-scheduler')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }

	mut row1 := TypedRowData.new()
	row1.set('id', '001')
	row1.set('name', 'ada')
	row1.set('email', 'ada@example.com')
	_ = session.put_row(mut db, 'users', '001'.bytes(), row1, cfg, CommitMeta{
		author:    'gwg'
		message:   'add ada'
		timestamp: 1
	}) or { panic(err) }

	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('name', 'alan')
	row2.set('email', 'alan@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row2, cfg, CommitMeta{
		author:    'gwg'
		message:   'add alan'
		timestamp: 2
	}) or { panic(err) }

	mut row3 := TypedRowData.new()
	row3.set('id', '003')
	row3.set('name', 'grace')
	row3.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '003'.bytes(), row3, cfg, CommitMeta{
		author:    'gwg'
		message:   'add grace'
		timestamp: 3
	}) or { panic(err) }
	db.checkpoint() or { panic(err) }
	head := db.branch('main') or { panic(err) }

	scheduler := db.snapshot_read_scheduler()
	mut h := scheduler.lookup_index_prefix_async(head.commit_cid, 'users', 'email', 'al',
		10)
	result := h.wait() or { panic(err) }
	assert result.rows.len == 1
	assert result.rows[0].primary_key.bytestr() == '002'
	name := result.rows[0].data.get('name') or { panic(err) }
	match name {
		string { assert name == 'alan' }
		else { panic('expected string name') }
	}
}

fn test_snapshot_read_scheduler_scans_table_from_primary_key() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-snapshot-scan-from')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }

	for pair in [
		['001', 'ada'],
		['002', 'alan'],
		['003', 'grace'],
	] {
		id := pair[0]
		name := pair[1]
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('name', name)
		row.set('email', '${name}@example.com')
		_ = session.put_row(mut db, 'users', id.bytes(), row, cfg, CommitMeta{
			author:    'gwg'
			message:   'add ${id}'
			timestamp: 1
		}) or { panic(err) }
	}
	db.checkpoint() or { panic(err) }
	head := db.branch('main') or { panic(err) }

	scheduler := db.snapshot_read_scheduler()
	mut h := scheduler.scan_table_from_async(head.commit_cid, 'users', '002'.bytes(),
		10)
	result := h.wait() or { panic(err) }
	assert result.rows.len == 2
	assert result.rows[0].primary_key.bytestr() == '002'
	assert result.rows[1].primary_key.bytestr() == '003'
}

fn test_snapshot_read_scheduler_prefix_index_lookup_from_primary_key() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-snapshot-prefix-from')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }

	for row_def in [
		['001', 'ada', 'albert@example.com'],
		['002', 'alan', 'alice@example.com'],
		['003', 'grace', 'grace@example.com'],
	] {
		id := row_def[0]
		name := row_def[1]
		email := row_def[2]
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('name', name)
		row.set('email', email)
		_ = session.put_row(mut db, 'users', id.bytes(), row, cfg, CommitMeta{
			author:    'gwg'
			message:   'add ${id}'
			timestamp: 1
		}) or { panic(err) }
	}
	db.checkpoint() or { panic(err) }
	head := db.branch('main') or { panic(err) }

	scheduler := db.snapshot_read_scheduler()
	mut h := scheduler.lookup_index_prefix_from_async(head.commit_cid, 'users', 'email',
		'al', '002'.bytes(), 10)
	result := h.wait() or { panic(err) }
	assert result.rows.len == 1
	assert result.rows[0].primary_key.bytestr() == '002'
}

fn test_database_preview_merge_reports_root_hash_merge_shape() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-preview')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	seed := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	mut main_row := TypedRowData.new()
	main_row.set('id', '002')
	main_row.set('name', 'main')
	main_row.set('email', 'main@example.com')
	_ = main_session.put_row(mut db, 'users', '002'.bytes(), main_row, cfg, CommitMeta{
		author:    'gwg'
		message:   'main update'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	mut feature_row := TypedRowData.new()
	feature_row.set('id', '003')
	feature_row.set('name', 'feature')
	feature_row.set('email', 'feature@example.com')
	_ = feature_session.put_row(mut db, 'users', '003'.bytes(), feature_row, cfg, CommitMeta{
		author:    'gwg'
		message:   'feature update'
		timestamp: 3
	}) or { panic(err) }

	preview := db.preview_merge('main', 'feature', cfg) or { panic(err) }
	assert preview.base_root_cid.len > 0
	assert preview.ours_root_cid.len > 0
	assert preview.theirs_root_cid.len > 0
	assert preview.changed_keys >= 2
	assert preview.conflicts == 0
	assert !preview.ours_unchanged
	assert !preview.theirs_unchanged
}

fn test_database_merge_report_groups_changes_by_table() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-report')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	seed := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	mut main_row := TypedRowData.new()
	main_row.set('id', '002')
	main_row.set('name', 'main')
	main_row.set('email', 'main@example.com')
	_ = main_session.put_row(mut db, 'users', '002'.bytes(), main_row, cfg, CommitMeta{
		author:    'gwg'
		message:   'main update'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	mut feature_row := TypedRowData.new()
	feature_row.set('id', '003')
	feature_row.set('name', 'feature')
	feature_row.set('email', 'feature@example.com')
	_ = feature_session.put_row(mut db, 'users', '003'.bytes(), feature_row, cfg, CommitMeta{
		author:    'gwg'
		message:   'feature update'
		timestamp: 3
	}) or { panic(err) }

	report := db.merge_report('main', 'feature', cfg, 8) or { panic(err) }
	assert report.preview.conflicts == 0
	assert report.table_stats.len >= 1
	assert report.table_stats[0].table_name == 'users'
	assert report.table_stats[0].row_changes >= 2
}

fn test_database_merge_report_decodes_conflicting_rows() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-report-conflict-preview')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	seed := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	mut main_row := TypedRowData.new()
	main_row.set('id', '001')
	main_row.set('name', 'main')
	main_row.set('email', 'main@example.com')
	_ = main_session.put_row(mut db, 'users', '001'.bytes(), main_row, cfg, CommitMeta{
		author:    'gwg'
		message:   'main conflict'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	mut feature_row := TypedRowData.new()
	feature_row.set('id', '001')
	feature_row.set('name', 'feature')
	feature_row.set('email', 'feature@example.com')
	_ = feature_session.put_row(mut db, 'users', '001'.bytes(), feature_row, cfg, CommitMeta{
		author:    'gwg'
		message:   'feature conflict'
		timestamp: 3
	}) or { panic(err) }

	report := db.merge_report('main', 'feature', cfg, 8) or { panic(err) }
	assert report.preview.conflicts == 1
	assert report.conflict_keys.len == 1
	assert report.conflict_keys[0].table_name == 'users'
	assert report.conflict_keys[0].base_row.contains('name=ada')
	assert report.conflict_keys[0].ours_row.contains('name=main')
	assert report.conflict_keys[0].theirs_row.contains('name=feature')
}

fn test_database_merge_report_includes_markdown_diff_summary_for_conflicts() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-merge-report-markdown-conflict')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	base_ref := db.ingest_markdown('# Title\n\nBase paragraph.\n') or { panic(err) }
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Original')
	seed.set('body', base_ref)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_update := db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed markdown'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed_update.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	_ = main_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Title\n\nMain paragraph.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'main markdown conflict'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	_ = feature_session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Title\n\nFeature paragraph.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'feature markdown conflict'
		timestamp: 3
	}) or { panic(err) }

	report := db.merge_report('main', 'feature', cfg, 8) or { panic(err) }
	assert report.preview.conflicts == 1
	assert report.conflict_keys.len == 1
	assert report.conflict_keys[0].table_name == 'notes'
	assert report.conflict_keys[0].ours_row.contains('body=markdown:')
	assert report.conflict_keys[0].ours_row.contains('diff=[')
	assert report.conflict_keys[0].theirs_row.contains('diff=[')
}

fn test_database_replays_checkpoint_journal_on_open() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-journal-replay')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'put row'
		timestamp: 2
	}) or { panic(err) }
	db.checkpoint_mode(.data_only) or { panic(err) }
	assert os.exists(repository_checkpoint_journal_path(dir))
	db.engine.repository.close_without_checkpoint()

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	assert !os.exists(repository_checkpoint_journal_path(dir))
	found := reopened.open_session('main') or { panic(err) }
	loaded := found.get_row(mut reopened, 'users', '002'.bytes()) or { panic(err) }
	email := loaded.data.get('email') or { panic(err) }
	match email {
		string { assert email == 'grace@example.com' }
		else { panic('expected string email') }
	}
}

fn test_database_replays_multiple_checkpoint_journal_segments_on_open() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-journal-multi-segment')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	for idx in 0 .. 2 {
		id := '${idx + 2:03}'
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('name', 'user-${id}')
		row.set('email', 'user-${id}@example.com')
		_ = session.put_row(mut db, 'users', id.bytes(), row, cfg, CommitMeta{
			author:    'gwg'
			message:   'put row ${id}'
			timestamp: idx + 2
		}) or { panic(err) }
		db.checkpoint_mode(.data_only) or { panic(err) }
		assert os.exists(repository_checkpoint_journal_path(dir))
	}
	db.engine.repository.close_without_checkpoint()

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	assert !os.exists(repository_checkpoint_journal_path(dir))
	found := reopened.open_session('main') or { panic(err) }
	for id in ['002', '003'] {
		loaded := found.get_row(mut reopened, 'users', id.bytes()) or { panic(err) }
		email := loaded.data.get('email') or { panic(err) }
		match email {
			string { assert email == 'user-${id}@example.com' }
			else { panic('expected string email') }
		}
	}
}

fn test_database_session_row_helpers() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-row-helpers')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or {
		panic(err)
	}
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '004')
	row.set('name', 'ken')
	row.set('email', 'ken@example.com')
	_ = session.put_row(mut db, 'users', '004'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'put row'
		timestamp: 2
	}) or { panic(err) }

	found := session.get_row(mut db, 'users', '004'.bytes()) or { panic(err) }
	found_name := found.data.get('name') or { panic(err) }
	match found_name {
		string { assert found_name == 'ken' }
		else { panic('expected string name') }
	}

	scanned := session.scan_table(mut db, 'users', 0) or { panic(err) }
	assert scanned.len == 2
	index_rows := session.lookup_index(mut db, 'users', 'email', 'ken@example.com', 0) or {
		panic(err)
	}
	assert index_rows.len == 1
	assert index_rows[0].primary_key.bytestr() == '004'

	_ = session.delete_row(mut db, 'users', '004'.bytes(), cfg, CommitMeta{
		author:    'gwg'
		message:   'delete row'
		timestamp: 3
	}) or { panic(err) }
	_ = session.get_row(mut db, 'users', '004'.bytes()) or {
		assert err.msg().contains('not found')
		return
	}
	panic('expected deleted row lookup to fail')
}

fn test_database_session_table_reader_fast_path() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-table-reader')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut reader := session.table_reader(mut db, 'users') or { panic(err) }
	row := reader.get_row('001'.bytes()) or { panic(err) }
	name := row.data.get('name') or { panic(err) }
	match name {
		string { assert name == 'ada' }
		else { panic('expected string name') }
	}
	stats := reader.get_row_with_stats('001'.bytes()) or { panic(err) }
	assert stats.stats.path_depth >= 1
	assert stats.stats.nodes_read >= 1
}

fn test_database_session_index_reader_fast_path() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-index-reader')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'put row'
		timestamp: 2
	}) or { panic(err) }

	mut reader := session.index_reader(mut db, 'users', 'email') or { panic(err) }
	rows := reader.find_rows('grace@example.com', 10) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '002'
	name := rows[0].data.get('name') or { panic(err) }
	match name {
		string { assert name == 'grace' }
		else { panic('expected string name') }
	}
}

fn test_database_session_lookup_index_prefix() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-index-prefix')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut alan := TypedRowData.new()
	alan.set('id', '002')
	alan.set('name', 'alan')
	alan.set('email', 'alan@example.com')
	writes.put('users', '002'.bytes(), alan)
	mut grace := TypedRowData.new()
	grace.set('id', '003')
	grace.set('name', 'grace')
	grace.set('email', 'grace@example.com')
	writes.put('users', '003'.bytes(), grace)
	_ = db.apply_typed_write_set('main', writes, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }

	session := db.begin_session(SessionOptions.for_branch('main')) or { panic(err) }
	rows := session.lookup_index_prefix(mut db, 'users', 'email', 'al', 10) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '002'
	email := rows[0].data.get('email') or { panic(err) }
	match email {
		string { assert email == 'alan@example.com' }
		else { panic('expected string email') }
	}
}

fn test_database_session_lookup_index_prefix_projected() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-index-prefix-projected')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'alice@example.com', cfg) or {
		panic(err)
	}
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut alan := TypedRowData.new()
	alan.set('id', '002')
	alan.set('name', 'alan')
	alan.set('email', 'albert@example.com')
	writes.put('users', '002'.bytes(), alan)
	_ = db.apply_typed_write_set('main', writes, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }

	session := db.begin_session(SessionOptions.for_branch('main')) or { panic(err) }
	rows := session.lookup_index_prefix_projected(mut db, 'users', 'email', 'al', 10,
		['email']) or { panic(err) }
	assert rows.len > 0
	assert rows[0].data.has('email')
	assert !rows[0].data.has('name')
	assert !rows[0].data.has('id')
}

fn test_database_session_query_uses_plain_index_and_projection() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-plain-index')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('name', 'ada')
	row.set('email', 'ada@example.com')
	_ = session.put_row(mut db, 'users', '001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert user'
		timestamp: 1
	}) or { panic(err) }
	result := session.query_rows(mut db, QueryRequest{
		table_name:     'users'
		filters:        [QueryFilter.eq('email', 'ada@example.com')]
		select_columns: ['name']
		limit:          10
	}) or { panic(err) }

	assert result.plan.strategy == 'index_exact'
	assert result.plan.index_name == 'email'
	assert result.plan.index_filter.column_name == 'email'
	assert result.plan.index_filter.op == .eq
	assert result.plan.post_filters.len == 0
	assert result.plan.post_filter_count == 0
	assert result.rows.len == 1
	assert result.rows[0].primary_key.bytestr() == '001'
	assert result.rows[0].data.has('name')
	assert !result.rows[0].data.has('email')
	name := result.rows[0].data.get('name') or { panic(err) }
	match name {
		string { assert name == 'ada' }
		else { panic('expected projected string name') }
	}
}

fn test_database_session_query_order_by_index_supports_continuation() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-order-continuation')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut rows := map[string]TypedRowData{}
	for seed in [
		['001', 'Ada', 'ada@example.com'],
		['002', 'Ben', 'ben@example.com'],
		['003', 'Cara', 'cara@example.com'],
	] {
		mut row := TypedRowData.new()
		row.set('id', seed[0])
		row.set('name', seed[1])
		row.set('email', seed[2])
		rows[seed[0]] = row
	}
	_ = session.put_rows(mut db, 'users', rows, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }

	first_page := session.query_page(mut db, QueryRequest{
		table_name:     'users'
		order_by:       QueryOrder{
			column_name: 'email'
			direction:   .asc
		}
		select_columns: ['name']
		limit:          2
	}) or { panic(err) }

	assert first_page.plan.strategy == 'index_order_asc_projected'
	assert first_page.rows.len == 2
	assert first_page.rows[0].primary_key.bytestr() == '001'
	assert first_page.rows[1].primary_key.bytestr() == '002'
	assert first_page.cursor.has_more
	assert first_page.cursor.next_continuation_token.len > 0

	second_page := session.query_page(mut db, QueryRequest{
		table_name:         'users'
		order_by:           QueryOrder{
			column_name: 'email'
			direction:   .asc
		}
		select_columns:     ['name']
		limit:              2
		continuation_token: first_page.cursor.next_continuation_token
	}) or { panic(err) }

	assert second_page.rows.len == 1
	assert second_page.rows[0].primary_key.bytestr() == '003'
	assert !second_page.cursor.has_more
}

fn test_database_session_query_order_by_desc_top_n() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-order-desc-topn')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut rows := map[string]TypedRowData{}
	for seed in [
		['001', 'Ada', 'ada@example.com'],
		['002', 'Ben', 'ben@example.com'],
		['003', 'Cara', 'cara@example.com'],
	] {
		mut row := TypedRowData.new()
		row.set('id', seed[0])
		row.set('name', seed[1])
		row.set('email', seed[2])
		rows[seed[0]] = row
	}
	_ = session.put_rows(mut db, 'users', rows, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }

	page := session.query_page(mut db, QueryRequest{
		table_name:     'users'
		order_by:       QueryOrder{
			column_name: 'email'
			direction:   .desc
		}
		select_columns: ['name']
		limit:          2
	}) or { panic(err) }

	assert page.plan.strategy == 'index_order_desc_projected'
	assert page.rows.len == 2
	assert page.rows[0].primary_key.bytestr() == '003'
	assert page.rows[1].primary_key.bytestr() == '002'
	assert page.cursor.has_more
}

fn test_database_session_query_before_desc_top_n() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-before-desc-topn')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut rows := map[string]TypedRowData{}
	for seed in [
		['001', 'Ada', 'ada@example.com'],
		['002', 'Ben', 'ben@example.com'],
		['003', 'Cara', 'cara@example.com'],
	] {
		mut row := TypedRowData.new()
		row.set('id', seed[0])
		row.set('name', seed[1])
		row.set('email', seed[2])
		rows[seed[0]] = row
	}
	_ = session.put_rows(mut db, 'users', rows, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }

	page := session.query_page(mut db, QueryRequest{
		table_name:     'users'
		filters:        [QueryFilter.before('email', 'd')]
		order_by:       QueryOrder{
			column_name: 'email'
			direction:   .desc
		}
		select_columns: ['name']
		limit:          2
	}) or { panic(err) }

	assert page.plan.strategy == 'index_before_order_desc_projected'
	assert page.rows.len == 2
	assert page.rows[0].primary_key.bytestr() == '003'
	assert page.rows[1].primary_key.bytestr() == '002'
	assert page.cursor.has_more
}

fn test_database_session_query_after_desc_top_n() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-after-desc-topn')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut rows := map[string]TypedRowData{}
	for seed in [
		['001', 'Ada', 'ada@example.com'],
		['002', 'Ben', 'ben@example.com'],
		['003', 'Cara', 'cara@example.com'],
	] {
		mut row := TypedRowData.new()
		row.set('id', seed[0])
		row.set('name', seed[1])
		row.set('email', seed[2])
		rows[seed[0]] = row
	}
	_ = session.put_rows(mut db, 'users', rows, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }

	page := session.query_page(mut db, QueryRequest{
		table_name:     'users'
		filters:        [QueryFilter.after('email', 'a')]
		order_by:       QueryOrder{
			column_name: 'email'
			direction:   .desc
		}
		select_columns: ['name']
		limit:          2
	}) or { panic(err) }

	assert page.plan.strategy == 'index_after_order_desc_projected'
	assert page.rows.len == 2
	assert page.rows[0].primary_key.bytestr() == '003'
	assert page.rows[1].primary_key.bytestr() == '002'
}

fn test_database_session_query_between_desc_top_n() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-between-desc-topn')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut rows := map[string]TypedRowData{}
	for seed in [
		['001', 'Ada', 'ada@example.com'],
		['002', 'Ben', 'ben@example.com'],
		['003', 'Cara', 'cara@example.com'],
	] {
		mut row := TypedRowData.new()
		row.set('id', seed[0])
		row.set('name', seed[1])
		row.set('email', seed[2])
		rows[seed[0]] = row
	}
	_ = session.put_rows(mut db, 'users', rows, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }

	page := session.query_page(mut db, QueryRequest{
		table_name:     'users'
		filters:        [QueryFilter.between('email', 'a', 'd')]
		order_by:       QueryOrder{
			column_name: 'email'
			direction:   .desc
		}
		select_columns: ['name']
		limit:          2
	}) or { panic(err) }

	assert page.plan.strategy == 'index_between_order_desc_projected'
	assert page.rows.len == 2
	assert page.rows[0].primary_key.bytestr() == '003'
	assert page.rows[1].primary_key.bytestr() == '002'
}

fn test_database_session_lookup_index_prefix_reverse() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-prefix-reverse')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut rows := map[string]TypedRowData{}
	for seed in [
		['001', 'Ada', 'anna@example.com'],
		['002', 'Ben', 'andrew@example.com'],
		['003', 'Cara', 'amy@example.com'],
		['004', 'Drew', 'ben@example.com'],
	] {
		mut row := TypedRowData.new()
		row.set('id', seed[0])
		row.set('name', seed[1])
		row.set('email', seed[2])
		rows[seed[0]] = row
	}
	_ = session.put_rows(mut db, 'users', rows, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }

	reverse_rows := session.lookup_index_prefix_reverse(mut db, 'users', 'email', 'a',
		3) or { panic(err) }

	assert reverse_rows.len == 3
	assert reverse_rows[0].primary_key.bytestr() == '001'
	assert reverse_rows[1].primary_key.bytestr() == '002'
	assert reverse_rows[2].primary_key.bytestr() == '003'
}

fn test_database_session_query_prefix_desc_top_n() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-prefix-desc-topn')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut rows := map[string]TypedRowData{}
	for seed in [
		['001', 'Ada', 'anna@example.com'],
		['002', 'Ben', 'andrew@example.com'],
		['003', 'Cara', 'amy@example.com'],
		['004', 'Drew', 'ben@example.com'],
	] {
		mut row := TypedRowData.new()
		row.set('id', seed[0])
		row.set('name', seed[1])
		row.set('email', seed[2])
		rows[seed[0]] = row
	}
	_ = session.put_rows(mut db, 'users', rows, cfg, CommitMeta{
		author:    'gwg'
		message:   'seed users'
		timestamp: 1
	}) or { panic(err) }

	page := session.query_page(mut db, QueryRequest{
		table_name:     'users'
		filters:        [QueryFilter.prefix('email', 'a')]
		order_by:       QueryOrder{
			column_name: 'email'
			direction:   .desc
		}
		select_columns: ['name']
		limit:          2
	}) or { panic(err) }

	assert page.plan.strategy == 'index_prefix_order_desc_projected'
	assert page.rows.len == 2
	assert page.rows[0].primary_key.bytestr() == '001'
	assert page.rows[1].primary_key.bytestr() == '002'
	assert page.cursor.has_more
}

fn test_database_session_query_uses_markdown_selector_prefix_index() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-markdown-selector')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row1 := TypedRowData.new()
	row1.set('id', 'note-1')
	row1.set('title', 'Roadmap')
	row1.set('body', MarkdownRef{
		doc_root_id: 'seed-1'
		source_hash: 'seed-1'
		source_len:  0
	})
	mut row2 := TypedRowData.new()
	row2.set('id', 'note-2')
	row2.set('title', 'Changelog')
	row2.set('body', MarkdownRef{
		doc_root_id: 'seed-2'
		source_hash: 'seed-2'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(row1)!
		},
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-2'.bytes())
			value: codec.encode(row2)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '## Roadmap\n\n[docs](https://docs.example.com/a)\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write roadmap'
		timestamp: 2
	}) or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-2'.bytes(), 'body', '## Changelog\n\nNothing yet.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write changelog'
		timestamp: 3
	}) or { panic(err) }

	result := session.query_rows(mut db, QueryRequest{
		table_name: 'notes'
		filters:    [
			QueryFilter.field_prefix('body', 'markdown', 'heading_text:2', 'Road'),
		]
		limit:      10
	}) or { panic(err) }

	assert result.plan.strategy == 'index_prefix'
	assert result.plan.index_name == 'body_heading_text_idx'
	assert result.rows.len == 1
	assert result.rows[0].primary_key.bytestr() == 'note-1'
}

fn test_database_session_lookup_markdown_fts_value_indexes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-markdown-fts-indexes')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_fts_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut row := TypedRowData.new()
	row.set('id', 'note-1')
	row.set('title', 'Roadmap')
	row.set('body', MarkdownRef{
		doc_root_id: 'seed-1'
		source_hash: 'seed-1'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Intro\n\nParagraph about PollyDB merge.\n\n## Roadmap\n\nShip agent sync.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write body'
		timestamp: 2
	}) or { panic(err) }

	heading_rows := session.lookup_index(mut db, 'notes', 'body_fts_heading_idx', 'roadmap',
		10) or { panic(err) }
	assert heading_rows.len == 1
	assert heading_rows[0].primary_key.bytestr() == 'note-1'

	prefix_rows := session.lookup_index_prefix(mut db, 'notes', 'body_fts_any_idx', 'agen',
		10) or { panic(err) }
	assert prefix_rows.len == 1
	assert prefix_rows[0].primary_key.bytestr() == 'note-1'
}

fn test_database_session_query_page_uses_markdown_fts_selector_index() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-page-markdown-fts')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_fts_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut note_1 := TypedRowData.new()
	note_1.set('id', 'note-1')
	note_1.set('title', 'Roadmap')
	note_1.set('body', MarkdownRef{
		doc_root_id: 'seed-1'
		source_hash: 'seed-1'
		source_len:  0
	})
	mut note_2 := TypedRowData.new()
	note_2.set('id', 'note-2')
	note_2.set('title', 'Changelog')
	note_2.set('body', MarkdownRef{
		doc_root_id: 'seed-2'
		source_hash: 'seed-2'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('note-1'.bytes())
			value: codec.encode(note_1)!
		},
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('note-2'.bytes())
			value: codec.encode(note_2)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Intro\n\nParagraph about PollyDB merge.\n\n## Roadmap\n\nShip agent sync.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write roadmap'
		timestamp: 2
	}) or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-2'.bytes(), 'body', '# Notes\n\nDiscuss metrics only.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write notes'
		timestamp: 3
	}) or { panic(err) }

	page := session.query_page(mut db, QueryRequest{
		table_name:     'notes'
		filters:        [QueryFilter.field_prefix('body', 'markdown', 'fts', 'agen')]
		select_columns: ['title']
		limit:          10
	}) or { panic(err) }

	assert page.plan.strategy == 'index_prefix'
	assert page.plan.index_name == 'body_fts_any_idx'
	assert page.plan.index_filter.column_name == 'body'
	assert page.plan.index_filter.plugin_name == 'markdown'
	assert page.plan.index_filter.selector == 'fts'
	assert page.rows.len == 1
	assert page.rows[0].primary_key.bytestr() == 'note-1'
	assert page.rows[0].data.has('title')
}

fn test_database_session_put_row_rebuilds_markdown_selector_indexes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-put-row-markdown-selector-indexes')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_fts_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed := TypedRowData.new()
	seed.set('id', 'note-1')
	seed.set('title', 'Seed')
	seed.set('body', MarkdownRef{
		doc_root_id: 'seed-1'
		source_hash: 'seed-1'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	body_column := spec.table.column('body') or { panic(err) }
	stored := ingest_external_field_value(mut db, body_column, '# Intro\n\nInspect the patch.\n\n## Roadmap\n\nShip agent sync.\n') or {
		panic(err)
	}
	mut updated := TypedRowData.new()
	updated.set('id', 'note-1')
	updated.set('title', 'Roadmap')
	updated.set('body', stored)
	_ = session.put_row(mut db, 'notes', 'note-1'.bytes(), updated, cfg, CommitMeta{
		author:    'gwg'
		message:   'rewrite note row'
		timestamp: 2
	}) or { panic(err) }

	prefix_rows := session.lookup_index_prefix(mut db, 'notes', 'body_fts_any_idx', 'insp',
		10) or { panic(err) }
	assert prefix_rows.len == 1
	assert prefix_rows[0].primary_key.bytestr() == 'note-1'

	heading_rows := session.lookup_index(mut db, 'notes', 'body_fts_heading_idx', 'roadmap',
		10) or { panic(err) }
	assert heading_rows.len == 1
	assert heading_rows[0].primary_key.bytestr() == 'note-1'
}

fn test_database_session_query_fts_all_intersects_exact_term_indexes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-fts-all')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_fts_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut rows := []KVPair{}
	for id, title in {
		'note-1': 'Roadmap'
		'note-2': 'PollyDB'
		'note-3': 'Merge'
	} {
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('title', title)
		row.set('body', MarkdownRef{
			doc_root_id: 'seed-${id}'
			source_hash: 'seed-${id}'
			source_len:  0
		})
		rows << KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for(id.bytes())
			value: codec.encode(row)!
		}
	}
	seed_tree := Tree.build(rows, cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Intro\n\nParagraph about PollyDB merge and agent sync.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write note-1'
		timestamp: 2
	}) or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-2'.bytes(), 'body', '# Intro\n\nParagraph about PollyDB only.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write note-2'
		timestamp: 3
	}) or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-3'.bytes(), 'body', '# Intro\n\nParagraph about merge only.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write note-3'
		timestamp: 4
	}) or { panic(err) }

	preview := session.preview_fts_query_details(FtsQuery{
		table_name:     'notes'
		column_name:    'body'
		kind:           .all
		terms:          ['PollyDB', 'merge']
		select_columns: ['title']
		limit:          10
	}) or { panic(err) }
	assert preview.plan.strategy == 'fts_index_all'
	assert preview.plan.index_name == 'body_fts_any_idx'
	assert preview.notes.len == 1

	result := session.query_fts(mut db, FtsQuery{
		table_name:     'notes'
		column_name:    'body'
		kind:           .all
		terms:          ['PollyDB', 'merge']
		select_columns: ['title']
		limit:          10
	}) or { panic(err) }
	assert result.plan.strategy == 'fts_index_all'
	assert result.rows.len == 1
	assert result.rows[0].primary_key.bytestr() == 'note-1'
	assert result.rows[0].data.has('title')
	assert !result.rows[0].data.has('body')
}

fn test_database_session_query_fts_any_unions_exact_term_indexes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-fts-any')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_fts_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut rows := []KVPair{}
	for id, title in {
		'note-1': 'Roadmap'
		'note-2': 'Metrics'
		'note-3': 'Other'
	} {
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('title', title)
		row.set('body', MarkdownRef{
			doc_root_id: 'seed-${id}'
			source_hash: 'seed-${id}'
			source_len:  0
		})
		rows << KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for(id.bytes())
			value: codec.encode(row)!
		}
	}
	seed_tree := Tree.build(rows, cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Roadmap\n\nShip agent sync.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write note-1'
		timestamp: 2
	}) or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-2'.bytes(), 'body', '# Metrics\n\nTrack dashboard metrics.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write note-2'
		timestamp: 3
	}) or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-3'.bytes(), 'body', '# Notes\n\nNothing relevant.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write note-3'
		timestamp: 4
	}) or { panic(err) }

	result := session.query_fts(mut db, FtsQuery{
		table_name:     'notes'
		column_name:    'body'
		kind:           .any
		terms:          ['metrics', 'sync']
		select_columns: ['title']
		limit:          10
	}) or { panic(err) }
	assert result.plan.strategy == 'fts_index_any'
	assert result.plan.index_name == 'body_fts_any_idx'
	assert result.rows.len == 2
	assert result.hits.len == 2
	assert result.rows[0].primary_key.bytestr() == 'note-2'
	assert result.rows[1].primary_key.bytestr() == 'note-1'
	assert result.hits[0].primary_key.bytestr() == 'note-2'
	assert result.hits[1].primary_key.bytestr() == 'note-1'
	assert result.hits[0].score > result.hits[1].score
	assert result.hits[0].matched_terms == ['metrics']
	assert result.hits[0].matched_scopes == [.heading, .paragraph]
	assert result.hits[0].summary.contains('terms=[metrics]')
	assert result.hits[1].matched_terms == ['sync']
	assert result.hits[1].matched_scopes == [.paragraph]
}

fn test_database_session_query_fts_falls_back_to_scan_without_fts_index() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-fts-scan')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut rows := []KVPair{}
	for id, title in {
		'note-1': 'Roadmap'
		'note-2': 'Notes'
	} {
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('title', title)
		row.set('body', MarkdownRef{
			doc_root_id: 'seed-${id}'
			source_hash: 'seed-${id}'
			source_len:  0
		})
		rows << KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for(id.bytes())
			value: codec.encode(row)!
		}
	}
	seed_tree := Tree.build(rows, cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Roadmap\n\nShip agent sync.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write note-1'
		timestamp: 2
	}) or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-2'.bytes(), 'body', '# Notes\n\nDiscuss metrics.\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'write note-2'
		timestamp: 3
	}) or { panic(err) }

	preview := session.preview_fts_query_details(FtsQuery{
		table_name:  'notes'
		column_name: 'body'
		scope:       .heading
		kind:        .any
		terms:       ['roadmap', 'notes']
		limit:       10
	}) or { panic(err) }
	assert preview.plan.strategy == 'fts_scan_any'
	assert preview.warnings.len == 1
	assert preview.warnings[0].contains('table scan')

	result := session.query_fts(mut db, FtsQuery{
		table_name:  'notes'
		column_name: 'body'
		scope:       .heading
		kind:        .any
		terms:       ['roadmap', 'notes']
		limit:       10
	}) or { panic(err) }
	assert result.plan.strategy == 'fts_scan_any'
	assert result.rows.len == 2
}

fn test_database_session_query_general_fts_term_and_prefix() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-general-fts-term')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_docs_general_fts_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	row1_body := db.ingest_markdown('# Search\n\nVisible alpha paragraph.\n') or { panic(err) }
	row2_body := db.ingest_markdown('# Search\n\nVisible beta paragraph.\n') or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut rows := []KVPair{}
	mut row1 := TypedRowData.new()
	row1.set('id', 'doc-1')
	row1.set('content_text', 'alpha searchable body')
	row1.set('body', row1_body)
	rows << KVPair{
		key:   TableView.new(Tree{}, spec.table.name).key_for('doc-1'.bytes())
		value: codec.encode(row1)!
	}
	mut row2 := TypedRowData.new()
	row2.set('id', 'doc-2')
	row2.set('content_text', 'beta searchable text')
	row2.set('body', row2_body)
	rows << KVPair{
		key:   TableView.new(Tree{}, spec.table.name).key_for('doc-2'.bytes())
		value: codec.encode(row2)!
	}
	seed_tree := Tree.build(rows, cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed docs'
		timestamp: 1
	}) or { panic(err) }
	_ = db.rebuild_indexes_at_branch('main', ['docs'], cfg) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	preview := session.preview_general_fts_query(GeneralFtsQuery{
		table_name:     'docs'
		index_name:     'content_text_fts_idx'
		kind:           .term
		terms:          ['alpha']
		select_columns: ['content_text']
		limit:          10
	}) or { panic(err) }
	assert preview.strategy == 'sqlite_fts5_match'
	assert preview.backend == 'sqlite_fts5'

	term_result := session.query_general_fts(mut db, GeneralFtsQuery{
		table_name:     'docs'
		index_name:     'content_text_fts_idx'
		kind:           .term
		terms:          ['alpha']
		select_columns: ['content_text']
		limit:          10
	}) or { panic(err) }
	assert term_result.rows.len == 1
	assert term_result.rows[0].primary_key.bytestr() == 'doc-1'
	content_text := term_result.rows[0].data.get('content_text') or { panic(err) }
	assert content_text == ColumnValue('alpha searchable body')

	prefix_result := session.query_general_fts(mut db, GeneralFtsQuery{
		table_name:     'docs'
		index_name:     'content_text_fts_idx'
		kind:           .prefix
		terms:          ['bet']
		select_columns: ['content_text']
		limit:          10
	}) or { panic(err) }
	assert prefix_result.rows.len == 1
	assert prefix_result.rows[0].primary_key.bytestr() == 'doc-2'
}

fn test_database_session_query_general_fts_all_matches_markdown_visible_text() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-general-fts-markdown')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_docs_general_fts_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	body1 := db.ingest_markdown('# Search Title\n\nVisible paragraph with gamma token.\n\n```v\nhelper code\n```\n') or {
		panic(err)
	}
	body2 := db.ingest_markdown('# Other\n\nVisible paragraph only.\n') or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut rows := []KVPair{}
	for id, text in {
		'doc-1': 'alpha'
		'doc-2': 'beta'
	} {
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('content_text', text)
		row.set('body', if id == 'doc-1' { body1 } else { body2 })
		rows << KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for(id.bytes())
			value: codec.encode(row)!
		}
	}
	seed_tree := Tree.build(rows, cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed docs'
		timestamp: 1
	}) or { panic(err) }
	_ = db.rebuild_indexes_at_branch('main', ['docs'], cfg) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	result := session.query_general_fts(mut db, GeneralFtsQuery{
		table_name:     'docs'
		index_name:     'body_fts_idx'
		kind:           .all
		terms:          ['search', 'gamma']
		select_columns: ['id']
		limit:          10
	}) or { panic(err) }
	assert result.plan.column_name == 'body'
	assert result.rows.len == 1
	assert result.rows[0].primary_key.bytestr() == 'doc-1'
	assert result.hits.len == 1
	assert result.hits[0].score <= 0
	assert result.hits[0].snippet.len > 0
}

fn test_database_session_query_page_supports_general_fts_clause() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-page-general-fts')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_docs_general_fts_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	body1 := db.ingest_markdown('# Search Title\n\nVisible paragraph with gamma token.\n') or {
		panic(err)
	}
	body2 := db.ingest_markdown('# Other\n\nVisible beta paragraph.\n') or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut rows := []KVPair{}
	for id, text in {
		'doc-1': 'alpha searchable body'
		'doc-2': 'beta searchable body'
	} {
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('content_text', text)
		row.set('body', if id == 'doc-1' { body1 } else { body2 })
		rows << KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for(id.bytes())
			value: codec.encode(row)!
		}
	}
	seed_tree := Tree.build(rows, cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed docs'
		timestamp: 1
	}) or { panic(err) }
	_ = db.rebuild_indexes_at_branch('main', ['docs'], cfg) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	page := session.query_page(mut db, QueryRequest{
		table_name:     'docs'
		general_fts:    QueryGeneralFtsClause{
			index_name: 'body_fts_idx'
			kind:       .all
			terms:      ['search', 'gamma']
		}
		select_columns: ['id']
		limit:          10
	}) or { panic(err) }
	assert page.plan.strategy == 'sqlite_fts5_match'
	assert page.plan.index_name == 'body_fts_idx'
	assert !page.cursor.has_more
	assert page.rows.len == 1
	assert page.rows[0].primary_key.bytestr() == 'doc-1'
	assert page.general_fts_hits.len == 1
	assert page.general_fts_hits[0].primary_key.bytestr() == 'doc-1'
	assert page.general_fts_hits[0].snippet.len > 0
}

fn test_transaction_session_query_uses_index_and_post_filters() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-transaction-post-filter')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	mut tx := session.begin_working_set(mut db) or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = tx.put_row('users', '001'.bytes(), row, cfg) or { panic(err) }

	result := tx.query_rows(QueryRequest{
		table_name: 'users'
		filters:    [QueryFilter.eq('email', 'grace@example.com'),
			QueryFilter.eq('name', 'grace')]
		limit:      10
	}) or { panic(err) }

	assert result.plan.strategy == 'index_exact'
	assert result.plan.index_name == 'email'
	assert result.plan.index_filter.column_name == 'email'
	assert result.plan.index_filter.op == .eq
	assert result.plan.post_filters.len == 1
	assert result.plan.post_filters[0].column_name == 'name'
	assert result.plan.post_filters[0].op == .eq
	assert result.plan.post_filter_count == 1
	assert result.rows.len == 1
	assert result.rows[0].primary_key.bytestr() == '001'
}

fn test_database_session_query_supports_between_on_datetime_index() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-between-datetime')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_events_datetime_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'seed')
	seed_row.set('title', 'Seed')
	seed_row.set('created_at', '2026-01-01T00:00:00.000000Z')
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'events').key_for('seed'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row1 := TypedRowData.new()
	row1.set('id', 'e1')
	row1.set('title', 'One')
	row1.set('created_at', '2026-01-01T00:00:00.000000Z')
	_ = session.put_row(mut db, 'events', 'e1'.bytes(), row1, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert e1'
		timestamp: 1
	}) or { panic(err) }
	mut row2 := TypedRowData.new()
	row2.set('id', 'e2')
	row2.set('title', 'Two')
	row2.set('created_at', '2026-01-02T00:00:00.000000Z')
	_ = session.put_row(mut db, 'events', 'e2'.bytes(), row2, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert e2'
		timestamp: 2
	}) or { panic(err) }
	mut row3 := TypedRowData.new()
	row3.set('id', 'e3')
	row3.set('title', 'Three')
	row3.set('created_at', '2026-01-03T00:00:00.000000Z')
	_ = session.put_row(mut db, 'events', 'e3'.bytes(), row3, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert e3'
		timestamp: 3
	}) or { panic(err) }

	result := session.query_rows(mut db, QueryRequest{
		table_name: 'events'
		filters:    [
			QueryFilter.between('created_at', '2026-01-02T00:00:00.000000Z', '2026-01-03T00:00:00.000000Z'),
		]
		limit:      10
	}) or { panic(err) }

	assert result.plan.strategy == 'index_between'
	assert result.plan.index_name == 'created_at_idx'
	assert result.plan.index_filter.column_name == 'created_at'
	assert result.plan.index_filter.op == .between
	assert result.plan.index_filter.has_second_value
	assert result.plan.post_filters.len == 0
	assert result.rows.len == 2
	assert result.rows[0].primary_key.bytestr() == 'e2'
	assert result.rows[1].primary_key.bytestr() == 'e3'
}

fn test_database_session_query_supports_after_on_markdown_metric_index() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-after-markdown-metric')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', 'note-1')
	seed_row.set('title', 'Doc 1')
	seed_row.set('body', MarkdownRef{
		doc_root_id: 'seed-1'
		source_hash: 'seed-1'
		source_len:  0
	})
	mut seed_row2 := TypedRowData.new()
	seed_row2.set('id', 'note-2')
	seed_row2.set('title', 'Doc 2')
	seed_row2.set('body', MarkdownRef{
		doc_root_id: 'seed-2'
		source_hash: 'seed-2'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(seed_row)!
		},
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-2'.bytes())
			value: codec.encode(seed_row2)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed notes'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Intro\n\n[a](https://a.example)\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'note 1 markdown'
		timestamp: 2
	}) or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-2'.bytes(), 'body', '# Intro\n\n[a](https://a.example)\n\n[b](https://b.example)\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'note 2 markdown'
		timestamp: 3
	}) or { panic(err) }

	result := session.query_rows(mut db, QueryRequest{
		table_name: 'notes'
		filters:    [QueryFilter.field_after('body', 'markdown', 'links', i64(1))]
		limit:      10
	}) or { panic(err) }

	assert result.plan.strategy == 'index_after'
	assert result.plan.index_name == 'body_link_count_idx'
	assert result.plan.index_filter.column_name == 'body'
	assert result.plan.index_filter.plugin_name == 'markdown'
	assert result.plan.index_filter.selector == 'links'
	assert result.plan.index_filter.op == .after
	assert result.rows.len == 1
	assert result.rows[0].primary_key.bytestr() == 'note-2'
}

fn test_database_session_query_rows_supports_primary_key_pagination() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-pagination')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	for pair in [
		['001', 'Ada'],
		['002', 'Grace'],
		['003', 'Linus'],
	] {
		id := pair[0]
		name := pair[1]
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('name', name)
		row.set('email', '${name.to_lower()}@example.com')
		_ = session.put_row(mut db, 'users', id.bytes(), row, cfg, CommitMeta{
			author:    'gwg'
			message:   'insert ${id}'
			timestamp: 1
		}) or { panic(err) }
	}

	first_page := session.query_rows(mut db, QueryRequest{
		table_name: 'users'
		filters:    [QueryFilter.prefix('email', '')]
		limit:      2
	}) or { panic(err) }
	assert first_page.rows.len == 2
	assert first_page.cursor.has_more
	assert first_page.cursor.next_primary_key.bytestr() == '002'
	assert first_page.has_more
	assert first_page.next_primary_key.bytestr() == '002'
	match first_page.next_index_value {
		string { assert first_page.next_index_value == 'grace@example.com' }
		else { panic('expected next_index_value string') }
	}
	match first_page.cursor.next_index_value {
		string { assert first_page.cursor.next_index_value == 'grace@example.com' }
		else { panic('expected cursor next_index_value string') }
	}
	assert first_page.cursor.next_continuation_token.len > 0
	assert first_page.rows[0].primary_key.bytestr() == '001'
	assert first_page.rows[1].primary_key.bytestr() == '002'

	second_page := session.query_rows(mut db, QueryRequest{
		table_name:            'users'
		filters:               [QueryFilter.prefix('email', '')]
		start_primary_key:     first_page.next_primary_key
		start_index_value:     first_page.next_index_value
		has_start_index_value: true
		limit:                 2
	}) or { panic(err) }
	assert second_page.rows.len == 1
	assert !second_page.cursor.has_more
	assert !second_page.has_more
	assert second_page.rows[0].primary_key.bytestr() == '003'
}

fn test_database_session_query_page_returns_indexed_cursor_page() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-page')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('name', 'Ada')
	row.set('email', 'ada@example.com')
	_ = session.put_row(mut db, 'users', '001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert user'
		timestamp: 1
	}) or { panic(err) }

	page := session.query_page(mut db, QueryRequest{
		table_name: 'users'
		filters:    [QueryFilter.eq('email', 'ada@example.com')]
		limit:      10
	}) or { panic(err) }
	assert page.rows.len == 1
	assert page.plan.index_name == 'email'
	assert !page.cursor.has_more
	assert page.rows[0].primary_key.bytestr() == '001'
}

fn test_database_session_query_page_uses_plain_index_and_projection() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-page-plain-index')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('name', 'ada')
	row.set('email', 'ada@example.com')
	_ = session.put_row(mut db, 'users', '001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert user'
		timestamp: 1
	}) or { panic(err) }
	page := session.query_page(mut db, QueryRequest{
		table_name:     'users'
		filters:        [QueryFilter.eq('email', 'ada@example.com')]
		select_columns: ['name']
		limit:          10
	}) or { panic(err) }

	assert page.plan.strategy == 'index_exact'
	assert page.plan.index_name == 'email'
	assert page.plan.index_filter.column_name == 'email'
	assert page.plan.index_filter.op == .eq
	assert page.plan.post_filters.len == 0
	assert page.plan.post_filter_count == 0
	assert page.rows.len == 1
	assert page.rows[0].primary_key.bytestr() == '001'
	assert page.rows[0].data.has('name')
	assert !page.rows[0].data.has('email')
	name := page.rows[0].data.get('name') or { panic(err) }
	match name {
		string { assert name == 'ada' }
		else { panic('expected projected string name') }
	}
}

fn test_database_session_query_page_marks_covering_projection_pushdown() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-page-covering-projected')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('name', 'ada')
	row.set('email', 'ada@example.com')
	_ = session.put_row(mut db, 'users', '001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert user'
		timestamp: 1
	}) or { panic(err) }

	page := session.query_page(mut db, QueryRequest{
		table_name:     'users'
		filters:        [QueryFilter.eq('email', 'ada@example.com')]
		select_columns: ['email']
		limit:          10
	}) or { panic(err) }

	assert page.plan.strategy == 'index_exact_projected'
	assert page.rows.len == 1
	assert page.rows[0].data.has('email')
	assert !page.rows[0].data.has('name')

	preview := db.preview_query_plan_details(QueryRequest{
		table_name:     'users'
		filters:        [QueryFilter.eq('email', 'ada@example.com')]
		select_columns: ['email']
		limit:          10
	}) or { panic(err) }
	assert preview.plan.strategy == 'index_exact_projected'
	assert preview.notes.any(it.contains('covering index'))
}

fn test_database_session_query_page_supports_primary_key_pagination() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-page-pagination')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '000', 'seed', 'seed@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	for pair in [
		['001', 'Ada'],
		['002', 'Grace'],
		['003', 'Linus'],
	] {
		id := pair[0]
		name := pair[1]
		mut row := TypedRowData.new()
		row.set('id', id)
		row.set('name', name)
		row.set('email', '${name.to_lower()}@example.com')
		_ = session.put_row(mut db, 'users', id.bytes(), row, cfg, CommitMeta{
			author:    'gwg'
			message:   'insert ${id}'
			timestamp: 1
		}) or { panic(err) }
	}

	first_page := session.query_page(mut db, QueryRequest{
		table_name: 'users'
		filters:    [QueryFilter.prefix('email', '')]
		limit:      2
	}) or { panic(err) }
	assert first_page.rows.len == 2
	assert first_page.cursor.has_more
	assert first_page.cursor.next_primary_key.bytestr() == '002'
	match first_page.cursor.next_index_value {
		string { assert first_page.cursor.next_index_value == 'grace@example.com' }
		else { panic('expected cursor next_index_value string') }
	}
	assert first_page.cursor.next_continuation_token.len > 0

	second_page := session.query_page(mut db, QueryRequest{
		table_name:         'users'
		filters:            [QueryFilter.prefix('email', '')]
		continuation_token: first_page.cursor.next_continuation_token
		limit:              2
	}) or { panic(err) }
	assert second_page.rows.len == 1
	assert !second_page.cursor.has_more
	assert second_page.rows[0].primary_key.bytestr() == '003'
}

fn test_database_table_query_schema_exposes_selectors_and_projection_metrics() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-schema')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_value_and_fts_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.count_field_selector('count(notes.body.links)',
		'notes', 'body', 'markdown', 'links') or { panic(err) }) or { panic(err) }

	schema := db.table_query_schema('notes') or { panic(err) }
	assert schema.table_name == 'notes'
	assert schema.default_result_shape == 'page'
	assert schema.supports_continuation_token
	assert schema.supports_select_projection
	assert schema.supported_filter_ops.len == 5

	mut body_column := QueryColumnCapability{}
	for column in schema.columns {
		if column.name == 'body' {
			body_column = column
			break
		}
	}
	assert body_column.name == 'body'
	assert body_column.typ == .markdown_
	assert body_column.filter_ops.len == 1
	assert body_column.filter_ops[0] == .eq
	assert body_column.planner_hints.len == 0
	assert body_column.filter_shapes.len == 1
	assert body_column.filter_shapes[0].op == .eq
	assert !body_column.filter_shapes[0].indexed
	assert body_column.filter_shapes[0].planner_strategy == 'table_scan'
	assert body_column.filter_shapes[0].sample_explain.strategy == 'table_scan'
	assert body_column.filter_shapes[0].sample_explain.warnings.len >= 1
	assert body_column.filter_shapes[0].sample_explain.warnings[0].contains('table scan')

	mut heading_selector := QueryFieldSelectorCapability{}
	mut fts_selector := QueryFieldSelectorCapability{}
	mut links_selector := QueryFieldSelectorCapability{}
	for selector in schema.field_selectors {
		if selector.column_name == 'body' && selector.plugin_name == 'markdown'
			&& selector.selector == 'heading_text:2' {
			heading_selector = selector
		}
		if selector.column_name == 'body' && selector.plugin_name == 'markdown'
			&& selector.selector == 'fts' {
			fts_selector = selector
		}
		if selector.column_name == 'body' && selector.plugin_name == 'markdown'
			&& selector.selector == 'links' {
			links_selector = selector
		}
	}
	assert heading_selector.selector == 'heading_text:2'
	assert heading_selector.value_type == .string_
	assert heading_selector.index_names == ['body_heading_text_idx']
	assert heading_selector.projection_names.len == 0
	assert heading_selector.filter_ops == [.eq, .prefix, .after, .before, .between]
	assert heading_selector.planner_hints.len == 5
	assert heading_selector.planner_hints[0].op == .eq
	assert heading_selector.planner_hints[0].strategy == 'index_exact'
	assert heading_selector.planner_hints[0].index_name == 'body_heading_text_idx'
	assert heading_selector.filter_shapes.len == 5
	assert heading_selector.filter_shapes[1].op == .prefix
	assert heading_selector.filter_shapes[1].indexed
	assert heading_selector.filter_shapes[1].index_name == 'body_heading_text_idx'
	assert heading_selector.filter_shapes[1].continuation_anchor
	assert heading_selector.filter_shapes[1].sample_explain.strategy == 'index_prefix'
	assert heading_selector.filter_shapes[1].sample_explain.index_name == 'body_heading_text_idx'
	assert heading_selector.filter_shapes[1].sample_explain.warnings.len == 0

	assert fts_selector.selector == 'fts'
	assert fts_selector.value_type == .string_
	assert fts_selector.index_names == ['body_fts_any_idx']
	assert fts_selector.filter_ops == [.eq, .prefix, .after, .before, .between]
	assert fts_selector.planner_hints.len == 5
	assert fts_selector.planner_hints[1].op == .prefix
	assert fts_selector.planner_hints[1].index_name == 'body_fts_any_idx'
	assert fts_selector.filter_shapes[1].indexed
	assert fts_selector.filter_shapes[1].index_name == 'body_fts_any_idx'
	assert fts_selector.filter_shapes[1].sample_explain.strategy == 'index_prefix'
	assert fts_selector.fts_query_kinds == [.term, .prefix, .all, .any]
	assert fts_selector.fts_shapes.len == 4
	assert fts_selector.fts_shapes[0].kind == .term
	assert fts_selector.fts_shapes[0].indexed
	assert fts_selector.fts_shapes[0].index_name == 'body_fts_any_idx'
	assert fts_selector.fts_shapes[0].planner_strategy == 'index_exact'
	assert fts_selector.fts_shapes[0].sample_explain.strategy == 'index_exact'
	assert fts_selector.fts_shapes[2].kind == .all
	assert fts_selector.fts_shapes[2].indexed
	assert fts_selector.fts_shapes[2].index_name == 'body_fts_any_idx'
	assert fts_selector.fts_shapes[2].planner_strategy == 'fts_index_all'
	assert fts_selector.fts_shapes[2].sample_explain.strategy == 'fts_index_all'
	assert fts_selector.fts_shapes[3].kind == .any
	assert fts_selector.fts_shapes[3].planner_strategy == 'fts_index_any'

	assert links_selector.selector == 'links'
	assert links_selector.value_type == .i64_
	assert links_selector.projection_names == ['count(notes.body.links)']
	assert links_selector.filter_ops == [.eq, .after, .before, .between]
	assert links_selector.planner_hints.len == 0
	assert links_selector.filter_shapes.len == 4
	assert links_selector.filter_shapes[0].op == .eq
	assert !links_selector.filter_shapes[0].indexed
	assert links_selector.filter_shapes[0].projection_only
	assert links_selector.filter_shapes[0].sample_explain.strategy == 'table_scan'
	assert links_selector.filter_shapes[0].sample_explain.warnings.any(it.contains('projection-only'))

	assert schema.projection_metrics.len == 1
	assert schema.projection_metrics[0].name == 'count(notes.body.links)'
	assert schema.projection_metrics[0].plugin_name == 'markdown'
	assert schema.projection_metrics[0].selector == 'links'
	assert schema.projection_metrics[0].value_type == .i64_
	assert schema.projection_metrics[0].aggregate == .sum
}

fn test_database_table_query_schema_exposes_general_fts_indexes() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-schema-general-fts')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_docs_general_fts_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	schema := db.table_query_schema('docs') or { panic(err) }
	assert schema.table_name == 'docs'
	assert schema.indexes.len == 2

	mut content_text_fts := QueryIndexCapability{}
	mut body_fts := QueryIndexCapability{}
	for index in schema.indexes {
		if index.name == 'content_text_fts_idx' {
			content_text_fts = index
		}
		if index.name == 'body_fts_idx' {
			body_fts = index
		}
	}

	assert content_text_fts.name == 'content_text_fts_idx'
	assert content_text_fts.column_name == 'content_text'
	assert content_text_fts.value_type == .string_
	assert content_text_fts.is_fts
	assert content_text_fts.fts_query_kinds == [.term, .prefix, .all, .any]
	assert content_text_fts.fts_shapes.len == 4
	assert content_text_fts.fts_shapes[0].kind == .term
	assert content_text_fts.fts_shapes[0].indexed
	assert content_text_fts.fts_shapes[0].index_name == 'content_text_fts_idx'
	assert content_text_fts.fts_shapes[0].planner_strategy == 'sqlite_fts5_match'
	assert content_text_fts.fts_shapes[0].sample_explain.strategy == 'sqlite_fts5_match'
	assert !content_text_fts.fts_shapes[0].sample_explain.supports_continuation_token
	assert content_text_fts.filter_ops.len == 0

	assert body_fts.name == 'body_fts_idx'
	assert body_fts.column_name == 'body'
	assert body_fts.value_type == .string_
	assert body_fts.is_fts
	assert body_fts.fts_query_kinds == [.term, .prefix, .all, .any]
	assert body_fts.fts_shapes.len == 4
	assert body_fts.fts_shapes[2].kind == .all
	assert body_fts.fts_shapes[2].indexed
	assert body_fts.fts_shapes[2].index_name == 'body_fts_idx'
	assert body_fts.fts_shapes[2].planner_strategy == 'sqlite_fts5_match'
	assert body_fts.fts_shapes[2].sample_explain.strategy == 'sqlite_fts5_match'
	assert body_fts.fts_shapes[2].sample_explain.notes.any(it.contains('QueryRequest.general_fts'))
	assert body_fts.filter_ops.len == 0
}

fn test_database_table_query_schema_marks_reverse_top_n_capability_for_before_filters() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-schema-before-capability')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	schema := db.table_query_schema('users') or { panic(err) }
	mut email_column := QueryColumnCapability{}
	for column in schema.columns {
		if column.name == 'email' {
			email_column = column
			break
		}
	}
	assert email_column.name == 'email'

	mut before_hint := QueryPlannerHint{}
	for hint in email_column.planner_hints {
		if hint.op == .before {
			before_hint = hint
			break
		}
	}
	assert before_hint.op == .before
	assert before_hint.strategy == 'index_before_order_desc'
	assert before_hint.supports_reverse_scan
	assert before_hint.supports_top_n

	mut before_shape := QueryFilterShapeCapability{}
	for shape in email_column.filter_shapes {
		if shape.op == .before {
			before_shape = shape
			break
		}
	}
	assert before_shape.op == .before
	assert before_shape.indexed
	assert before_shape.planner_strategy == 'index_before_order_desc'
	assert before_shape.supports_reverse_scan
	assert before_shape.supports_top_n
	assert before_shape.sample_explain.supports_reverse_scan
	assert before_shape.sample_explain.supports_top_n
	assert before_shape.sample_explain.notes.any(it.contains('reverse index scan executor'))
	assert before_shape.sample_explain.notes.any(it.contains('Top-N retrieval'))
}

fn test_database_table_query_schema_marks_reverse_top_n_capability_for_prefix_filters() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-schema-prefix-capability')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	schema := db.table_query_schema('users') or { panic(err) }
	mut email_column := QueryColumnCapability{}
	for column in schema.columns {
		if column.name == 'email' {
			email_column = column
			break
		}
	}
	assert email_column.name == 'email'

	mut prefix_hint := QueryPlannerHint{}
	for hint in email_column.planner_hints {
		if hint.op == .prefix {
			prefix_hint = hint
			break
		}
	}
	assert prefix_hint.op == .prefix
	assert prefix_hint.strategy == 'index_prefix_order_desc'
	assert prefix_hint.supports_reverse_scan
	assert prefix_hint.supports_top_n

	mut prefix_shape := QueryFilterShapeCapability{}
	for shape in email_column.filter_shapes {
		if shape.op == .prefix {
			prefix_shape = shape
			break
		}
	}
	assert prefix_shape.op == .prefix
	assert prefix_shape.indexed
	assert prefix_shape.planner_strategy == 'index_prefix_order_desc'
	assert prefix_shape.supports_reverse_scan
	assert prefix_shape.supports_top_n
	assert prefix_shape.sample_explain.supports_reverse_scan
	assert prefix_shape.sample_explain.supports_top_n
	assert prefix_shape.sample_explain.notes.any(it.contains('reverse index scan executor'))
	assert prefix_shape.sample_explain.notes.any(it.contains('Top-N retrieval'))
}

fn test_database_table_query_schema_exposes_order_shapes_for_indexed_column() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-schema-order-shapes')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	schema := db.table_query_schema('users') or { panic(err) }
	mut email_column := QueryColumnCapability{}
	for column in schema.columns {
		if column.name == 'email' {
			email_column = column
			break
		}
	}
	assert email_column.name == 'email'
	assert email_column.order_shapes.len > 0

	mut prefix_desc := QueryOrderCapability{}
	mut before_desc := QueryOrderCapability{}
	for shape in email_column.order_shapes {
		if shape.filter_op == .prefix && shape.direction == .desc {
			prefix_desc = shape
		}
		if shape.filter_op == .before && shape.direction == .desc {
			before_desc = shape
		}
	}

	assert prefix_desc.filter_op == .prefix
	assert prefix_desc.direction == .desc
	assert prefix_desc.indexed
	assert prefix_desc.index_name == 'email'
	assert prefix_desc.planner_strategy == 'index_prefix_order_desc'
	assert prefix_desc.supports_reverse_scan
	assert prefix_desc.supports_top_n

	assert before_desc.filter_op == .before
	assert before_desc.direction == .desc
	assert before_desc.indexed
	assert before_desc.index_name == 'email'
	assert before_desc.planner_strategy == 'index_before_order_desc'
	assert before_desc.supports_reverse_scan
	assert before_desc.supports_top_n
}

fn test_database_preview_query_plan_details_marks_reverse_top_n_for_before_index_strategy() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-plan-before-reverse-capability')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	preview := db.preview_query_plan_details(QueryRequest{
		table_name: 'users'
		filters:    [QueryFilter.before('email', 'm')]
		limit:      10
	}) or { panic(err) }

	assert preview.plan.strategy == 'index_before'
	explain := preview.sample_explain()
	assert explain.supports_reverse_scan
	assert explain.supports_top_n
	assert explain.notes.any(it.contains('reverse index scan executor'))
	assert explain.notes.any(it.contains('Top-N retrieval'))
}

fn test_database_preview_query_plan_details_marks_ordered_index_strategy() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-plan-order-capability')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	preview := db.preview_query_plan_details(QueryRequest{
		table_name:     'users'
		order_by:       QueryOrder{
			column_name: 'email'
			direction:   .desc
		}
		select_columns: ['name']
		limit:          5
	}) or { panic(err) }

	assert preview.plan.strategy == 'index_order_desc_projected'
	assert preview.plan.index_name == 'email'
	explain := preview.sample_explain()
	assert explain.supports_reverse_scan
	assert explain.supports_top_n
	assert explain.notes.any(it.contains('Requested ordering can be satisfied directly from the chosen index'))
}

fn test_database_preview_query_plan_details_marks_before_desc_order_as_reverse_top_n() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-plan-before-desc-order')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	preview := db.preview_query_plan_details(QueryRequest{
		table_name:     'users'
		filters:        [QueryFilter.before('email', 'm')]
		order_by:       QueryOrder{
			column_name: 'email'
			direction:   .desc
		}
		select_columns: ['name']
		limit:          5
	}) or { panic(err) }

	assert preview.plan.strategy == 'index_before_order_desc_projected'
	assert preview.plan.index_name == 'email'
	explain := preview.sample_explain()
	assert explain.supports_reverse_scan
	assert explain.supports_top_n
}

fn test_database_preview_query_plan_details_marks_prefix_desc_order_as_reverse_top_n() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-plan-prefix-desc-order')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	preview := db.preview_query_plan_details(QueryRequest{
		table_name:     'users'
		filters:        [QueryFilter.prefix('email', 'a')]
		order_by:       QueryOrder{
			column_name: 'email'
			direction:   .desc
		}
		select_columns: ['name']
		limit:          5
	}) or { panic(err) }

	assert preview.plan.strategy == 'index_prefix_order_desc_projected'
	assert preview.plan.index_name == 'email'
	explain := preview.sample_explain()
	assert explain.supports_reverse_scan
	assert explain.supports_top_n
	assert explain.notes.any(it.contains('reverse index scan executor'))
	assert explain.notes.any(it.contains('Top-N retrieval'))
}

fn test_database_preview_query_plan_returns_expected_index_strategy() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-plan-preview')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	plan := db.preview_query_plan(QueryRequest{
		table_name:     'notes'
		filters:        [
			QueryFilter.field_prefix('body', 'markdown', 'heading_text:2', 'Road'),
			QueryFilter.eq('title', 'Doc'),
		]
		select_columns: ['title']
		limit:          10
	}) or { panic(err) }

	assert plan.strategy == 'index_prefix'
	assert plan.index_name == 'body_heading_text_idx'
	assert plan.index_filter.column_name == 'body'
	assert plan.index_filter.plugin_name == 'markdown'
	assert plan.index_filter.selector == 'heading_text:2'
	assert plan.post_filter_count == 1
	assert plan.post_filters.len == 1
	assert plan.post_filters[0].column_name == 'title'
}

fn test_database_preview_query_plan_details_reports_notes_for_indexed_markdown_query() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-plan-preview-details-indexed')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	preview := db.preview_query_plan_details(QueryRequest{
		table_name:     'notes'
		filters:        [
			QueryFilter.field_prefix('body', 'markdown', 'heading_text:2', 'Road'),
			QueryFilter.eq('title', 'Doc'),
		]
		select_columns: ['title']
		limit:          10
	}) or { panic(err) }

	assert preview.plan.strategy == 'index_prefix'
	assert preview.plan.index_name == 'body_heading_text_idx'
	assert preview.warnings.len == 0
	assert preview.notes.len >= 1
	assert preview.notes.any(it.contains('post-filters'))
	assert preview.sample_explain().strategy == preview.plan.strategy
	assert preview.sample_explain().index_name == preview.plan.index_name
	assert preview.sample_explain().notes == preview.notes
}

fn test_database_preview_query_plan_details_reports_projection_only_warning() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-plan-preview-details-projection-only')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.count_field_selector('count(notes.body.links)',
		'notes', 'body', 'markdown', 'links') or { panic(err) }) or { panic(err) }

	preview := db.preview_query_plan_details(QueryRequest{
		table_name: 'notes'
		filters:    [
			QueryFilter.field_eq('body', 'markdown', 'links', i64(1)),
		]
		limit:      10
	}) or { panic(err) }

	assert preview.plan.strategy == 'table_scan'
	assert preview.warnings.len >= 2
	assert preview.warnings.any(it.contains('table scan'))
	assert preview.warnings.any(it.contains('projection-only'))
	assert preview.sample_explain().strategy == 'table_scan'
	assert preview.sample_explain().warnings == preview.warnings
}

fn test_database_preview_query_plan_details_supports_general_fts_clause() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-plan-preview-general-fts')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_docs_general_fts_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	preview := db.preview_query_plan_details(QueryRequest{
		table_name:     'docs'
		general_fts:    QueryGeneralFtsClause{
			index_name: 'body_fts_idx'
			kind:       .all
			terms:      ['search', 'gamma']
		}
		select_columns: ['id']
		limit:          10
	}) or { panic(err) }

	assert preview.plan.strategy == 'sqlite_fts5_match'
	assert preview.plan.index_name == 'body_fts_idx'
	assert preview.warnings.len == 0
	assert preview.notes.len >= 1
	assert preview.notes.any(it.contains('SQLite FTS5 sidecar'))
	assert preview.default_result_shape == 'rows'
	assert !preview.supports_continuation_token
	assert preview.sample_explain().strategy == 'sqlite_fts5_match'
	assert preview.sample_explain().index_name == 'body_fts_idx'
}

fn test_database_lower_query_request_maps_plain_and_field_selector_predicates() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-lowering-success')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	request := db.lower_query_request(QueryLoweringRequest{
		table_name:     'notes'
		predicates:     [
			QueryPredicateSpec.field_prefix('body', 'markdown', 'heading_text:2', 'Road'),
			QueryPredicateSpec.column_eq('title', 'Doc'),
		]
		select_columns: ['title']
		limit:          10
	}) or { panic(err) }

	assert request.table_name == 'notes'
	assert request.filters.len == 2
	assert request.filters[0].column_name == 'body'
	assert request.filters[0].plugin_name == 'markdown'
	assert request.filters[0].selector == 'heading_text:2'
	assert request.filters[0].op == .prefix
	assert request.filters[1].column_name == 'title'
	assert request.filters[1].op == .eq
	assert request.select_columns == ['title']
	assert request.limit == 10
}

fn test_database_lower_query_request_rejects_unsupported_field_selector_op() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-lowering-bad-op')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.count_field_selector('count(notes.body.links)',
		'notes', 'body', 'markdown', 'links') or { panic(err) }) or { panic(err) }

	if _ := db.lower_query_request(QueryLoweringRequest{
		table_name: 'notes'
		predicates: [
			QueryPredicateSpec.field_prefix('body', 'markdown', 'links', 'docs'),
		]
		limit:      10
	})
	{
		panic('expected unsupported field selector op to fail')
	} else {
		assert err.msg().contains('value type mismatch') || err.msg().contains('is not supported')
	}
}

fn test_database_lower_query_request_rejects_unknown_field_selector() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-lowering-unknown-selector')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	if _ := db.lower_query_request(QueryLoweringRequest{
		table_name: 'notes'
		predicates: [
			QueryPredicateSpec.field_eq('body', 'markdown', 'missing_selector', 'x'),
		]
		limit:      10
	})
	{
		panic('expected unknown field selector to fail')
	} else {
		assert err.msg().contains('field selector not found')
	}
}

fn test_normalized_query_predicate_maps_sql_like_comparisons() {
	gt := NormalizedQueryPredicate.column_gt('created_at', '2025-01-01T00:00:00Z').to_query_predicate_spec() or {
		panic(err)
	}
	assert gt.target.column_name == 'created_at'
	assert gt.op == .after

	lt := NormalizedQueryPredicate.column_lt('created_at', '2025-12-31T00:00:00Z').to_query_predicate_spec() or {
		panic(err)
	}
	assert lt.op == .before

	between := NormalizedQueryPredicate.field_between('body', 'markdown', 'links', i64(1),
		i64(3)).to_query_predicate_spec() or { panic(err) }
	assert between.target.column_name == 'body'
	assert between.target.plugin_name == 'markdown'
	assert between.target.selector == 'links'
	assert between.op == .between
	assert between.has_second_value
}

fn test_database_lower_normalized_query_request_supports_field_selector_prefix() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-normalized-lowering')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	request := db.lower_normalized_query_request(QueryNormalizedLoweringRequest{
		table_name:     'notes'
		predicates:     [
			NormalizedQueryPredicate.field_prefix('body', 'markdown', 'heading_text:2',
				'Road'),
			NormalizedQueryPredicate.column_eq('title', 'Doc'),
		]
		select_columns: ['title']
		limit:          5
	}) or { panic(err) }

	assert request.table_name == 'notes'
	assert request.filters.len == 2
	assert request.filters[0].op == .prefix
	assert request.filters[0].plugin_name == 'markdown'
	assert request.filters[0].selector == 'heading_text:2'
	assert request.filters[1].op == .eq
	assert request.limit == 5
}

fn test_sql_filter_fragment_maps_sql_like_prefix_to_normalized_predicate() {
	predicate := SqlFilterFragment.field_like_prefix('body', 'markdown', 'heading_text:2',
		'Road').to_normalized_query_predicate() or { panic(err) }
	assert predicate.target.column_name == 'body'
	assert predicate.target.plugin_name == 'markdown'
	assert predicate.target.selector == 'heading_text:2'
	assert predicate.op == .prefix
	assert predicate.value == ColumnValue('Road')
}

fn test_database_lower_sql_filter_request_supports_sql_style_fragments() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-query-sql-filter-lowering')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_notes_value_indexed_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	request := db.lower_sql_filter_request(SqlFilterLoweringRequest{
		table_name:     'notes'
		filters:        [
			SqlFilterFragment.field_like_prefix('body', 'markdown', 'heading_text:2',
				'Road'),
			SqlFilterFragment.column_eq('title', 'Doc'),
		]
		select_columns: ['title']
		limit:          7
	}) or { panic(err) }

	assert request.table_name == 'notes'
	assert request.filters.len == 2
	assert request.filters[0].op == .prefix
	assert request.filters[0].plugin_name == 'markdown'
	assert request.filters[0].selector == 'heading_text:2'
	assert request.filters[1].op == .eq
	assert request.limit == 7
}

fn test_sql_predicate_adapter_exposes_supported_sql_subset() {
	assert sql_supported_filter_kinds() == [.eq, .like_prefix, .gt, .lt, .between]
}

fn test_sql_predicate_adapter_rejects_incomplete_field_selector_target() {
	if _ := adapt_sql_predicate_fragment(SqlPredicateAdapterInput{
		target:     QueryPredicateTarget{
			column_name: 'body'
			plugin_name: 'markdown'
		}
		kind:       .eq
		value:      'Road'
		source_sql: "markdown_selector(body, 'heading_text:2') = 'Road'"
	})
	{
		panic('expected incomplete field selector target to fail')
	} else {
		assert err.msg().contains('plugin_name and selector')
	}
}

fn test_database_session_lookup_json_path_index_prefix_projected() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-json-prefix-projected')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_items_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut seed_row := TypedRowData.new()
	seed_row.set('id', '000')
	seed_row.set('status', 'draft')
	seed_row.set('meta', '{"kind":"seed.zero","enabled":false}')
	seed_row.set('enabled', false)
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: TypedRowCodec.new(spec.table).encode(seed_row) or { panic(err) }
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.begin_session(SessionOptions.for_branch('main')) or { panic(err) }
	mut row1 := TypedRowData.new()
	row1.set('id', '001')
	row1.set('status', 'draft')
	row1.set('meta', '{"kind":"alpha.one","enabled":false}')
	row1.set('enabled', false)
	_ = session.put_row(mut db, 'items', '001'.bytes(), row1, cfg, CommitMeta{
		author:    'gwg'
		message:   'put first item'
		timestamp: 1
	}) or { panic(err) }
	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('status', 'active')
	row2.set('meta', '{"kind":"alpha.two","enabled":true}')
	row2.set('enabled', true)
	_ = session.put_row(mut db, 'items', '002'.bytes(), row2, cfg, CommitMeta{
		author:    'gwg'
		message:   'put second item'
		timestamp: 2
	}) or { panic(err) }
	rows := session.lookup_index_prefix_projected(mut db, 'items', 'kind_cover', 'alpha.',
		10, [
		'status',
	]) or { panic(err) }
	assert rows.len == 2
	assert rows[0].data.has('status')
	assert !rows[0].data.has('meta')
	assert !rows[0].data.has('id')
}

fn test_database_session_count_rows_and_sum_i64_column() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-count-sum')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_metrics_plain_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed := TypedRowData.new()
	seed.set('id', i64(0))
	seed.set('name', 'zero')
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	for idx in 1 .. 4 {
		mut row := TypedRowData.new()
		row.set('id', i64(idx))
		row.set('name', 'user-${idx}')
		_ = session.put_row(mut db, 'metrics', '${idx:03}'.bytes(), row, cfg, CommitMeta{
			author:    'gwg'
			message:   'seed row ${idx}'
			timestamp: idx
		}) or { panic(err) }
	}

	assert session.count_rows(mut db, 'metrics') or { panic(err) } == 4
	assert session.sum_i64_column(mut db, 'metrics', 'id') or { panic(err) } == i64(6)
}

fn test_database_session_sum_i64_column_tracks_incremental_updates() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-sum-incremental')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_metrics_plain_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut row1 := TypedRowData.new()
	row1.set('id', i64(1))
	row1.set('name', 'one')
	codec := TypedRowCodec.new(spec.table)
	mut seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'metrics').key_for('001'.bytes())
			value: codec.encode(row1) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_aggregates_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed 1'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session()!
	assert session.sum_i64_column(mut db, 'metrics', 'id') or { panic(err) } == i64(1)

	mut row2 := TypedRowData.new()
	row2.set('id', i64(5))
	row2.set('name', 'five')
	_ = session.put_row(mut db, 'metrics', '005'.bytes(), row2, cfg, CommitMeta{
		author:    'gwg'
		message:   'put 5'
		timestamp: 2
	}) or { panic(err) }
	assert session.sum_i64_column(mut db, 'metrics', 'id') or { panic(err) } == i64(6)

	mut updated := TypedRowData.new()
	updated.set('id', i64(9))
	updated.set('name', 'nine')
	_ = session.put_row(mut db, 'metrics', '005'.bytes(), updated, cfg, CommitMeta{
		author:    'gwg'
		message:   'update 5->9'
		timestamp: 3
	}) or { panic(err) }
	assert session.sum_i64_column(mut db, 'metrics', 'id') or { panic(err) } == i64(10)
}

fn test_database_session_sum_i64_column_range_uses_declared_aggregate_buckets() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-sum-range-buckets')
	defer {
		os.rmdir_all(dir) or {}
	}
	spec := database_metrics_plain_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', i64(1))
	seed_row.set('name', 'one')
	mut seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'metrics').key_for('a1'.bytes())
			value: codec.encode(seed_row) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_aggregates_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed range'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session()!
	mut rows := [
		['a2', '2', 'two'],
		['b1', '3', 'three'],
		['c1', '4', 'four'],
	]
	for idx, raw in rows {
		mut row := TypedRowData.new()
		row.set('id', raw[1].i64())
		row.set('name', raw[2])
		_ = session.put_row(mut db, 'metrics', raw[0].bytes(), row, cfg, CommitMeta{
			author:    'gwg'
			message:   'put ${idx + 1}'
			timestamp: idx + 2
		}) or { panic(err) }
	}
	assert session.sum_i64_column_range(mut db, 'metrics', 'id', 'a2'.bytes(), 'c1'.bytes()) or {
		panic(err)
	} == i64(5)
}

fn test_database_session_covering_index_lookup_roundtrip() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-covering-index')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_covering_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or {
		panic(err)
	}
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	rows := session.lookup_index(mut db, 'users', 'email', 'ada@example.com', 1) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '001'
	name := rows[0].data.get('name') or { panic(err) }
	match name {
		string { assert name == 'ada' }
		else { panic('expected string name') }
	}
}

fn test_persistent_database_default_session() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-default-session')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	db.close() or { panic(err) }

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	session := reopened.begin_default_session() or { panic(err) }
	assert session.branch_name == 'main'
	row := session.get_row(mut reopened, 'users', '001'.bytes()) or { panic(err) }
	name := row.data.get('name') or { panic(err) }
	match name {
		string { assert name == 'ada' }
		else { panic('expected string name') }
	}
}

fn test_persistent_database_checkpoint_persists_catalog_and_repo() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-checkpoint')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	db.checkpoint() or { panic(err) }

	assert os.exists(os.join_path(dir, '.pollydb', 'repo.meta'))
	assert os.exists(os.join_path(dir, '.pollydb', 'catalog.meta'))
	assert os.exists(os.join_path(dir, '.pollydb', 'nodes.chunk.idx'))
	assert os.exists(os.join_path(dir, '.pollydb', 'commits.chunk.idx'))
	db.close() or { panic(err) }
}

fn test_persistent_database_checkpoint_info_and_recovery_status() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-status')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	db.checkpoint() or { panic(err) }

	info := db.checkpoint_info()
	assert info.catalog_exists
	assert info.registered_tables == 1
	assert info.engine.repository.repository_exists
	assert info.engine.repository.node_store.chunk_store.index_snapshot_exists
	assert info.engine.repository.commit_store.chunk_store.index_snapshot_exists

	status := PersistentDatabase.recovery_status(dir, 'main') or { panic(err) }
	assert status.catalog_exists
	assert status.engine.repository.repository_exists
	assert status.engine.repository.node_store.chunk_store.index_snapshot_valid
	assert status.engine.repository.commit_store.chunk_store.index_snapshot_valid
	assert status.engine.repository.node_store.chunk_store.index_entries > 0
	assert status.engine.repository.commit_store.chunk_store.index_entries > 0

	report := db.status_report() or { panic(err) }
	assert report.repository_exists
	assert report.catalog_exists
	assert report.registered_tables == 1
	assert report.branch_count == 1
	assert report.branches == ['main']
	assert report.node_index_snapshot_valid
	assert report.commit_index_snapshot_valid
	assert report.durable

	inspected := PersistentDatabase.inspect(dir, 'main') or { panic(err) }
	assert inspected.repository_exists
	assert inspected.catalog_exists
	assert inspected.registered_tables == 1
	assert inspected.branch_count == 1
	assert inspected.branches == ['main']
	assert inspected.node_index_entries > 0
	assert inspected.commit_index_entries > 0
	assert inspected.durable
	assert report.recommended_aggregate_projection_refresh_policy == 'stale_one'
	assert inspected.recommended_aggregate_projection_refresh_policy == 'stale_one'

	lines := report.summary_lines()
	assert lines.len >= 9
	assert lines[0].contains('root_dir=')
	assert lines.any(it.contains('branches=1 [main]'))
	assert lines.any(it.contains('recommended_aggregate_projection_refresh_policy=stale_one'))
	formatted := report.format()
	assert formatted.contains('durable=true')
	assert formatted.contains('node_index_snapshot_valid=true')
}

fn test_database_session_cursors() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-cursors')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }

	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'add grace'
		timestamp: 2
	}) or { panic(err) }

	mut table_cursor := session.table_cursor(mut db, 'users', []u8{}, 0) or { panic(err) }
	peeked := table_cursor.peek() or { panic(err) }
	assert peeked.primary_key.bytestr() == '001'
	nexted := table_cursor.next() or { panic(err) }
	assert nexted.primary_key.bytestr() == '001'
	collected := table_cursor.collect(0) or { panic(err) }
	assert collected.len == 1
	assert collected[0].primary_key.bytestr() == '002'

	mut index_cursor := session.index_cursor(mut db, 'users', 'email', 'grace@example.com',
		[]u8{}, 0) or { panic(err) }
	index_row := index_cursor.peek() or { panic(err) }
	assert index_row.primary_key.bytestr() == '002'
	email := index_row.row.data.get('email') or { panic(err) }
	match email {
		string { assert email == 'grace@example.com' }
		else { panic('expected string email') }
	}
}

fn test_persistent_database_inspect_uninitialized_directory() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-inspect-empty')
	defer {
		os.rmdir_all(dir) or {}
	}
	os.mkdir_all(dir) or { panic(err) }

	report := PersistentDatabase.inspect(dir, 'main') or { panic(err) }
	assert !report.repository_exists
	assert !report.catalog_exists
	assert report.registered_tables == 0
	assert report.branch_count == 0
	assert report.branches.len == 0
	assert !report.node_index_snapshot_valid
	assert !report.commit_index_snapshot_valid
	assert !report.durable
}

fn test_register_aggregate_projection_binds_virtual_root_to_commit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-binding')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_metrics_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.sum_i64('sum(metrics.id)',
		'metrics', 'id') or { panic(err) }) or { panic(err) }
	assert db.projector_names() == ['sum(metrics.id)']
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', i64(1))
	seed_row.set('name', 'seed')
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'metrics').key_for('m-000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed metrics branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', i64(7))
	row.set('name', 'sample')
	_ = session.put_row(mut db, 'metrics', 'm-001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert metric row'
		timestamp: 1
	}) or { panic(err) }

	head := db.head() or { panic(err) }
	commit := db.engine.commit_by_cid(head.commit_cid) or { panic(err) }
	assert commit.virtual_roots.len == 1
	assert commit.virtual_roots[0].name == 'sum(metrics.id)'
	assert commit.virtual_roots[0].source_data_root_cid == commit.root_cid
	assert !commit.virtual_roots[0].fresh
	assert commit.virtual_roots[0].stale_reason == 'registration_backfill'

	states := db.projection_states_at_branch('main') or { panic(err) }
	assert states.len == 1
	assert states[0].projection.name == 'sum(metrics.id)'
	assert states[0].source_data_root_cid == commit.root_cid
	assert !states[0].fresh
	assert states[0].stale_reason == 'registration_backfill'
	report := db.status_report() or { panic(err) }
	assert report.registered_projectors == 1
	assert report.stale_projectors == 1
	assert report.fresh_projectors == 0

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	assert reopened.projector_names() == ['sum(metrics.id)']
	assert (reopened.projector_spec('sum(metrics.id)') or { panic(err) }).priority == 100
	assert (reopened.projector_spec('sum(metrics.id)') or { panic(err) }).cost_hint == .medium
}

fn test_refresh_aggregate_projections_marks_virtual_root_fresh() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-refresh')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_metrics_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.sum_i64('sum(metrics.id)',
		'metrics', 'id') or { panic(err) }) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', i64(2))
	seed_row.set('name', 'seed')
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'metrics').key_for('m-000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed metrics branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', i64(7))
	row.set('name', 'sample')
	_ = session.put_row(mut db, 'metrics', 'm-001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert metric row'
		timestamp: 1
	}) or { panic(err) }

	refreshed := db.refresh_aggregate_projections('main', cfg, CommitMeta{
		author:    'gwg'
		message:   'refresh aggregate projector'
		timestamp: 2
	}) or { panic(err) }
	assert refreshed.virtual_roots.len == 1
	assert refreshed.virtual_roots[0].fresh
	assert refreshed.virtual_roots[0].source_data_root_cid == refreshed.root_cid
	assert refreshed.virtual_roots[0].root_cid.len > 0

	item := Tree.lookup_in_byte_store(refreshed.virtual_roots[0].root_cid, 'aggregate:sum(metrics.id)'.bytes(), mut
		db.engine.repository.node_store) or { panic(err) }
	value := TypedValueEncoder.decode_value(item.value, .i64_) or { panic(err) }
	match value {
		i64 { assert value == i64(9) }
		else { panic('expected i64 aggregate projection value') }
	}
	report := db.status_report() or { panic(err) }
	assert report.registered_projectors == 1
	assert report.stale_projectors == 0
	assert report.fresh_projectors == 1
}

fn test_refresh_aggregate_projections_counts_markdown_structures() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-markdown-structures')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.count_markdown_blocks('count(notes.body.blocks)',
		'notes', 'body') or { panic(err) }) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.count_markdown_links('count(notes.body.links)',
		'notes', 'body') or { panic(err) }) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.count_markdown_heading_level('count(notes.body.h2)',
		'notes', 'body', 2) or { panic(err) }) or { panic(err) }

	codec := TypedRowCodec.new(spec.table)
	mut row := TypedRowData.new()
	row.set('id', 'note-1')
	row.set('title', 'Architecture')
	row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed note branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Intro\n\nSee [docs](https://example.com/docs).\n\n## Details\n\n```v\nprintln("ok")\n```\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'seed note markdown'
		timestamp: 2
	}) or { panic(err) }

	refreshed := db.refresh_aggregate_projections('main', cfg, CommitMeta{
		author:    'gwg'
		message:   'refresh markdown aggregate projectors'
		timestamp: 3
	}) or { panic(err) }
	assert refreshed.virtual_roots.len == 3
	mut roots := map[string]string{}
	for virtual_root in refreshed.virtual_roots {
		roots[virtual_root.name] = virtual_root.root_cid
	}

	block_item := Tree.lookup_in_byte_store(roots['count(notes.body.blocks)'], 'aggregate:count(notes.body.blocks)'.bytes(), mut
		db.engine.repository.node_store) or { panic(err) }
	block_value := TypedValueEncoder.decode_value(block_item.value, .i64_) or { panic(err) }
	match block_value {
		i64 { assert block_value == i64(4) }
		else { panic('expected markdown block count') }
	}

	link_item := Tree.lookup_in_byte_store(roots['count(notes.body.h2)'], 'aggregate:count(notes.body.h2)'.bytes(), mut
		db.engine.repository.node_store) or { panic(err) }
	link_value := TypedValueEncoder.decode_value(link_item.value, .i64_) or { panic(err) }
	match link_value {
		i64 { assert link_value == i64(1) }
		else { panic('expected markdown heading count') }
	}

	heading_item := Tree.lookup_in_byte_store(roots['count(notes.body.links)'], 'aggregate:count(notes.body.links)'.bytes(), mut
		db.engine.repository.node_store) or { panic(err) }
	heading_value := TypedValueEncoder.decode_value(heading_item.value, .i64_) or { panic(err) }
	match heading_value {
		i64 { assert heading_value == i64(1) }
		else { panic('expected markdown link count') }
	}
}

fn test_refresh_aggregate_projections_persists_markdown_selector_metadata() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-markdown-metadata')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection((AggregateProjectionDef.count_markdown_code_blocks_with_lang('count(notes.body.code.v)',
		'notes', 'body', 'v') or { panic(err) }).with_cost_hint(.low).with_priority(250)) or {
		panic(err)
	}

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	projector := reopened.projector_spec('count(notes.body.code.v)') or { panic(err) }
	assert projector.is_field_projection_selector()
	assert projector.field_projection_plugin() == 'markdown'
	assert projector.field_projection_selector() == 'code_blocks:v'
	assert projector.source_markdown_selector == 'code_blocks:v'
	assert projector.priority == 250
	assert projector.cost_hint == .low
}

fn test_refresh_aggregate_projections_rejects_markdown_selector_on_non_markdown_column() {
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-markdown-invalid')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_items_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	if _ := db.register_aggregate_projection(AggregateProjectionDef.count_markdown_links('count(items.meta.links)',
		'items', 'meta') or { panic(err) })
	{
		panic('expected non-markdown markdown projector registration to fail')
	} else {
		assert err.msg().contains('requires markdown column')
	}
}

fn test_projection_value_at_branch_reads_markdown_projector_value() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-markdown-read')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.count_markdown_code_blocks_with_lang('count(notes.body.code.v)',
		'notes', 'body', 'v') or { panic(err) }) or { panic(err) }

	codec := TypedRowCodec.new(spec.table)
	mut row := TypedRowData.new()
	row.set('id', 'note-1')
	row.set('title', 'Snippet')
	row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed note branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '```v\nprintln("a")\n```\n\n```sql\nselect 1;\n```\n\n```v\nprintln("b")\n```\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'seed note markdown'
		timestamp: 2
	}) or { panic(err) }
	_ = db.refresh_aggregate_projections('main', cfg, CommitMeta{
		author:    'gwg'
		message:   'refresh markdown aggregate projector'
		timestamp: 3
	}) or { panic(err) }

	value := db.projection_value_at_branch('main', 'count(notes.body.code.v)') or { panic(err) }
	assert value.value == i64(2)
	assert value.fresh
	assert value.virtual_root_cid.len > 0
	assert value.projection.source_markdown_selector == 'code_blocks:v'
	assert (db.projection_i64('count(notes.body.code.v)') or { panic(err) }) == i64(2)
}

fn test_markdown_projection_i64_computes_ad_hoc_selector_counts() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-markdown-adhoc')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_notes_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }

	codec := TypedRowCodec.new(spec.table)
	mut row := TypedRowData.new()
	row.set('id', 'note-1')
	row.set('title', 'Doc')
	row.set('body', MarkdownRef{
		doc_root_id: 'seed'
		source_hash: 'seed'
		source_len:  0
	})
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'notes').key_for('note-1'.bytes())
			value: codec.encode(row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed note branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	_ = session.put_markdown(mut db, 'notes', 'note-1'.bytes(), 'body', '# Intro\n\nPara with `x` and [docs](https://example.com).\n\n![alt](https://example.com/a.png)\n',
		cfg, CommitMeta{
		author:    'gwg'
		message:   'seed note markdown'
		timestamp: 2
	}) or { panic(err) }

	assert (db.markdown_projection_i64('notes', 'body', 'headings') or { panic(err) }) == i64(1)
	assert (db.markdown_projection_i64('notes', 'body', 'links') or { panic(err) }) == i64(1)
	assert (db.markdown_projection_i64('notes', 'body', 'images') or { panic(err) }) == i64(1)
	assert (db.markdown_projection_i64('notes', 'body', 'code_spans') or { panic(err) }) == i64(1)
}

fn test_projector_stale_reason_new_data_root_after_refresh() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-new-data-root')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_metrics_plain_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.sum_i64('sum(metrics.id)',
		'metrics', 'id') or { panic(err) }) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', i64(2))
	seed_row.set('name', 'seed')
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'metrics').key_for('m-000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed metrics branch'
		timestamp: 0
	}) or { panic(err) }
	_ = db.refresh_aggregate_projections('main', cfg, CommitMeta{
		author:    'gwg'
		message:   'refresh aggregate projector'
		timestamp: 1
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', i64(7))
	row.set('name', 'sample')
	_ = session.put_row(mut db, 'metrics', 'm-001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert metric row'
		timestamp: 2
	}) or { panic(err) }

	states := db.projection_states_at_branch('main') or { panic(err) }
	assert states.len == 1
	assert !states[0].fresh
	assert states[0].stale_reason == 'new_data_root'

	db.close() or { panic(err) }
	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	reopened_states := reopened.projection_states_at_branch('main') or { panic(err) }
	assert reopened_states.len == 1
	assert !reopened_states[0].fresh
	assert reopened_states[0].stale_reason == 'new_data_root'
}

fn test_refresh_aggregate_projections_async_for_marks_virtual_root_fresh() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-async-refresh')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_metrics_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.sum_i64('sum(metrics.id)',
		'metrics', 'id') or { panic(err) }) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', i64(3))
	seed_row.set('name', 'seed')
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'metrics').key_for('m-000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed metrics branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', i64(5))
	row.set('name', 'sample')
	_ = session.put_row(mut db, 'metrics', 'm-001'.bytes(), row, cfg, CommitMeta{
		author:    'gwg'
		message:   'insert metric row'
		timestamp: 1
	}) or { panic(err) }

	mut handle := db.refresh_aggregate_projections_async('main') or { panic(err) }
	handle.wait() or { panic(err) }

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	states := reopened.projection_states_at_branch('main') or { panic(err) }
	assert states.len == 1
	assert states[0].fresh
	assert states[0].virtual_root_cid.len > 0
}

fn test_refresh_aggregate_projections_limited_keeps_remaining_stale() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-limited-refresh')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_items_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).a',
		'items', 'meta', 'amount') or { panic(err) }) or { panic(err) }
	db.register_aggregate_projection(AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).b',
		'items', 'meta', 'amount') or { panic(err) }) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', '001')
	seed_row.set('status', 'active')
	seed_row.set('enabled', true)
	seed_row.set('meta', '{"amount":4,"kind":"seed"}')
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'items').key_for('001'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed items branch'
		timestamp: 0
	}) or { panic(err) }

	refreshed := db.refresh_aggregate_projections_limited('main', cfg, CommitMeta{
		author:    'gwg'
		message:   'limited refresh aggregate projectors'
		timestamp: 1
	}, 1) or { panic(err) }
	assert refreshed.virtual_roots.len == 2
	mut fresh_count := 0
	mut stale_count := 0
	for virtual_root in refreshed.virtual_roots {
		if virtual_root.fresh {
			fresh_count++
			assert virtual_root.root_cid.len > 0
		} else {
			stale_count++
			assert virtual_root.stale_reason == 'policy_budget_skipped'
		}
	}
	assert fresh_count == 1
	assert stale_count == 1
}

fn test_refresh_aggregate_projections_limited_prefers_higher_priority() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-priority-refresh')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_items_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection((AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).low',
		'items', 'meta', 'amount') or { panic(err) }).with_priority(10)) or { panic(err) }
	db.register_aggregate_projection((AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).high',
		'items', 'meta', 'amount') or { panic(err) }).with_priority(500)) or { panic(err) }
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', '001')
	seed_row.set('status', 'active')
	seed_row.set('enabled', true)
	seed_row.set('meta', '{"amount":4,"kind":"seed"}')
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'items').key_for('001'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed items branch'
		timestamp: 0
	}) or { panic(err) }

	refreshed := db.refresh_aggregate_projections_limited('main', cfg, CommitMeta{
		author:    'gwg'
		message:   'priority refresh aggregate projectors'
		timestamp: 1
	}, 1) or { panic(err) }
	assert refreshed.virtual_roots.len == 2
	mut high_fresh := false
	mut low_stale := false
	for virtual_root in refreshed.virtual_roots {
		if virtual_root.name == 'sum(items.meta.amount).high' {
			assert virtual_root.fresh
			high_fresh = true
		}
		if virtual_root.name == 'sum(items.meta.amount).low' {
			assert !virtual_root.fresh
			assert virtual_root.stale_reason == 'policy_budget_skipped'
			low_stale = true
		}
	}
	assert high_fresh
	assert low_stale
}

fn test_refresh_aggregate_projections_limited_prefers_lower_cost_at_same_priority() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-aggregate-projector-cost-refresh')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_items_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	db.register_table(spec) or { panic(err) }
	db.register_aggregate_projection((AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).slow',
		'items', 'meta', 'amount') or { panic(err) }).with_priority(200).with_cost_hint(.high)) or {
		panic(err)
	}
	db.register_aggregate_projection((AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).fast',
		'items', 'meta', 'amount') or { panic(err) }).with_priority(200).with_cost_hint(.low)) or {
		panic(err)
	}
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', '001')
	seed_row.set('status', 'active')
	seed_row.set('enabled', true)
	seed_row.set('meta', '{"amount":4,"kind":"seed"}')
	seed_tree := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'items').key_for('001'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author:    'gwg'
		message:   'seed items branch'
		timestamp: 0
	}) or { panic(err) }

	refreshed := db.refresh_aggregate_projections_limited('main', cfg, CommitMeta{
		author:    'gwg'
		message:   'cost refresh aggregate projectors'
		timestamp: 1
	}, 1) or { panic(err) }
	assert refreshed.virtual_roots.len == 2
	mut fast_fresh := false
	mut slow_stale := false
	for virtual_root in refreshed.virtual_roots {
		if virtual_root.name == 'sum(items.meta.amount).fast' {
			assert virtual_root.fresh
			fast_fresh = true
		}
		if virtual_root.name == 'sum(items.meta.amount).slow' {
			assert !virtual_root.fresh
			slow_stale = true
		}
	}
	assert fast_fresh
	assert slow_stale

	mut reopened := PersistentDatabase.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	assert (reopened.projector_spec('sum(items.meta.amount).fast') or { panic(err) }).cost_hint == .low
	assert (reopened.projector_spec('sum(items.meta.amount).slow') or { panic(err) }).cost_hint == .high
}
