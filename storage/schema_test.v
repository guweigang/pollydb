module storage

fn test_row_codec_roundtrip_preserves_declared_columns() {
	codec := RowCodec.new(['name', 'email', 'city']) or { panic(err) }
	mut row := RowData.new()
	row.set('name', 'ada'.bytes())
	row.set('email', 'ada@example.com'.bytes())

	encoded := codec.encode(row) or { panic(err) }
	decoded := codec.decode(encoded) or { panic(err) }

	assert (decoded.get('name') or { panic(err) }).bytestr() == 'ada'
	assert (decoded.get('email') or { panic(err) }).bytestr() == 'ada@example.com'
	assert !decoded.has('city')
}

fn test_row_codec_rejects_unknown_columns() {
	codec := RowCodec.new(['name']) or { panic(err) }
	mut row := RowData.new()
	row.set('email', 'ada@example.com'.bytes())

	if _ := codec.encode(row) {
		assert false
	} else {
		assert err.msg().contains('does not define column')
	}
}

fn test_schema_view_put_get_and_collect_decode_rows() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut seed := RowData.new()
	seed.set('name', 'ada'.bytes())
	seed.set('email', 'ada@example.com'.bytes())

	base := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }

	table := TableView.new(base, 'users')
	mut schema := SchemaView.new(table, codec)
	mut second := RowData.new()
	second.set('name', 'grace'.bytes())
	second.set('email', 'grace@example.com'.bytes())
	schema = schema.put('002'.bytes(), second, cfg) or { panic(err) }

	row := schema.get('002'.bytes()) or { panic(err) }
	rows := schema.collect(0) or { panic(err) }

	assert row.primary_key.bytestr() == '002'
	assert (row.data.get('name') or { panic(err) }).bytestr() == 'grace'
	assert rows.len == 2
	assert rows[0].primary_key.bytestr() == '001'
	assert (rows[1].data.get('email') or { panic(err) }).bytestr() == 'grace@example.com'
}

fn test_schema_cursor_seek_peek_and_skip_work() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	codec := RowCodec.new(['name']) or { panic(err) }
	mut first := RowData.new()
	first.set('name', 'ada'.bytes())
	base := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(first) or { panic(err) }
		},
	], cfg) or { panic(err) }

	table := TableView.new(base, 'users')
	mut schema := SchemaView.new(table, codec)
	for idx, name in ['grace', 'linus'] {
		mut row := RowData.new()
		row.set('name', name.bytes())
		schema = schema.put('${idx + 2:03}'.bytes(), row, cfg) or { panic(err) }
	}

	mut cursor := schema.cursor('001'.bytes(), 0) or { panic(err) }
	assert (cursor.peek() or { panic(err) }).primary_key.bytestr() == '001'
	assert (cursor.skip(1) or { panic(err) }) == 1
	cursor.seek('003'.bytes()) or { panic(err) }
	row := cursor.next() or { panic(err) }

	assert row.primary_key.bytestr() == '003'
	assert (row.data.get('name') or { panic(err) }).bytestr() == 'linus'
}

fn test_indexed_schema_view_put_builds_secondary_index() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut seed := RowData.new()
	seed.set('name', 'ada'.bytes())
	seed.set('email', 'ada@example.com'.bytes())
	base := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }

	table := TableView.new(base, 'users')
	schema := SchemaView.new(table, codec)
	email_index := SchemaIndexDef.new('email', 'email') or { panic(err) }
	mut indexed := IndexedSchemaView.new(schema, [email_index]) or { panic(err) }
	mut second := RowData.new()
	second.set('name', 'grace'.bytes())
	second.set('email', 'grace@example.com'.bytes())
	indexed = indexed.put('002'.bytes(), second, cfg) or { panic(err) }

	rows := indexed.find_by_index('email', 'grace@example.com'.bytes(), 0) or { panic(err) }

	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '002'
	assert (rows[0].data.get('name') or { panic(err) }).bytestr() == 'grace'
}

fn test_indexed_schema_view_updates_stale_index_entries() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut seed := RowData.new()
	seed.set('name', 'ada'.bytes())
	seed.set('email', 'ada@example.com'.bytes())
	base := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }

	table := TableView.new(base, 'users')
	schema := SchemaView.new(table, codec)
	email_index := SchemaIndexDef.new('email', 'email') or { panic(err) }
	mut indexed := IndexedSchemaView.new(schema, [email_index]) or { panic(err) }

	mut updated := RowData.new()
	updated.set('name', 'ada'.bytes())
	updated.set('email', 'ada+new@example.com'.bytes())
	indexed = indexed.put('001'.bytes(), updated, cfg) or { panic(err) }

	old_rows := indexed.find_by_index('email', 'ada@example.com'.bytes(), 0) or { panic(err) }
	new_rows := indexed.find_by_index('email', 'ada+new@example.com'.bytes(), 0) or { panic(err) }

	assert old_rows.len == 0
	assert new_rows.len == 1
	assert new_rows[0].primary_key.bytestr() == '001'
	assert (new_rows[0].data.get('email') or { panic(err) }).bytestr() == 'ada+new@example.com'
}

fn test_indexed_schema_view_apply_mutations_batches_table_and_index_updates() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut seed := RowData.new()
	seed.set('name', 'ada'.bytes())
	seed.set('email', 'ada@example.com'.bytes())
	base := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }

	table := TableView.new(base, 'users')
	schema := SchemaView.new(table, codec)
	email_index := SchemaIndexDef.new('email', 'email') or { panic(err) }
	indexed := IndexedSchemaView.new(schema, [email_index]) or { panic(err) }

	mut second := RowData.new()
	second.set('name', 'grace'.bytes())
	second.set('email', 'grace@example.com'.bytes())
	mut third := RowData.new()
	third.set('name', 'linus'.bytes())
	third.set('email', 'linus@example.com'.bytes())
	update := indexed.apply_mutations([
		SchemaMutation.put('002'.bytes(), second),
		SchemaMutation.put('003'.bytes(), third),
	], cfg) or { panic(err) }

	assert update.diff.added_cids.len > 0
	rows := update.view.find_by_index('email', 'linus@example.com'.bytes(), 0) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '003'
}

