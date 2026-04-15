module storage

import time
import x.json2

pub enum ColumnType {
	bool_
	i64_
	string_
	bytes_
	enum_
	json_
	datetime_
	markdown_
}

pub enum ColumnAggregate {
	none
	sum
}

pub enum JsonPathUpdateOp {
	set
	delete
}

pub struct NullValue {}

pub struct MarkdownRef {
pub:
	version     u8 = 1
	doc_root_id string
	source_hash string
	source_len  i64
	ast_version u8 = 1
	parse_flags u32
}

pub type ColumnValue = MarkdownRef | NullValue | bool | i64 | string | []u8

pub struct JsonPathUpdate {
pub:
	path  string
	op    JsonPathUpdateOp
	value ColumnValue
}

pub struct ColumnDef {
pub:
	name                          string
	typ                           ColumnType
	nullable                      bool
	aggregate                     ColumnAggregate
	enum_values                   []string
	default_current_timestamp     bool
	auto_update_current_timestamp bool
}

pub struct TableDef {
pub:
	name        string
	columns     []ColumnDef
	primary_key []string
}

pub struct TypedRowData {
mut:
	values map[string]ColumnValue
}

pub struct TypedRowCodec {
pub:
	table TableDef
}

pub struct TypedValueEncoder {}

pub struct TypedSchemaRow {
pub:
	primary_key []u8
	data        TypedRowData
}

pub struct TypedSchemaView {
pub:
	table TableView
	codec TypedRowCodec
}

pub struct TypedIndexedSchemaView {
pub:
	schema        TypedSchemaView
	indexes       []SchemaIndexDef
	split_storage SplitTableView
}

pub struct TypedIndexedSchemaUpdate {
pub:
	view    TypedIndexedSchemaView
	diff    TreeDiff
	timings TypedIndexedWriteTimings
}

pub struct TypedTableSpec {
pub:
	table   TableDef
	indexes []SchemaIndexDef
}

pub struct TypedWriteOp {
pub:
	table_name  string
	primary_key []u8
	row         TypedRowData
	delete      bool
}

pub struct TypedWriteSet {
mut:
	ops []TypedWriteOp
}

pub struct TypedTransaction {
mut:
	tree  Tree
	specs map[string]TypedTableSpec
}

pub struct TypedTransactionResult {
pub:
	tx           TypedTransaction
	diff         TreeDiff
	timings      TypedTransactionStageTimings
	group_commit GroupCommitStageTimings
}

pub struct TypedSplitTransaction {
mut:
	tables map[string]SplitTableView
	specs  map[string]TypedTableSpec
}

pub struct TypedSplitTransactionResult {
pub:
	tx           TypedSplitTransaction
	group_commit GroupCommitStageTimings
}

pub struct TypedWorkingSet {
pub:
	branch_name string
mut:
	base_commit_cid string
	base_tree       Tree
	tx              TypedTransaction
	specs           []TypedTableSpec
}

pub struct TypedSplitWorkingSet {
pub:
	branch_name string
mut:
	base_commit_cid string
	base_tree       Tree
	tx              TypedSplitTransaction
	specs           []TypedTableSpec
}

struct FastLeafUpdateGroup {
mut:
	anchor_key []u8
	row_keys   []string
}

struct FastWriteOpResult {
	view          TypedIndexedSchemaView
	remaining_ops []TypedWriteOp
	timings       FastWriteOpTimings
}

struct FastWriteOpTimings {
	can_ms     i64
	path_ms    i64
	encode_ms  i64
	replace_ms i64
}

struct TypedAggregateDelta {
mut:
	total         i64
	bucket_deltas map[u8]i64
}

pub struct ReindexStageTimings {
pub:
	items_ms         i64
	remove_ms        i64
	insert_ms        i64
	rebuild_ms       i64
	strategy         string
	item_count       int
	changed_tables   int
	changed_rows     int
	removed_indexes  int
	inserted_indexes int
}

pub struct TypedTransactionStageTimings {
pub:
	aggregate_ms                          i64
	fast_update_ms                        i64
	fast_update_can_ms                    i64
	fast_update_path_ms                   i64
	fast_update_encode_ms                 i64
	fast_update_replace_ms                i64
	fallback_ms                           i64
	fallback_items_ms                     i64
	fallback_items_key_ms                 i64
	fallback_items_fill_ms                i64
	fallback_ops_ms                       i64
	fallback_ops_key_ms                   i64
	fallback_ops_lookup_ms                i64
	fallback_ops_encode_ms                i64
	fallback_ops_state_ms                 i64
	fallback_ops_state_new_key_ms         i64
	fallback_ops_state_item_ms            i64
	fallback_ops_state_cache_ms           i64
	fallback_ops_index_ms                 i64
	fallback_build_ms                     i64
	fallback_build_prepare_ms             i64
	fallback_build_prepare_keys_ms        i64
	fallback_build_prepare_keys_sort_ms   i64
	fallback_build_prepare_keys_merge_ms  i64
	fallback_build_prepare_rows_ms        i64
	fallback_build_prepare_rows_key_ms    i64
	fallback_build_prepare_rows_value_ms  i64
	fallback_build_leaf_ms                i64
	fallback_build_leaf_chunk_ms          i64
	fallback_build_leaf_node_ms           i64
	fallback_build_leaf_node_serialize_ms i64
	fallback_build_leaf_node_cid_ms       i64
	fallback_build_leaf_node_add_ms       i64
	fallback_build_internal_ms            i64
	table_count                           int
	fallback_ops                          int
}

pub struct GroupCommitStageTimings {
pub:
	transaction_ms i64
	commit_ms      i64
	checkpoint_ms  i64
	flush_ms       i64
	flushed        bool
}

pub struct TypedIndexedWriteTimings {
pub:
	items_ms                     i64
	items_key_ms                 i64
	items_fill_ms                i64
	ops_ms                       i64
	ops_key_ms                   i64
	ops_lookup_ms                i64
	ops_encode_ms                i64
	ops_state_ms                 i64
	ops_state_new_key_ms         i64
	ops_state_item_ms            i64
	ops_state_cache_ms           i64
	ops_index_ms                 i64
	build_ms                     i64
	build_prepare_ms             i64
	build_prepare_keys_ms        i64
	build_prepare_keys_sort_ms   i64
	build_prepare_keys_merge_ms  i64
	build_prepare_rows_ms        i64
	build_prepare_rows_key_ms    i64
	build_prepare_rows_value_ms  i64
	build_leaf_ms                i64
	build_leaf_chunk_ms          i64
	build_leaf_node_ms           i64
	build_leaf_node_serialize_ms i64
	build_leaf_node_cid_ms       i64
	build_leaf_node_add_ms       i64
	build_internal_ms            i64
}

pub struct MutationSpanPlanStats {
pub:
	existing_keys         int
	changed_keys          int
	new_keys              int
	deleted_existing_keys int
	touched_existing_keys int
	covered_existing_keys int
	covered_existing_pct  int
	spans                 int
	max_span_keys         int
	avg_span_keys         int
	partition_candidate   bool
}

struct TypedRowCacheEntry {
	status u8
	data   TypedRowData
}

struct SplitIndexMutationRowState {
	primary_key     []u8
	had_old         bool
	old_row         TypedRowData
	new_row         TypedRowData
	delete          bool
	encoded_new_row []u8
}

struct SplitIndexMutationBatch {
mut:
	put_items     map[string][]u8
	delete_keys   map[string]bool
	key_bytes_map map[string][]u8
}

struct MergeExistingItemsResult {
	items         []KVPair
	rows_key_us   i64
	rows_value_us i64
}

struct MutationKeySpan {
mut:
	start_key string
	end_key   string
	key_count int
}

fn micros_to_millis(us i64) i64 {
	return us / 1000
}

pub fn ColumnDef.new(name string, typ ColumnType, nullable bool) !ColumnDef {
	return ColumnDef.new_with_options(name, typ, nullable, .none, false, false)
}

pub fn ColumnDef.new_with_aggregate(name string, typ ColumnType, nullable bool, aggregate ColumnAggregate) !ColumnDef {
	return ColumnDef.new_with_options(name, typ, nullable, aggregate, false, false)
}

pub fn ColumnDef.new_with_options(name string, typ ColumnType, nullable bool, aggregate ColumnAggregate, default_current_timestamp bool, auto_update_current_timestamp bool) !ColumnDef {
	if name.len == 0 {
		return error('column name cannot be empty')
	}
	if aggregate == .sum && typ != .i64_ {
		return error('aggregate sum requires i64 column: ${name}')
	}
	if (default_current_timestamp || auto_update_current_timestamp) && typ != .datetime_ {
		return error('current timestamp behaviors require datetime column: ${name}')
	}
	return ColumnDef{
		name:                          name
		typ:                           typ
		nullable:                      nullable
		aggregate:                     aggregate
		enum_values:                   []string{}
		default_current_timestamp:     default_current_timestamp
		auto_update_current_timestamp: auto_update_current_timestamp
	}
}

pub fn ColumnDef.sum_i64(name string, nullable bool) !ColumnDef {
	return ColumnDef.new_with_aggregate(name, .i64_, nullable, .sum)
}

pub fn ColumnDef.datetime(name string, nullable bool) !ColumnDef {
	return ColumnDef.new(name, .datetime_, nullable)
}

pub fn ColumnDef.datetime_with_current_timestamp(name string, nullable bool, auto_update_current_timestamp bool) !ColumnDef {
	return ColumnDef.new_with_options(name, .datetime_, nullable, .none, true, auto_update_current_timestamp)
}

pub fn current_datetime_string() string {
	return time.now().as_utc().format_rfc3339_micro()
}

pub fn ColumnDef.enum_string(name string, values []string, nullable bool) !ColumnDef {
	if values.len == 0 {
		return error('enum column requires at least one value: ${name}')
	}
	mut normalized := []string{cap: values.len}
	mut seen := map[string]bool{}
	for value in values {
		if value.len == 0 {
			return error('enum value cannot be empty: ${name}')
		}
		if seen[value] {
			return error('duplicate enum value ${value} for column ${name}')
		}
		seen[value] = true
		normalized << value
	}
	return ColumnDef{
		name:        name
		typ:         .enum_
		nullable:    nullable
		aggregate:   .none
		enum_values: normalized
	}
}

pub fn TableDef.new(name string, columns []ColumnDef, primary_key []string) !TableDef {
	if name.len == 0 {
		return error('table name cannot be empty')
	}
	if columns.len == 0 {
		return error('table requires at least one column')
	}
	mut seen := map[string]bool{}
	for column in columns {
		if column.name in seen {
			return error('duplicate column: ${column.name}')
		}
		seen[column.name] = true
	}
	if primary_key.len == 0 {
		return error('table requires at least one primary key column')
	}
	for key in primary_key {
		if key !in seen {
			return error('primary key column not found: ${key}')
		}
	}
	return TableDef{
		name:        name
		columns:     columns.clone()
		primary_key: primary_key.clone()
	}
}

pub fn (def TableDef) has_column(name string) bool {
	for column in def.columns {
		if column.name == name {
			return true
		}
	}
	return false
}

pub fn (def TableDef) column(name string) !ColumnDef {
	for column in def.columns {
		if column.name == name {
			return column
		}
	}
	return error('column not found: ${name}')
}

pub fn (def TableDef) supports_sum_aggregate(name string) bool {
	column := def.column(name) or { return false }
	return column.aggregate == .sum
}

pub fn (def TableDef) sum_aggregate_columns() []ColumnDef {
	mut columns := []ColumnDef{}
	for column in def.columns {
		if column.aggregate == .sum {
			columns << column
		}
	}
	return columns
}

pub fn (def TableDef) column_names() []string {
	mut names := []string{cap: def.columns.len}
	for column in def.columns {
		names << column.name
	}
	return names
}

pub fn (def TableDef) primary_key_columns() ![]ColumnDef {
	mut columns := []ColumnDef{cap: def.primary_key.len}
	for key in def.primary_key {
		columns << def.column(key)!
	}
	return columns
}

pub fn TypedRowData.new() TypedRowData {
	return TypedRowData{
		values: map[string]ColumnValue{}
	}
}

pub fn (mut row TypedRowData) set(name string, value ColumnValue) {
	row.values[name] = clone_column_value(value)
}

pub fn (mut row TypedRowData) set_null(name string) {
	row.values[name] = NullValue{}
}

pub fn (row TypedRowData) get(name string) !ColumnValue {
	value := row.values[name] or { return error('typed row field not found: ${name}') }
	return clone_column_value(value)
}

fn (row TypedRowData) lookup(name string) (ColumnValue, bool) {
	value := row.values[name] or { return NullValue{}, false }
	return value, true
}

pub fn (row TypedRowData) has(name string) bool {
	return name in row.values
}

pub fn (row TypedRowData) fields() map[string]ColumnValue {
	mut cloned := map[string]ColumnValue{}
	for key, value in row.values {
		cloned[key] = clone_column_value(value)
	}
	return cloned
}

pub fn (row TypedRowData) clone() TypedRowData {
	mut cloned := TypedRowData.new()
	for key, value in row.values {
		cloned.values[key] = clone_column_value(value)
	}
	return cloned
}

pub fn TypedRowCodec.new(table TableDef) TypedRowCodec {
	return TypedRowCodec{
		table: table
	}
}

pub fn TypedSchemaView.new(table TableView, codec TypedRowCodec) TypedSchemaView {
	return TypedSchemaView{
		table: table
		codec: codec
	}
}

pub fn TypedSchemaView.new_with_split_storage(split_storage SplitTableView, codec TypedRowCodec) TypedSchemaView {
	return TypedSchemaView.new(split_storage.rows_view(), codec)
}

pub fn (view TypedSchemaView) split_storage() SplitTableView {
	return SplitTableView.new(view.table.name, view.table.tree, map[string]Tree{})
}

pub fn (view TypedSchemaView) with_table(table TableView) TypedSchemaView {
	return TypedSchemaView.new(table, view.codec)
}

pub fn (view TypedSchemaView) put(primary_key []u8, row TypedRowData, cfg ChunkConfig) !TypedSchemaView {
	next_table := view.table.put(primary_key, view.codec.encode(row)!, cfg)!
	return view.with_table(next_table)
}

pub fn (view TypedSchemaView) get(primary_key []u8) !TypedSchemaRow {
	row := view.table.get(primary_key)!
	return TypedSchemaRow{
		primary_key: row.primary_key
		data:        view.codec.decode(row.value)!
	}
}

pub fn TypedIndexedSchemaView.new(schema TypedSchemaView, indexes []SchemaIndexDef) !TypedIndexedSchemaView {
	return TypedIndexedSchemaView.new_with_split_storage(schema, indexes, typed_indexed_split_storage_for_schema(schema,
		indexes))
}

pub fn TypedIndexedSchemaView.new_with_split_storage(schema TypedSchemaView, indexes []SchemaIndexDef, split_storage SplitTableView) !TypedIndexedSchemaView {
	if split_storage.name != schema.table.name {
		return error('split storage table name mismatch: expected ${schema.table.name}, got ${split_storage.name}')
	}
	for index in indexes {
		if !schema.codec.table.has_column(index.column) {
			return error('typed schema index column not in table: ${index.column}')
		}
		if index.is_json_path() {
			column := schema.codec.table.column(index.column)!
			if column.typ != .json_ {
				return error('typed schema json-path index requires json column: ${index.column}')
			}
		} else if index.is_fts() {
			column := schema.codec.table.column(index.column)!
			validate_fts_index(column, index)!
		} else if index.is_embedding() {
			column := schema.codec.table.column(index.column)!
			validate_embedding_index(column, index)!
		} else if index.is_field_selector() {
			column := schema.codec.table.column(index.column)!
			validate_field_selector_index(column, index)!
		}
		if !split_storage.has_index(index.name) {
			return error('split storage missing index tree: ${schema.table.name}.${index.name}')
		}
	}
	return TypedIndexedSchemaView{
		schema:        schema
		indexes:       indexes.clone()
		split_storage: split_storage
	}
}

fn typed_indexed_split_storage_for_schema(schema TypedSchemaView, indexes []SchemaIndexDef) SplitTableView {
	mut index_names := []string{}
	for index in indexes {
		index_names << index.name
	}
	return SplitTableView.from_mixed_tree(schema.table.tree, schema.table.name, index_names)
}

pub fn (view TypedIndexedSchemaView) split_storage() SplitTableView {
	return view.split_storage
}

pub fn (view TypedIndexedSchemaView) is_split_backed() bool {
	if view.split_storage.rows_tree.root.cid != view.schema.table.tree.root.cid {
		return true
	}
	for index in view.indexes {
		index_tree := view.split_storage.index_trees[index.name] or { continue }
		if index_tree.root.cid != view.schema.table.tree.root.cid {
			return true
		}
	}
	return false
}

pub fn (view TypedIndexedSchemaView) materialize_split_storage(cfg ChunkConfig) !SplitTableView {
	mut mixed_backed := view.split_storage.rows_tree.root.cid == view.schema.table.tree.root.cid
	if mixed_backed {
		for index in view.indexes {
			index_tree := view.split_storage.index_trees[index.name] or { continue }
			if index_tree.root.cid != view.schema.table.tree.root.cid {
				mixed_backed = false
				break
			}
		}
	}
	if !mixed_backed {
		return view.split_storage
	}
	return SplitTableView.materialize_from_mixed_tree(view.schema.table.tree, view.schema.table.name,
		view.index_names(), cfg)
}

pub fn (view TypedIndexedSchemaView) split_backed(cfg ChunkConfig) !TypedIndexedSchemaView {
	if view.is_split_backed() {
		return view
	}
	split_storage := view.materialize_split_storage(cfg)!
	schema := TypedSchemaView.new_with_split_storage(split_storage, view.schema.codec)
	return TypedIndexedSchemaView.new_with_split_storage(schema, view.indexes, split_storage)
}

pub fn (view TypedIndexedSchemaView) mixed_backed(cfg ChunkConfig) !TypedIndexedSchemaView {
	if !view.is_split_backed() {
		return view
	}
	mixed_tree := view.split_storage.materialize_mixed_tree(cfg)!
	schema := TypedSchemaView.new(TableView.new(mixed_tree, view.schema.table.name), view.schema.codec)
	return TypedIndexedSchemaView.new(schema, view.indexes)
}

