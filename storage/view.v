module storage

const table_view_scope = 't|'
const index_view_scope = 'i|'
const aggregate_view_scope = 'g|'

pub struct TableRow {
pub:
	primary_key []u8
	value       []u8
}

pub struct IndexEntry {
pub:
	index_key   []u8
	primary_key []u8
	value       []u8
}

pub struct TableView {
pub:
	tree Tree
	name string
}

pub struct IndexView {
pub:
	tree       Tree
	table_name string
	index_name string
}

// SplitTableView is a compatibility layer for the long-term "rows tree + index trees"
// storage layout. Today it can still be backed by one mixed tree; later it can point
// to physically separate trees without changing higher-level typed access paths.
pub struct SplitTableView {
pub:
	name        string
	rows_tree   Tree
	index_trees map[string]Tree
}

pub struct TableCursor {
pub:
	view TableView
mut:
	cursor TreeCursor
}

pub struct TableRawCursor {
pub:
	view TableView
mut:
	cursor TreeRawCursor
}

pub struct IndexCursor {
pub:
	view IndexView
mut:
	cursor TreeCursor
}

pub fn TableView.new(tree Tree, name string) TableView {
	return TableView{
		tree: tree
		name: name
	}
}

pub fn SplitTableView.new(name string, rows_tree Tree, index_trees map[string]Tree) SplitTableView {
	return SplitTableView{
		name: name
		rows_tree: rows_tree
		index_trees: index_trees.clone()
	}
}

pub fn (view SplitTableView) clone() SplitTableView {
	return SplitTableView.new(view.name, view.rows_tree, view.index_trees)
}

pub fn SplitTableView.from_mixed_tree(tree Tree, name string, index_names []string) SplitTableView {
	mut index_trees := map[string]Tree{}
	for index_name in index_names {
		index_trees[index_name] = tree
	}
	return SplitTableView.new(name, tree, index_trees)
}

pub fn (view SplitTableView) rows_view() TableView {
	return TableView.new(view.rows_tree, view.name)
}

pub fn (view SplitTableView) has_index(index_name string) bool {
	return index_name in view.index_trees
}

pub fn (view SplitTableView) index_view(index_name string) !IndexView {
	tree := view.index_trees[index_name] or {
		return error('split table index not found: ${view.name}.${index_name}')
	}
	return IndexView.new(tree, view.name, index_name)
}

pub fn (view SplitTableView) with_rows_tree(tree Tree) SplitTableView {
	return SplitTableView.new(view.name, tree, view.index_trees)
}

pub fn (view SplitTableView) with_index_tree(index_name string, tree Tree) SplitTableView {
	mut next_indexes := view.index_trees.clone()
	next_indexes[index_name] = tree
	return SplitTableView.new(view.name, view.rows_tree, next_indexes)
}

pub fn SplitTableView.materialize_from_mixed_tree(tree Tree, name string, index_names []string, cfg ChunkConfig) !SplitTableView {
	items := tree.items()!
	row_prefix := encode_table_prefix(name)
	mut index_prefixes := map[string][]u8{}
	for index_name in index_names {
		index_prefixes[index_name] = encode_index_prefix(name, index_name)
	}
	mut row_items := []KVPair{}
	mut index_items := map[string][]KVPair{}
	for index_name in index_names {
		index_items[index_name] = []KVPair{}
	}
	for item in items {
		if has_prefix_bytes(item.key, row_prefix) {
			row_items << item
			continue
		}
		for index_name, prefix in index_prefixes {
			if has_prefix_bytes(item.key, prefix) {
				mut bucket := index_items[index_name]
				bucket << item
				index_items[index_name] = bucket
				break
			}
		}
	}
	row_tree := if row_items.len == 0 { Tree{} } else { Tree.build(row_items, cfg)! }
	mut trees := map[string]Tree{}
	for index_name, bucket in index_items {
		trees[index_name] = if bucket.len == 0 { Tree{} } else { Tree.build(bucket, cfg)! }
	}
	return SplitTableView.new(name, row_tree, trees)
}

