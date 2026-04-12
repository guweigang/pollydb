module storage

pub struct RowData {
mut:
	values map[string][]u8
}

pub struct RowCodec {
pub:
	columns []string
}

pub struct SchemaRow {
pub:
	primary_key []u8
	data        RowData
}

pub enum SchemaMutationOp {
	put
	delete
}

pub struct SchemaMutation {
pub:
	op          SchemaMutationOp
	primary_key []u8
	row         RowData
}

pub struct FieldSelectorRef {
pub:
	plugin_name string
	selector    string
	value_type  ColumnType
	stores_row  bool
}

pub enum FtsTextMode {
	plain_text
	visible_text
	visible_text_with_code
	raw_markdown
}

pub struct FtsIndexOptions {
pub:
	tokenizer      string = 'unicode61'
	prefix_lengths []int
}

pub struct SchemaView {
pub:
	table TableView
	codec RowCodec
}

pub struct SchemaIndexDef {
pub:
	name               string
	column             string
	json_field         string
	markdown_selector  string
	fts_source_plugin  string
	fts_text_mode      string
	fts_tokenizer      string
	fts_prefix_lengths []int
	json_field_type    ColumnType
	stores_row         bool
}

pub struct IndexedSchemaView {
pub:
	schema  SchemaView
	indexes []SchemaIndexDef
}

pub struct IndexedSchemaUpdate {
pub:
	view IndexedSchemaView
	diff TreeDiff
}

pub struct SchemaCursor {
pub:
	view SchemaView
mut:
	cursor TableCursor
}

pub fn RowData.new() RowData {
	return RowData{
		values: map[string][]u8{}
	}
}

pub fn (mut row RowData) set(name string, value []u8) {
	row.values[name] = value.clone()
}

pub fn (row RowData) get(name string) ![]u8 {
	value := row.values[name] or { return error('row field not found: ${name}') }
	return value.clone()
}

pub fn (row RowData) has(name string) bool {
	_ := row.values[name] or { return false }
	return true
}

pub fn (row RowData) len() int {
	return row.values.len
}

pub fn (row RowData) fields() map[string][]u8 {
	mut cloned := map[string][]u8{}
	for key, value in row.values {
		cloned[key] = value.clone()
	}
	return cloned
}

pub fn (row RowData) clone() RowData {
	mut cloned := RowData.new()
	for key, value in row.values {
		cloned.values[key] = value.clone()
	}
	return cloned
}

pub fn RowCodec.new(columns []string) !RowCodec {
	if columns.len == 0 {
		return error('row codec requires at least one column')
	}
	mut seen := map[string]bool{}
	mut normalized := []string{cap: columns.len}
	for column in columns {
		if column.len == 0 {
			return error('row codec column name cannot be empty')
		}
		if seen[column] {
			return error('duplicate row codec column: ${column}')
		}
		seen[column] = true
		normalized << column
	}
	return RowCodec{
		columns: normalized
	}
}

pub fn (codec RowCodec) has_column(name string) bool {
	for column in codec.columns {
		if column == name {
			return true
		}
	}
	return false
}

pub fn (codec RowCodec) encode(row RowData) ![]u8 {
	for name, _ in row.fields() {
		if !codec.has_column(name) {
			return error('row codec does not define column: ${name}')
		}
	}
	mut out := ByteWriter{}
	out.write_u32(u32(codec.columns.len))
	for column in codec.columns {
		if row.has(column) {
			value := row.get(column)!
			out.write_u8(1)
			out.write_u32(u32(value.len))
			out.write_bytes(value)
		} else {
			out.write_u8(0)
			out.write_u32(0)
		}
	}
	return out.bytes()
}

pub fn (codec RowCodec) decode(data []u8) !RowData {
	if data.len < 4 {
		return error('row payload too short')
	}
	column_count := int(read_u32_le(data[..4]))
	if column_count != codec.columns.len {
		return error('row payload column count mismatch')
	}
	mut cursor := 4
	mut row := RowData.new()
	for column in codec.columns {
		if cursor + 5 > data.len {
			return error('row payload truncated')
		}
		present := data[cursor]
		cursor++
		value_len := int(read_u32_le(data[cursor..cursor + 4]))
		cursor += 4
		if present == 0 {
			continue
		}
		if cursor + value_len > data.len {
			return error('row payload value overflow')
		}
		row.set(column, data[cursor..cursor + value_len])
		cursor += value_len
	}
	if cursor != data.len {
		return error('row payload trailing bytes')
	}
	return row
}