pub fn (view TypedIndexedSchemaView) apply_write_ops_split_rebuild(ops []TypedWriteOp, cfg ChunkConfig) !SplitTableView {
	base_split := view.materialize_split_storage(cfg)!
	row_schema := TypedSchemaView.new_with_split_storage(SplitTableView.new(base_split.name,
		base_split.rows_tree, map[string]Tree{}), view.schema.codec)
	row_view := TypedIndexedSchemaView.new_with_split_storage(row_schema, []SchemaIndexDef{},
		SplitTableView.new(base_split.name, base_split.rows_tree, map[string]Tree{}))!
	row_update := row_view.apply_write_ops(ops, cfg)!
	next_rows_tree := row_update.view.schema.table.tree
	mut index_trees := map[string]Tree{}
	for index in view.indexes {
		index_trees[index.name] = rebuild_typed_single_index_tree(next_rows_tree, view.schema.codec,
			view.schema.table.name, index, cfg)!
	}
	return SplitTableView.new(view.schema.table.name, next_rows_tree, index_trees)
}

pub fn (view TypedIndexedSchemaView) apply_write_ops_split_delta(ops []TypedWriteOp, cfg ChunkConfig) !SplitTableView {
	base_split := view.materialize_split_storage(cfg)!
	row_schema := TypedSchemaView.new_with_split_storage(SplitTableView.new(base_split.name,
		base_split.rows_tree, map[string]Tree{}), view.schema.codec)
	row_view := TypedIndexedSchemaView.new_with_split_storage(row_schema, []SchemaIndexDef{},
		SplitTableView.new(base_split.name, base_split.rows_tree, map[string]Tree{}))!
	row_update := row_view.apply_write_ops(ops, cfg)!
	next_rows_tree := row_update.view.schema.table.tree
	row_states := build_split_index_mutation_row_states(base_split.rows_view(), view.schema.codec,
		ops)!
	mut index_trees := map[string]Tree{}
	for index in view.indexes {
		if index.is_field_selector() || index.is_fts() {
			index_trees[index.name] = rebuild_typed_single_index_tree(next_rows_tree,
				view.schema.codec, view.schema.table.name, index, cfg)!
			continue
		}
		index_tree := base_split.index_trees[index.name] or { Tree{} }
		index_trees[index.name] = apply_split_index_mutations(index_tree, view.schema.table.name,
			view.schema.codec, index, row_states, cfg)!
	}
	return SplitTableView.new(view.schema.table.name, next_rows_tree, index_trees)
}

pub fn (view TypedIndexedSchemaView) apply_write_ops_split_batched(ops []TypedWriteOp, cfg ChunkConfig) !SplitTableView {
	for index in view.indexes {
		if index.is_field_selector() || index.is_fts() {
			mixed_view := view.mixed_backed(cfg)!
			next_mixed := mixed_view.apply_write_ops(ops, cfg)!
			return next_mixed.view.materialize_split_storage(cfg)!
		}
	}
	base_split := view.materialize_split_storage(cfg)!
	row_schema := TypedSchemaView.new_with_split_storage(SplitTableView.new(base_split.name,
		base_split.rows_tree, map[string]Tree{}), view.schema.codec)
	row_view := TypedIndexedSchemaView.new_with_split_storage(row_schema, []SchemaIndexDef{},
		SplitTableView.new(base_split.name, base_split.rows_tree, map[string]Tree{}))!
	row_update := row_view.apply_write_ops(ops, cfg)!
	next_rows_tree := row_update.view.schema.table.tree
	row_states := build_split_index_mutation_row_states(base_split.rows_view(), view.schema.codec,
		ops)!
	mutation_batches := build_split_index_mutation_batches(view.schema.table.name, view.schema.codec,
		view.indexes, row_states)!
	mut index_trees := map[string]Tree{}
	for index in view.indexes {
		if index.is_field_selector() || index.is_fts() {
			index_trees[index.name] = rebuild_typed_single_index_tree(next_rows_tree,
				view.schema.codec, view.schema.table.name, index, cfg)!
			continue
		}
		index_tree := base_split.index_trees[index.name] or { Tree{} }
		batch := mutation_batches[index.name] or { SplitIndexMutationBatch{} }
		index_trees[index.name] = apply_split_index_mutation_batch(index_tree, view.schema.table.name,
			view.schema.codec, index, batch, cfg)!
	}
	return SplitTableView.new(view.schema.table.name, next_rows_tree, index_trees)
}

fn (view TypedIndexedSchemaView) index_view_by_name(name string) !IndexView {
	return view.split_storage().index_view(name)
}

pub fn (view TypedIndexedSchemaView) with_schema(schema TypedSchemaView) TypedIndexedSchemaView {
	return TypedIndexedSchemaView{
		schema:        schema
		indexes:       view.indexes.clone()
		split_storage: typed_indexed_split_storage_for_schema(schema, view.indexes)
	}
}

pub fn (view TypedIndexedSchemaView) get(primary_key []u8) !TypedSchemaRow {
	return view.schema.get(primary_key)
}

pub fn TypedTableSpec.new(table TableDef, indexes []SchemaIndexDef) !TypedTableSpec {
	for index in indexes {
		if !table.has_column(index.column) {
			return error('typed table spec index column not in table: ${index.column}')
		}
		if index.is_json_path() {
			column := table.column(index.column)!
			if column.typ != .json_ {
				return error('typed table spec json-path index requires json column: ${index.column}')
			}
		} else if index.is_fts() {
			column := table.column(index.column)!
			validate_fts_index(column, index)!
		} else if index.is_embedding() {
			column := table.column(index.column)!
			validate_embedding_index(column, index)!
		} else if index.is_field_selector() {
			column := table.column(index.column)!
			validate_field_selector_index(column, index)!
		}
	}
	return TypedTableSpec{
		table:   table
		indexes: indexes.clone()
	}
}

pub fn (spec TypedTableSpec) name() string {
	return spec.table.name
}

pub fn (spec TypedTableSpec) index_names() []string {
	mut names := []string{cap: spec.indexes.len}
	for index in spec.indexes {
		names << index.name
	}
	return names
}

pub fn (view TypedIndexedSchemaView) index_names() []string {
	mut names := []string{cap: view.indexes.len}
	for index in view.indexes {
		names << index.name
	}
	return names
}

fn (spec TypedTableSpec) table_spec() !TableSpec {
	return TableSpec.new(spec.table.name, RowCodec.new(spec.table.column_names())!, spec.indexes)
}

pub fn TypedWriteSet.new() TypedWriteSet {
	return TypedWriteSet{
		ops: []TypedWriteOp{}
	}
}

pub fn (mut set TypedWriteSet) put(table_name string, primary_key []u8, row TypedRowData) {
	set.ops << TypedWriteOp{
		table_name:  table_name
		primary_key: primary_key.clone()
		row:         row.clone()
		delete:      false
	}
}

pub fn (mut set TypedWriteSet) put_many(table_name string, rows map[string]TypedRowData) {
	mut primary_keys := rows.keys()
	primary_keys.sort()
	for primary_key in primary_keys {
		set.put(table_name, primary_key.bytes(), rows[primary_key])
	}
}

pub fn (mut set TypedWriteSet) delete(table_name string, primary_key []u8) {
	set.ops << TypedWriteOp{
		table_name:  table_name
		primary_key: primary_key.clone()
		row:         TypedRowData.new()
		delete:      true
	}
}

pub fn (mut set TypedWriteSet) delete_many(table_name string, primary_keys [][]u8) {
	mut sorted_primary_keys := primary_keys.clone()
	sorted_primary_keys.sort(a.hex() < b.hex())
	for primary_key in sorted_primary_keys {
		set.delete(table_name, primary_key)
	}
}

pub fn (set TypedWriteSet) len() int {
	return set.ops.len
}

pub fn (set TypedWriteSet) operations() []TypedWriteOp {
	return set.ops.clone()
}

pub fn TypedTransaction.new(tree Tree) TypedTransaction {
	return TypedTransaction{
		tree:  tree
		specs: map[string]TypedTableSpec{}
	}
}

fn new_typed_transaction_with_specs(tree Tree, specs []TypedTableSpec) !TypedTransaction {
	mut tx := TypedTransaction.new(tree)
	for spec in specs {
		tx.register_table(spec)!
	}
	return tx
}

fn new_typed_split_transaction_with_specs(tree Tree, specs []TypedTableSpec, cfg ChunkConfig) !TypedSplitTransaction {
	mut tx := TypedSplitTransaction{
		tables: map[string]SplitTableView{}
		specs:  map[string]TypedTableSpec{}
	}
	for spec in specs {
		tx.register_table(spec, tree, cfg)!
	}
	return tx
}

pub fn (mut tx TypedTransaction) register_table(spec TypedTableSpec) ! {
	if spec.name() in tx.specs {
		return error('typed table already registered: ${spec.name()}')
	}
	tx.specs[spec.name()] = spec
}

pub fn (mut tx TypedSplitTransaction) register_table(spec TypedTableSpec, tree Tree, cfg ChunkConfig) ! {
	if spec.name() in tx.specs {
		return error('typed split table already registered: ${spec.name()}')
	}
	tx.specs[spec.name()] = spec
	tx.tables[spec.name()] = SplitTableView.materialize_from_mixed_tree(tree, spec.table.name,
		spec.index_names(), cfg)!
}

pub fn (tx TypedTransaction) current_tree() Tree {
	return tx.tree
}

pub fn (tx TypedTransaction) split_backed(cfg ChunkConfig) !TypedSplitTransaction {
	mut specs := []TypedTableSpec{cap: tx.specs.len}
	for _, spec in tx.specs {
		specs << spec
	}
	return new_typed_split_transaction_with_specs(tx.tree, specs, cfg)
}

pub fn (tx TypedTransaction) indexed_view(name string) !TypedIndexedSchemaView {
	spec := tx.specs[name] or { return error('typed table not registered: ${name}') }
	split_storage := SplitTableView.from_mixed_tree(tx.tree, spec.table.name, spec.index_names())
	schema := TypedSchemaView.new_with_split_storage(split_storage, TypedRowCodec.new(spec.table))
	return TypedIndexedSchemaView.new_with_split_storage(schema, spec.indexes, split_storage)
}

pub fn (tx TypedTransaction) indexed_view_split_backed(name string, cfg ChunkConfig) !TypedIndexedSchemaView {
	return (tx.indexed_view(name)!).split_backed(cfg)
}

pub fn (tx TypedSplitTransaction) indexed_view(name string) !TypedIndexedSchemaView {
	spec := tx.specs[name] or { return error('typed split table not registered: ${name}') }
	split_storage := tx.tables[name] or {
		return error('typed split table storage not found: ${name}')
	}
	schema := TypedSchemaView.new_with_split_storage(split_storage, TypedRowCodec.new(spec.table))
	return TypedIndexedSchemaView.new_with_split_storage(schema, spec.indexes, split_storage)
}

pub fn (tx TypedSplitTransaction) clone() TypedSplitTransaction {
	mut tables := map[string]SplitTableView{}
	for name, table in tx.tables {
		tables[name] = table.clone()
	}
	return TypedSplitTransaction{
		tables: tables
		specs:  tx.specs.clone()
	}
}

pub fn (tx TypedSplitTransaction) materialize_mixed_tree(cfg ChunkConfig) !Tree {
	mut items := []KVPair{}
	for _, split in tx.tables {
		items << (split.materialize_mixed_tree(cfg)!.items() or { []KVPair{} })
	}
	if items.len == 0 {
		return Tree{}
	}
	return Tree.build(items, cfg)
}

pub fn (tx TypedSplitTransaction) current_tree(cfg ChunkConfig) !Tree {
	return tx.materialize_mixed_tree(cfg)
}

pub fn (tx TypedSplitTransaction) apply_write_set(write_set TypedWriteSet, cfg ChunkConfig) !TypedSplitTransactionResult {
	if write_set.len() == 0 {
		return TypedSplitTransactionResult{
			tx: tx
		}
	}
	mut next_tx := TypedSplitTransaction{
		tables: tx.tables.clone()
		specs:  tx.specs.clone()
	}
	mut grouped := map[string][]TypedWriteOp{}
	mut order := []string{}
	for op in write_set.operations() {
		if op.table_name !in next_tx.specs {
			return error('typed split table not registered: ${op.table_name}')
		}
		if op.table_name !in grouped {
			grouped[op.table_name] = []TypedWriteOp{}
			order << op.table_name
		}
		grouped[op.table_name] << op
	}
	for table_name in order {
		spec := next_tx.specs[table_name] or {
			return error('typed split table not registered: ${table_name}')
		}
		if spec.table.sum_aggregate_columns().len > 0 {
			return error('typed split transaction does not yet support aggregate columns: ${table_name}')
		}
		view := tx.indexed_view(table_name)!
		next_tx.tables[table_name] = view.apply_write_ops_split_batched(grouped[table_name],
			cfg)!
	}
	return TypedSplitTransactionResult{
		tx: next_tx
	}
}

pub fn (tx TypedTransaction) apply_write_set(write_set TypedWriteSet, cfg ChunkConfig) !TypedTransactionResult {
	if write_set.len() == 0 {
		return TypedTransactionResult{
			tx:   tx
			diff: tx.tree.diff(tx.tree)
		}
	}
	mut next_tx := TypedTransaction{
		tree:  tx.tree
		specs: tx.specs.clone()
	}
	mut grouped := map[string][]TypedWriteOp{}
	mut order := []string{}
	for op in write_set.operations() {
		if op.table_name !in next_tx.specs {
			return error('typed table not registered: ${op.table_name}')
		}
		if op.table_name !in grouped {
			grouped[op.table_name] = []TypedWriteOp{}
			order << op.table_name
		}
		grouped[op.table_name] << op
	}
	mut total_aggregate_ms := i64(0)
	mut total_fast_update_ms := i64(0)
	mut total_fast_update_can_ms := i64(0)
	mut total_fast_update_path_ms := i64(0)
	mut total_fast_update_encode_ms := i64(0)
	mut total_fast_update_replace_ms := i64(0)
	mut total_fallback_ms := i64(0)
	mut total_fallback_items_ms := i64(0)
	mut total_fallback_items_key_ms := i64(0)
	mut total_fallback_items_fill_ms := i64(0)
	mut total_fallback_build_ms := i64(0)
	mut total_fallback_ops_key_ms := i64(0)
	mut total_fallback_ops_lookup_ms := i64(0)
	mut total_fallback_ops_encode_ms := i64(0)
	mut total_fallback_ops_state_ms := i64(0)
	mut total_fallback_ops_state_new_key_ms := i64(0)
	mut total_fallback_ops_state_item_ms := i64(0)
	mut total_fallback_ops_state_cache_ms := i64(0)
	mut total_fallback_ops_index_ms := i64(0)
	mut total_fallback_build_prepare_ms := i64(0)
	mut total_fallback_build_prepare_keys_ms := i64(0)
	mut total_fallback_build_prepare_keys_sort_ms := i64(0)
	mut total_fallback_build_prepare_keys_merge_ms := i64(0)
	mut total_fallback_build_prepare_rows_ms := i64(0)
	mut total_fallback_build_prepare_rows_key_ms := i64(0)
	mut total_fallback_build_prepare_rows_value_ms := i64(0)
	mut total_fallback_build_leaf_ms := i64(0)
	mut total_fallback_build_leaf_chunk_ms := i64(0)
	mut total_fallback_build_leaf_node_ms := i64(0)
	mut total_fallback_build_leaf_node_serialize_ms := i64(0)
	mut total_fallback_build_leaf_node_cid_ms := i64(0)
	mut total_fallback_build_leaf_node_add_ms := i64(0)
	mut total_fallback_build_internal_ms := i64(0)
	mut fallback_op_count := 0
	for table_name in order {
		tree_before := next_tx.tree
		mut view := next_tx.indexed_view(table_name)!
		spec := next_tx.specs[table_name] or {
			return error('typed table not registered: ${table_name}')
		}
		mut aggregate_sw := time.new_stopwatch()
		aggregate_deltas := typed_aggregate_deltas_for_ops(view, spec, grouped[table_name])!
		total_aggregate_ms += aggregate_sw.elapsed().milliseconds()
		mut fast_sw := time.new_stopwatch()
		fast_update := view.apply_fast_write_ops(grouped[table_name], cfg)!
		total_fast_update_ms += fast_sw.elapsed().milliseconds()
		total_fast_update_can_ms += fast_update.timings.can_ms
		total_fast_update_path_ms += fast_update.timings.path_ms
		total_fast_update_encode_ms += fast_update.timings.encode_ms
		total_fast_update_replace_ms += fast_update.timings.replace_ms
		view = fast_update.view
		mut remaining_ops := fast_update.remaining_ops.clone()
		if remaining_ops.len > 0 {
			fallback_op_count += remaining_ops.len
			mut fallback_sw := time.new_stopwatch()
			update := view.apply_write_ops(remaining_ops, cfg)!
			total_fallback_ms += fallback_sw.elapsed().milliseconds()
			total_fallback_items_ms += update.timings.items_ms
			total_fallback_items_key_ms += update.timings.items_key_ms
			total_fallback_items_fill_ms += update.timings.items_fill_ms
			total_fallback_ops_key_ms += update.timings.ops_key_ms
			total_fallback_ops_lookup_ms += update.timings.ops_lookup_ms
			total_fallback_ops_encode_ms += update.timings.ops_encode_ms
			total_fallback_ops_state_ms += update.timings.ops_state_ms
			total_fallback_ops_state_new_key_ms += update.timings.ops_state_new_key_ms
			total_fallback_ops_state_item_ms += update.timings.ops_state_item_ms
			total_fallback_ops_state_cache_ms += update.timings.ops_state_cache_ms
			total_fallback_ops_index_ms += update.timings.ops_index_ms
			total_fallback_build_ms += update.timings.build_ms
			total_fallback_build_prepare_ms += update.timings.build_prepare_ms
			total_fallback_build_prepare_keys_ms += update.timings.build_prepare_keys_ms
			total_fallback_build_prepare_keys_sort_ms += update.timings.build_prepare_keys_sort_ms
			total_fallback_build_prepare_keys_merge_ms += update.timings.build_prepare_keys_merge_ms
			total_fallback_build_prepare_rows_ms += update.timings.build_prepare_rows_ms
			total_fallback_build_prepare_rows_key_ms += update.timings.build_prepare_rows_key_ms
			total_fallback_build_prepare_rows_value_ms += update.timings.build_prepare_rows_value_ms
			total_fallback_build_leaf_ms += update.timings.build_leaf_ms
			total_fallback_build_leaf_chunk_ms += update.timings.build_leaf_chunk_ms
			total_fallback_build_leaf_node_ms += update.timings.build_leaf_node_ms
			total_fallback_build_leaf_node_serialize_ms += update.timings.build_leaf_node_serialize_ms
			total_fallback_build_leaf_node_cid_ms += update.timings.build_leaf_node_cid_ms
			total_fallback_build_leaf_node_add_ms += update.timings.build_leaf_node_add_ms
			total_fallback_build_internal_ms += update.timings.build_internal_ms
			view = update.view
		}
		next_tx.tree = apply_typed_aggregate_deltas(tree_before, view.schema.table.tree,
			spec, aggregate_deltas, cfg)!
	}
	return TypedTransactionResult{
		tx:      next_tx
		diff:    tx.tree.diff(next_tx.tree)
		timings: TypedTransactionStageTimings{
			aggregate_ms:                          total_aggregate_ms
			fast_update_ms:                        total_fast_update_ms
			fast_update_can_ms:                    total_fast_update_can_ms
			fast_update_path_ms:                   total_fast_update_path_ms
			fast_update_encode_ms:                 total_fast_update_encode_ms
			fast_update_replace_ms:                total_fast_update_replace_ms
			fallback_ms:                           total_fallback_ms
			fallback_items_ms:                     total_fallback_items_ms
			fallback_items_key_ms:                 total_fallback_items_key_ms
			fallback_items_fill_ms:                total_fallback_items_fill_ms
			fallback_ops_ms:                       total_fallback_ms - total_fallback_items_ms - total_fallback_build_ms
			fallback_ops_key_ms:                   total_fallback_ops_key_ms
			fallback_ops_lookup_ms:                total_fallback_ops_lookup_ms
			fallback_ops_encode_ms:                total_fallback_ops_encode_ms
			fallback_ops_state_ms:                 total_fallback_ops_state_ms
			fallback_ops_state_new_key_ms:         total_fallback_ops_state_new_key_ms
			fallback_ops_state_item_ms:            total_fallback_ops_state_item_ms
			fallback_ops_state_cache_ms:           total_fallback_ops_state_cache_ms
			fallback_ops_index_ms:                 total_fallback_ops_index_ms
			fallback_build_ms:                     total_fallback_build_ms
			fallback_build_prepare_ms:             total_fallback_build_prepare_ms
			fallback_build_prepare_keys_ms:        total_fallback_build_prepare_keys_ms
			fallback_build_prepare_keys_sort_ms:   total_fallback_build_prepare_keys_sort_ms
			fallback_build_prepare_keys_merge_ms:  total_fallback_build_prepare_keys_merge_ms
			fallback_build_prepare_rows_ms:        total_fallback_build_prepare_rows_ms
			fallback_build_prepare_rows_key_ms:    total_fallback_build_prepare_rows_key_ms
			fallback_build_prepare_rows_value_ms:  total_fallback_build_prepare_rows_value_ms
			fallback_build_leaf_ms:                total_fallback_build_leaf_ms
			fallback_build_leaf_chunk_ms:          total_fallback_build_leaf_chunk_ms
			fallback_build_leaf_node_ms:           total_fallback_build_leaf_node_ms
			fallback_build_leaf_node_serialize_ms: total_fallback_build_leaf_node_serialize_ms
			fallback_build_leaf_node_cid_ms:       total_fallback_build_leaf_node_cid_ms
			fallback_build_leaf_node_add_ms:       total_fallback_build_leaf_node_add_ms
			fallback_build_internal_ms:            total_fallback_build_internal_ms
			table_count:                           order.len
			fallback_ops:                          fallback_op_count
		}
	}
}