fn test_indexed_schema_view_apply_mutations_coalesces_repeated_primary_key_changes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask:     0
	}
	codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut seed := RowData.new()
	seed.set('name', 'ada'.bytes())
	seed.set('email', 'ada@example.com'.bytes())
	base := Tree.build([
		KVPair{
			key:   TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }

	table := TableView.new(base, 'users')
	schema := SchemaView.new(table, codec)
	email_index := SchemaIndexDef.new('email', 'email') or { panic(err) }
	indexed := IndexedSchemaView.new(schema, [email_index]) or { panic(err) }

	mut first := RowData.new()
	first.set('name', 'ada'.bytes())
	first.set('email', 'ada+1@example.com'.bytes())
	mut second := RowData.new()
	second.set('name', 'ada'.bytes())
	second.set('email', 'ada+2@example.com'.bytes())
	update := indexed.apply_mutations([
		SchemaMutation.put('001'.bytes(), first),
		SchemaMutation.put('001'.bytes(), second),
	], cfg) or { panic(err) }

	old_rows := update.view.find_by_index('email', 'ada@example.com'.bytes(), 0) or { panic(err) }
	mid_rows := update.view.find_by_index('email', 'ada+1@example.com'.bytes(), 0) or { panic(err) }
	final_rows := update.view.find_by_index('email', 'ada+2@example.com'.bytes(), 0) or {
		panic(err)
	}

	assert old_rows.len == 0
	assert mid_rows.len == 0
	assert final_rows.len == 1
	assert final_rows[0].primary_key.bytestr() == '001'
}

fn test_schema_index_def_exposes_field_selector_metadata() {
	index := SchemaIndexDef.markdown_value('body_link_host_idx', 'body', 'link_host') or {
		panic(err)
	}
	table := TableDef.new('notes', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id']) or { panic(err) }

	assert index.is_markdown_selector()
	assert index.is_field_selector()
	assert index.field_selector_plugin() == 'markdown'
	assert index.field_selector() == 'link_host'
	assert index.target_label() == 'body#link_host'
	assert (index.value_column(table) or { panic(err) }).typ == .string_
}

fn test_schema_index_def_field_selector_constructor_supports_markdown_plugin() {
	index := SchemaIndexDef.field_selector('body_links_idx', 'body', 'markdown', 'links',
		.i64_, false) or { panic(err) }

	assert index.is_field_selector()
	assert index.field_selector_plugin() == 'markdown'
	assert index.field_selector() == 'links'
	selector_ref := index.field_selector_ref() or { panic('expected field selector ref') }
	assert selector_ref.plugin_name == 'markdown'
	assert selector_ref.selector == 'links'
	assert selector_ref.value_type == .i64_
	selector_meta := index.field_selector_meta() or { panic('expected field selector meta') }
	assert selector_meta.plugin_name == 'markdown'
	assert selector_meta.selector == 'links'
	assert selector_meta.value_type == .i64_
	assert !selector_meta.stores_row
	assert index.json_field_type == .i64_
	assert !index.stores_row
}

fn test_schema_index_def_exposes_fts_metadata_for_text_columns() {
	index := SchemaIndexDef.fts_with_options('content_fts_idx', 'content', FtsIndexOptions{
		tokenizer:      'unicode61 remove_diacritics 2'
		prefix_lengths: [3, 2, 3, 4]
	}) or { panic(err) }
	table := TableDef.new('docs', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('content', .string_, false)!,
	], ['id']) or { panic(err) }

	assert index.is_fts()
	assert !index.is_field_selector()
	assert index.fts_source_plugin == ''
	assert index.fts_text_mode == FtsTextMode.plain_text.str()
	assert index.fts_tokenizer == 'unicode61 remove_diacritics 2'
	assert index.fts_prefix_lengths == [2, 3, 4]
	assert index.target_label() == 'content#fts'
	assert (index.value_column(table) or { panic(err) }).typ == .string_
	validate_fts_index(table.column('content') or { panic(err) }, index) or { panic(err) }
}

fn test_schema_index_def_exposes_fts_metadata_for_markdown_columns() {
	index := SchemaIndexDef.fts_markdown_with_options('body_fts_idx', 'body', .visible_text,
		FtsIndexOptions{
		prefix_lengths: [2, 4]
	}) or { panic(err) }
	table := TableDef.new('docs', [
		ColumnDef.new('id', .string_, false)!,
		ColumnDef.new('body', .markdown_, false)!,
	], ['id']) or { panic(err) }

	assert index.is_fts()
	assert index.fts_source_plugin == 'markdown'
	assert index.fts_text_mode == FtsTextMode.visible_text.str()
	assert index.fts_tokenizer == 'unicode61'
	assert index.fts_prefix_lengths == [2, 4]
	validate_fts_index(table.column('body') or { panic(err) }, index) or { panic(err) }
}

fn test_validate_fts_index_rejects_markdown_mode_on_plain_text_column() {
	index := SchemaIndexDef{
		...SchemaIndexDef.fts_text('content_fts_idx', 'content') or { panic(err) }
		fts_source_plugin: 'markdown'
		fts_text_mode:     FtsTextMode.visible_text.str()
	}
	column := ColumnDef.new('content', .string_, false) or { panic(err) }

	if _ := validate_fts_index(column, index) {
		assert false
	} else {
		assert err.msg().contains('string fts index')
	}
}