pub fn SchemaView.new(table TableView, codec RowCodec) SchemaView {
	return SchemaView{
		table: table
		codec: codec
	}
}

pub fn SchemaMutation.put(primary_key []u8, row RowData) SchemaMutation {
	return SchemaMutation{
		op:          .put
		primary_key: primary_key.clone()
		row:         row.clone()
	}
}

pub fn SchemaMutation.delete(primary_key []u8) SchemaMutation {
	return SchemaMutation{
		op:          .delete
		primary_key: primary_key.clone()
		row:         RowData.new()
	}
}

pub fn (view SchemaView) with_table(table TableView) SchemaView {
	return SchemaView.new(table, view.codec)
}

pub fn (view SchemaView) put(primary_key []u8, row RowData, cfg ChunkConfig) !SchemaView {
	next_table := view.table.put(primary_key, view.codec.encode(row)!, cfg)!
	return view.with_table(next_table)
}

pub fn (view SchemaView) get(primary_key []u8) !SchemaRow {
	row := view.table.get(primary_key)!
	return SchemaRow{
		primary_key: row.primary_key
		data:        view.codec.decode(row.value)!
	}
}

pub fn (view SchemaView) lower_bound(primary_key []u8) !SchemaRow {
	row := view.table.lower_bound(primary_key)!
	return SchemaRow{
		primary_key: row.primary_key
		data:        view.codec.decode(row.value)!
	}
}

pub fn (view SchemaView) cursor(start_primary_key []u8, limit int) !SchemaCursor {
	return SchemaCursor{
		view:   view
		cursor: view.table.cursor(start_primary_key, limit)!
	}
}

pub fn (view SchemaView) collect(limit int) ![]SchemaRow {
	mut cursor := view.cursor([]u8{}, limit)!
	return cursor.collect(limit)
}

pub fn (mut cursor SchemaCursor) seek(primary_key []u8) ! {
	cursor.cursor.seek(primary_key)!
}

pub fn (cursor SchemaCursor) current() !SchemaRow {
	row := cursor.cursor.current()!
	return SchemaRow{
		primary_key: row.primary_key
		data:        cursor.view.codec.decode(row.value)!
	}
}

pub fn (mut cursor SchemaCursor) peek() !SchemaRow {
	row := cursor.cursor.peek()!
	return SchemaRow{
		primary_key: row.primary_key
		data:        cursor.view.codec.decode(row.value)!
	}
}

pub fn (mut cursor SchemaCursor) next() !SchemaRow {
	row := cursor.cursor.next()!
	return SchemaRow{
		primary_key: row.primary_key
		data:        cursor.view.codec.decode(row.value)!
	}
}

pub fn (mut cursor SchemaCursor) skip(count int) !int {
	return cursor.cursor.skip(count)
}

pub fn (mut cursor SchemaCursor) collect(count int) ![]SchemaRow {
	rows := cursor.cursor.collect(count)!
	mut decoded := []SchemaRow{cap: rows.len}
	for row in rows {
		decoded << SchemaRow{
			primary_key: row.primary_key
			data:        cursor.view.codec.decode(row.value)!
		}
	}
	return decoded
}

pub fn SchemaIndexDef.new(name string, column string) !SchemaIndexDef {
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	return SchemaIndexDef{
		name:               name
		column:             column
		json_field:         ''
		markdown_selector:  ''
		fts_source_plugin:  ''
		fts_text_mode:      ''
		fts_tokenizer:      ''
		fts_prefix_lengths: []int{}
		json_field_type:    .string_
		stores_row:         false
	}
}

pub fn SchemaIndexDef.covering(name string, column string) !SchemaIndexDef {
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	return SchemaIndexDef{
		name:               name
		column:             column
		json_field:         ''
		markdown_selector:  ''
		fts_source_plugin:  ''
		fts_text_mode:      ''
		fts_tokenizer:      ''
		fts_prefix_lengths: []int{}
		json_field_type:    .string_
		stores_row:         true
	}
}