pub fn TypedWorkingSet.new(branch_name string, base_commit_cid string, tree Tree, specs []TypedTableSpec) !TypedWorkingSet {
	return TypedWorkingSet{
		branch_name:     branch_name
		base_commit_cid: base_commit_cid
		base_tree:       tree
		tx:              new_typed_transaction_with_specs(tree, specs)!
		specs:           specs.clone()
	}
}

pub fn TypedSplitWorkingSet.new(branch_name string, base_commit_cid string, tree Tree, specs []TypedTableSpec, cfg ChunkConfig) !TypedSplitWorkingSet {
	return TypedSplitWorkingSet{
		branch_name:     branch_name
		base_commit_cid: base_commit_cid
		base_tree:       tree
		tx:              new_typed_split_transaction_with_specs(tree, specs, cfg)!
		specs:           specs.clone()
	}
}

pub fn (set TypedWorkingSet) has_changes() bool {
	return set.base_tree.root.cid != set.tx.current_tree().root.cid
}

pub fn (set TypedWorkingSet) staged_diff() TreeDiff {
	return set.base_tree.diff(set.tx.current_tree())
}

pub fn (set TypedWorkingSet) transaction() TypedTransaction {
	return set.tx
}

pub fn (set TypedWorkingSet) split_backed(cfg ChunkConfig) !TypedSplitWorkingSet {
	return TypedSplitWorkingSet{
		branch_name:     set.branch_name
		base_commit_cid: set.base_commit_cid
		base_tree:       set.base_tree
		tx:              set.tx.split_backed(cfg)!
		specs:           set.specs.clone()
	}
}

pub fn (set TypedWorkingSet) indexed_view(name string) !TypedIndexedSchemaView {
	return set.tx.indexed_view(name)
}

pub fn (set TypedWorkingSet) indexed_view_split_backed(name string, cfg ChunkConfig) !TypedIndexedSchemaView {
	return set.tx.indexed_view_split_backed(name, cfg)
}

pub fn (set TypedSplitWorkingSet) transaction() TypedSplitTransaction {
	return set.tx
}

pub fn (set TypedSplitWorkingSet) clone() TypedSplitWorkingSet {
	return TypedSplitWorkingSet{
		branch_name:     set.branch_name
		base_commit_cid: set.base_commit_cid
		base_tree:       set.base_tree
		tx:              set.tx.clone()
		specs:           set.specs.clone()
	}
}

pub fn (set TypedSplitWorkingSet) indexed_view(name string) !TypedIndexedSchemaView {
	return set.tx.indexed_view(name)
}

pub fn (set TypedSplitWorkingSet) current_tree(cfg ChunkConfig) !Tree {
	return set.tx.current_tree(cfg)
}

pub fn (set TypedSplitWorkingSet) has_changes(cfg ChunkConfig) bool {
	current_tree := set.tx.current_tree(cfg) or { return true }
	return set.base_tree.root.cid != current_tree.root.cid
}

pub fn (mut set TypedSplitWorkingSet) apply_write_set(write_set TypedWriteSet, cfg ChunkConfig) !TypedSplitTransactionResult {
	result := set.tx.apply_write_set(write_set, cfg)!
	set.tx = result.tx
	return result
}

pub fn (mut set TypedSplitWorkingSet) reset(cfg ChunkConfig) ! {
	set.tx = new_typed_split_transaction_with_specs(set.base_tree, set.specs, cfg)!
}

pub fn (mut set TypedSplitWorkingSet) sync_to_tree(tree Tree, commit_cid string, cfg ChunkConfig) ! {
	set.base_tree = tree
	set.base_commit_cid = commit_cid
	set.tx = new_typed_split_transaction_with_specs(tree, set.specs, cfg)!
}

pub fn (set TypedWorkingSet) status() !WorkingSetStatus {
	mut specs := []TableSpec{cap: set.specs.len}
	for spec in set.specs {
		specs << spec.table_spec()!
	}
	return build_working_set_status(set.branch_name, specs, set.base_tree, set.tx.current_tree())
}

pub fn (mut set TypedWorkingSet) apply_write_set(write_set TypedWriteSet, cfg ChunkConfig) !TypedTransactionResult {
	result := set.tx.apply_write_set(write_set, cfg)!
	set.tx = result.tx
	return result
}

pub fn (mut set TypedWorkingSet) reset() ! {
	set.tx = new_typed_transaction_with_specs(set.base_tree, set.specs)!
}

pub fn (mut set TypedWorkingSet) replace_working_tree(tree Tree) ! {
	set.tx = new_typed_transaction_with_specs(tree, set.specs)!
}

pub fn (mut set TypedWorkingSet) sync_to_tree(tree Tree, commit_cid string) ! {
	set.base_tree = tree
	set.base_commit_cid = commit_cid
	set.tx = new_typed_transaction_with_specs(tree, set.specs)!
}

pub fn (view TypedIndexedSchemaView) put(primary_key []u8, row TypedRowData, cfg ChunkConfig) !TypedIndexedSchemaView {
	if view.can_fast_update(primary_key, row)! {
		next_table := view.schema.table.put(primary_key, view.schema.codec.encode(row)!,
			cfg)!
		return view.with_schema(TypedSchemaView.new(next_table, view.schema.codec))
	}
	update := view.apply_write_ops([
		TypedWriteOp{
			table_name:  view.schema.table.name
			primary_key: primary_key.clone()
			row:         row.clone()
			delete:      false
		},
	], cfg)!
	return update.view
}

pub fn (view TypedIndexedSchemaView) delete(primary_key []u8, cfg ChunkConfig) !TypedIndexedSchemaView {
	update := view.apply_write_ops([
		TypedWriteOp{
			table_name:  view.schema.table.name
			primary_key: primary_key.clone()
			row:         TypedRowData.new()
			delete:      true
		},
	], cfg)!
	return update.view
}

pub fn (view TypedIndexedSchemaView) find_by_index(name string, value ColumnValue, limit int) ![]TypedSchemaRow {
	mut target_index := SchemaIndexDef{}
	mut found := false
	for index in view.indexes {
		if index.name == name {
			target_index = index
			found = true
			break
		}
	}
	if !found {
		return error('typed schema index not found: ${name}')
	}
	column := target_index.value_column(view.schema.codec.table)!
	encoded := TypedValueEncoder.encode_index_value(value, column)!
	index_view := view.index_view_by_name(name)!
	mut cursor := index_view.cursor(encoded, []u8{}, limit)!
	mut rows := []TypedSchemaRow{}
	for {
		if limit > 0 && rows.len >= limit {
			break
		}
		entry := cursor.peek() or { break }
		if compare_key_bytes(entry.index_key, encoded) != 0 {
			break
		}
		matched := cursor.next() or { break }
		rows << view.schema.get(matched.primary_key)!
	}
	return rows
}

fn (view TypedIndexedSchemaView) can_fast_update(primary_key []u8, row TypedRowData) !bool {
	existing_row := view.schema.get(primary_key) or { return false }
	old_row := existing_row.data
	if old_row.fields().len == 0 {
		return false
	}
	mut indexed_columns := map[string]bool{}
	for index in view.indexes {
		indexed_columns[index.column] = true
	}
	mut has_changed_column := false
	mut requires_equal_encoded_len := false
	for column in view.schema.codec.table.columns {
		old_has := old_row.has(column.name)
		new_has := row.has(column.name)
		if old_has != new_has {
			return false
		}
		if !old_has && !new_has {
			continue
		}
		old_value := old_row.get(column.name)!
		new_value := row.get(column.name)!
		if column_values_equal(old_value, new_value) {
			continue
		}
		has_changed_column = true
		if column.name in indexed_columns {
			return false
		}
		if !is_fixed_width_column(column) {
			requires_equal_encoded_len = true
		}
	}
	if !has_changed_column {
		return false
	}
	if requires_equal_encoded_len {
		old_encoded := view.schema.codec.encode(old_row)!
		new_encoded := view.schema.codec.encode(row)!
		return old_encoded.len == new_encoded.len
	}
	return has_changed_column
}

fn (view TypedIndexedSchemaView) apply_fast_write_ops(ops []TypedWriteOp, cfg ChunkConfig) !FastWriteOpResult {
	mut groups := map[string]FastLeafUpdateGroup{}
	mut group_order := []string{}
	mut fallback_ops := []TypedWriteOp{}
	mut op_by_key := map[string]TypedWriteOp{}
	mut can_ms := i64(0)
	mut path_ms := i64(0)
	mut encode_ms := i64(0)
	mut replace_ms := i64(0)
	mut sampled := 0
	mut sampled_fast := 0
	for idx, op in ops {
		if sampled >= 16 && sampled_fast == 0 && group_order.len == 0 {
			fallback_ops << ops[idx..]
			break
		}
		mut can_sw := time.new_stopwatch()
		can_fast := !op.delete && view.can_fast_update(op.primary_key, op.row)!
		can_ms += can_sw.elapsed().milliseconds()
		if !op.delete {
			sampled++
			if can_fast {
				sampled_fast++
			}
		}
		if !can_fast {
			fallback_ops << op
			continue
		}
		op_by_key[op.primary_key.hex()] = op
		table_key := view.schema.table.key_for(op.primary_key)
		mut path_sw := time.new_stopwatch()
		path := view.schema.table.tree.path_to_leaf(table_key)!
		path_ms += path_sw.elapsed().milliseconds()
		leaf := path[path.len - 1].node
		group_id := leaf.cid
		if group_id !in groups {
			groups[group_id] = FastLeafUpdateGroup{
				anchor_key: table_key.clone()
				row_keys:   []string{}
			}
			group_order << group_id
		}
		mut group := groups[group_id]
		group.row_keys << op.primary_key.hex()
		groups[group_id] = group
	}
	if group_order.len == 0 {
		return FastWriteOpResult{
			view:          view
			remaining_ops: fallback_ops
			timings:       FastWriteOpTimings{
				can_ms:     can_ms
				path_ms:    path_ms
				encode_ms:  encode_ms
				replace_ms: replace_ms
			}
		}
	}

	mut current_view := view
	for group_id in group_order {
		group := groups[group_id]
		path := current_view.schema.table.tree.path_to_leaf(group.anchor_key)!
		leaf := path[path.len - 1].node
		mut leaf_items := leaf.leaf_items()!
		row_prefix_len := current_view.schema.table.row_prefix().len
		mut encode_sw := time.new_stopwatch()
		for idx, item in leaf_items {
			key_id := item.key[row_prefix_len..].hex()
			if key_id !in op_by_key {
				continue
			}
			leaf_items[idx] = KVPair{
				key:   item.key.clone()
				value: current_view.schema.codec.encode(op_by_key[key_id].row)!
			}
		}
		encode_ms += encode_sw.elapsed().milliseconds()
		mut replace_sw := time.new_stopwatch()
		next_tree := current_view.schema.table.tree.replace_leaf_items(group.anchor_key,
			leaf_items, cfg)!
		replace_ms += replace_sw.elapsed().milliseconds()
		current_view = current_view.with_schema(TypedSchemaView.new(TableView.new(next_tree,
			current_view.schema.table.name), current_view.schema.codec))
	}
	return FastWriteOpResult{
		view:          current_view
		remaining_ops: fallback_ops
		timings:       FastWriteOpTimings{
			can_ms:     can_ms
			path_ms:    path_ms
			encode_ms:  encode_ms
			replace_ms: replace_ms
		}
	}
}