pub fn (view SplitTableView) materialize_mixed_tree(cfg ChunkConfig) !Tree {
	mut items := []KVPair{}
	row_items := view.rows_tree.items() or { []KVPair{} }
	items << row_items
	for _, index_tree in view.index_trees {
		index_items := index_tree.items() or { []KVPair{} }
		items << index_items
	}
	if items.len == 0 {
		return Tree{}
	}
	return Tree.build(items, cfg)
}

pub fn (view TableView) with_tree(tree Tree) TableView {
	return TableView.new(tree, view.name)
}

pub fn (view TableView) row_key(primary_key []u8) []u8 {
	return view.key_for(primary_key)
}

fn (view TableView) row_prefix() []u8 {
	return encode_table_prefix(view.name)
}

fn (view TableView) key_for(primary_key []u8) []u8 {
	return build_table_row_key(view.row_prefix(), primary_key)
}

pub fn (view TableView) put(primary_key []u8, value []u8, cfg ChunkConfig) !TableView {
	next_tree := view.tree.put(KVPair{
		key: view.key_for(primary_key)
		value: value.clone()
	}, cfg)!
	return view.with_tree(next_tree)
}

pub fn (view TableView) delete(primary_key []u8, cfg ChunkConfig) !TableView {
	next_tree := view.tree.delete(view.key_for(primary_key), cfg)!
	return view.with_tree(next_tree)
}

pub fn (view TableView) get(primary_key []u8) !TableRow {
	item := view.tree.get(view.key_for(primary_key))!
	return decode_table_row(view, item)
}

pub fn (view TableView) has(primary_key []u8) bool {
	return view.tree.has(view.key_for(primary_key))
}

pub fn (view TableView) lower_bound(primary_key []u8) !TableRow {
	item := view.tree.lower_bound(view.key_for(primary_key))!
	return decode_table_row(view, item)
}

pub fn (view TableView) cursor(start_primary_key []u8, limit int) !TableCursor {
	start_key := view.key_for(start_primary_key)
	end_key := prefix_upper_bound(view.row_prefix())!
	return TableCursor{
		view: view
		cursor: view.tree.cursor(start_key, end_key, limit)!
	}
}

pub fn (view TableView) collect(limit int) ![]TableRow {
	mut cursor := view.cursor([]u8{}, limit)!
	return cursor.collect(limit)
}

pub fn (view TableView) raw_cursor(start_primary_key []u8, limit int) !TableRawCursor {
	return view.raw_range_cursor(start_primary_key, []u8{}, limit)
}

pub fn (view TableView) raw_range_cursor(start_primary_key []u8, end_primary_key []u8, limit int) !TableRawCursor {
	start_key := view.key_for(start_primary_key)
	end_key := if end_primary_key.len == 0 {
		prefix_upper_bound(view.row_prefix())!
	} else {
		view.key_for(end_primary_key)
	}
	return TableRawCursor{
		view: view
		cursor: view.tree.raw_cursor(start_key, end_key, limit)!
	}
}

pub fn IndexView.new(tree Tree, table_name string, index_name string) IndexView {
	return IndexView{
		tree: tree
		table_name: table_name
		index_name: index_name
	}
}

pub fn (view IndexView) with_tree(tree Tree) IndexView {
	return IndexView.new(tree, view.table_name, view.index_name)
}

fn (view IndexView) entry_prefix() []u8 {
	return encode_index_prefix(view.table_name, view.index_name)
}

fn build_index_entry_key(prefix []u8, index_key []u8, primary_key []u8) []u8 {
	mut out := []u8{cap: prefix.len + index_key.len + 1 + primary_key.len}
	out << prefix
	out << index_key
	out << [u8(`|`)]
	out << primary_key
	return out
}

fn build_table_row_key(prefix []u8, primary_key []u8) []u8 {
	mut out := []u8{cap: prefix.len + primary_key.len}
	out << prefix
	out << primary_key
	return out
}

fn build_index_entry_key_string(prefix string, index_key []u8, primary_key string) string {
	return prefix + index_key.bytestr() + '|' + primary_key
}

fn (view IndexView) key_for(index_key []u8, primary_key []u8) []u8 {
	return build_index_entry_key(view.entry_prefix(), index_key, primary_key)
}

pub fn (view IndexView) put(index_key []u8, primary_key []u8, value []u8, cfg ChunkConfig) !IndexView {
	next_tree := view.tree.put(KVPair{
		key: view.key_for(index_key, primary_key)
		value: value.clone()
	}, cfg)!
	return view.with_tree(next_tree)
}