pub fn SchemaIndexDef.json_path(name string, column string, json_field string, json_field_type ColumnType) !SchemaIndexDef {
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	if json_field.len == 0 {
		return error('schema index json field cannot be empty')
	}
	match json_field_type {
		.bool_, .i64_, .string_ {}
		else { return error('schema index json field type must be bool, i64, or string') }
	}
	return SchemaIndexDef{
		name:               name
		column:             column
		json_field:         json_field
		markdown_selector:  ''
		fts_source_plugin:  ''
		fts_text_mode:      ''
		fts_tokenizer:      ''
		fts_prefix_lengths: []int{}
		json_field_type:    json_field_type
		stores_row:         false
	}
}

pub fn SchemaIndexDef.json_path_covering(name string, column string, json_field string, json_field_type ColumnType) !SchemaIndexDef {
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	if json_field.len == 0 {
		return error('schema index json field cannot be empty')
	}
	match json_field_type {
		.bool_, .i64_, .string_ {}
		else { return error('schema index json field type must be bool, i64, or string') }
	}
	return SchemaIndexDef{
		name:               name
		column:             column
		json_field:         json_field
		markdown_selector:  ''
		fts_source_plugin:  ''
		fts_text_mode:      ''
		fts_tokenizer:      ''
		fts_prefix_lengths: []int{}
		json_field_type:    json_field_type
		stores_row:         true
	}
}

pub fn SchemaIndexDef.markdown_metric(name string, column string, selector string) !SchemaIndexDef {
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	validate_markdown_index_selector(selector, .i64_)!
	return SchemaIndexDef{
		name:               name
		column:             column
		json_field:         ''
		markdown_selector:  selector
		fts_source_plugin:  ''
		fts_text_mode:      ''
		fts_tokenizer:      ''
		fts_prefix_lengths: []int{}
		json_field_type:    .i64_
		stores_row:         false
	}
}

pub fn SchemaIndexDef.markdown_metric_covering(name string, column string, selector string) !SchemaIndexDef {
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	validate_markdown_index_selector(selector, .i64_)!
	return SchemaIndexDef{
		name:               name
		column:             column
		json_field:         ''
		markdown_selector:  selector
		fts_source_plugin:  ''
		fts_text_mode:      ''
		fts_tokenizer:      ''
		fts_prefix_lengths: []int{}
		json_field_type:    .i64_
		stores_row:         true
	}
}

pub fn SchemaIndexDef.markdown_value(name string, column string, selector string) !SchemaIndexDef {
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	validate_markdown_index_selector(selector, .string_)!
	return SchemaIndexDef{
		name:               name
		column:             column
		json_field:         ''
		markdown_selector:  selector
		fts_source_plugin:  ''
		fts_text_mode:      ''
		fts_tokenizer:      ''
		fts_prefix_lengths: []int{}
		json_field_type:    .string_
		stores_row:         false
	}
}

pub fn SchemaIndexDef.markdown_value_covering(name string, column string, selector string) !SchemaIndexDef {
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	validate_markdown_index_selector(selector, .string_)!
	return SchemaIndexDef{
		name:               name
		column:             column
		json_field:         ''
		markdown_selector:  selector
		fts_source_plugin:  ''
		fts_text_mode:      ''
		fts_tokenizer:      ''
		fts_prefix_lengths: []int{}
		json_field_type:    .string_
		stores_row:         true
	}
}

pub fn SchemaIndexDef.fts(name string, column string) !SchemaIndexDef {
	return SchemaIndexDef.fts_text(name, column)
}

pub fn SchemaIndexDef.fts_with_options(name string, column string, options FtsIndexOptions) !SchemaIndexDef {
	return SchemaIndexDef.fts_text_with_options(name, column, options)
}

pub fn SchemaIndexDef.fts_text(name string, column string) !SchemaIndexDef {
	return SchemaIndexDef.fts_text_with_options(name, column, FtsIndexOptions{})
}

pub fn SchemaIndexDef.fts_text_with_options(name string, column string, options FtsIndexOptions) !SchemaIndexDef {
	validate_fts_index_options(options)!
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	return SchemaIndexDef{
		name:               name
		column:             column
		json_field:         ''
		markdown_selector:  ''
		fts_source_plugin:  ''
		fts_text_mode:      FtsTextMode.plain_text.str()
		fts_tokenizer:      normalized_fts_tokenizer(options)
		fts_prefix_lengths: normalized_fts_prefix_lengths(options.prefix_lengths)
		json_field_type:    .string_
		stores_row:         false
	}
}