pub fn (view TypedIndexedSchemaView) apply_write_ops(ops []TypedWriteOp, cfg ChunkConfig) !TypedIndexedSchemaUpdate {
	detailed := cfg.detailed_timings
	mut items_sw := if detailed { time.new_stopwatch() } else { time.StopWatch{} }
	mut items := view.schema.table.tree.items()!
	items_ms := if detailed { items_sw.elapsed().milliseconds() } else { i64(0) }
	use_map_strategy := ops.len >= 128 || (items.len >= 4096 && ops.len >= 16)
	if use_map_strategy {
		return view.apply_write_ops_with_map(ops, items, items_ms, cfg)
	}
	mut row_state := map[string]TypedRowData{}
	mut row_exists := map[string]bool{}
	table_name := view.schema.table.name
	codec := view.schema.codec
	split := view.split_storage()
	mut regular_indexes := []SchemaIndexDef{}
	mut regular_index_columns := []ColumnDef{}
	mut regular_index_simple_lookup := []bool{}
	mut regular_index_prefixes := [][]u8{}
	for index in view.indexes {
		if index.is_field_selector() || index.is_fts() {
			continue
		}
		regular_indexes << index
		regular_index_columns << index.value_column(codec.table)!
		regular_index_simple_lookup << (!index.is_json_path() && !index.is_field_selector()
			&& !index.is_fts())
		index_view := split.index_view(index.name)!
		prefix := index_view.entry_prefix()
		regular_index_prefixes << prefix
	}
	mut ops_sw := if detailed { time.new_stopwatch() } else { time.StopWatch{} }
	mut ops_lookup_ms := i64(0)
	mut ops_encode_ms := i64(0)
	mut ops_index_ms := i64(0)
	for op in ops {
		key_id := op.primary_key.bytestr()
		if key_id !in row_exists {
			existing_row := if detailed {
				mut lookup_sw := time.new_stopwatch()
				row := view.schema.get(op.primary_key) or { TypedSchemaRow{} }
				ops_lookup_ms += lookup_sw.elapsed().milliseconds()
				row
			} else {
				view.schema.get(op.primary_key) or { TypedSchemaRow{} }
			}
			if existing_row.primary_key.len > 0 {
				row_state[key_id] = existing_row.data
				row_exists[key_id] = true
			} else {
				row_state[key_id] = TypedRowData.new()
				row_exists[key_id] = false
			}
		}
		had_old := row_exists[key_id]
		old_row := if had_old { row_state[key_id] } else { TypedRowData.new() }
		match op.delete {
			false {
				encoded_row := if detailed {
					mut encode_sw := time.new_stopwatch()
					row := codec.encode_without_validation(op.row)!
					ops_encode_ms += encode_sw.elapsed().milliseconds()
					row
				} else {
					codec.encode_without_validation(op.row)!
				}
				upsert_item(mut items, view.schema.table.key_for(op.primary_key), encoded_row)
				if !had_old {
					if detailed {
						mut index_sw := time.new_stopwatch()
						for idx, index in regular_indexes {
							new_value, new_has := typed_index_value_lookup_with_hint(op.row,
								index, codec.table, regular_index_simple_lookup[idx])!
							if !new_has {
								continue
							}
							column := regular_index_columns[idx]
							index_prefix := regular_index_prefixes[idx]
							index_value := if index.stores_row { encoded_row } else { []u8{} }
							encoded_index := encode_index_value_without_validation(new_value,
								column)!
							upsert_item(mut items, build_index_entry_key(index_prefix,
								encoded_index, op.primary_key), index_value)
						}
						ops_index_ms += index_sw.elapsed().milliseconds()
					} else {
						for idx, index in regular_indexes {
							new_value, new_has := typed_index_value_lookup_with_hint(op.row,
								index, codec.table, regular_index_simple_lookup[idx])!
							if !new_has {
								continue
							}
							column := regular_index_columns[idx]
							index_prefix := regular_index_prefixes[idx]
							index_value := if index.stores_row { encoded_row } else { []u8{} }
							encoded_index := encode_index_value_without_validation(new_value,
								column)!
							upsert_item(mut items, build_index_entry_key(index_prefix,
								encoded_index, op.primary_key), index_value)
						}
					}
					row_state[key_id] = op.row
					row_exists[key_id] = true
					continue
				}
				if detailed {
					mut index_sw := time.new_stopwatch()
					for idx, index in regular_indexes {
						column := regular_index_columns[idx]
						index_prefix := regular_index_prefixes[idx]
						old_value, old_has := typed_index_value_lookup_with_hint(old_row,
							index, codec.table, regular_index_simple_lookup[idx])!
						new_value, new_has := typed_index_value_lookup_with_hint(op.row,
							index, codec.table, regular_index_simple_lookup[idx])!
						if old_has && (!new_has || !column_values_equal(old_value, new_value)) {
							old_encoded := encode_index_value_without_validation(old_value,
								column)!
							delete_item(mut items, build_index_entry_key(index_prefix,
								old_encoded, op.primary_key))
						}
						if new_has && (!old_has || !column_values_equal(old_value, new_value)) {
							index_value := if index.stores_row { encoded_row } else { []u8{} }
							new_encoded := encode_index_value_without_validation(new_value,
								column)!
							upsert_item(mut items, build_index_entry_key(index_prefix,
								new_encoded, op.primary_key), index_value)
						}
					}
					ops_index_ms += index_sw.elapsed().milliseconds()
				} else {
					for idx, index in regular_indexes {
						column := regular_index_columns[idx]
						index_prefix := regular_index_prefixes[idx]
						old_value, old_has := typed_index_value_lookup_with_hint(old_row,
							index, codec.table, regular_index_simple_lookup[idx])!
						new_value, new_has := typed_index_value_lookup_with_hint(op.row,
							index, codec.table, regular_index_simple_lookup[idx])!
						if old_has && (!new_has || !column_values_equal(old_value, new_value)) {
							old_encoded := encode_index_value_without_validation(old_value,
								column)!
							delete_item(mut items, build_index_entry_key(index_prefix,
								old_encoded, op.primary_key))
						}
						if new_has && (!old_has || !column_values_equal(old_value, new_value)) {
							index_value := if index.stores_row { encoded_row } else { []u8{} }
							new_encoded := encode_index_value_without_validation(new_value,
								column)!
							upsert_item(mut items, build_index_entry_key(index_prefix,
								new_encoded, op.primary_key), index_value)
						}
					}
				}
				row_state[key_id] = op.row
				row_exists[key_id] = true
			}
			true {
				if !had_old {
					continue
				}
				delete_item(mut items, view.schema.table.key_for(op.primary_key))
				if detailed {
					mut index_sw := time.new_stopwatch()
					for idx, index in regular_indexes {
						index_value, has_value := typed_index_value_lookup_with_hint(old_row,
							index, codec.table, regular_index_simple_lookup[idx])!
						if !has_value {
							continue
						}
						column := regular_index_columns[idx]
						index_prefix := regular_index_prefixes[idx]
						encoded_index := encode_index_value_without_validation(index_value,
							column)!
						delete_item(mut items, build_index_entry_key(index_prefix, encoded_index,
							op.primary_key))
					}
					ops_index_ms += index_sw.elapsed().milliseconds()
				} else {
					for idx, index in regular_indexes {
						index_value, has_value := typed_index_value_lookup_with_hint(old_row,
							index, codec.table, regular_index_simple_lookup[idx])!
						if !has_value {
							continue
						}
						column := regular_index_columns[idx]
						index_prefix := regular_index_prefixes[idx]
						encoded_index := encode_index_value_without_validation(index_value,
							column)!
						delete_item(mut items, build_index_entry_key(index_prefix, encoded_index,
							op.primary_key))
					}
				}
				row_state[key_id] = TypedRowData.new()
				row_exists[key_id] = false
			}
		}
	}
	ops_ms := if detailed { ops_sw.elapsed().milliseconds() } else { i64(0) }
	if items.len == 0 {
		return error('typed indexed schema batch would produce an empty tree')
	}
	mut build_sw := if detailed { time.new_stopwatch() } else { time.StopWatch{} }
	next_tree := Tree.build(items, cfg)!
	build_ms := if detailed { build_sw.elapsed().milliseconds() } else { i64(0) }
	if next_tree.root.cid == view.schema.table.tree.root.cid {
		return TypedIndexedSchemaUpdate{
			view:    view
			diff:    view.schema.table.tree.diff(view.schema.table.tree)
			timings: TypedIndexedWriteTimings{
				items_ms:      items_ms
				ops_ms:        ops_ms
				ops_lookup_ms: ops_lookup_ms
				ops_encode_ms: ops_encode_ms
				ops_index_ms:  ops_index_ms
				build_ms:      build_ms
			}
		}
	}
	next_view := view.with_schema(TypedSchemaView.new(TableView.new(next_tree, table_name),
		codec))
	return TypedIndexedSchemaUpdate{
		view:    next_view
		diff:    view.schema.table.tree.diff(next_tree)
		timings: TypedIndexedWriteTimings{
			items_ms:      items_ms
			ops_ms:        ops_ms
			ops_lookup_ms: ops_lookup_ms
			ops_encode_ms: ops_encode_ms
			ops_index_ms:  ops_index_ms
			build_ms:      build_ms
		}
	}
}

pub fn (view TypedIndexedSchemaView) plan_write_spans(ops []TypedWriteOp) !MutationSpanPlanStats {
	items := view.schema.table.tree.items()!
	mut existing_key_set := map[string]bool{}
	mut ordered_keys := []string{cap: items.len}
	for item in items {
		key := item.key.bytestr()
		existing_key_set[key] = true
		ordered_keys << key
	}
	codec := view.schema.codec
	table_row_prefix := view.schema.table.row_prefix()
	table_row_prefix_str := table_row_prefix.bytestr()
	mut regular_indexes := []SchemaIndexDef{}
	mut regular_index_columns := []ColumnDef{}
	mut regular_index_simple_lookup := []bool{}
	mut regular_index_prefixes := [][]u8{}
	split := view.split_storage()
	for index in view.indexes {
		if index.is_field_selector() || index.is_fts() {
			continue
		}
		regular_indexes << index
		regular_index_columns << index.value_column(codec.table)!
		regular_index_simple_lookup << (!index.is_json_path() && !index.is_field_selector()
			&& !index.is_fts())
		index_view := split.index_view(index.name)!
		regular_index_prefixes << index_view.entry_prefix()
	}
	mut new_row_keys := []string{}
	mut new_row_keys_sorted := true
	mut last_new_row_key := ''
	mut new_index_keys := [][]string{len: regular_index_prefixes.len}
	mut new_index_keys_sorted := []bool{len: regular_index_prefixes.len, init: true}
	mut last_new_index_key := []string{len: regular_index_prefixes.len}
	mut deleted_existing_keys := map[string]bool{}
	mut touched_existing_keys := map[string]bool{}
	for op in ops {
		key_id := op.primary_key.bytestr()
		row_key := table_row_prefix_str + key_id
		existing_row := view.schema.get(op.primary_key) or { TypedSchemaRow{} }
		had_old := existing_row.primary_key.len > 0
		old_row := if had_old { existing_row.data } else { TypedRowData.new() }
		if op.delete {
			if row_key in existing_key_set {
				deleted_existing_keys[row_key] = true
			}
			if !had_old {
				continue
			}
			for idx, index in regular_indexes {
				index_value, has_value := typed_index_value_lookup_with_hint(old_row,
					index, codec.table, regular_index_simple_lookup[idx])!
				if !has_value {
					continue
				}
				column := regular_index_columns[idx]
				index_prefix := regular_index_prefixes[idx]
				encoded_index := encode_index_value_without_validation(index_value, column)!
				delete_key := build_index_entry_key(index_prefix, encoded_index, op.primary_key).bytestr()
				if delete_key in existing_key_set {
					deleted_existing_keys[delete_key] = true
				}
			}
			continue
		}
		if row_key in existing_key_set {
			touched_existing_keys[row_key] = true
		} else {
			if last_new_row_key.len > 0 && row_key < last_new_row_key {
				new_row_keys_sorted = false
			}
			new_row_keys << row_key
			last_new_row_key = row_key
		}
		for idx, index in regular_indexes {
			column := regular_index_columns[idx]
			index_prefix := regular_index_prefixes[idx]
			old_value, old_has := typed_index_value_lookup_with_hint(old_row, index, codec.table,
				regular_index_simple_lookup[idx])!
			new_value, new_has := typed_index_value_lookup_with_hint(op.row, index, codec.table,
				regular_index_simple_lookup[idx])!
			if old_has && (!new_has || !column_values_equal(old_value, new_value)) {
				old_encoded := encode_index_value_without_validation(old_value, column)!
				delete_key := build_index_entry_key(index_prefix, old_encoded, op.primary_key).bytestr()
				if delete_key in existing_key_set {
					deleted_existing_keys[delete_key] = true
				}
			}
			if new_has && (!old_has || !column_values_equal(old_value, new_value)) {
				new_encoded := encode_index_value_without_validation(new_value, column)!
				index_key := build_index_entry_key(index_prefix, new_encoded, op.primary_key).bytestr()
				if index_key in existing_key_set {
					touched_existing_keys[index_key] = true
				} else {
					if last_new_index_key[idx].len > 0 && index_key < last_new_index_key[idx] {
						new_index_keys_sorted[idx] = false
					}
					new_index_keys[idx] << index_key
					last_new_index_key[idx] = index_key
				}
			}
		}
	}
	if !new_row_keys_sorted {
		new_row_keys.sort()
	}
	for idx, mut bucket in new_index_keys {
		if !new_index_keys_sorted[idx] {
			bucket.sort()
			new_index_keys[idx] = bucket
		}
	}
	new_keys := merge_sorted_key_buckets(new_row_keys, new_index_keys)
	spans := plan_mutation_key_spans(ordered_keys, new_keys, deleted_existing_keys, touched_existing_keys)
	mut span_total := 0
	mut span_max := 0
	for span in spans {
		span_total += span.key_count
		if span.key_count > span_max {
			span_max = span.key_count
		}
	}
	covered_existing := count_existing_keys_covered_by_spans(ordered_keys, spans)
	coverage_pct := if ordered_keys.len > 0 {
		(covered_existing * 100) / ordered_keys.len
	} else {
		0
	}
	return MutationSpanPlanStats{
		existing_keys:         ordered_keys.len
		changed_keys:          new_keys.len + deleted_existing_keys.len + touched_existing_keys.len
		new_keys:              new_keys.len
		deleted_existing_keys: deleted_existing_keys.len
		touched_existing_keys: touched_existing_keys.len
		covered_existing_keys: covered_existing
		covered_existing_pct:  coverage_pct
		spans:                 spans.len
		max_span_keys:         span_max
		avg_span_keys:         if spans.len > 0 { span_total / spans.len } else { 0 }
		partition_candidate:   should_use_partitioned_rebuild(ordered_keys, new_keys,
			spans, false, deleted_existing_keys.len > 0)
	}
}

fn count_existing_keys_covered_by_spans(existing_keys []string, spans []MutationKeySpan) int {
	if existing_keys.len == 0 || spans.len == 0 {
		return 0
	}
	mut covered := 0
	mut key_idx := 0
	for span in spans {
		for key_idx < existing_keys.len && existing_keys[key_idx] < span.start_key {
			key_idx++
		}
		mut scan_idx := key_idx
		for scan_idx < existing_keys.len && existing_keys[scan_idx] <= span.end_key {
			covered++
			scan_idx++
		}
		key_idx = scan_idx
		if key_idx >= existing_keys.len {
			break
		}
	}
	return covered
}