pub fn (view IndexView) delete(index_key []u8, primary_key []u8, cfg ChunkConfig) !IndexView {
	next_tree := view.tree.delete(view.key_for(index_key, primary_key), cfg)!
	return view.with_tree(next_tree)
}

pub fn (view IndexView) get(index_key []u8, primary_key []u8) !IndexEntry {
	item := view.tree.get(view.key_for(index_key, primary_key))!
	return decode_index_entry(view, item)
}

pub fn (view IndexView) cursor(start_index_key []u8, start_primary_key []u8, limit int) !IndexCursor {
	start_key := if start_index_key.len == 0 && start_primary_key.len == 0 {
		view.entry_prefix()
	} else {
		view.key_for(start_index_key, start_primary_key)
	}
	end_key := prefix_upper_bound(view.entry_prefix())!
	return IndexCursor{
		view: view
		cursor: view.tree.cursor(start_key, end_key, limit)!
	}
}

pub fn (view IndexView) prefix_cursor(prefix_index_key []u8, limit int) !IndexCursor {
	mut start_key := view.entry_prefix()
	start_key << prefix_index_key
	end_key := prefix_upper_bound(view.entry_prefix())!
	return IndexCursor{
		view: view
		cursor: view.tree.cursor(start_key, end_key, limit)!
	}
}

pub fn (view IndexView) reverse_prefix_cursor(prefix_index_key []u8, limit int) !IndexCursor {
	mut start_key := view.entry_prefix()
	start_key << prefix_index_key
	mut end_key := view.entry_prefix()
	end_key << prefix_upper_bound(prefix_index_key)!
	return IndexCursor{
		view: view
		cursor: view.tree.reverse_cursor(start_key, end_key, limit)!
	}
}

pub fn (view IndexView) reverse_cursor(start_index_key []u8, start_primary_key []u8, end_index_key []u8, end_primary_key []u8, limit int) !IndexCursor {
	start_key := if start_index_key.len == 0 && start_primary_key.len == 0 {
		view.entry_prefix()
	} else {
		view.key_for(start_index_key, start_primary_key)
	}
	end_key := if end_index_key.len == 0 && end_primary_key.len == 0 {
		prefix_upper_bound(view.entry_prefix())!
	} else {
		view.key_for(end_index_key, end_primary_key)
	}
	return IndexCursor{
		view: view
		cursor: view.tree.reverse_cursor(start_key, end_key, limit)!
	}
}

pub fn (mut cursor TableCursor) seek(primary_key []u8) ! {
	cursor.cursor.seek(cursor.view.key_for(primary_key))!
}

pub fn (cursor TableCursor) current() !TableRow {
	item := cursor.cursor.current()!
	return decode_table_row(cursor.view, item)
}

pub fn (mut cursor TableCursor) peek() !TableRow {
	item := cursor.cursor.peek()!
	return decode_table_row(cursor.view, item)
}

pub fn (mut cursor TableCursor) next() !TableRow {
	item := cursor.cursor.next()!
	return decode_table_row(cursor.view, item)
}

pub fn (mut cursor TableCursor) skip(count int) !int {
	return cursor.cursor.skip(count)
}

pub fn (mut cursor TableCursor) collect(count int) ![]TableRow {
	items := cursor.cursor.collect(count)!
	mut rows := []TableRow{cap: items.len}
	for item in items {
		rows << decode_table_row(cursor.view, item)!
	}
	return rows
}

pub fn (mut cursor TableRawCursor) seek(primary_key []u8) ! {
	cursor.cursor.seek(cursor.view.key_for(primary_key))!
}

pub fn (cursor TableRawCursor) current() !TableRow {
	item := cursor.cursor.current()!
	return decode_table_row_raw(cursor.view, item)
}

pub fn (mut cursor TableRawCursor) next() !TableRow {
	item := cursor.cursor.next()!
	return decode_table_row_raw(cursor.view, item)
}

pub fn (mut cursor TableRawCursor) next_value() ![]u8 {
	item := cursor.cursor.next()!
	return item.value
}

pub fn (mut cursor TableRawCursor) skip(count int) !int {
	return cursor.cursor.skip(count)
}