pub fn SchemaIndexDef.fts_markdown(name string, column string, mode FtsTextMode) !SchemaIndexDef {
	return SchemaIndexDef.fts_markdown_with_options(name, column, mode, FtsIndexOptions{})
}

pub fn SchemaIndexDef.fts_markdown_with_options(name string, column string, mode FtsTextMode, options FtsIndexOptions) !SchemaIndexDef {
	validate_fts_index_options(options)!
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	match mode {
		.visible_text, .visible_text_with_code, .raw_markdown {}
		.plain_text {
			return error('markdown fts index requires markdown text mode')
		}
	}
	return SchemaIndexDef{
		name:               name
		column:             column
		json_field:         ''
		markdown_selector:  ''
		fts_source_plugin:  'markdown'
		fts_text_mode:      mode.str()
		fts_tokenizer:      normalized_fts_tokenizer(options)
		fts_prefix_lengths: normalized_fts_prefix_lengths(options.prefix_lengths)
		json_field_type:    .string_
		stores_row:         false
	}
}

pub fn SchemaIndexDef.field_selector(name string, column string, plugin_name string, selector string, value_type ColumnType, stores_row bool) !SchemaIndexDef {
	if name.len == 0 {
		return error('schema index name cannot be empty')
	}
	if column.len == 0 {
		return error('schema index column cannot be empty')
	}
	if plugin_name.len == 0 {
		return error('schema field selector plugin cannot be empty')
	}
	if selector.len == 0 {
		return error('schema field selector cannot be empty')
	}
	validate_named_field_selector(plugin_name, selector, value_type)!
	return match plugin_name {
		'markdown' {
			if value_type == .i64_ {
				if stores_row {
					SchemaIndexDef.markdown_metric_covering(name, column, selector)!
				} else {
					SchemaIndexDef.markdown_metric(name, column, selector)!
				}
			} else if stores_row {
				SchemaIndexDef.markdown_value_covering(name, column, selector)!
			} else {
				SchemaIndexDef.markdown_value(name, column, selector)!
			}
		}
		else {
			return error('unsupported field selector plugin: ${plugin_name}')
		}
	}
}

pub fn (index SchemaIndexDef) is_json_path() bool {
	return index.json_field.len > 0
}

pub fn (index SchemaIndexDef) is_markdown_selector() bool {
	return index.markdown_selector.len > 0
}

pub fn (index SchemaIndexDef) is_fts() bool {
	return index.fts_text_mode.len > 0
}

pub fn (index SchemaIndexDef) is_field_selector() bool {
	return index.is_markdown_selector()
}

pub fn (index SchemaIndexDef) field_selector_plugin() string {
	if index.is_markdown_selector() {
		return 'markdown'
	}
	return ''
}

pub fn (index SchemaIndexDef) field_selector() string {
	if index.is_markdown_selector() {
		return index.markdown_selector
	}
	return ''
}

pub fn (index SchemaIndexDef) field_selector_ref() ?FieldSelectorRef {
	plugin_name := index.field_selector_plugin()
	selector := index.field_selector()
	if plugin_name.len == 0 || selector.len == 0 {
		return none
	}
	return FieldSelectorRef{
		plugin_name: plugin_name
		selector:    selector
		value_type:  index.json_field_type
		stores_row:  index.stores_row
	}
}

pub fn (index SchemaIndexDef) field_selector_meta() ?FieldSelectorMeta {
	plugin_name := index.field_selector_plugin()
	selector := index.field_selector()
	if plugin_name.len == 0 || selector.len == 0 {
		return none
	}
	return FieldSelectorMeta{
		plugin_name: plugin_name
		selector:    selector
		value_type:  index.json_field_type
		stores_row:  index.stores_row
	}
}

pub fn (index SchemaIndexDef) target_label() string {
	if index.is_fts() {
		return '${index.column}#fts'
	}
	if index.json_field.len == 0 {
		selector := index.field_selector()
		if selector.len == 0 {
			return index.column
		}
		return '${index.column}#${selector}'
	}
	return '${index.column}.${index.json_field}'
}

pub fn (index SchemaIndexDef) value_column(table TableDef) !ColumnDef {
	if index.is_fts() {
		return ColumnDef.new('fts_text', .string_, false)
	}
	if index.is_field_selector() {
		return ColumnDef.new('field_index', index.json_field_type, false)
	}
	if index.json_field.len == 0 {
		return table.column(index.column)
	}
	return ColumnDef.new(index.json_field, index.json_field_type, true)
}