fn (view TypedIndexedSchemaView) apply_write_ops_with_map(ops []TypedWriteOp, items []KVPair, items_ms i64, cfg ChunkConfig) !TypedIndexedSchemaUpdate {
	detailed := cfg.detailed_timings
	mut item_map := map[string][]u8{}
	mut key_bytes_map := map[string][]u8{}
	mut ordered_keys := []string{cap: items.len}
	mut items_key_us := i64(0)
	mut items_fill_us := i64(0)
	for item in items {
		if detailed {
			mut key_sw := time.new_stopwatch()
			key := item.key.bytestr()
			items_key_us += key_sw.elapsed().microseconds()
			mut fill_sw := time.new_stopwatch()
			item_map[key] = item.value
			ordered_keys << key
			items_fill_us += fill_sw.elapsed().microseconds()
		} else {
			key := item.key.bytestr()
			item_map[key] = item.value
			ordered_keys << key
		}
	}
	mut new_row_keys := []string{}
	mut new_row_keys_sorted := true
	mut last_new_row_key := ''
	mut is_new_key := map[string]bool{}
	mut insert_only_rebuild := true
	mut has_delete_ops := false
	for op in ops {
		if op.delete {
			has_delete_ops = true
			break
		}
	}
	mut deleted_new_keys := map[string]bool{}
	mut deleted_existing_keys := map[string]bool{}
	mut touched_existing_keys := map[string]bool{}
	mut row_cache := map[string]TypedRowCacheEntry{}
	table_name := view.schema.table.name
	codec := view.schema.codec
	table_row_prefix := view.schema.table.row_prefix()
	table_row_prefix_str := table_row_prefix.bytestr()
	split := view.split_storage()
	mut regular_indexes := []SchemaIndexDef{}
	mut regular_index_columns := []ColumnDef{}
	mut regular_index_simple_lookup := []bool{}
	mut regular_index_prefixes := [][]u8{}
	mut regular_index_prefix_strings := []string{}
	mut projected_old_columns := []string{}
	mut projected_old_column_seen := map[string]bool{}
	for index in view.indexes {
		if index.is_field_selector() || index.is_fts() {
			continue
		}
		regular_indexes << index
		regular_index_columns << index.value_column(codec.table)!
		regular_index_simple_lookup << (!index.is_json_path() && !index.is_field_selector()
			&& !index.is_fts())
		index_view := split.index_view(index.name)!
		prefix := index_view.entry_prefix()
		regular_index_prefixes << prefix
		regular_index_prefix_strings << prefix.bytestr()
		if index.column !in projected_old_column_seen {
			projected_old_column_seen[index.column] = true
			projected_old_columns << index.column
		}
	}
	mut new_index_keys := [][]string{len: regular_index_prefixes.len}
	mut new_index_keys_sorted := []bool{len: regular_index_prefixes.len, init: true}
	mut last_new_index_key := []string{len: regular_index_prefixes.len}
	mut ops_sw := if detailed { time.new_stopwatch() } else { time.StopWatch{} }
	mut ops_key_us := i64(0)
	mut ops_lookup_us := i64(0)
	mut ops_encode_us := i64(0)
	mut ops_state_us := i64(0)
	mut ops_index_us := i64(0)
	for op in ops {
		key_id := op.primary_key.bytestr()
		row_key := table_row_prefix_str + key_id
		if detailed {
			mut key_sw := time.new_stopwatch()
			_ = key_sw
			ops_key_us += key_sw.elapsed().microseconds()
		}
		mut cached := row_cache[key_id] or { TypedRowCacheEntry{} }
		if cached.status == 0 {
			if row_key !in item_map {
				cached = TypedRowCacheEntry{
					status: 1
				}
				row_cache[key_id] = cached
			} else {
				existing_row := if detailed {
					mut lookup_sw := time.new_stopwatch()
					row := view.schema.get(op.primary_key) or { TypedSchemaRow{} }
					ops_lookup_us += lookup_sw.elapsed().microseconds()
					row
				} else {
					view.schema.get(op.primary_key) or { TypedSchemaRow{} }
				}
				if existing_row.primary_key.len > 0 {
					cached = TypedRowCacheEntry{
						status: 2
						data:   existing_row.data
					}
				} else {
					cached = TypedRowCacheEntry{
						status: 1
					}
				}
				row_cache[key_id] = cached
			}
		}
		had_old := cached.status == 2
		old_row := if had_old { cached.data } else { TypedRowData.new() }
		match op.delete {
			false {
				encoded_row := if detailed {
					mut encode_sw := time.new_stopwatch()
					row := codec.encode_without_validation(op.row)!
					ops_encode_us += encode_sw.elapsed().microseconds()
					row
				} else {
					codec.encode_without_validation(op.row)!
				}
				if row_key !in item_map && row_key !in is_new_key {
					row_key_bytes := build_table_row_key(table_row_prefix, op.primary_key)
					is_new_key[row_key] = true
					key_bytes_map[row_key] = row_key_bytes
					if last_new_row_key.len > 0 && row_key < last_new_row_key {
						new_row_keys_sorted = false
					}
					new_row_keys << row_key
					last_new_row_key = row_key
				}
				if has_delete_ops {
					deleted_new_keys.delete(row_key)
					deleted_existing_keys.delete(row_key)
				}
				item_map[row_key] = encoded_row
				if !had_old {
					if detailed {
						mut index_sw := time.new_stopwatch()
						for idx, index in regular_indexes {
							new_value, new_has := typed_index_value_lookup_with_hint(op.row,
								index, codec.table, regular_index_simple_lookup[idx])!
							if !new_has {
								continue
							}
							column := regular_index_columns[idx]
							index_prefix_str := regular_index_prefix_strings[idx]
							index_value := if index.stores_row { encoded_row } else { []u8{} }
							index_key := build_index_entry_key_string_for_value(index_prefix_str,
								new_value, column, key_id)!
							if index_key !in item_map && index_key !in is_new_key {
								is_new_key[index_key] = true
								key_bytes_map[index_key] = index_key.bytes()
								if last_new_index_key[idx].len > 0
									&& index_key < last_new_index_key[idx] {
									new_index_keys_sorted[idx] = false
								}
								new_index_keys[idx] << index_key
								last_new_index_key[idx] = index_key
							}
							if has_delete_ops {
								deleted_new_keys.delete(index_key)
								deleted_existing_keys.delete(index_key)
							}
							item_map[index_key] = index_value
						}
						ops_index_us += index_sw.elapsed().microseconds()
					} else {
						for idx, index in regular_indexes {
							new_value, new_has := typed_index_value_lookup_with_hint(op.row,
								index, codec.table, regular_index_simple_lookup[idx])!
							if !new_has {
								continue
							}
							column := regular_index_columns[idx]
							index_prefix_str := regular_index_prefix_strings[idx]
							index_value := if index.stores_row { encoded_row } else { []u8{} }
							index_key := build_index_entry_key_string_for_value(index_prefix_str,
								new_value, column, key_id)!
							if index_key !in item_map && index_key !in is_new_key {
								is_new_key[index_key] = true
								key_bytes_map[index_key] = index_key.bytes()
								if last_new_index_key[idx].len > 0
									&& index_key < last_new_index_key[idx] {
									new_index_keys_sorted[idx] = false
								}
								new_index_keys[idx] << index_key
								last_new_index_key[idx] = index_key
							}
							if has_delete_ops {
								deleted_new_keys.delete(index_key)
								deleted_existing_keys.delete(index_key)
							}
							item_map[index_key] = index_value
						}
					}
					row_cache[key_id] = TypedRowCacheEntry{
						status: 2
						data:   op.row
					}
					if detailed {
						ops_state_us += 0
					}
					continue
				}
				insert_only_rebuild = false
				if row_key !in is_new_key {
					touched_existing_keys[row_key] = true
				}
				if detailed {
					mut state_sw := time.new_stopwatch()
					mut index_sw := time.new_stopwatch()
					for idx, index in regular_indexes {
						column := regular_index_columns[idx]
						index_prefix_str := regular_index_prefix_strings[idx]
						old_value, old_has := typed_index_value_lookup_with_hint(old_row,
							index, codec.table, regular_index_simple_lookup[idx])!
						new_value, new_has := typed_index_value_lookup_with_hint(op.row,
							index, codec.table, regular_index_simple_lookup[idx])!
						if old_has && (!new_has || !column_values_equal(old_value, new_value)) {
							delete_key := build_index_entry_key_string_for_value(index_prefix_str,
								old_value, column, key_id)!
							item_map.delete(delete_key)
							if delete_key in is_new_key {
								deleted_new_keys[delete_key] = true
							} else {
								deleted_existing_keys[delete_key] = true
							}
						}
						if new_has && (!old_has || !column_values_equal(old_value, new_value)) {
							index_value := if index.stores_row { encoded_row } else { []u8{} }
							index_key := build_index_entry_key_string_for_value(index_prefix_str,
								new_value, column, key_id)!
							if index_key !in item_map && index_key !in is_new_key {
								is_new_key[index_key] = true
								key_bytes_map[index_key] = index_key.bytes()
								if last_new_index_key[idx].len > 0
									&& index_key < last_new_index_key[idx] {
									new_index_keys_sorted[idx] = false
								}
								new_index_keys[idx] << index_key
								last_new_index_key[idx] = index_key
							} else {
								touched_existing_keys[index_key] = true
							}
							if has_delete_ops {
								deleted_new_keys.delete(index_key)
								deleted_existing_keys.delete(index_key)
							}
							item_map[index_key] = index_value
						}
					}
					ops_index_us += index_sw.elapsed().microseconds()
					row_cache[key_id] = TypedRowCacheEntry{
						status: 2
						data:   op.row
					}
					ops_state_us += state_sw.elapsed().microseconds()
				} else {
					for idx, index in regular_indexes {
						column := regular_index_columns[idx]
						index_prefix_str := regular_index_prefix_strings[idx]
						old_value, old_has := typed_index_value_lookup_with_hint(old_row,
							index, codec.table, regular_index_simple_lookup[idx])!
						new_value, new_has := typed_index_value_lookup_with_hint(op.row,
							index, codec.table, regular_index_simple_lookup[idx])!
						if old_has && (!new_has || !column_values_equal(old_value, new_value)) {
							delete_key := build_index_entry_key_string_for_value(index_prefix_str,
								old_value, column, key_id)!
							item_map.delete(delete_key)
							if delete_key in is_new_key {
								deleted_new_keys[delete_key] = true
							} else {
								deleted_existing_keys[delete_key] = true
							}
						}
						if new_has && (!old_has || !column_values_equal(old_value, new_value)) {
							index_value := if index.stores_row { encoded_row } else { []u8{} }
							index_key := build_index_entry_key_string_for_value(index_prefix_str,
								new_value, column, key_id)!
							if index_key !in item_map && index_key !in is_new_key {
								is_new_key[index_key] = true
								key_bytes_map[index_key] = index_key.bytes()
								if last_new_index_key[idx].len > 0
									&& index_key < last_new_index_key[idx] {
									new_index_keys_sorted[idx] = false
								}
								new_index_keys[idx] << index_key
								last_new_index_key[idx] = index_key
							} else {
								touched_existing_keys[index_key] = true
							}
							if has_delete_ops {
								deleted_new_keys.delete(index_key)
								deleted_existing_keys.delete(index_key)
							}
							item_map[index_key] = index_value
						}
					}
					row_cache[key_id] = TypedRowCacheEntry{
						status: 2
						data:   op.row
					}
				}
			}
			true {
				insert_only_rebuild = false
				if !had_old {
					continue
				}
				if detailed {
					mut state_sw := time.new_stopwatch()
					item_map.delete(row_key)
					if row_key in is_new_key {
						deleted_new_keys[row_key] = true
					} else {
						deleted_existing_keys[row_key] = true
					}
					mut index_sw := time.new_stopwatch()
					for idx, index in regular_indexes {
						index_value, has_value := typed_index_value_lookup_with_hint(old_row,
							index, codec.table, regular_index_simple_lookup[idx])!
						if !has_value {
							continue
						}
						column := regular_index_columns[idx]
						index_prefix_str := regular_index_prefix_strings[idx]
						delete_key := build_index_entry_key_string_for_value(index_prefix_str,
							index_value, column, key_id)!
						item_map.delete(delete_key)
						if delete_key in is_new_key {
							deleted_new_keys[delete_key] = true
						} else {
							deleted_existing_keys[delete_key] = true
						}
					}
					ops_index_us += index_sw.elapsed().microseconds()
					row_cache[key_id] = TypedRowCacheEntry{
						status: 1
					}
					ops_state_us += state_sw.elapsed().microseconds()
				} else {
					item_map.delete(row_key)
					if row_key in is_new_key {
						deleted_new_keys[row_key] = true
					} else {
						deleted_existing_keys[row_key] = true
					}
					for idx, index in regular_indexes {
						index_value, has_value := typed_index_value_lookup_with_hint(old_row,
							index, codec.table, regular_index_simple_lookup[idx])!
						if !has_value {
							continue
						}
						column := regular_index_columns[idx]
						index_prefix_str := regular_index_prefix_strings[idx]
						delete_key := build_index_entry_key_string_for_value(index_prefix_str,
							index_value, column, key_id)!
						item_map.delete(delete_key)
						if delete_key in is_new_key {
							deleted_new_keys[delete_key] = true
						} else {
							deleted_existing_keys[delete_key] = true
						}
					}
					row_cache[key_id] = TypedRowCacheEntry{
						status: 1
					}
				}
			}
		}
	}
	ops_ms := if detailed { ops_sw.elapsed().milliseconds() } else { i64(0) }
	if item_map.len == 0 {
		return error('typed indexed schema batch would produce an empty tree')
	}
	mut build_sw := if detailed { time.new_stopwatch() } else { time.StopWatch{} }
	mut prepare_sw := if detailed { time.new_stopwatch() } else { time.StopWatch{} }
	mut keys_sw := if detailed { time.new_stopwatch() } else { time.StopWatch{} }
	mut sort_sw := if detailed { time.new_stopwatch() } else { time.StopWatch{} }
	if !new_row_keys_sorted {
		new_row_keys.sort()
	}
	for idx, mut bucket in new_index_keys {
		if !new_index_keys_sorted[idx] {
			bucket.sort()
			new_index_keys[idx] = bucket
		}
	}
	build_prepare_keys_sort_ms := if detailed { sort_sw.elapsed().milliseconds() } else { i64(0) }
	mut merge_sw := if detailed { time.new_stopwatch() } else { time.StopWatch{} }
	new_keys := merge_sorted_key_buckets(new_row_keys, new_index_keys)
	spans := plan_mutation_key_spans(ordered_keys, new_keys, deleted_existing_keys, touched_existing_keys)
	use_partitioned_rebuild := if cfg.force_partitioned_rebuild {
		!insert_only_rebuild && spans.len > 0
	} else {
		cfg.enable_partitioned_rebuild
			&& should_use_partitioned_rebuild(ordered_keys, new_keys, spans, insert_only_rebuild, has_delete_ops)
	}
	mut keys := if use_partitioned_rebuild {
		[]string{}
	} else {
		merge_sorted_item_keys(ordered_keys, new_keys, is_new_key, deleted_new_keys, deleted_existing_keys)
	}
	build_prepare_keys_merge_ms := if detailed { merge_sw.elapsed().milliseconds() } else { i64(0) }
	build_prepare_keys_ms := if detailed { keys_sw.elapsed().milliseconds() } else { i64(0) }
	mut rows_sw := if detailed { time.new_stopwatch() } else { time.StopWatch{} }
	mut rows_key_us := i64(0)
	mut rows_value_us := i64(0)
	mut rebuilt := if insert_only_rebuild && !has_delete_ops {
		result := merge_existing_items_with_new_keys(items, new_keys, item_map, key_bytes_map,
			detailed)
		rows_key_us += result.rows_key_us
		rows_value_us += result.rows_value_us
		result.items
	} else if use_partitioned_rebuild {
		result := build_partitioned_items(items, ordered_keys, new_keys, item_map, key_bytes_map,
			deleted_new_keys, deleted_existing_keys, touched_existing_keys, spans, detailed)
		rows_key_us += result.rows_key_us
		rows_value_us += result.rows_value_us
		result.items
	} else {
		mut merged := []KVPair{len: keys.len}
		for idx, key in keys {
			key_bytes := if detailed {
				mut row_key_sw := time.new_stopwatch()
				bytes := key_bytes_map[key] or { key.bytes() }
				rows_key_us += row_key_sw.elapsed().microseconds()
				bytes
			} else {
				key_bytes_map[key] or { key.bytes() }
			}
			value := if detailed {
				mut row_value_sw := time.new_stopwatch()
				val := item_map[key]
				rows_value_us += row_value_sw.elapsed().microseconds()
				val
			} else {
				item_map[key]
			}
			merged[idx] = KVPair{
				key:   key_bytes
				value: value
			}
		}
		merged
	}
	build_prepare_rows_ms := if detailed { rows_sw.elapsed().milliseconds() } else { i64(0) }
	build_prepare_ms := if detailed { prepare_sw.elapsed().milliseconds() } else { i64(0) }
	build_result := Tree.build_sorted_bulk_with_timings(rebuilt, cfg)!
	next_tree := build_result.tree
	build_ms := if detailed { build_sw.elapsed().milliseconds() } else { i64(0) }
	if next_tree.root.cid == view.schema.table.tree.root.cid {
		return TypedIndexedSchemaUpdate{
			view:    view
			diff:    view.schema.table.tree.diff(view.schema.table.tree)
			timings: TypedIndexedWriteTimings{
				items_ms:                     items_ms
				items_key_ms:                 micros_to_millis(items_key_us)
				items_fill_ms:                micros_to_millis(items_fill_us)
				ops_ms:                       ops_ms
				ops_key_ms:                   micros_to_millis(ops_key_us)
				ops_lookup_ms:                micros_to_millis(ops_lookup_us)
				ops_encode_ms:                micros_to_millis(ops_encode_us)
				ops_state_ms:                 micros_to_millis(ops_state_us)
				ops_state_new_key_ms:         0
				ops_state_item_ms:            0
				ops_state_cache_ms:           0
				ops_index_ms:                 micros_to_millis(ops_index_us)
				build_ms:                     build_ms
				build_prepare_ms:             build_prepare_ms
				build_prepare_keys_ms:        build_prepare_keys_ms
				build_prepare_keys_sort_ms:   build_prepare_keys_sort_ms
				build_prepare_keys_merge_ms:  build_prepare_keys_merge_ms
				build_prepare_rows_ms:        build_prepare_rows_ms
				build_prepare_rows_key_ms:    micros_to_millis(rows_key_us)
				build_prepare_rows_value_ms:  micros_to_millis(rows_value_us)
				build_leaf_ms:                build_result.timings.leaf_ms
				build_leaf_chunk_ms:          build_result.timings.leaf_chunk_ms
				build_leaf_node_ms:           build_result.timings.leaf_node_ms
				build_leaf_node_serialize_ms: build_result.timings.leaf_node_serialize_ms
				build_leaf_node_cid_ms:       build_result.timings.leaf_node_cid_ms
				build_leaf_node_add_ms:       build_result.timings.leaf_node_add_ms
				build_internal_ms:            build_result.timings.internal_ms
			}
		}
	}
	next_view := view.with_schema(TypedSchemaView.new(TableView.new(next_tree, table_name),
		codec))
	return TypedIndexedSchemaUpdate{
		view:    next_view
		diff:    view.schema.table.tree.diff(next_tree)
		timings: TypedIndexedWriteTimings{
			items_ms:                     items_ms
			items_key_ms:                 micros_to_millis(items_key_us)
			items_fill_ms:                micros_to_millis(items_fill_us)
			ops_ms:                       ops_ms
			ops_key_ms:                   micros_to_millis(ops_key_us)
			ops_lookup_ms:                micros_to_millis(ops_lookup_us)
			ops_encode_ms:                micros_to_millis(ops_encode_us)
			ops_state_ms:                 micros_to_millis(ops_state_us)
			ops_state_new_key_ms:         0
			ops_state_item_ms:            0
			ops_state_cache_ms:           0
			ops_index_ms:                 micros_to_millis(ops_index_us)
			build_ms:                     build_ms
			build_prepare_ms:             build_prepare_ms
			build_prepare_keys_ms:        build_prepare_keys_ms
			build_prepare_keys_sort_ms:   build_prepare_keys_sort_ms
			build_prepare_keys_merge_ms:  build_prepare_keys_merge_ms
			build_prepare_rows_ms:        build_prepare_rows_ms
			build_prepare_rows_key_ms:    micros_to_millis(rows_key_us)
			build_prepare_rows_value_ms:  micros_to_millis(rows_value_us)
			build_leaf_ms:                build_result.timings.leaf_ms
			build_leaf_chunk_ms:          build_result.timings.leaf_chunk_ms
			build_leaf_node_ms:           build_result.timings.leaf_node_ms
			build_leaf_node_serialize_ms: build_result.timings.leaf_node_serialize_ms
			build_leaf_node_cid_ms:       build_result.timings.leaf_node_cid_ms
			build_leaf_node_add_ms:       build_result.timings.leaf_node_add_ms
			build_internal_ms:            build_result.timings.internal_ms
		}
	}
}

fn merge_existing_items_with_new_keys(items []KVPair, new_keys []string, item_map map[string][]u8, key_bytes_map map[string][]u8, detailed bool) MergeExistingItemsResult {
	mut merged := []KVPair{cap: items.len + new_keys.len}
	mut item_idx := 0
	mut new_idx := 0
	mut rows_key_us := i64(0)
	mut rows_value_us := i64(0)
	for item_idx < items.len && new_idx < new_keys.len {
		existing := items[item_idx]
		new_key := new_keys[new_idx]
		new_key_bytes := key_bytes_map[new_key] or { new_key.bytes() }
		cmp := compare_key_bytes(existing.key, new_key_bytes)
		if cmp <= 0 {
			merged << existing
			item_idx++
			continue
		}
		value := if detailed {
			mut row_value_sw := time.new_stopwatch()
			val := item_map[new_key]
			rows_value_us += row_value_sw.elapsed().microseconds()
			val
		} else {
			item_map[new_key]
		}
		merged << KVPair{
			key:   new_key_bytes
			value: value
		}
		new_idx++
	}
	for item_idx < items.len {
		merged << items[item_idx]
		item_idx++
	}
	for new_idx < new_keys.len {
		new_key := new_keys[new_idx]
		new_key_bytes := key_bytes_map[new_key] or { new_key.bytes() }
		value := if detailed {
			mut row_value_sw := time.new_stopwatch()
			val := item_map[new_key]
			rows_value_us += row_value_sw.elapsed().microseconds()
			val
		} else {
			item_map[new_key]
		}
		merged << KVPair{
			key:   new_key_bytes
			value: value
		}
		new_idx++
	}
	return MergeExistingItemsResult{
		items:         merged
		rows_key_us:   rows_key_us
		rows_value_us: rows_value_us
	}
}

fn should_use_partitioned_rebuild(existing_keys []string, new_keys []string, spans []MutationKeySpan, insert_only_rebuild bool, has_delete_ops bool) bool {
	if insert_only_rebuild || spans.len == 0 {
		return false
	}
	if existing_keys.len == 0 {
		return false
	}
	covered_existing := count_existing_keys_covered_by_spans(existing_keys, spans)
	coverage_pct := (covered_existing * 100) / existing_keys.len
	mut span_total := 0
	mut span_max := 0
	for span in spans {
		span_total += span.key_count
		if span.key_count > span_max {
			span_max = span.key_count
		}
	}
	avg_span := if spans.len > 0 { span_total / spans.len } else { 0 }
	if spans.len > 64 && !(spans.len <= 128 && coverage_pct <= 20 && avg_span >= 64) {
		return false
	}
	if coverage_pct > 25 {
		return false
	}
	if !has_delete_ops && new_keys.len > existing_keys.len / 2 {
		return false
	}
	return true
}

