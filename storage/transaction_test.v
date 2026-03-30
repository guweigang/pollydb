module storage

fn test_transaction_apply_write_set_updates_multiple_tables() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	user_codec := RowCodec.new(['name', 'email']) or { panic(err) }
	order_codec := RowCodec.new(['user_id', 'status']) or { panic(err) }
	mut seed_user := RowData.new()
	seed_user.set('name', 'ada'.bytes())
	seed_user.set('email', 'ada@example.com'.bytes())
	mut seed_order := RowData.new()
	seed_order.set('user_id', '001'.bytes())
	seed_order.set('status', 'pending'.bytes())

	base := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'orders').key_for('order-001'.bytes())
			value: order_codec.encode(seed_order) or { panic(err) }
		},
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: user_codec.encode(seed_user) or { panic(err) }
		},
	], cfg) or { panic(err) }

	mut tx := Transaction.new(base)
	tx.register_table(TableSpec.new('users', user_codec, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }) or { panic(err) }
	tx.register_table(TableSpec.new('orders', order_codec, [
		SchemaIndexDef.new('status', 'status') or { panic(err) },
	]) or { panic(err) }) or { panic(err) }

	mut writes := WriteSet.new()
	mut user_row := RowData.new()
	user_row.set('name', 'grace'.bytes())
	user_row.set('email', 'grace@example.com'.bytes())
	writes.put('users', '002'.bytes(), user_row)
	mut order_row := RowData.new()
	order_row.set('user_id', '002'.bytes())
	order_row.set('status', 'paid'.bytes())
	writes.put('orders', 'order-002'.bytes(), order_row)

	result := tx.apply_write_set(writes, cfg) or { panic(err) }
	users := result.tx.indexed_view('users') or { panic(err) }
	orders := result.tx.indexed_view('orders') or { panic(err) }
	user_hits := users.find_by_index('email', 'grace@example.com'.bytes(), 0) or { panic(err) }
	order_hits := orders.find_by_index('status', 'paid'.bytes(), 0) or { panic(err) }

	assert result.diff.added_cids.len > 0
	assert user_hits.len == 1
	assert user_hits[0].primary_key.bytestr() == '002'
	assert order_hits.len == 1
	assert order_hits[0].primary_key.bytestr() == 'order-002'
}

fn test_transaction_write_set_handles_delete_and_put_together() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut first := RowData.new()
	first.set('name', 'ada'.bytes())
	first.set('email', 'ada@example.com'.bytes())
	mut second := RowData.new()
	second.set('name', 'grace'.bytes())
	second.set('email', 'grace@example.com'.bytes())

	base := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(first) or { panic(err) }
		},
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('002'.bytes())
			value: codec.encode(second) or { panic(err) }
		},
	], cfg) or { panic(err) }

	mut tx := Transaction.new(base)
	tx.register_table(TableSpec.new('users', codec, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }) or { panic(err) }

	mut writes := WriteSet.new()
	writes.delete('users', '001'.bytes())
	mut replacement := RowData.new()
	replacement.set('name', 'linus'.bytes())
	replacement.set('email', 'linus@example.com'.bytes())
	writes.put('users', '003'.bytes(), replacement)

	result := tx.apply_write_set(writes, cfg) or { panic(err) }
	users := result.tx.indexed_view('users') or { panic(err) }
	old_hits := users.find_by_index('email', 'ada@example.com'.bytes(), 0) or { panic(err) }
	new_hits := users.find_by_index('email', 'linus@example.com'.bytes(), 0) or { panic(err) }

	assert old_hits.len == 0
	assert new_hits.len == 1
	assert new_hits[0].primary_key.bytestr() == '003'
}

fn test_working_set_status_summarizes_row_and_index_changes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut seed := RowData.new()
	seed.set('name', 'ada'.bytes())
	seed.set('email', 'ada@example.com'.bytes())
	base := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }

	spec := TableSpec.new('users', codec, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }
	mut set := WorkingSet.new('main', 'base-commit', base, [spec]) or { panic(err) }
	mut writes := WriteSet.new()
	mut second := RowData.new()
	second.set('name', 'grace'.bytes())
	second.set('email', 'grace@example.com'.bytes())
	writes.put('users', '002'.bytes(), second)
	_ = set.apply_write_set(writes, cfg) or { panic(err) }

	status := set.status() or { panic(err) }

	assert status.branch_name == 'main'
	assert status.has_changes
	assert status.tables.len == 1
	assert status.tables[0].table_name == 'users'
	assert status.tables[0].row_changes.len == 1
	assert status.tables[0].row_changes[0].kind == .added
	assert status.tables[0].row_changes[0].key.bytestr().contains('t|users|002')
	assert status.tables[0].index_entry_changes.len == 1
	assert status.tables[0].index_entry_changes[0].kind == .added
	assert status.tables[0].index_entry_changes[0].index_name == 'email'
}

fn test_working_set_status_marks_deleted_keys() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut first := RowData.new()
	first.set('name', 'ada'.bytes())
	first.set('email', 'ada@example.com'.bytes())
	mut second := RowData.new()
	second.set('name', 'grace'.bytes())
	second.set('email', 'grace@example.com'.bytes())

	spec := TableSpec.new('users', codec, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }
	base_tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(first) or { panic(err) }
		},
	], cfg) or { panic(err) }
	base_schema := SchemaView.new(TableView.new(base_tree, 'users'), codec)
	mut indexed := IndexedSchemaView.new(base_schema, spec.indexes) or { panic(err) }
	indexed = indexed.put('002'.bytes(), second, cfg) or { panic(err) }
	base := indexed.schema.table.tree

	mut set := WorkingSet.new('main', 'base-commit', base, [spec]) or { panic(err) }
	mut writes := WriteSet.new()
	writes.delete('users', '002'.bytes())
	_ = set.apply_write_set(writes, cfg) or { panic(err) }

	status := set.status() or { panic(err) }

	assert status.tables.len == 1
	assert status.tables[0].row_changes.len == 1
	assert status.tables[0].row_changes[0].kind == .deleted
	assert status.tables[0].index_entry_changes.len == 1
	assert status.tables[0].index_entry_changes[0].kind == .deleted
}