pub fn IndexedSchemaView.new(schema SchemaView, indexes []SchemaIndexDef) !IndexedSchemaView {
	mut names := map[string]bool{}
	for index in indexes {
		if names[index.name] {
			return error('duplicate schema index: ${index.name}')
		}
		if !schema.codec.has_column(index.column) {
			return error('schema index column not in codec: ${index.column}')
		}
		if index.is_json_path() || index.is_field_selector() || index.is_fts() {
			return error('schema json-path indexes are only supported by typed tables')
		}
		names[index.name] = true
	}
	return IndexedSchemaView{
		schema:  schema
		indexes: indexes.clone()
	}
}

pub fn (view IndexedSchemaView) with_schema(schema SchemaView) IndexedSchemaView {
	return IndexedSchemaView{
		schema:  schema
		indexes: view.indexes.clone()
	}
}

pub fn (view IndexedSchemaView) index_view(name string) !IndexView {
	for index in view.indexes {
		if index.name == name {
			return IndexView.new(view.schema.table.tree, view.schema.table.name, name)
		}
	}
	return error('schema index not found: ${name}')
}

pub fn (view IndexedSchemaView) get(primary_key []u8) !SchemaRow {
	return view.schema.get(primary_key)
}

pub fn (view IndexedSchemaView) put(primary_key []u8, row RowData, cfg ChunkConfig) !IndexedSchemaView {
	update := view.apply_mutations([
		SchemaMutation.put(primary_key, row),
	], cfg)!
	return update.view
}

pub fn (view IndexedSchemaView) apply_mutations(mutations []SchemaMutation, cfg ChunkConfig) !IndexedSchemaUpdate {
	mut items := view.schema.table.tree.items()!
	mut row_state := map[string]RowData{}
	mut row_exists := map[string]bool{}
	table_name := view.schema.table.name
	codec := view.schema.codec
	for mutation in mutations {
		key_id := mutation.primary_key.hex()
		if key_id !in row_exists {
			existing_row := view.schema.get(mutation.primary_key) or { SchemaRow{} }
			if existing_row.primary_key.len > 0 {
				row_state[key_id] = existing_row.data.clone()
				row_exists[key_id] = true
			} else {
				row_state[key_id] = RowData.new()
				row_exists[key_id] = false
			}
		}
		old_row := row_state[key_id].clone()
		had_old := row_exists[key_id]
		match mutation.op {
			.put {
				upsert_item(mut items, view.schema.table.key_for(mutation.primary_key),
					codec.encode(mutation.row)!)
				for index in view.indexes {
					mut old_value := []u8{}
					mut old_has := false
					if had_old && old_row.has(index.column) {
						old_value = old_row.get(index.column)!
						old_has = true
					}
					mut new_value := []u8{}
					mut new_has := false
					if mutation.row.has(index.column) {
						new_value = mutation.row.get(index.column)!
						new_has = true
					}
					index_view := IndexView.new(view.schema.table.tree, table_name, index.name)
					if old_has && (!new_has || compare_key_bytes(old_value, new_value) != 0) {
						delete_item(mut items, index_view.key_for(old_value, mutation.primary_key))
					}
					if new_has && (!old_has || compare_key_bytes(old_value, new_value) != 0) {
						upsert_item(mut items, index_view.key_for(new_value, mutation.primary_key),
							[]u8{})
					}
				}
				row_state[key_id] = mutation.row.clone()
				row_exists[key_id] = true
			}
			.delete {
				if !had_old {
					continue
				}
				delete_item(mut items, view.schema.table.key_for(mutation.primary_key))
				for index in view.indexes {
					if !old_row.has(index.column) {
						continue
					}
					index_value := old_row.get(index.column)!
					index_view := IndexView.new(view.schema.table.tree, table_name, index.name)
					delete_item(mut items, index_view.key_for(index_value, mutation.primary_key))
				}
				row_state[key_id] = RowData.new()
				row_exists[key_id] = false
			}
		}
	}
	if items.len == 0 {
		return error('indexed schema batch would produce an empty tree')
	}
	next_tree := Tree.build(items, cfg)!
	if next_tree.root.cid == view.schema.table.tree.root.cid {
		return IndexedSchemaUpdate{
			view: view
			diff: view.schema.table.tree.diff(view.schema.table.tree)
		}
	}
	next_view := view.with_schema(SchemaView.new(TableView.new(next_tree, table_name),
		codec))
	return IndexedSchemaUpdate{
		view: next_view
		diff: view.schema.table.tree.diff(next_tree)
	}
}