fn build_partitioned_items(items []KVPair, ordered_keys []string, new_keys []string, item_map map[string][]u8, key_bytes_map map[string][]u8, deleted_new_keys map[string]bool, deleted_existing_keys map[string]bool, touched_existing_keys map[string]bool, spans []MutationKeySpan, detailed bool) MergeExistingItemsResult {
	mut merged := []KVPair{cap: items.len + new_keys.len - deleted_existing_keys.len - deleted_new_keys.len}
	mut item_idx := 0
	mut new_idx := 0
	mut rows_key_us := i64(0)
	mut rows_value_us := i64(0)
	for span in spans {
		prefix_start := item_idx
		for item_idx < items.len && ordered_keys[item_idx] < span.start_key {
			item_idx++
		}
		if item_idx > prefix_start {
			merged << items[prefix_start..item_idx]
		}
		for new_idx < new_keys.len && new_keys[new_idx] < span.start_key {
			new_key := new_keys[new_idx]
			if new_key !in deleted_new_keys {
				new_key_bytes := if detailed {
					mut row_key_sw := time.new_stopwatch()
					bytes := key_bytes_map[new_key] or { new_key.bytes() }
					rows_key_us += row_key_sw.elapsed().microseconds()
					bytes
				} else {
					key_bytes_map[new_key] or { new_key.bytes() }
				}
				new_value := if detailed {
					mut row_value_sw := time.new_stopwatch()
					val := item_map[new_key]
					rows_value_us += row_value_sw.elapsed().microseconds()
					val
				} else {
					item_map[new_key]
				}
				merged << KVPair{
					key:   new_key_bytes
					value: new_value
				}
			}
			new_idx++
		}
		for {
			have_existing := item_idx < items.len && ordered_keys[item_idx] <= span.end_key
			have_new := new_idx < new_keys.len && new_keys[new_idx] <= span.end_key
			if !have_existing && !have_new {
				break
			}
			if have_existing && (!have_new || ordered_keys[item_idx] <= new_keys[new_idx]) {
				existing_key := ordered_keys[item_idx]
				if existing_key in deleted_existing_keys {
					item_idx++
					continue
				}
				if existing_key in touched_existing_keys {
					existing := items[item_idx]
					new_value := if detailed {
						mut row_value_sw := time.new_stopwatch()
						val := item_map[existing_key]
						rows_value_us += row_value_sw.elapsed().microseconds()
						val
					} else {
						item_map[existing_key]
					}
					merged << KVPair{
						key:   existing.key
						value: new_value
					}
				} else {
					mut run_end := item_idx + 1
					for run_end < items.len && ordered_keys[run_end] <= span.end_key {
						run_key := ordered_keys[run_end]
						if run_key in deleted_existing_keys || run_key in touched_existing_keys {
							break
						}
						if have_new && run_key > new_keys[new_idx] {
							break
						}
						run_end++
					}
					merged << items[item_idx..run_end]
					item_idx = run_end
					continue
				}
				item_idx++
				continue
			}
			new_key := new_keys[new_idx]
			if new_key !in deleted_new_keys {
				new_key_bytes := if detailed {
					mut row_key_sw := time.new_stopwatch()
					bytes := key_bytes_map[new_key] or { new_key.bytes() }
					rows_key_us += row_key_sw.elapsed().microseconds()
					bytes
				} else {
					key_bytes_map[new_key] or { new_key.bytes() }
				}
				new_value := if detailed {
					mut row_value_sw := time.new_stopwatch()
					val := item_map[new_key]
					rows_value_us += row_value_sw.elapsed().microseconds()
					val
				} else {
					item_map[new_key]
				}
				merged << KVPair{
					key:   new_key_bytes
					value: new_value
				}
			}
			new_idx++
		}
	}
	for item_idx < items.len {
		merged << items[item_idx]
		item_idx++
	}
	for new_idx < new_keys.len {
		new_key := new_keys[new_idx]
		if new_key !in deleted_new_keys {
			new_key_bytes := if detailed {
				mut row_key_sw := time.new_stopwatch()
				bytes := key_bytes_map[new_key] or { new_key.bytes() }
				rows_key_us += row_key_sw.elapsed().microseconds()
				bytes
			} else {
				key_bytes_map[new_key] or { new_key.bytes() }
			}
			new_value := if detailed {
				mut row_value_sw := time.new_stopwatch()
				val := item_map[new_key]
				rows_value_us += row_value_sw.elapsed().microseconds()
				val
			} else {
				item_map[new_key]
			}
			merged << KVPair{
				key:   new_key_bytes
				value: new_value
			}
		}
		new_idx++
	}
	return MergeExistingItemsResult{
		items:         merged
		rows_key_us:   rows_key_us
		rows_value_us: rows_value_us
	}
}

fn rebuild_typed_single_index_tree(rows_tree Tree, codec TypedRowCodec, table_name string, index SchemaIndexDef, cfg ChunkConfig) !Tree {
	if index.is_fts() {
		return Tree{}
	}
	table_view := TableView.new(rows_tree, table_name)
	items := rows_tree.items()!
	column := index.value_column(codec.table)!
	simple_lookup := !index.is_json_path() && !index.is_field_selector() && !index.is_fts()
	index_prefix := IndexView.new(Tree{}, table_name, index.name).entry_prefix()
	mut index_items := []KVPair{}
	for item in items {
		row := decode_table_row(table_view, item)!
		row_data := codec.decode(row.value)!
		index_value, has_value := typed_index_value_lookup_with_hint(row_data, index,
			codec.table, simple_lookup)!
		if !has_value {
			continue
		}
		encoded := encode_index_value_without_validation(index_value, column)!
		index_items << KVPair{
			key:   build_index_entry_key(index_prefix, encoded, row.primary_key)
			value: if index.stores_row { row.value } else { []u8{} }
		}
	}
	if index_items.len == 0 {
		return Tree{}
	}
	return Tree.build(index_items, cfg)
}

fn build_split_index_mutation_row_states(rows_view TableView, codec TypedRowCodec, ops []TypedWriteOp) ![]SplitIndexMutationRowState {
	mut states := []SplitIndexMutationRowState{cap: ops.len}
	for op in ops {
		existing := rows_view.get(op.primary_key) or { TableRow{} }
		had_old := existing.primary_key.len > 0
		old_row := if had_old { codec.decode(existing.value)! } else { TypedRowData.new() }
		encoded_new_row := if op.delete { []u8{} } else { codec.encode_without_validation(op.row)! }
		states << SplitIndexMutationRowState{
			primary_key:     op.primary_key.clone()
			had_old:         had_old
			old_row:         old_row
			new_row:         op.row
			delete:          op.delete
			encoded_new_row: encoded_new_row
		}
	}
	return states
}

fn apply_split_index_mutations(base_tree Tree, table_name string, codec TypedRowCodec, index SchemaIndexDef, states []SplitIndexMutationRowState, cfg ChunkConfig) !Tree {
	if index.is_fts() {
		return Tree{}
	}
	column := index.value_column(codec.table)!
	simple_lookup := !index.is_json_path() && !index.is_field_selector() && !index.is_fts()
	mut index_view := IndexView.new(base_tree, table_name, index.name)
	for state in states {
		old_value, old_has := if state.had_old {
			typed_index_value_lookup_with_hint(state.old_row, index, codec.table, simple_lookup)!
		} else {
			ColumnValue(NullValue{}), false
		}
		new_value, new_has := if state.delete {
			ColumnValue(NullValue{}), false
		} else {
			typed_index_value_lookup_with_hint(state.new_row, index, codec.table, simple_lookup)!
		}
		if old_has && (!new_has || !column_values_equal(old_value, new_value)) {
			old_encoded := encode_index_value_without_validation(old_value, column)!
			index_view = index_view.delete(old_encoded, state.primary_key, cfg) or { index_view }
		}
		if new_has && (!old_has || !column_values_equal(old_value, new_value)) {
			new_encoded := encode_index_value_without_validation(new_value, column)!
			index_value := if index.stores_row { state.encoded_new_row } else { []u8{} }
			index_view = index_view.put(new_encoded, state.primary_key, index_value, cfg)!
		}
	}
	return index_view.tree
}

fn build_split_index_mutation_batches(table_name string, codec TypedRowCodec, indexes []SchemaIndexDef, states []SplitIndexMutationRowState) !map[string]SplitIndexMutationBatch {
	mut batches := map[string]SplitIndexMutationBatch{}
	for index in indexes {
		if index.is_field_selector() || index.is_fts() {
			continue
		}
		column := index.value_column(codec.table)!
		simple_lookup := !index.is_json_path() && !index.is_field_selector() && !index.is_fts()
		index_prefix := IndexView.new(Tree{}, table_name, index.name).entry_prefix().bytestr()
		mut batch := SplitIndexMutationBatch{
			put_items:     map[string][]u8{}
			delete_keys:   map[string]bool{}
			key_bytes_map: map[string][]u8{}
		}
		for state in states {
			old_value, old_has := if state.had_old {
				typed_index_value_lookup_with_hint(state.old_row, index, codec.table,
					simple_lookup)!
			} else {
				ColumnValue(NullValue{}), false
			}
			new_value, new_has := if state.delete {
				ColumnValue(NullValue{}), false
			} else {
				typed_index_value_lookup_with_hint(state.new_row, index, codec.table,
					simple_lookup)!
			}
			old_key := if old_has {
				build_index_entry_key_string_for_value(index_prefix, old_value, column,
					state.primary_key.bytestr())!
			} else {
				''
			}
			new_key := if new_has {
				build_index_entry_key_string_for_value(index_prefix, new_value, column,
					state.primary_key.bytestr())!
			} else {
				''
			}
			old_encoded_row := if state.had_old && index.stores_row {
				codec.encode_without_validation(state.old_row)!
			} else {
				[]u8{}
			}
			if old_has && (!new_has || old_key != new_key || (index.stores_row
				&& state.encoded_new_row != old_encoded_row)) {
				batch.delete_keys[old_key] = true
				batch.put_items.delete(old_key)
			}
			if new_has {
				batch.delete_keys.delete(new_key)
				batch.put_items[new_key] = if index.stores_row {
					state.encoded_new_row.clone()
				} else {
					[]u8{}
				}
				batch.key_bytes_map[new_key] = new_key.bytes()
			}
		}
		batches[index.name] = batch
	}
	return batches
}

fn apply_split_index_mutation_batch(base_tree Tree, table_name string, codec TypedRowCodec, index SchemaIndexDef, batch SplitIndexMutationBatch, cfg ChunkConfig) !Tree {
	_ = table_name
	_ = codec
	_ = index
	if batch.put_items.len == 0 && batch.delete_keys.len == 0 {
		return base_tree
	}
	items := base_tree.items()!
	mut ordered_keys := []string{cap: items.len}
	mut existing_item_index := map[string]int{}
	mut item_pos := 0
	for item in items {
		key := item.key.bytestr()
		ordered_keys << key
		existing_item_index[key] = item_pos
		item_pos++
	}
	mut existing_key_set := map[string]bool{}
	for key in ordered_keys {
		existing_key_set[key] = true
	}
	mut item_map := map[string][]u8{}
	mut new_keys := []string{}
	mut new_key_set := map[string]bool{}
	mut deleted_existing_keys := map[string]bool{}
	mut touched_existing_keys := map[string]bool{}
	for key, value in batch.put_items {
		item_map[key] = value
		if key in existing_key_set {
			touched_existing_keys[key] = true
		} else {
			new_keys << key
			new_key_set[key] = true
		}
	}
	for key, _ in batch.delete_keys {
		if key in batch.put_items {
			continue
		}
		if key in existing_key_set {
			deleted_existing_keys[key] = true
		}
	}
	new_keys.sort()
	spans := plan_mutation_key_spans(ordered_keys, new_keys, deleted_existing_keys, touched_existing_keys)
	insert_only_rebuild := deleted_existing_keys.len == 0 && touched_existing_keys.len == 0
	use_partitioned_rebuild := cfg.enable_partitioned_rebuild
		&& should_use_partitioned_rebuild(ordered_keys, new_keys, spans, insert_only_rebuild, deleted_existing_keys.len > 0)
	mut rebuilt := if insert_only_rebuild {
		merge_existing_items_with_new_keys(items, new_keys, item_map, batch.key_bytes_map,
			false).items
	} else if use_partitioned_rebuild {
		build_partitioned_items(items, ordered_keys, new_keys, item_map, batch.key_bytes_map,
			map[string]bool{}, deleted_existing_keys, touched_existing_keys, spans, false).items
	} else {
		keys := merge_sorted_item_keys(ordered_keys, new_keys, new_key_set, map[string]bool{},
			deleted_existing_keys)
		mut merged := []KVPair{len: keys.len}
		for idx, key in keys {
			value := if key in item_map {
				item_map[key]
			} else {
				items[existing_item_index[key]].value
			}
			merged[idx] = KVPair{
				key:   if key in batch.key_bytes_map {
					batch.key_bytes_map[key]
				} else {
					key.bytes()
				}
				value: value
			}
		}
		merged
	}
	if rebuilt.len == 0 {
		return Tree{}
	}
	return Tree.build_sorted_bulk_with_timings(rebuilt, cfg)!.tree
}

fn is_fixed_width_column(column ColumnDef) bool {
	return match column.typ {
		.bool_, .i64_ { true }
		.string_, .bytes_, .enum_, .json_, .datetime_, .markdown_ { false }
	}
}

fn rebuild_typed_indexes(tree Tree, specs []TypedTableSpec, cfg ChunkConfig) !Tree {
	return rebuild_typed_indexes_for_tables(tree, specs, []string{}, cfg)
}

pub fn rebuild_typed_indexes_for_specs(tree Tree, specs []TypedTableSpec, cfg ChunkConfig) !Tree {
	return rebuild_typed_indexes(tree, specs, cfg)
}

fn rebuild_typed_indexes_for_tables(tree Tree, specs []TypedTableSpec, table_names []string, cfg ChunkConfig) !Tree {
	items := tree.items()!
	mut item_map := map[string][]u8{}
	for item in items {
		item_map[item.key.bytestr()] = item.value.clone()
	}

	mut scoped_names := map[string]bool{}
	for name in table_names {
		scoped_names[name] = true
	}
	mut target_specs := []TypedTableSpec{}
	for spec in specs {
		if scoped_names.len == 0 || spec.table.name in scoped_names {
			target_specs << spec
		}
	}

	for spec in target_specs {
		for index in spec.indexes {
			prefix := IndexView.new(Tree{}, spec.table.name, index.name).entry_prefix().bytestr()
			for key in item_map.keys() {
				if key.starts_with(prefix) {
					item_map.delete(key)
				}
			}
		}
	}

	for spec in target_specs {
		codec := TypedRowCodec.new(spec.table)
		table_view := TableView.new(Tree{}, spec.table.name)
		row_prefix := table_view.row_prefix()
		row_prefix_str := row_prefix.bytestr()
		row_keys := item_map.keys().filter(it.starts_with(row_prefix_str))
		for row_key in row_keys {
			primary_key := row_key.bytes()[row_prefix.len..]
			row := codec.decode(item_map[row_key])!
			for index in spec.indexes {
				if index.is_field_selector() || index.is_fts() {
					continue
				}
				index_value, has_value := typed_index_value_lookup(row, index, spec.table)!
				if !has_value {
					continue
				}
				column := index.value_column(spec.table)!
				index_key := encode_index_value_without_validation(index_value, column)!
				index_view := IndexView.new(Tree{}, spec.table.name, index.name)
				item_map[index_view.key_for(index_key, primary_key).bytestr()] = if index.stores_row {
					codec.encode(row)!
				} else {
					[]u8{}
				}
			}
		}
	}

	mut keys := item_map.keys()
	keys.sort()
	mut rebuilt := []KVPair{cap: keys.len}
	for key in keys {
		rebuilt << KVPair{
			key:   key.bytes()
			value: item_map[key].clone()
		}
	}
	return Tree.build(rebuilt, cfg)
}

pub fn rebuild_typed_aggregates_for_specs(tree Tree, specs []TypedTableSpec, cfg ChunkConfig) !Tree {
	mut next_tree := tree
	for spec in specs {
		sum_columns := spec.table.sum_aggregate_columns()
		if sum_columns.len == 0 {
			continue
		}
		codec := TypedRowCodec.new(spec.table)
		mut cursor := TableView.new(next_tree, spec.table.name).raw_cursor([]u8{}, 0)!
		mut sums := map[string]i64{}
		mut bucket_sums := map[string][]i64{}
		for column in sum_columns {
			sums[column.name] = i64(0)
			bucket_sums[column.name] = []i64{len: 256, init: i64(0)}
		}
		for {
			row := cursor.next() or {
				if err.msg().contains('iterator exhausted') {
					break
				}
				return err
			}
			bucket := int(typed_aggregate_bucket(row.primary_key))
			for column in sum_columns {
				value := codec.decode_i64_column(row.value, column.name)!
				sums[column.name] = (sums[column.name] or { i64(0) }) + value
				mut column_buckets := bucket_sums[column.name] or { []i64{len: 256, init: i64(0)} }
				column_buckets[bucket] += value
				bucket_sums[column.name] = column_buckets
			}
		}
		for column in sum_columns {
			next_tree = next_tree.put(KVPair{
				key:   encode_table_sum_aggregate_key(spec.table.name, column.name)
				value: TypedValueEncoder.encode_value(sums[column.name] or { i64(0) },
					.i64_)!
			}, cfg)!
			column_buckets := bucket_sums[column.name] or { []i64{len: 256, init: i64(0)} }
			for bucket := 0; bucket < 256; bucket++ {
				next_tree = next_tree.put(KVPair{
					key:   encode_table_sum_bucket_key(spec.table.name, column.name, u8(bucket))
					value: TypedValueEncoder.encode_value(column_buckets[bucket], .i64_)!
				}, cfg)!
			}
		}
	}
	return next_tree
}

