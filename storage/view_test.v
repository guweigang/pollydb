module storage

fn test_table_view_put_get_and_lower_bound_wrap_tree_keys() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	base := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: 'ada'.bytes()
		},
	], cfg) or { panic(err) }
	mut table := TableView.new(base, 'users')
	table = table.put('003'.bytes(), 'grace'.bytes(), cfg) or { panic(err) }
	table = table.put('005'.bytes(), 'linus'.bytes(), cfg) or { panic(err) }

	row := table.get('003'.bytes()) or { panic(err) }
	lower := table.lower_bound('004'.bytes()) or { panic(err) }

	assert row.primary_key.bytestr() == '003'
	assert row.value.bytestr() == 'grace'
	assert lower.primary_key.bytestr() == '005'
	assert table.has('001'.bytes())
	assert !table.has('999'.bytes())
}

fn test_table_cursor_collects_decoded_rows() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	base := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: 'ada'.bytes()
		},
	], cfg) or { panic(err) }
	mut table := TableView.new(base, 'users')
	table = table.put('002'.bytes(), 'grace'.bytes(), cfg) or { panic(err) }
	table = table.put('003'.bytes(), 'linus'.bytes(), cfg) or { panic(err) }

	mut cursor := table.cursor('002'.bytes(), 0) or { panic(err) }
	first := cursor.peek() or { panic(err) }
	rows := cursor.collect(0) or { panic(err) }

	assert first.primary_key.bytestr() == '002'
	assert rows.len == 2
	assert rows[0].primary_key.bytestr() == '002'
	assert rows[0].value.bytestr() == 'grace'
	assert rows[1].primary_key.bytestr() == '003'
}

fn test_table_raw_cursor_count_and_sum_i64_column() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('name', .string_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut rows := []KVPair{}
	for idx in 1 .. 4 {
		mut row := TypedRowData.new()
		row.set('id', i64(idx))
		row.set('name', 'user-${idx}')
		rows << KVPair{
			key: TableView.new(Tree{}, 'users').key_for('${idx:03}'.bytes())
			value: codec.encode(row) or { panic(err) }
		}
	}
	tree := Tree.build(rows, cfg) or { panic(err) }
	table := TableView.new(tree, 'users')

	mut count_cursor := table.raw_cursor([]u8{}, 0) or { panic(err) }
	assert count_cursor.count_remaining() or { panic(err) } == 3

	mut sum_cursor := table.raw_cursor([]u8{}, 0) or { panic(err) }
	assert sum_cursor.sum_i64_column(codec, 'id') or { panic(err) } == i64(6)
}

fn test_index_view_orders_entries_by_index_key_then_primary_key() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	base := Tree.build([
		KVPair{
			key: IndexView.new(Tree{}, 'users', 'email').key_for('b@example.com'.bytes(), '002'.bytes())
			value: 'row-002'.bytes()
		},
	], cfg) or { panic(err) }
	mut index := IndexView.new(base, 'users', 'email')
	index = index.put('a@example.com'.bytes(), '003'.bytes(), 'row-003'.bytes(), cfg) or { panic(err) }
	index = index.put('b@example.com'.bytes(), '001'.bytes(), 'row-001'.bytes(), cfg) or { panic(err) }

	entry := index.get('b@example.com'.bytes(), '001'.bytes()) or { panic(err) }
	mut cursor := index.cursor([]u8{}, []u8{}, 0) or { panic(err) }
	entries := cursor.collect(0) or { panic(err) }

	assert entry.index_key.bytestr() == 'b@example.com'
	assert entry.primary_key.bytestr() == '001'
	assert entry.value.bytestr() == 'row-001'
	assert entries.len == 3
	assert entries[0].index_key.bytestr() == 'a@example.com'
	assert entries[0].primary_key.bytestr() == '003'
	assert entries[1].index_key.bytestr() == 'b@example.com'
	assert entries[1].primary_key.bytestr() == '001'
	assert entries[2].primary_key.bytestr() == '002'
}