pub fn (view IndexedSchemaView) delete(primary_key []u8, cfg ChunkConfig) !IndexedSchemaView {
	update := view.apply_mutations([
		SchemaMutation.delete(primary_key),
	], cfg)!
	return update.view
}

pub fn (view IndexedSchemaView) find_by_index(name string, index_key []u8, limit int) ![]SchemaRow {
	index_view := view.index_view(name)!
	mut cursor := index_view.cursor(index_key, []u8{}, limit)!
	mut rows := []SchemaRow{}
	for {
		if limit > 0 && rows.len >= limit {
			break
		}
		entry := cursor.peek() or { break }
		if compare_key_bytes(entry.index_key, index_key) != 0 {
			break
		}
		matched := cursor.next() or { break }
		rows << view.schema.get(matched.primary_key)!
	}
	return rows
}

fn upsert_item(mut items []KVPair, key []u8, value []u8) {
	for idx, item in items {
		cmp := compare_key_bytes(item.key, key)
		if cmp == 0 {
			items[idx] = KVPair{
				key:   key.clone()
				value: value.clone()
			}
			return
		}
		if cmp > 0 {
			items.insert(idx, KVPair{
				key:   key.clone()
				value: value.clone()
			})
			return
		}
	}
	items << KVPair{
		key:   key.clone()
		value: value.clone()
	}
}

fn delete_item(mut items []KVPair, key []u8) {
	for idx, item in items {
		if compare_key_bytes(item.key, key) == 0 {
			items.delete(idx)
			return
		}
	}
}

pub fn validate_fts_index(column ColumnDef, index SchemaIndexDef) ! {
	if !index.is_fts() {
		return
	}
	if index.stores_row {
		return error('fts indexes cannot be covering indexes: ${index.name}')
	}
	if index.json_field.len > 0 || index.markdown_selector.len > 0 {
		return error('fts indexes cannot also be json-path or field-selector indexes: ${index.name}')
	}
	if index.fts_tokenizer.trim_space().len == 0 {
		return error('fts index tokenizer cannot be empty: ${index.name}')
	}
	for prefix_len in index.fts_prefix_lengths {
		if prefix_len <= 0 {
			return error('fts index prefix lengths must be positive: ${index.name}')
		}
	}
	match column.typ {
		.string_ {
			if index.fts_source_plugin.len > 0 {
				return error('string fts index cannot use field text source plugin: ${index.name}')
			}
			if index.fts_text_mode != FtsTextMode.plain_text.str() {
				return error('string fts index requires plain_text mode: ${index.name}')
			}
		}
		.markdown_ {
			if index.fts_source_plugin != 'markdown' {
				return error('markdown fts index requires markdown text source plugin: ${index.name}')
			}
			if index.fts_text_mode !in [FtsTextMode.visible_text.str(),
				FtsTextMode.visible_text_with_code.str(), FtsTextMode.raw_markdown.str()] {
				return error('markdown fts index requires a markdown text mode: ${index.name}')
			}
		}
		else {
			return error('fts index requires string or markdown column: ${index.column}')
		}
	}
}

fn validate_fts_index_options(options FtsIndexOptions) ! {
	if normalized_fts_tokenizer(options).len == 0 {
		return error('fts index tokenizer cannot be empty')
	}
	for prefix_len in options.prefix_lengths {
		if prefix_len <= 0 {
			return error('fts index prefix lengths must be positive')
		}
	}
}

fn normalized_fts_tokenizer(options FtsIndexOptions) string {
	tokenizer := options.tokenizer.trim_space()
	return if tokenizer.len > 0 { tokenizer } else { 'unicode61' }
}

fn normalized_fts_prefix_lengths(prefix_lengths []int) []int {
	if prefix_lengths.len == 0 {
		return []int{}
	}
	mut seen := map[int]bool{}
	mut out := []int{}
	for prefix_len in prefix_lengths {
		if prefix_len <= 0 || seen[prefix_len] {
			continue
		}
		seen[prefix_len] = true
		out << prefix_len
	}
	out.sort()
	return out
}
