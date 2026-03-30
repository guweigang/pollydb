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

fn database_seed_tree(spec TypedTableSpec, primary_key string, name string, email string, cfg ChunkConfig) !Tree {
	codec := TypedRowCodec.new(spec.table)
	mut row := TypedRowData.new()
	row.set('id', primary_key)
	row.set('name', name)
	row.set('email', email)
	return Tree.build([
		KVPair{
			key: TableView.new(Tree{}, spec.table.name).key_for(primary_key.bytes())
			value: codec.encode(row)!
		},
	], cfg)
}

fn test_persistent_database_typed_roundtrip() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
		timestamp: 0
	}) or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('name', 'ada')
	row.set('email', 'ada@example.com')
	writes.put('users', '001'.bytes(), row)
	result := db.apply_typed_write_set('main', writes, cfg, CommitMeta{
		author: 'gwg'
		message: 'seed users'
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
		mask: 0
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
			key: TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }

	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('title', 'draft')
	_ = session.put_row(mut db, 'events', '001'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'insert event'
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
		else { panic('expected created_at datetime string') }
	}
	match updated_at {
		string {
			updated_at_text = updated_at
			_ := time.parse_rfc3339(updated_at_text) or { panic(err) }
		}
		else { panic('expected updated_at datetime string') }
	}
	time.sleep(2 * time.millisecond)
	mut patch := TypedRowData.new()
	patch.set('title', 'published')
	_ = session.put_row(mut db, 'events', '001'.bytes(), patch, cfg, CommitMeta{
		author: 'gwg'
		message: 'update event'
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
		else { panic('expected updated_at datetime string after update') }
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
		mask: 0
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
			key: TableView.new(Tree{}, spec.table.name).key_for('001'.bytes())
			value: codec.encode(row1)!
		},
		KVPair{
			key: TableView.new(Tree{}, spec.table.name).key_for('002'.bytes())
			value: codec.encode(row2)!
		},
		KVPair{
			key: TableView.new(Tree{}, spec.table.name).key_for('003'.bytes())
			value: codec.encode(row3)!
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed events'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	rows := session.lookup_index_between(
		mut db,
		'events',
		'created_at_idx',
		'2026-03-30T10:30:00.000000Z',
		'2026-03-30T12:00:00.000000Z',
		10,
	) or { panic(err) }
	assert rows.len == 2
	assert rows[0].primary_key.bytestr() == '002'
	assert rows[1].primary_key.bytestr() == '003'
}

fn test_persistent_database_datetime_index_after_lookup() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
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
			key: TableView.new(Tree{}, spec.table.name).key_for('001'.bytes())
			value: codec.encode(row1)!
		},
		KVPair{
			key: TableView.new(Tree{}, spec.table.name).key_for('002'.bytes())
			value: codec.encode(row2)!
		},
		KVPair{
			key: TableView.new(Tree{}, spec.table.name).key_for('003'.bytes())
			value: codec.encode(row3)!
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed events'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	rows := session.lookup_index_after(
		mut db,
		'events',
		'created_at_idx',
		'2026-03-30T11:00:00.000000Z',
		10,
	) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '003'
}

fn test_persistent_database_datetime_index_before_lookup() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
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
			key: TableView.new(Tree{}, spec.table.name).key_for('001'.bytes())
			value: codec.encode(row1)!
		},
		KVPair{
			key: TableView.new(Tree{}, spec.table.name).key_for('002'.bytes())
			value: codec.encode(row2)!
		},
		KVPair{
			key: TableView.new(Tree{}, spec.table.name).key_for('003'.bytes())
			value: codec.encode(row3)!
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed events'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	rows := session.lookup_index_before(
		mut db,
		'events',
		'created_at_idx',
		'2026-03-30T11:00:00.000000Z',
		10,
	) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '001'
}