pub fn (mut cursor TableRawCursor) count_remaining() !int {
	mut count := 0
	for {
		_ = cursor.next_value() or {
			if err.msg().contains('iterator exhausted') {
				break
			}
			return err
		}
		count++
	}
	return count
}

pub fn (mut cursor TableRawCursor) sum_i64_column(codec TypedRowCodec, column_name string) !i64 {
	mut total := i64(0)
	for {
		value := cursor.next_value() or {
			if err.msg().contains('iterator exhausted') {
				break
			}
			return err
		}
		total += codec.decode_i64_column(value, column_name)!
	}
	return total
}

pub fn (mut cursor IndexCursor) seek(index_key []u8, primary_key []u8) ! {
	cursor.cursor.seek(cursor.view.key_for(index_key, primary_key))!
}

pub fn (cursor IndexCursor) current() !IndexEntry {
	item := cursor.cursor.current()!
	return decode_index_entry(cursor.view, item)
}

pub fn (mut cursor IndexCursor) peek() !IndexEntry {
	item := cursor.cursor.peek()!
	return decode_index_entry(cursor.view, item)
}

pub fn (mut cursor IndexCursor) next() !IndexEntry {
	item := cursor.cursor.next()!
	return decode_index_entry(cursor.view, item)
}

pub fn (mut cursor IndexCursor) skip(count int) !int {
	return cursor.cursor.skip(count)
}

pub fn (mut cursor IndexCursor) collect(count int) ![]IndexEntry {
	items := cursor.cursor.collect(count)!
	mut entries := []IndexEntry{cap: items.len}
	for item in items {
		entries << decode_index_entry(cursor.view, item)!
	}
	return entries
}

fn encode_table_prefix(name string) []u8 {
	return '${table_view_scope}${name}|'.bytes()
}

pub fn encode_table_row_key(table_name string, primary_key []u8) []u8 {
	mut out := encode_table_prefix(table_name)
	out << primary_key
	return out
}

pub fn encode_table_range_end(table_name string) ![]u8 {
	return prefix_upper_bound(encode_table_prefix(table_name))
}

pub fn encode_table_sum_aggregate_key(table_name string, column_name string) []u8 {
	return '${aggregate_view_scope}${table_name}|sum|${column_name}'.bytes()
}

pub fn encode_table_sum_bucket_key(table_name string, column_name string, bucket u8) []u8 {
	mut out := '${aggregate_view_scope}${table_name}|sum|${column_name}|b|'.bytes()
	out << bucket
	return out
}

fn encode_index_prefix(table_name string, index_name string) []u8 {
	return '${index_view_scope}${table_name}|${index_name}|'.bytes()
}

fn prefix_upper_bound(prefix []u8) ![]u8 {
	mut upper := prefix.clone()
	for idx := upper.len - 1; idx >= 0; idx-- {
		if upper[idx] != u8(0xff) {
			upper[idx]++
			return upper[..idx + 1]
		}
	}
	return error('prefix upper bound not found')
}

fn decode_table_row(view TableView, item KVPair) !TableRow {
	prefix := view.row_prefix()
	if !has_prefix_bytes(item.key, prefix) {
		return error('table row key not in table view: ${view.name}')
	}
	return TableRow{
		primary_key: item.key[prefix.len..].clone()
		value: item.value.clone()
	}
}

fn decode_table_row_raw(view TableView, item KVPair) !TableRow {
	prefix := view.row_prefix()
	if !has_prefix_bytes(item.key, prefix) {
		return error('table row key not in table view: ${view.name}')
	}
	return TableRow{
		primary_key: item.key[prefix.len..]
		value: item.value
	}
}

fn decode_index_entry(view IndexView, item KVPair) !IndexEntry {
	prefix := view.entry_prefix()
	if !has_prefix_bytes(item.key, prefix) {
		return error('index key not in index view: ${view.table_name}.${view.index_name}')
	}
	rest := item.key[prefix.len..]
	separator_idx := rest.last_index(u8(`|`))
	if separator_idx < 0 {
		return error('invalid index key encoding')
	}
	return IndexEntry{
		index_key: rest[..separator_idx].clone()
		primary_key: rest[separator_idx + 1..].clone()
		value: item.value.clone()
	}
}