fn typed_aggregate_bucket(primary_key []u8) u8 {
	if primary_key.len == 0 {
		return u8(0)
	}
	return primary_key[0]
}

fn typed_aggregate_value_from_row(row TypedRowData, column ColumnDef) !i64 {
	if !row.has(column.name) {
		return i64(0)
	}
	value := row.get(column.name)!
	return match value {
		NullValue { i64(0) }
		i64 { value }
		else { error('aggregate ${column.name} requires i64 row value') }
	}
}

pub fn column_value_to_json_any(value ColumnValue) !json2.Any {
	return match value {
		NullValue { json2.Null{} }
		bool { json2.Any(value) }
		i64 { json2.Any(value) }
		string { json2.Any(value) }
		else { error('json path updates only support bool, i64, string, or null') }
	}
}

fn json_set_path_value(mut root map[string]json2.Any, path string, value ColumnValue) ! {
	segments := path.split('.')
	if segments.len == 0 {
		return error('json path cannot be empty')
	}
	json_value := column_value_to_json_any(value)!
	if segments.len == 1 {
		root[segments[0]] = json_value
		return
	}
	head := segments[0]
	rest := segments[1..].join('.')
	existing := root[head] or { json2.Any(map[string]json2.Any{}) }
	mut nested := match existing {
		map[string]json2.Any {
			existing.clone()
		}
		else {
			map[string]json2.Any{}
		}
	}
	json_set_path_value(mut nested, rest, value)!
	root[head] = nested
}

fn json_delete_path_value(mut root map[string]json2.Any, path string) ! {
	segments := path.split('.')
	if segments.len == 0 {
		return error('json path cannot be empty')
	}
	if segments.len == 1 {
		root.delete(segments[0])
		return
	}
	head := segments[0]
	rest := segments[1..].join('.')
	existing := root[head] or { return }
	match existing {
		map[string]json2.Any {
			mut nested := existing.clone()
			json_delete_path_value(mut nested, rest)!
			root[head] = nested
		}
		else {
			return
		}
	}
}

pub fn json_set_scalar_path(raw string, path string, value ColumnValue) !string {
	mut root := json2.decode[map[string]json2.Any](raw)!
	json_set_path_value(mut root, path, value)!
	return root.str()
}

pub fn json_delete_path(raw string, path string) !string {
	mut root := json2.decode[map[string]json2.Any](raw)!
	json_delete_path_value(mut root, path)!
	return root.str()
}

pub fn json_patch_scalar_paths(raw string, updates []JsonPathUpdate) !string {
	mut root := json2.decode[map[string]json2.Any](raw)!
	for update in updates {
		if update.path.len == 0 {
			return error('json patch path cannot be empty')
		}
		match update.op {
			.set { json_set_path_value(mut root, update.path, update.value)! }
			.delete { json_delete_path_value(mut root, update.path)! }
		}
	}
	return root.str()
}

fn json_lookup_path_value(root map[string]json2.Any, path string) !ColumnValue {
	if path.len == 0 {
		return NullValue{}
	}
	segments := path.split('.')
	if segments.len == 0 {
		return NullValue{}
	}
	mut current := root[segments[0]] or { return NullValue{} }
	for idx := 1; idx < segments.len; idx++ {
		segment := segments[idx]
		match current {
			map[string]json2.Any {
				nested := current as map[string]json2.Any
				current = nested[segment] or { return NullValue{} }
			}
			else {
				return NullValue{}
			}
		}
	}
	return match current {
		json2.Null {
			ColumnValue(NullValue{})
		}
		string {
			ColumnValue(current as string)
		}
		bool {
			ColumnValue(current as bool)
		}
		i64 {
			ColumnValue(current as i64)
		}
		int {
			ColumnValue(i64(current as int))
		}
		i32 {
			ColumnValue(i64(current as i32))
		}
		i16 {
			ColumnValue(i64(current as i16))
		}
		i8 {
			ColumnValue(i64(current as i8))
		}
		u64 {
			ColumnValue(i64(current as u64))
		}
		u32 {
			ColumnValue(i64(current as u32))
		}
		u16 {
			ColumnValue(i64(current as u16))
		}
		u8 {
			ColumnValue(i64(current as u8))
		}
		f64 {
			ColumnValue(i64(current as f64))
		}
		f32 {
			ColumnValue(i64(current as f32))
		}
		else {
			return error('json index only supports nested scalar fields: ${path}')
		}
	}
}

fn json_scalar_value_for_index(raw string, index SchemaIndexDef) !ColumnValue {
	root := json2.decode[map[string]json2.Any](raw)!
	value := json_lookup_path_value(root, index.json_field)!
	return match value {
		NullValue {
			ColumnValue(NullValue{})
		}
		string {
			if index.json_field_type != .string_ && index.json_field_type != .enum_ {
				return error('json field ${index.target_label()} did not match declared type')
			}
			s := value as string
			ColumnValue(s)
		}
		bool {
			if index.json_field_type != .bool_ {
				return error('json field ${index.target_label()} did not match declared type')
			}
			b := value as bool
			ColumnValue(b)
		}
		i64 {
			if index.json_field_type != .i64_ {
				return error('json field ${index.target_label()} did not match declared type')
			}
			n := value as i64
			ColumnValue(n)
		}
		else {
			return error('json index only supports scalar fields: ${index.target_label()}')
		}
	}
}

fn merge_sorted_item_keys(existing_keys []string, new_keys []string, is_new_key map[string]bool, deleted_new_keys map[string]bool, deleted_existing_keys map[string]bool) []string {
	if deleted_new_keys.len == 0 && deleted_existing_keys.len == 0 {
		return merge_two_sorted_key_lists(existing_keys, new_keys)
	}
	mut merged := []string{cap: existing_keys.len + new_keys.len - deleted_existing_keys.len - deleted_new_keys.len}
	mut new_idx := 0
	for key in existing_keys {
		if key in is_new_key {
			continue
		}
		for new_idx < new_keys.len && new_keys[new_idx] < key {
			candidate := new_keys[new_idx]
			if candidate !in deleted_new_keys {
				merged << candidate
			}
			new_idx++
		}
		if key !in deleted_existing_keys {
			merged << key
		}
	}
	for new_idx < new_keys.len {
		candidate := new_keys[new_idx]
		if candidate !in deleted_new_keys {
			merged << candidate
		}
		new_idx++
	}
	return merged
}

fn merge_two_sorted_key_lists(existing_keys []string, new_keys []string) []string {
	if existing_keys.len == 0 {
		return new_keys.clone()
	}
	if new_keys.len == 0 {
		return existing_keys.clone()
	}
	mut merged := []string{cap: existing_keys.len + new_keys.len}
	mut existing_idx := 0
	mut new_idx := 0
	for existing_idx < existing_keys.len && new_idx < new_keys.len {
		if existing_keys[existing_idx] <= new_keys[new_idx] {
			merged << existing_keys[existing_idx]
			existing_idx++
		} else {
			merged << new_keys[new_idx]
			new_idx++
		}
	}
	for existing_idx < existing_keys.len {
		merged << existing_keys[existing_idx]
		existing_idx++
	}
	for new_idx < new_keys.len {
		merged << new_keys[new_idx]
		new_idx++
	}
	return merged
}

fn merge_sorted_key_buckets(row_keys []string, index_buckets [][]string) []string {
	mut total := row_keys.len
	for bucket in index_buckets {
		total += bucket.len
	}
	if total == 0 {
		return []string{}
	}
	if index_buckets.len == 0 {
		return row_keys.clone()
	}
	mut bucket_positions := []int{len: index_buckets.len}
	mut merged := []string{cap: total}
	mut row_idx := 0
	for merged.len < total {
		mut best_key := ''
		mut best_bucket := -2
		if row_idx < row_keys.len {
			best_key = row_keys[row_idx]
			best_bucket = -1
		}
		for idx, bucket in index_buckets {
			pos := bucket_positions[idx]
			if pos >= bucket.len {
				continue
			}
			candidate := bucket[pos]
			if best_bucket == -2 || candidate < best_key {
				best_key = candidate
				best_bucket = idx
			}
		}
		if best_bucket == -2 {
			break
		}
		merged << best_key
		if best_bucket == -1 {
			row_idx++
		} else {
			bucket_positions[best_bucket]++
		}
	}
	return merged
}

fn plan_mutation_key_spans(existing_keys []string, new_keys []string, deleted_existing_keys map[string]bool, touched_existing_keys map[string]bool) []MutationKeySpan {
	mut spans := []MutationKeySpan{}
	mut existing_idx := 0
	mut new_idx := 0
	mut active := false
	mut current := MutationKeySpan{}
	for existing_idx < existing_keys.len || new_idx < new_keys.len {
		mut key := ''
		mut changed := false
		if existing_idx < existing_keys.len
			&& (new_idx >= new_keys.len || existing_keys[existing_idx] <= new_keys[new_idx]) {
			key = existing_keys[existing_idx]
			changed = key in deleted_existing_keys || key in touched_existing_keys
			existing_idx++
		} else {
			key = new_keys[new_idx]
			changed = true
			new_idx++
		}
		if changed {
			if !active {
				current = MutationKeySpan{
					start_key: key
					end_key:   key
					key_count: 1
				}
				active = true
			} else {
				current.end_key = key
				current.key_count++
			}
			continue
		}
		if active {
			spans << current
			active = false
		}
	}
	if active {
		spans << current
	}
	return spans
}

fn typed_index_value_lookup(row TypedRowData, index SchemaIndexDef, table TableDef) !(ColumnValue, bool) {
	if index.is_fts() {
		return error('fts indexes do not use typed tree value lookup: ${index.name}')
	}
	if index.is_field_selector() {
		return ColumnValue(i64(0)), true
	}
	if !index.is_json_path() {
		value, ok := row.lookup(index.column)
		return value, ok
	}
	base_value, ok := row.lookup(index.column)
	if !ok {
		return NullValue{}, false
	}
	base_column := table.column(index.column)!
	match base_value {
		NullValue {
			return NullValue{}, true
		}
		string {
			if base_column.typ != .json_ {
				return error('json-path index requires json column: ${index.column}')
			}
			value := json_scalar_value_for_index(base_value, index)!
			return value, true
		}
		else {
			return error('json-path index requires json string payload: ${index.column}')
		}
	}
}

fn typed_index_value_lookup_with_hint(row TypedRowData, index SchemaIndexDef, table TableDef, simple bool) !(ColumnValue, bool) {
	if simple {
		value, ok := row.lookup(index.column)
		return value, ok
	}
	return typed_index_value_lookup(row, index, table)
}

fn typed_index_value_from_row(row TypedRowData, index SchemaIndexDef, table TableDef) !ColumnValue {
	value, ok := typed_index_value_lookup(row, index, table)!
	if !ok {
		return NullValue{}
	}
	return value
}

fn typed_aggregate_deltas_for_ops(view TypedIndexedSchemaView, spec TypedTableSpec, ops []TypedWriteOp) !map[string]TypedAggregateDelta {
	sum_columns := spec.table.sum_aggregate_columns()
	if sum_columns.len == 0 || ops.len == 0 {
		return map[string]TypedAggregateDelta{}
	}
	mut final_ops := map[string]TypedWriteOp{}
	for op in ops {
		final_ops[op.primary_key.hex()] = op
	}
	mut deltas := map[string]TypedAggregateDelta{}
	for column in sum_columns {
		deltas[column.name] = TypedAggregateDelta{
			total:         i64(0)
			bucket_deltas: map[u8]i64{}
		}
	}
	for _, op in final_ops {
		bucket := typed_aggregate_bucket(op.primary_key)
		old_row := view.schema.get(op.primary_key) or { TypedSchemaRow{} }
		for column in sum_columns {
			mut delta := deltas[column.name] or {
				TypedAggregateDelta{
					total:         i64(0)
					bucket_deltas: map[u8]i64{}
				}
			}
			mut bucket_delta := i64(0)
			if old_row.primary_key.len > 0 {
				old_value := typed_aggregate_value_from_row(old_row.data, column)!
				delta.total -= old_value
				bucket_delta -= old_value
			}
			if !op.delete {
				new_value := typed_aggregate_value_from_row(op.row, column)!
				delta.total += new_value
				bucket_delta += new_value
			}
			delta.bucket_deltas[bucket] = (delta.bucket_deltas[bucket] or { i64(0) }) + bucket_delta
			deltas[column.name] = delta
		}
	}
	return deltas
}

fn current_typed_aggregate_sum(tree Tree, spec TypedTableSpec, column ColumnDef) !i64 {
	aggregate_key := encode_table_sum_aggregate_key(spec.table.name, column.name)
	item := tree.get(aggregate_key) or {
		codec := TypedRowCodec.new(spec.table)
		mut cursor := TableView.new(tree, spec.table.name).raw_cursor([]u8{}, 0)!
		return cursor.sum_i64_column(codec, column.name)
	}
	value := TypedValueEncoder.decode_value(item.value, .i64_)!
	return match value {
		i64 { value }
		else { error('aggregate ${spec.table.name}.${column.name} did not decode as i64') }
	}
}

fn current_typed_aggregate_bucket_sum(tree Tree, spec TypedTableSpec, column ColumnDef, bucket u8) !i64 {
	item := tree.get(encode_table_sum_bucket_key(spec.table.name, column.name, bucket)) or {
		return i64(0)
	}
	value := TypedValueEncoder.decode_value(item.value, .i64_)!
	return match value {
		i64 { value }
		else { error('aggregate bucket ${spec.table.name}.${column.name} did not decode as i64') }
	}
}

fn apply_typed_aggregate_deltas(tree_before Tree, tree_after Tree, spec TypedTableSpec, deltas map[string]TypedAggregateDelta, cfg ChunkConfig) !Tree {
	if deltas.len == 0 {
		return tree_after
	}
	mut next_tree := tree_after
	for column in spec.table.sum_aggregate_columns() {
		delta := deltas[column.name] or {
			TypedAggregateDelta{
				total:         i64(0)
				bucket_deltas: map[u8]i64{}
			}
		}
		base_sum := current_typed_aggregate_sum(tree_before, spec, column)!
		next_tree = next_tree.put(KVPair{
			key:   encode_table_sum_aggregate_key(spec.table.name, column.name)
			value: TypedValueEncoder.encode_value(base_sum + delta.total, .i64_)!
		}, cfg)!
		for bucket, bucket_delta in delta.bucket_deltas {
			base_bucket_sum := current_typed_aggregate_bucket_sum(tree_before, spec, column,
				bucket)!
			next_tree = next_tree.put(KVPair{
				key:   encode_table_sum_bucket_key(spec.table.name, column.name, bucket)
				value: TypedValueEncoder.encode_value(base_bucket_sum + bucket_delta,
					.i64_)!
			}, cfg)!
		}
	}
	return next_tree
}

fn rebuild_typed_indexes_for_changed_rows(tree Tree, specs []TypedTableSpec, changed_rows map[string]map[string][]u8, cfg ChunkConfig) !(Tree, ReindexStageTimings) {
	if changed_rows.len == 0 {
		return tree, ReindexStageTimings{}
	}
	mut items_sw := time.new_stopwatch()
	items := tree.items()!
	items_ms := items_sw.elapsed().milliseconds()
	mut item_map := map[string][]u8{}
	for item in items {
		item_map[item.key.bytestr()] = item.value.clone()
	}

	mut removed_indexes := 0
	mut changed_tables := 0
	mut changed_row_count := 0
	mut mutations := []Mutation{}
	mut remove_sw := time.new_stopwatch()
	for spec in specs {
		changed := (changed_rows[spec.table.name] or {
			map[string][]u8{}
		}).clone()
		if changed.len == 0 {
			continue
		}
		changed_tables++
		changed_row_count += changed.len
		for index in spec.indexes {
			index_view := IndexView.new(Tree{}, spec.table.name, index.name)
			prefix := index_view.entry_prefix()
			for key, _ in item_map {
				key_bytes := key.bytes()
				if !has_prefix_bytes(key_bytes, prefix) {
					continue
				}
				entry := decode_index_entry(index_view, KVPair{
					key:   key_bytes
					value: item_map[key]
				}) or { continue }
				if entry.primary_key.hex() in changed {
					item_map.delete(key)
					mutations << Mutation.delete(key_bytes)
					removed_indexes++
				}
			}
		}
	}
	remove_ms := remove_sw.elapsed().milliseconds()

	mut inserted_indexes := 0
	mut insert_sw := time.new_stopwatch()
	for spec in specs {
		changed := (changed_rows[spec.table.name] or {
			map[string][]u8{}
		}).clone()
		if changed.len == 0 {
			continue
		}
		codec := TypedRowCodec.new(spec.table)
		table_view := TableView.new(Tree{}, spec.table.name)
		for _, primary_key in changed {
			row_key := table_view.key_for(primary_key).bytestr()
			if row_key !in item_map {
				continue
			}
			row := codec.decode(item_map[row_key])!
			encoded_row := codec.encode_without_validation(row)!
			for index in spec.indexes {
				if index.is_field_selector() || index.is_fts() {
					continue
				}
				index_value, has_value := typed_index_value_lookup(row, index, spec.table)!
				if !has_value {
					continue
				}
				column := index.value_column(spec.table)!
				index_key := encode_index_value_without_validation(index_value, column)!
				index_view := IndexView.new(Tree{}, spec.table.name, index.name)
				index_entry_key := index_view.key_for(index_key, primary_key)
				stored_index_value := if index.stores_row { encoded_row } else { []u8{} }
				item_map[index_entry_key.bytestr()] = stored_index_value
				mutations << Mutation.put(index_entry_key, stored_index_value)
				inserted_indexes++
			}
		}
	}
	insert_ms := insert_sw.elapsed().milliseconds()

	mut rebuild_sw := time.new_stopwatch()
	use_patch_strategy := should_patch_reindex(items.len, changed_row_count, mutations.len)
	rebuilt_tree := if use_patch_strategy {
		tree.apply_mutations(mutations, cfg)!.tree
	} else {
		mut keys := item_map.keys()
		keys.sort()
		mut rebuilt := []KVPair{cap: keys.len}
		for key in keys {
			rebuilt << KVPair{
				key:   key.bytes()
				value: item_map[key].clone()
			}
		}
		Tree.build(rebuilt, cfg)!
	}
	rebuild_ms := rebuild_sw.elapsed().milliseconds()
	return rebuilt_tree, ReindexStageTimings{
		items_ms:         items_ms
		remove_ms:        remove_ms
		insert_ms:        insert_ms
		rebuild_ms:       rebuild_ms
		strategy:         if use_patch_strategy { 'patch' } else { 'build' }
		item_count:       items.len
		changed_tables:   changed_tables
		changed_rows:     changed_row_count
		removed_indexes:  removed_indexes
		inserted_indexes: inserted_indexes
	}
}