fn test_persistent_database_json_path_indexes_lookup() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
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
			key: TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('status', 'active')
	row.set('meta', '{"kind":"alpha","enabled":true}')
	row.set('enabled', true)
	_ = session.put_row(mut db, 'items', '001'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'put item'
		timestamp: 1
	}) or { panic(err) }

	status_rows := session.lookup_index(mut db, 'items', 'status_idx', 'active', 10) or { panic(err) }
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
		mask: 0
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
			key: TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: TypedRowCodec.new(spec.table).encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row1 := TypedRowData.new()
	row1.set('id', '001')
	row1.set('status', 'active')
	row1.set('meta', '{"kind":{"code":"alpha.one"}}')
	_ = session.put_row(mut db, 'items', '001'.bytes(), row1, cfg, CommitMeta{
		author: 'gwg'
		message: 'put first item'
		timestamp: 1
	}) or { panic(err) }
	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('status', 'draft')
	row2.set('meta', '{"kind":{"code":"alpha.two"}}')
	_ = session.put_row(mut db, 'items', '002'.bytes(), row2, cfg, CommitMeta{
		author: 'gwg'
		message: 'put second item'
		timestamp: 2
	}) or { panic(err) }

	exact_rows := session.lookup_index(mut db, 'items', 'kind_code_idx', 'alpha.one', 10) or { panic(err) }
	assert exact_rows.len == 1
	assert exact_rows[0].primary_key.bytestr() == '001'

	projected_rows := session.lookup_index_prefix_projected(mut db, 'items', 'kind_code_cover', 'alpha.', 10, [
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
		mask: 0
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
			key: TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: TypedRowCodec.new(spec.table).encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('status', 'active')
	row.set('meta', '{"kind":"alpha","enabled":true}')
	row.set('enabled', true)
	_ = session.put_row(mut db, 'items', '001'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'put item'
		timestamp: 1
	}) or { panic(err) }

	before := session.lookup_index(mut db, 'items', 'kind_idx', 'alpha', 10) or { panic(err) }
	assert before.len == 1
	_ = session.set_json_path(mut db, 'items', '001'.bytes(), 'meta', 'kind', 'beta', cfg, CommitMeta{
		author: 'gwg'
		message: 'set json path'
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
		mask: 0
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
			key: TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: TypedRowCodec.new(spec.table).encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '001')
	row.set('status', 'active')
	row.set('meta', '{"kind":"alpha","enabled":true,"legacy":"old"}')
	row.set('enabled', true)
	_ = session.put_row(mut db, 'items', '001'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'put item'
		timestamp: 1
	}) or { panic(err) }

	_ = session.set_json_path_null(mut db, 'items', '001'.bytes(), 'meta', 'kind', cfg, CommitMeta{
		author: 'gwg'
		message: 'null kind'
		timestamp: 2
	}) or { panic(err) }
	null_lookup := session.lookup_index(mut db, 'items', 'kind_idx', NullValue{}, 10) or { panic(err) }
	assert null_lookup.len == 1

	_ = session.delete_json_path(mut db, 'items', '001'.bytes(), 'meta', 'legacy', cfg, CommitMeta{
		author: 'gwg'
		message: 'delete legacy'
		timestamp: 3
	}) or { panic(err) }

	_ = session.patch_json_paths(mut db, 'items', '001'.bytes(), 'meta', [
		JsonPathUpdate{
			path: 'kind'
			op: .set
			value: 'gamma'
		},
		JsonPathUpdate{
			path: 'enabled'
			op: .set
			value: false
		},
	], cfg, CommitMeta{
		author: 'gwg'
		message: 'patch json'
		timestamp: 4
	}) or { panic(err) }

	old_kind := session.lookup_index(mut db, 'items', 'kind_idx', 'alpha', 10) or { panic(err) }
	new_kind := session.lookup_index(mut db, 'items', 'kind_idx', 'gamma', 10) or { panic(err) }
	enabled_false := session.lookup_index(mut db, 'items', 'enabled_idx', false, 10) or { panic(err) }
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
		else { panic('expected patched json payload') }
	}
}