fn should_patch_reindex(item_count int, changed_rows int, mutation_count int) bool {
	if item_count < 100000 {
		return false
	}
	if changed_rows > 1024 {
		return false
	}
	return mutation_count * 64 <= item_count
}

pub fn (codec TypedRowCodec) encode(row TypedRowData) ![]u8 {
	for name, value in row.values {
		column := codec.table.column(name)!
		TypedValueEncoder.validate(column, value)!
	}
	return codec.encode_without_validation(row)
}

fn (codec TypedRowCodec) encode_without_validation(row TypedRowData) ![]u8 {
	mut total_len := 4 + (codec.table.columns.len * 5)
	for column in codec.table.columns {
		value := row.values[column.name] or { continue }
		if value is NullValue {
			continue
		}
		total_len += estimated_encoded_value_len(value, column.typ)
	}
	mut out := ByteWriter{
		buf: []u8{cap: total_len}
	}
	out.write_u32(u32(codec.table.columns.len))
	for column in codec.table.columns {
		value := row.values[column.name] or {
			if column.nullable {
				out.write_u8(0)
				out.write_u32(0)
				continue
			}
			return error('missing required column: ${column.name}')
		}
		if value is NullValue {
			if !column.nullable {
				return error('column is not nullable: ${column.name}')
			}
			out.write_u8(0)
			out.write_u32(0)
			continue
		}
		out.write_u8(1)
		encoded_len := estimated_encoded_value_len(value, column.typ)
		out.write_u32(u32(encoded_len))
		write_encoded_value(mut out, value, column.typ)!
	}
	return out.owned_bytes()
}

fn estimated_encoded_value_len(value ColumnValue, typ ColumnType) int {
	return match typ {
		.bool_ {
			1
		}
		.i64_ {
			8
		}
		.string_, .enum_, .json_, .datetime_ {
			match value {
				string { value.len }
				else { 0 }
			}
		}
		.bytes_ {
			match value {
				[]u8 { value.len }
				else { 0 }
			}
		}
		.markdown_ {
			match value {
				MarkdownRef { 18 + value.doc_root_id.len + value.source_hash.len }
				else { 0 }
			}
		}
	}
}

fn write_encoded_value(mut out ByteWriter, value ColumnValue, typ ColumnType) ! {
	match typ {
		.bool_ {
			if value is bool {
				out.write_u8(if value { u8(1) } else { u8(0) })
				return
			}
		}
		.i64_ {
			if value is i64 {
				sortable := u64(value) ^ u64(0x8000000000000000)
				out.write_u64(sortable)
				return
			}
		}
		.string_, .enum_, .json_, .datetime_ {
			if value is string {
				out.write_bytes(value.bytes())
				return
			}
		}
		.bytes_ {
			if value is []u8 {
				out.write_bytes(value)
				return
			}
		}
		.markdown_ {
			if value is MarkdownRef {
				out.write_u8(value.version)
				doc_root_id := value.doc_root_id.bytes()
				source_hash := value.source_hash.bytes()
				out.write_u16(u16(doc_root_id.len))
				out.write_bytes(doc_root_id)
				out.write_u16(u16(source_hash.len))
				out.write_bytes(source_hash)
				out.write_u32(u32(value.source_len & 0xffffffff))
				out.write_u32(u32((u64(value.source_len) >> 32) & 0xffffffff))
				out.write_u8(value.ast_version)
				out.write_u32(value.parse_flags)
				return
			}
		}
	}
	return error('value does not match requested column type: type=${typ} value_type=${typeof(value).name}')
}

pub fn (codec TypedRowCodec) decode(data []u8) !TypedRowData {
	if data.len < 4 {
		return error('typed row payload too short')
	}
	column_count := int(read_u32_le(data[..4]))
	if column_count != codec.table.columns.len {
		return error('typed row payload column count mismatch')
	}
	mut cursor := 4
	mut row := TypedRowData.new()
	for column in codec.table.columns {
		if cursor + 5 > data.len {
			return error('typed row payload truncated')
		}
		present := data[cursor]
		cursor++
		value_len := int(read_u32_le(data[cursor..cursor + 4]))
		cursor += 4
		if present == 0 {
			if column.nullable {
				row.set_null(column.name)
				continue
			}
			return error('required column missing from payload: ${column.name}')
		}
		if cursor + value_len > data.len {
			return error('typed row payload value overflow')
		}
		value := TypedValueEncoder.decode_value(data[cursor..cursor + value_len], column.typ)!
		row.set(column.name, value)
		cursor += value_len
	}
	if cursor != data.len {
		return error('typed row payload trailing bytes')
	}
	return row
}

pub fn (codec TypedRowCodec) decode_projected(data []u8, columns []string) !TypedRowData {
	if columns.len == 0 {
		return codec.decode(data)
	}
	if data.len < 4 {
		return error('typed row payload too short')
	}
	column_count := int(read_u32_le(data[..4]))
	if column_count != codec.table.columns.len {
		return error('typed row payload column count mismatch')
	}
	mut selected := map[string]bool{}
	for name in columns {
		if !codec.table.has_column(name) {
			return error('column not found: ${name}')
		}
		selected[name] = true
	}
	mut cursor := 4
	mut row := TypedRowData.new()
	for column in codec.table.columns {
		if cursor + 5 > data.len {
			return error('typed row payload truncated')
		}
		present := data[cursor]
		cursor++
		value_len := int(read_u32_le(data[cursor..cursor + 4]))
		cursor += 4
		if present == 0 {
			if column.name in selected && column.nullable {
				row.set_null(column.name)
				continue
			}
			if column.name in selected && !column.nullable {
				return error('required column missing from payload: ${column.name}')
			}
			continue
		}
		if cursor + value_len > data.len {
			return error('typed row payload value overflow')
		}
		if column.name in selected {
			value := TypedValueEncoder.decode_value(data[cursor..cursor + value_len],
				column.typ)!
			row.set(column.name, value)
		}
		cursor += value_len
	}
	if cursor != data.len {
		return error('typed row payload trailing bytes')
	}
	return row
}

pub fn (codec TypedRowCodec) decode_i64_column(data []u8, name string) !i64 {
	column := codec.table.column(name)!
	if column.typ != .i64_ {
		return error('column ${name} is not i64')
	}
	if data.len < 4 {
		return error('typed row payload too short')
	}
	column_count := int(read_u32_le(data[..4]))
	if column_count != codec.table.columns.len {
		return error('typed row payload column count mismatch')
	}
	mut cursor := 4
	for current in codec.table.columns {
		if cursor + 5 > data.len {
			return error('typed row payload truncated')
		}
		present := data[cursor]
		cursor++
		value_len := int(read_u32_le(data[cursor..cursor + 4]))
		cursor += 4
		if current.name == name {
			if present == 0 {
				if current.nullable {
					return error('column ${name} is null')
				}
				return error('required column missing from payload: ${name}')
			}
			if cursor + value_len > data.len {
				return error('typed row payload value overflow')
			}
			value := TypedValueEncoder.decode_value(data[cursor..cursor + value_len],
				current.typ)!
			match value {
				i64 { return value }
				else { return error('column ${name} did not decode as i64') }
			}
		}
		if present != 0 && cursor + value_len > data.len {
			return error('typed row payload value overflow')
		}
		cursor += value_len
	}
	return error('column not found in payload: ${name}')
}

pub fn TypedValueEncoder.validate(column ColumnDef, value ColumnValue) ! {
	if value is NullValue {
		if !column.nullable {
			return error('column is not nullable: ${column.name}')
		}
		return
	}
	match column.typ {
		.bool_ {
			if value !is bool {
				return error('column ${column.name} expects bool')
			}
		}
		.i64_ {
			if value !is i64 {
				return error('column ${column.name} expects i64')
			}
		}
		.string_ {
			if value !is string {
				return error('column ${column.name} expects string')
			}
		}
		.bytes_ {
			if value !is []u8 {
				return error('column ${column.name} expects bytes')
			}
		}
		.enum_ {
			if value !is string {
				return error('column ${column.name} expects enum string')
			}
			enum_value := value as string
			if enum_value !in column.enum_values {
				return error('column ${column.name} expects one of ${column.enum_values.join('|')}')
			}
		}
		.json_ {
			if value !is string {
				return error('column ${column.name} expects json string')
			}
			json_text := value as string
			json2.decode[json2.Any](json_text)!
		}
		.datetime_ {
			if value !is string {
				return error('column ${column.name} expects datetime string')
			}
			time.parse_rfc3339(value as string)!
		}
		.markdown_ {
			if value !is MarkdownRef {
				return error('column ${column.name} expects MarkdownRef')
			}
			markdown := value as MarkdownRef
			if markdown.doc_root_id.len == 0 {
				return error('column ${column.name} requires markdown doc_root_id')
			}
			if markdown.source_hash.len == 0 {
				return error('column ${column.name} requires markdown source_hash')
			}
			if markdown.source_len < 0 {
				return error('column ${column.name} requires non-negative markdown source_len')
			}
			if markdown.version == 0 {
				return error('column ${column.name} requires markdown version')
			}
			if markdown.ast_version == 0 {
				return error('column ${column.name} requires markdown ast_version')
			}
		}
	}
}

pub fn TypedValueEncoder.encode_value(value ColumnValue, typ ColumnType) ![]u8 {
	match typ {
		.bool_ {
			if value is bool {
				encoded := if value { u8(1) } else { u8(0) }
				return [encoded]
			}
		}
		.i64_ {
			if value is i64 {
				mut out := []u8{len: 8}
				mut sortable := u64(value) ^ u64(0x8000000000000000)
				for idx := 7; idx >= 0; idx-- {
					out[idx] = u8(sortable & 0xff)
					sortable >>= 8
				}
				return out
			}
		}
		.string_ {
			if value is string {
				return value.bytes()
			}
		}
		.enum_, .json_, .datetime_ {
			if value is string {
				return value.bytes()
			}
		}
		.bytes_ {
			if value is []u8 {
				return value.clone()
			}
		}
		.markdown_ {
			if value is MarkdownRef {
				return value.encode()
			}
		}
	}
	return error('value does not match requested column type: type=${typ} value_type=${typeof(value).name}')
}

pub fn TypedValueEncoder.decode_value(data []u8, typ ColumnType) !ColumnValue {
	match typ {
		.bool_ {
			if data.len != 1 {
				return error('bool payload must be 1 byte')
			}
			return match data[0] {
				u8(0) { ColumnValue(false) }
				u8(1) { ColumnValue(true) }
				else { return error('invalid bool payload') }
			}
		}
		.i64_ {
			if data.len != 8 {
				return error('i64 payload must be 8 bytes')
			}
			mut sortable := u64(0)
			for b in data {
				sortable = (sortable << 8) | u64(b)
			}
			return ColumnValue(i64(sortable ^ u64(0x8000000000000000)))
		}
		.string_ {
			return ColumnValue(data.bytestr())
		}
		.enum_, .json_, .datetime_ {
			return ColumnValue(data.bytestr())
		}
		.bytes_ {
			return ColumnValue(data.clone())
		}
		.markdown_ {
			return ColumnValue(decode_markdown_ref(data)!)
		}
	}
	return error('unsupported column type')
}

pub fn TypedValueEncoder.encode_index_value(value ColumnValue, column ColumnDef) ![]u8 {
	if value is NullValue {
		if !column.nullable {
			return error('column is not nullable: ${column.name}')
		}
		return [u8(0)]
	}
	TypedValueEncoder.validate(column, value)!
	return encode_index_value_without_validation(value, column)
}

fn encode_index_value_without_validation(value ColumnValue, column ColumnDef) ![]u8 {
	if value is NullValue {
		return [u8(0)]
	}
	match column.typ {
		.bool_ {
			if value is bool {
				return [u8(1), if value {
					u8(1)
				} else {
					u8(0)
				}]
			}
		}
		.i64_ {
			if value is i64 {
				sortable := u64(value) ^ u64(0x8000000000000000)
				return [
					u8(1),
					u8((sortable >> 56) & 0xff),
					u8((sortable >> 48) & 0xff),
					u8((sortable >> 40) & 0xff),
					u8((sortable >> 32) & 0xff),
					u8((sortable >> 24) & 0xff),
					u8((sortable >> 16) & 0xff),
					u8((sortable >> 8) & 0xff),
					u8(sortable & 0xff),
				]
			}
		}
		.string_, .enum_, .json_, .datetime_ {
			if value is string {
				mut out := []u8{cap: value.len + 1}
				out << u8(1)
				out << value.bytes()
				return out
			}
		}
		.bytes_ {
			if value is []u8 {
				mut out := []u8{cap: value.len + 1}
				out << u8(1)
				out << value
				return out
			}
		}
		.markdown_ {
			if value is MarkdownRef {
				encoded := value.encode()
				mut out := []u8{cap: encoded.len + 1}
				out << u8(1)
				out << encoded
				return out
			}
		}
	}
	mut out := [u8(1)]
	out << (TypedValueEncoder.encode_value(value, column.typ)!)
	return out
}

fn build_index_entry_key_string_for_value(prefix string, value ColumnValue, column ColumnDef, primary_key string) !string {
	if column.typ in [.string_, .enum_, .json_, .datetime_] {
		if value is string {
			return prefix + [u8(1)].bytestr() + value + '|' + primary_key
		}
	}
	encoded := encode_index_value_without_validation(value, column)!
	return build_index_entry_key_string(prefix, encoded, primary_key)
}

pub fn TypedValueEncoder.encode_index_prefix(value ColumnValue, column ColumnDef) ![]u8 {
	match column.typ {
		.string_, .bytes_, .enum_, .datetime_ {}
		else {
			return error('index prefix scans only support string, bytes, enum, or datetime columns')
		}
	}
	if value is NullValue {
		return error('index prefix scans do not support null prefixes')
	}
	TypedValueEncoder.validate(column, value)!
	mut out := []u8{cap: 1}
	out << u8(1)
	match value {
		string {
			out << value.bytes()
		}
		[]u8 {
			out << value
		}
		else {
			return error('index prefix scans only support string or bytes values')
		}
	}
	return out
}

fn clone_column_value(value ColumnValue) ColumnValue {
	return match value {
		MarkdownRef { value }
		NullValue { NullValue{} }
		bool { value }
		i64 { value }
		string { value }
		[]u8 { value.clone() }
	}
}

fn column_values_equal(left ColumnValue, right ColumnValue) bool {
	return match left {
		MarkdownRef { right is MarkdownRef && left == right }
		NullValue { right is NullValue }
		bool { right is bool && left == right }
		i64 { right is i64 && left == right }
		string { right is string && left == right }
		[]u8 { right is []u8 && left == right }
	}
}

pub fn (ref MarkdownRef) encode() []u8 {
	mut out := ByteWriter{}
	doc_root_id := ref.doc_root_id.bytes()
	source_hash := ref.source_hash.bytes()
	out.write_u8(ref.version)
	out.write_u16(u16(doc_root_id.len))
	out.write_bytes(doc_root_id)
	out.write_u16(u16(source_hash.len))
	out.write_bytes(source_hash)
	out.write_u32(u32(ref.source_len & 0xffffffff))
	out.write_u32(u32((u64(ref.source_len) >> 32) & 0xffffffff))
	out.write_u8(ref.ast_version)
	out.write_u32(ref.parse_flags)
	return out.bytes()
}

pub fn decode_markdown_ref(data []u8) !MarkdownRef {
	if data.len < 18 {
		return error('markdown ref payload too short')
	}
	mut cursor := 0
	version := data[cursor]
	cursor++
	if cursor + 2 > data.len {
		return error('markdown ref missing doc_root_id length')
	}
	doc_root_len := int(markdown_read_u16_le(data[cursor..cursor + 2]))
	cursor += 2
	if cursor + doc_root_len > data.len {
		return error('markdown ref doc_root_id overflow')
	}
	doc_root_id := data[cursor..cursor + doc_root_len].bytestr()
	cursor += doc_root_len
	if cursor + 2 > data.len {
		return error('markdown ref missing source_hash length')
	}
	source_hash_len := int(markdown_read_u16_le(data[cursor..cursor + 2]))
	cursor += 2
	if cursor + source_hash_len > data.len {
		return error('markdown ref source_hash overflow')
	}
	source_hash := data[cursor..cursor + source_hash_len].bytestr()
	cursor += source_hash_len
	if cursor + 4 > data.len {
		return error('markdown ref missing source_len low bits')
	}
	low := u64(read_u32_le(data[cursor..cursor + 4]))
	cursor += 4
	if cursor + 4 > data.len {
		return error('markdown ref missing source_len high bits')
	}
	high := u64(read_u32_le(data[cursor..cursor + 4]))
	cursor += 4
	source_len := i64(low | (high << 32))
	if cursor + 1 > data.len {
		return error('markdown ref missing ast_version')
	}
	ast_version := data[cursor]
	cursor++
	if cursor + 4 > data.len {
		return error('markdown ref missing parse_flags')
	}
	parse_flags := read_u32_le(data[cursor..cursor + 4])
	cursor += 4
	if cursor != data.len {
		return error('markdown ref trailing bytes')
	}
	return MarkdownRef{
		version:     version
		doc_root_id: doc_root_id
		source_hash: source_hash
		source_len:  source_len
		ast_version: ast_version
		parse_flags: parse_flags
	}
}

fn markdown_read_u16_le(data []u8) u16 {
	return u16(data[0]) | (u16(data[1]) << 8)
}