fn test_persistent_database_commit_typed_working_set() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	dir := os.join_path(os.vtmp_dir(), 'pollydb-database-working-set')
	defer {
		os.rmdir_all(dir) or {}
	}

	spec := database_users_spec() or { panic(err) }
	mut db := PersistentDatabase.init(dir, 'main') or { panic(err) }
	db.register_table(spec) or { panic(err) }
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
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
		author: 'gwg'
		message: 'commit working set'
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
		mask: 0
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
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
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
		author: 'gwg'
		message: 'session commit'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'put row'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'put row'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
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
		author: 'gwg'
		message: 'update row'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
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
		author: 'gwg'
		message: 'add grace'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }

	mut row1 := TypedRowData.new()
	row1.set('id', '001')
	row1.set('name', 'ada')
	row1.set('email', 'ada@example.com')
	_ = session.put_row(mut db, 'users', '001'.bytes(), row1, cfg, CommitMeta{
		author: 'gwg'
		message: 'add ada'
		timestamp: 1
	}) or { panic(err) }

	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('name', 'alan')
	row2.set('email', 'alan@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row2, cfg, CommitMeta{
		author: 'gwg'
		message: 'add alan'
		timestamp: 2
	}) or { panic(err) }

	mut row3 := TypedRowData.new()
	row3.set('id', '003')
	row3.set('name', 'grace')
	row3.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '003'.bytes(), row3, cfg, CommitMeta{
		author: 'gwg'
		message: 'add grace'
		timestamp: 3
	}) or { panic(err) }
	db.checkpoint() or { panic(err) }
	head := db.branch('main') or { panic(err) }

	scheduler := db.snapshot_read_scheduler()
	mut h := scheduler.lookup_index_prefix_async(head.commit_cid, 'users', 'email', 'al', 10)
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
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
			author: 'gwg'
			message: 'add ${id}'
			timestamp: 1
		}) or { panic(err) }
	}
	db.checkpoint() or { panic(err) }
	head := db.branch('main') or { panic(err) }

	scheduler := db.snapshot_read_scheduler()
	mut h := scheduler.scan_table_from_async(head.commit_cid, 'users', '002'.bytes(), 10)
	result := h.wait() or { panic(err) }
	assert result.rows.len == 2
	assert result.rows[0].primary_key.bytestr() == '002'
	assert result.rows[1].primary_key.bytestr() == '003'
}

fn test_snapshot_read_scheduler_prefix_index_lookup_from_primary_key() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
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
			author: 'gwg'
			message: 'add ${id}'
			timestamp: 1
		}) or { panic(err) }
	}
	db.checkpoint() or { panic(err) }
	head := db.branch('main') or { panic(err) }

	scheduler := db.snapshot_read_scheduler()
	mut h := scheduler.lookup_index_prefix_from_async(head.commit_cid, 'users', 'email', 'al', '002'.bytes(), 10)
	result := h.wait() or { panic(err) }
	assert result.rows.len == 1
	assert result.rows[0].primary_key.bytestr() == '002'
}

fn test_database_preview_merge_reports_root_hash_merge_shape() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	mut main_row := TypedRowData.new()
	main_row.set('id', '002')
	main_row.set('name', 'main')
	main_row.set('email', 'main@example.com')
	_ = main_session.put_row(mut db, 'users', '002'.bytes(), main_row, cfg, CommitMeta{
		author: 'gwg'
		message: 'main update'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	mut feature_row := TypedRowData.new()
	feature_row.set('id', '003')
	feature_row.set('name', 'feature')
	feature_row.set('email', 'feature@example.com')
	_ = feature_session.put_row(mut db, 'users', '003'.bytes(), feature_row, cfg, CommitMeta{
		author: 'gwg'
		message: 'feature update'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	mut main_row := TypedRowData.new()
	main_row.set('id', '002')
	main_row.set('name', 'main')
	main_row.set('email', 'main@example.com')
	_ = main_session.put_row(mut db, 'users', '002'.bytes(), main_row, cfg, CommitMeta{
		author: 'gwg'
		message: 'main update'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	mut feature_row := TypedRowData.new()
	feature_row.set('id', '003')
	feature_row.set('name', 'feature')
	feature_row.set('email', 'feature@example.com')
	_ = feature_session.put_row(mut db, 'users', '003'.bytes(), feature_row, cfg, CommitMeta{
		author: 'gwg'
		message: 'feature update'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
		timestamp: 1
	}) or { panic(err) }
	_ = db.create_branch('feature', seed.branch.commit_cid) or { panic(err) }

	main_session := db.open_session('main') or { panic(err) }
	mut main_row := TypedRowData.new()
	main_row.set('id', '001')
	main_row.set('name', 'main')
	main_row.set('email', 'main@example.com')
	_ = main_session.put_row(mut db, 'users', '001'.bytes(), main_row, cfg, CommitMeta{
		author: 'gwg'
		message: 'main conflict'
		timestamp: 2
	}) or { panic(err) }

	feature_session := db.open_session('feature') or { panic(err) }
	mut feature_row := TypedRowData.new()
	feature_row.set('id', '001')
	feature_row.set('name', 'feature')
	feature_row.set('email', 'feature@example.com')
	_ = feature_session.put_row(mut db, 'users', '001'.bytes(), feature_row, cfg, CommitMeta{
		author: 'gwg'
		message: 'feature conflict'
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

fn test_database_replays_checkpoint_journal_on_open() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'put row'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
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
			author: 'gwg'
			message: 'put row ${id}'
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
		mask: 0
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
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
		timestamp: 1
	}) or { panic(err) }

	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '004')
	row.set('name', 'ken')
	row.set('email', 'ken@example.com')
	_ = session.put_row(mut db, 'users', '004'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'put row'
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
		author: 'gwg'
		message: 'delete row'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.open_session('main') or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'put row'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
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
		author: 'gwg'
		message: 'seed users'
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
		mask: 0
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
	seed_tree := database_seed_tree(spec, '001', 'ada', 'alice@example.com', cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
		timestamp: 0
	}) or { panic(err) }
	mut writes := TypedWriteSet.new()
	mut alan := TypedRowData.new()
	alan.set('id', '002')
	alan.set('name', 'alan')
	alan.set('email', 'albert@example.com')
	writes.put('users', '002'.bytes(), alan)
	_ = db.apply_typed_write_set('main', writes, cfg, CommitMeta{
		author: 'gwg'
		message: 'seed users'
		timestamp: 1
	}) or { panic(err) }

	session := db.begin_session(SessionOptions.for_branch('main')) or { panic(err) }
	rows := session.lookup_index_prefix_projected(mut db, 'users', 'email', 'al', 10, ['email']) or {
		panic(err)
	}
	assert rows.len > 0
	assert rows[0].data.has('email')
	assert !rows[0].data.has('name')
	assert !rows[0].data.has('id')
}

fn test_database_session_lookup_json_path_index_prefix_projected() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
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
			key: TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: TypedRowCodec.new(spec.table).encode(seed_row) or { panic(err) }
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.begin_session(SessionOptions.for_branch('main')) or { panic(err) }
	mut row1 := TypedRowData.new()
	row1.set('id', '001')
	row1.set('status', 'draft')
	row1.set('meta', '{"kind":"alpha.one","enabled":false}')
	row1.set('enabled', false)
	_ = session.put_row(mut db, 'items', '001'.bytes(), row1, cfg, CommitMeta{
		author: 'gwg'
		message: 'put first item'
		timestamp: 1
	}) or { panic(err) }
	mut row2 := TypedRowData.new()
	row2.set('id', '002')
	row2.set('status', 'active')
	row2.set('meta', '{"kind":"alpha.two","enabled":true}')
	row2.set('enabled', true)
	_ = session.put_row(mut db, 'items', '002'.bytes(), row2, cfg, CommitMeta{
		author: 'gwg'
		message: 'put second item'
		timestamp: 2
	}) or { panic(err) }
	rows := session.lookup_index_prefix_projected(mut db, 'items', 'kind_cover', 'alpha.', 10, [
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
		mask: 0
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
			key: TableView.new(Tree{}, spec.table.name).key_for('000'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
		timestamp: 0
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }
	for idx in 1 .. 4 {
		mut row := TypedRowData.new()
		row.set('id', i64(idx))
		row.set('name', 'user-${idx}')
		_ = session.put_row(mut db, 'metrics', '${idx:03}'.bytes(), row, cfg, CommitMeta{
			author: 'gwg'
			message: 'seed row ${idx}'
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
		mask: 0
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
			key: TableView.new(Tree{}, 'metrics').key_for('001'.bytes())
			value: codec.encode(row1) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_aggregates_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed 1'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session()!
	assert session.sum_i64_column(mut db, 'metrics', 'id') or { panic(err) } == i64(1)

	mut row2 := TypedRowData.new()
	row2.set('id', i64(5))
	row2.set('name', 'five')
	_ = session.put_row(mut db, 'metrics', '005'.bytes(), row2, cfg, CommitMeta{
		author: 'gwg'
		message: 'put 5'
		timestamp: 2
	}) or { panic(err) }
	assert session.sum_i64_column(mut db, 'metrics', 'id') or { panic(err) } == i64(6)

	mut updated := TypedRowData.new()
	updated.set('id', i64(9))
	updated.set('name', 'nine')
	_ = session.put_row(mut db, 'metrics', '005'.bytes(), updated, cfg, CommitMeta{
		author: 'gwg'
		message: 'update 5->9'
		timestamp: 3
	}) or { panic(err) }
	assert session.sum_i64_column(mut db, 'metrics', 'id') or { panic(err) } == i64(10)
}

fn test_database_session_sum_i64_column_range_uses_declared_aggregate_buckets() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
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
			key: TableView.new(Tree{}, 'metrics').key_for('a1'.bytes())
			value: codec.encode(seed_row) or { panic(err) }
		},
	], cfg) or { panic(err) }
	seed_tree = rebuild_typed_aggregates_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed range'
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
			author: 'gwg'
			message: 'put ${idx + 1}'
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
		mask: 0
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
	mut seed_tree := database_seed_tree(spec, '001', 'ada', 'ada@example.com', cfg) or { panic(err) }
	seed_tree = rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed branch'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
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
		mask: 0
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
		author: 'gwg'
		message: 'seed branch'
		timestamp: 1
	}) or { panic(err) }
	session := db.begin_default_session() or { panic(err) }

	mut row := TypedRowData.new()
	row.set('id', '002')
	row.set('name', 'grace')
	row.set('email', 'grace@example.com')
	_ = session.put_row(mut db, 'users', '002'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'add grace'
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

	mut index_cursor := session.index_cursor(mut db, 'users', 'email', 'grace@example.com', []u8{}, 0) or {
		panic(err)
	}
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
		mask: 0
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
	db.register_aggregate_projection(AggregateProjectionDef.sum_i64('sum(metrics.id)', 'metrics', 'id') or { panic(err) }) or {
		panic(err)
	}
	assert db.projector_names() == ['sum(metrics.id)']
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', i64(1))
	seed_row.set('name', 'seed')
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'metrics').key_for('m-000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed metrics branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', i64(7))
	row.set('name', 'sample')
	_ = session.put_row(mut db, 'metrics', 'm-001'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'insert metric row'
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
		mask: 0
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
	db.register_aggregate_projection(AggregateProjectionDef.sum_i64('sum(metrics.id)', 'metrics', 'id') or { panic(err) }) or {
		panic(err)
	}
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', i64(2))
	seed_row.set('name', 'seed')
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'metrics').key_for('m-000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed metrics branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', i64(7))
	row.set('name', 'sample')
	_ = session.put_row(mut db, 'metrics', 'm-001'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'insert metric row'
		timestamp: 1
	}) or { panic(err) }

	refreshed := db.refresh_aggregate_projections('main', cfg, CommitMeta{
		author: 'gwg'
		message: 'refresh aggregate projector'
		timestamp: 2
	}) or { panic(err) }
	assert refreshed.virtual_roots.len == 1
	assert refreshed.virtual_roots[0].fresh
	assert refreshed.virtual_roots[0].source_data_root_cid == refreshed.root_cid
	assert refreshed.virtual_roots[0].root_cid.len > 0

	item := Tree.lookup_in_byte_store(refreshed.virtual_roots[0].root_cid, 'aggregate:sum(metrics.id)'.bytes(), mut db.engine.repository.node_store) or {
		panic(err)
	}
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

fn test_projector_stale_reason_new_data_root_after_refresh() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
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
	db.register_aggregate_projection(AggregateProjectionDef.sum_i64('sum(metrics.id)', 'metrics', 'id') or { panic(err) }) or {
		panic(err)
	}
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', i64(2))
	seed_row.set('name', 'seed')
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'metrics').key_for('m-000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed metrics branch'
		timestamp: 0
	}) or { panic(err) }
	_ = db.refresh_aggregate_projections('main', cfg, CommitMeta{
		author: 'gwg'
		message: 'refresh aggregate projector'
		timestamp: 1
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', i64(7))
	row.set('name', 'sample')
	_ = session.put_row(mut db, 'metrics', 'm-001'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'insert metric row'
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
		mask: 0
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
	db.register_aggregate_projection(AggregateProjectionDef.sum_i64('sum(metrics.id)', 'metrics', 'id') or { panic(err) }) or {
		panic(err)
	}
	codec := TypedRowCodec.new(spec.table)
	mut seed_row := TypedRowData.new()
	seed_row.set('id', i64(3))
	seed_row.set('name', 'seed')
	seed_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'metrics').key_for('m-000'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed metrics branch'
		timestamp: 0
	}) or { panic(err) }

	session := db.begin_default_session() or { panic(err) }
	mut row := TypedRowData.new()
	row.set('id', i64(5))
	row.set('name', 'sample')
	_ = session.put_row(mut db, 'metrics', 'm-001'.bytes(), row, cfg, CommitMeta{
		author: 'gwg'
		message: 'insert metric row'
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
		mask: 0
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
	db.register_aggregate_projection(AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).a', 'items', 'meta', 'amount') or { panic(err) }) or {
		panic(err)
	}
	db.register_aggregate_projection(AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).b', 'items', 'meta', 'amount') or { panic(err) }) or {
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
			key: TableView.new(Tree{}, 'items').key_for('001'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed items branch'
		timestamp: 0
	}) or { panic(err) }

	refreshed := db.refresh_aggregate_projections_limited('main', cfg, CommitMeta{
		author: 'gwg'
		message: 'limited refresh aggregate projectors'
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
		mask: 0
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
	db.register_aggregate_projection((AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).low', 'items', 'meta', 'amount') or {
		panic(err)
	}).with_priority(10)) or {
		panic(err)
	}
	db.register_aggregate_projection((AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).high', 'items', 'meta', 'amount') or {
		panic(err)
	}).with_priority(500)) or {
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
			key: TableView.new(Tree{}, 'items').key_for('001'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed items branch'
		timestamp: 0
	}) or { panic(err) }

	refreshed := db.refresh_aggregate_projections_limited('main', cfg, CommitMeta{
		author: 'gwg'
		message: 'priority refresh aggregate projectors'
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
		mask: 0
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
	db.register_aggregate_projection((AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).slow', 'items', 'meta', 'amount') or {
		panic(err)
	}).with_priority(200).with_cost_hint(.high)) or {
		panic(err)
	}
	db.register_aggregate_projection((AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).fast', 'items', 'meta', 'amount') or {
		panic(err)
	}).with_priority(200).with_cost_hint(.low)) or {
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
			key: TableView.new(Tree{}, 'items').key_for('001'.bytes())
			value: codec.encode(seed_row)!
		},
	], cfg) or { panic(err) }
	_ = db.commit_to_branch('main', seed_tree, CommitMeta{
		author: 'gwg'
		message: 'seed items branch'
		timestamp: 0
	}) or { panic(err) }

	refreshed := db.refresh_aggregate_projections_limited('main', cfg, CommitMeta{
		author: 'gwg'
		message: 'cost refresh aggregate projectors'
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
