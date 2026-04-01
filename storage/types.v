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
	name     string
	typ      ColumnType
	nullable bool
	aggregate ColumnAggregate
	enum_values []string
	default_current_timestamp bool
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
	schema  TypedSchemaView
	indexes []SchemaIndexDef
}

pub struct TypedIndexedSchemaUpdate {
pub:
	view TypedIndexedSchemaView
	diff TreeDiff
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
	tx   TypedTransaction
	diff TreeDiff
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

struct FastLeafUpdateGroup {
mut:
	anchor_key []u8
	row_keys   []string
}

struct FastWriteOpResult {
	view         TypedIndexedSchemaView
	remaining_ops []TypedWriteOp
}

struct TypedAggregateDelta {
mut:
	total         i64
	bucket_deltas map[u8]i64
}

pub struct ReindexStageTimings {
pub:
	items_ms        i64
	remove_ms       i64
	insert_ms       i64
	rebuild_ms      i64
	strategy        string
	item_count      int
	changed_tables  int
	changed_rows    int
	removed_indexes int
	inserted_indexes int
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
		name: name
		typ: typ
		nullable: nullable
		aggregate: aggregate
		enum_values: []string{}
		default_current_timestamp: default_current_timestamp
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
		name: name
		typ: .enum_
		nullable: nullable
		aggregate: .none
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
		name: name
		columns: columns.clone()
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
	column := def.column(name) or {
		return false
	}
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
	value := row.values[name] or {
		return error('typed row field not found: ${name}')
	}
	return clone_column_value(value)
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
		data: view.codec.decode(row.value)!
	}
}

pub fn TypedIndexedSchemaView.new(schema TypedSchemaView, indexes []SchemaIndexDef) !TypedIndexedSchemaView {
	for index in indexes {
		if !schema.codec.table.has_column(index.column) {
			return error('typed schema index column not in table: ${index.column}')
		}
		if index.is_json_path() {
			column := schema.codec.table.column(index.column)!
			if column.typ != .json_ {
				return error('typed schema json-path index requires json column: ${index.column}')
			}
		} else if index.is_field_selector() {
			column := schema.codec.table.column(index.column)!
			validate_field_selector_index(column, index)!
		}
	}
	return TypedIndexedSchemaView{
		schema: schema
		indexes: indexes.clone()
	}
}

pub fn (view TypedIndexedSchemaView) with_schema(schema TypedSchemaView) TypedIndexedSchemaView {
	return TypedIndexedSchemaView{
		schema: schema
		indexes: view.indexes.clone()
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
		} else if index.is_field_selector() {
			column := table.column(index.column)!
			validate_field_selector_index(column, index)!
		}
	}
	return TypedTableSpec{
		table: table
		indexes: indexes.clone()
	}
}

pub fn (spec TypedTableSpec) name() string {
	return spec.table.name
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
		table_name: table_name
		primary_key: primary_key.clone()
		row: row.clone()
		delete: false
	}
}

pub fn (mut set TypedWriteSet) delete(table_name string, primary_key []u8) {
	set.ops << TypedWriteOp{
		table_name: table_name
		primary_key: primary_key.clone()
		row: TypedRowData.new()
		delete: true
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
		tree: tree
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

pub fn (mut tx TypedTransaction) register_table(spec TypedTableSpec) ! {
	if spec.name() in tx.specs {
		return error('typed table already registered: ${spec.name()}')
	}
	tx.specs[spec.name()] = spec
}

pub fn (tx TypedTransaction) current_tree() Tree {
	return tx.tree
}

pub fn (tx TypedTransaction) indexed_view(name string) !TypedIndexedSchemaView {
	spec := tx.specs[name] or {
		return error('typed table not registered: ${name}')
	}
	table := TableView.new(tx.tree, spec.table.name)
	schema := TypedSchemaView.new(table, TypedRowCodec.new(spec.table))
	return TypedIndexedSchemaView.new(schema, spec.indexes)
}

pub fn (tx TypedTransaction) apply_write_set(write_set TypedWriteSet, cfg ChunkConfig) !TypedTransactionResult {
	if write_set.len() == 0 {
		return TypedTransactionResult{
			tx: tx
			diff: tx.tree.diff(tx.tree)
		}
	}
	mut next_tx := TypedTransaction{
		tree: tx.tree
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
	for table_name in order {
		tree_before := next_tx.tree
		mut view := next_tx.indexed_view(table_name)!
		spec := next_tx.specs[table_name] or { return error('typed table not registered: ${table_name}') }
		aggregate_deltas := typed_aggregate_deltas_for_ops(view, spec, grouped[table_name])!
		fast_update := view.apply_fast_write_ops(grouped[table_name], cfg)!
		view = fast_update.view
		mut fallback_ops := fast_update.remaining_ops.clone()
		if fallback_ops.len > 0 {
			update := view.apply_write_ops(fallback_ops, cfg)!
			view = update.view
		}
		next_tx.tree = apply_typed_aggregate_deltas(tree_before, view.schema.table.tree, spec, aggregate_deltas, cfg)!
	}
	return TypedTransactionResult{
		tx: next_tx
		diff: tx.tree.diff(next_tx.tree)
	}
}

pub fn TypedWorkingSet.new(branch_name string, base_commit_cid string, tree Tree, specs []TypedTableSpec) !TypedWorkingSet {
	return TypedWorkingSet{
		branch_name: branch_name
		base_commit_cid: base_commit_cid
		base_tree: tree
		tx: new_typed_transaction_with_specs(tree, specs)!
		specs: specs.clone()
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
		next_table := view.schema.table.put(primary_key, view.schema.codec.encode(row)!, cfg)!
		return view.with_schema(TypedSchemaView.new(next_table, view.schema.codec))
	}
	update := view.apply_write_ops([
		TypedWriteOp{
			table_name: view.schema.table.name
			primary_key: primary_key.clone()
			row: row.clone()
			delete: false
		},
	], cfg)!
	return update.view
}

pub fn (view TypedIndexedSchemaView) delete(primary_key []u8, cfg ChunkConfig) !TypedIndexedSchemaView {
	update := view.apply_write_ops([
		TypedWriteOp{
			table_name: view.schema.table.name
			primary_key: primary_key.clone()
			row: TypedRowData.new()
			delete: true
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
	index_view := IndexView.new(view.schema.table.tree, view.schema.table.name, name)
	mut cursor := index_view.cursor(encoded, []u8{}, limit)!
	mut rows := []TypedSchemaRow{}
	for {
		if limit > 0 && rows.len >= limit {
			break
		}
		entry := cursor.peek() or {
			break
		}
		if compare_key_bytes(entry.index_key, encoded) != 0 {
			break
		}
		matched := cursor.next() or {
			break
		}
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
	for op in ops {
		if op.delete || !view.can_fast_update(op.primary_key, op.row)! {
			fallback_ops << op
			continue
		}
		table_key := view.schema.table.key_for(op.primary_key)
		path := view.schema.table.tree.path_to_leaf(table_key)!
		leaf := path[path.len - 1].node
		group_id := leaf.cid
		if group_id !in groups {
			groups[group_id] = FastLeafUpdateGroup{
				anchor_key: table_key.clone()
				row_keys: []string{}
			}
			group_order << group_id
		}
		mut group := groups[group_id]
		group.row_keys << op.primary_key.hex()
		groups[group_id] = group
	}
	if group_order.len == 0 {
		return FastWriteOpResult{
			view: view
			remaining_ops: fallback_ops
		}
	}

	mut current_view := view
	for group_id in group_order {
		group := groups[group_id]
		path := current_view.schema.table.tree.path_to_leaf(group.anchor_key)!
		leaf := path[path.len - 1].node
		mut leaf_items := leaf.leaf_items()!
		row_prefix_len := current_view.schema.table.row_prefix().len
		mut op_map := map[string]TypedWriteOp{}
		for op in ops {
			key_id := op.primary_key.hex()
			if key_id in group.row_keys {
				op_map[key_id] = op
			}
		}
		for idx, item in leaf_items {
			key_id := item.key[row_prefix_len..].hex()
			if key_id !in op_map {
				continue
			}
			leaf_items[idx] = KVPair{
				key: item.key.clone()
				value: current_view.schema.codec.encode(op_map[key_id].row)!
			}
		}
		next_tree := current_view.schema.table.tree.replace_leaf_items(group.anchor_key, leaf_items, cfg)!
		current_view = current_view.with_schema(TypedSchemaView.new(TableView.new(next_tree, current_view.schema.table.name),
			current_view.schema.codec))
	}
	return FastWriteOpResult{
		view: current_view
		remaining_ops: fallback_ops
	}
}

pub fn (view TypedIndexedSchemaView) apply_write_ops(ops []TypedWriteOp, cfg ChunkConfig) !TypedIndexedSchemaUpdate {
	mut items := view.schema.table.tree.items()!
	mut row_state := map[string]TypedRowData{}
	mut row_exists := map[string]bool{}
	table_name := view.schema.table.name
	codec := view.schema.codec
	for op in ops {
		key_id := op.primary_key.hex()
		if key_id !in row_exists {
			existing_row := view.schema.get(op.primary_key) or { TypedSchemaRow{} }
			if existing_row.primary_key.len > 0 {
				row_state[key_id] = existing_row.data.clone()
				row_exists[key_id] = true
			} else {
				row_state[key_id] = TypedRowData.new()
				row_exists[key_id] = false
			}
		}
		old_row := row_state[key_id].clone()
		had_old := row_exists[key_id]
		match op.delete {
			false {
				upsert_item(mut items, view.schema.table.key_for(op.primary_key), codec.encode(op.row)!)
				for index in view.indexes {
					column := index.value_column(codec.table)!
					mut old_value := ColumnValue(NullValue{})
					old_has := had_old && old_row.has(index.column)
					if old_has {
						old_value = typed_index_value_from_row(old_row, index, codec.table)!
					}
					mut new_value := ColumnValue(NullValue{})
					new_has := op.row.has(index.column)
					if new_has {
						new_value = typed_index_value_from_row(op.row, index, codec.table)!
					}
					index_view := IndexView.new(view.schema.table.tree, table_name, index.name)
					if old_has && (!new_has || !column_values_equal(old_value, new_value)) {
						delete_item(mut items, index_view.key_for(TypedValueEncoder.encode_index_value(old_value, column)!,
							op.primary_key))
					}
					if new_has && (!old_has || !column_values_equal(old_value, new_value)) {
						index_value := if index.stores_row { codec.encode(op.row)! } else { []u8{} }
						upsert_item(mut items, index_view.key_for(TypedValueEncoder.encode_index_value(new_value,
							column)!, op.primary_key), index_value)
					}
				}
				row_state[key_id] = op.row.clone()
				row_exists[key_id] = true
			}
			true {
				if !had_old {
					continue
				}
				delete_item(mut items, view.schema.table.key_for(op.primary_key))
				for index in view.indexes {
					if !old_row.has(index.column) {
						continue
					}
					column := index.value_column(codec.table)!
					index_value := typed_index_value_from_row(old_row, index, codec.table)!
					index_view := IndexView.new(view.schema.table.tree, table_name, index.name)
					delete_item(mut items, index_view.key_for(TypedValueEncoder.encode_index_value(index_value,
						column)!, op.primary_key))
				}
				row_state[key_id] = TypedRowData.new()
				row_exists[key_id] = false
			}
		}
	}
	if items.len == 0 {
		return error('typed indexed schema batch would produce an empty tree')
	}
	next_tree := Tree.build(items, cfg)!
	if next_tree.root.cid == view.schema.table.tree.root.cid {
		return TypedIndexedSchemaUpdate{
			view: view
			diff: view.schema.table.tree.diff(view.schema.table.tree)
		}
	}
	next_view := view.with_schema(TypedSchemaView.new(TableView.new(next_tree, table_name), codec))
	return TypedIndexedSchemaUpdate{
		view: next_view
		diff: view.schema.table.tree.diff(next_tree)
	}
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
				if !row.has(index.column) {
					continue
				}
				column := index.value_column(spec.table)!
				index_key := TypedValueEncoder.encode_index_value(typed_index_value_from_row(row, index, spec.table)!,
					column)!
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
			key: key.bytes()
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
				key: encode_table_sum_aggregate_key(spec.table.name, column.name)
				value: TypedValueEncoder.encode_value(sums[column.name] or { i64(0) }, .i64_)!
			}, cfg)!
			column_buckets := bucket_sums[column.name] or { []i64{len: 256, init: i64(0)} }
			for bucket := 0; bucket < 256; bucket++ {
				next_tree = next_tree.put(KVPair{
					key: encode_table_sum_bucket_key(spec.table.name, column.name, u8(bucket))
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
		map[string]json2.Any { existing.clone() }
		else { map[string]json2.Any{} }
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
		else { return }
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
	mut current := root[segments[0]] or {
		return NullValue{}
	}
	for idx := 1; idx < segments.len; idx++ {
		segment := segments[idx]
		match current {
			map[string]json2.Any {
				nested := current as map[string]json2.Any
				current = nested[segment] or {
					return NullValue{}
				}
			}
			else {
				return NullValue{}
			}
		}
	}
	return match current {
		json2.Null { ColumnValue(NullValue{}) }
		string { ColumnValue(current as string) }
		bool { ColumnValue(current as bool) }
		i64 { ColumnValue(current as i64) }
		int { ColumnValue(i64(current as int)) }
		i32 { ColumnValue(i64(current as i32)) }
		i16 { ColumnValue(i64(current as i16)) }
		i8 { ColumnValue(i64(current as i8)) }
		u64 { ColumnValue(i64(current as u64)) }
		u32 { ColumnValue(i64(current as u32)) }
		u16 { ColumnValue(i64(current as u16)) }
		u8 { ColumnValue(i64(current as u8)) }
		f64 { ColumnValue(i64(current as f64)) }
		f32 { ColumnValue(i64(current as f32)) }
		else {
			return error('json index only supports nested scalar fields: ${path}')
		}
	}
}

fn json_scalar_value_for_index(raw string, index SchemaIndexDef) !ColumnValue {
	root := json2.decode[map[string]json2.Any](raw)!
	value := json_lookup_path_value(root, index.json_field)!
	return match value {
		NullValue { ColumnValue(NullValue{}) }
		string {
			if index.json_field_type != .string_ && index.json_field_type != .enum_ {
				return error('json field ${index.target_label()} did not match declared type')
			}
			ColumnValue(value)
		}
		bool {
			if index.json_field_type != .bool_ {
				return error('json field ${index.target_label()} did not match declared type')
			}
			ColumnValue(value)
		}
		i64 {
			if index.json_field_type != .i64_ {
				return error('json field ${index.target_label()} did not match declared type')
			}
			ColumnValue(value)
		}
		else {
			return error('json index only supports scalar fields: ${index.target_label()}')
		}
	}
}

fn typed_index_value_from_row(row TypedRowData, index SchemaIndexDef, table TableDef) !ColumnValue {
	if index.is_field_selector() {
		return ColumnValue(i64(0))
	}
	if !index.is_json_path() {
		return row.get(index.column)
	}
	if !row.has(index.column) {
		return NullValue{}
	}
	base_column := table.column(index.column)!
	base_value := row.get(index.column)!
	match base_value {
		NullValue { return NullValue{} }
		string {
			if base_column.typ != .json_ {
				return error('json-path index requires json column: ${index.column}')
			}
			return json_scalar_value_for_index(base_value, index)
		}
		else { return error('json-path index requires json string payload: ${index.column}') }
	}
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
			total: i64(0)
			bucket_deltas: map[u8]i64{}
		}
	}
	for _, op in final_ops {
		bucket := typed_aggregate_bucket(op.primary_key)
		old_row := view.schema.get(op.primary_key) or { TypedSchemaRow{} }
		for column in sum_columns {
			mut delta := deltas[column.name] or {
				TypedAggregateDelta{
					total: i64(0)
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
				total: i64(0)
				bucket_deltas: map[u8]i64{}
			}
		}
		base_sum := current_typed_aggregate_sum(tree_before, spec, column)!
		next_tree = next_tree.put(KVPair{
			key: encode_table_sum_aggregate_key(spec.table.name, column.name)
			value: TypedValueEncoder.encode_value(base_sum + delta.total, .i64_)!
		}, cfg)!
		for bucket, bucket_delta in delta.bucket_deltas {
			base_bucket_sum := current_typed_aggregate_bucket_sum(tree_before, spec, column, bucket)!
			next_tree = next_tree.put(KVPair{
				key: encode_table_sum_bucket_key(spec.table.name, column.name, bucket)
				value: TypedValueEncoder.encode_value(base_bucket_sum + bucket_delta, .i64_)!
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
		changed := (changed_rows[spec.table.name] or { map[string][]u8{} }).clone()
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
					key: key_bytes
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
		changed := (changed_rows[spec.table.name] or { map[string][]u8{} }).clone()
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
			for index in spec.indexes {
				if !row.has(index.column) {
					continue
				}
				column := index.value_column(spec.table)!
				index_key := TypedValueEncoder.encode_index_value(typed_index_value_from_row(row, index, spec.table)!,
					column)!
				index_view := IndexView.new(Tree{}, spec.table.name, index.name)
				index_entry_key := index_view.key_for(index_key, primary_key)
				index_value := if index.stores_row { codec.encode(row)! } else { []u8{} }
				item_map[index_entry_key.bytestr()] = index_value.clone()
				mutations << Mutation.put(index_entry_key, index_value)
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
				key: key.bytes()
				value: item_map[key].clone()
			}
		}
		Tree.build(rebuilt, cfg)!
	}
	rebuild_ms := rebuild_sw.elapsed().milliseconds()
	return rebuilt_tree, ReindexStageTimings{
		items_ms: items_ms
		remove_ms: remove_ms
		insert_ms: insert_ms
		rebuild_ms: rebuild_ms
		strategy: if use_patch_strategy { 'patch' } else { 'build' }
		item_count: items.len
		changed_tables: changed_tables
		changed_rows: changed_row_count
		removed_indexes: removed_indexes
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
	for name, value in row.fields() {
		column := codec.table.column(name)!
		TypedValueEncoder.validate(column, value)!
	}
	mut out := ByteWriter{}
	out.write_u32(u32(codec.table.columns.len))
	for column in codec.table.columns {
		if !row.has(column.name) {
			if column.nullable {
				out.write_u8(0)
				out.write_u32(0)
				continue
			}
			return error('missing required column: ${column.name}')
		}
		value := row.get(column.name)!
		if value is NullValue {
			if !column.nullable {
				return error('column is not nullable: ${column.name}')
			}
			out.write_u8(0)
			out.write_u32(0)
			continue
		}
		TypedValueEncoder.validate(column, value)!
		encoded := TypedValueEncoder.encode_value(value, column.typ)!
		out.write_u8(1)
		out.write_u32(u32(encoded.len))
		out.write_bytes(encoded)
	}
	return out.bytes()
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
			value := TypedValueEncoder.decode_value(data[cursor..cursor + value_len], column.typ)!
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
			value := TypedValueEncoder.decode_value(data[cursor..cursor + value_len], current.typ)!
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
				return error('column ${column.name} expects one of ${column.enum_values.join("|")}')
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
	return error('value does not match requested column type')
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
	mut out := [u8(1)]
	out << (TypedValueEncoder.encode_value(value, column.typ)!)
	return out
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
		version: version
		doc_root_id: doc_root_id
		source_hash: source_hash
		source_len: source_len
		ast_version: ast_version
		parse_flags: parse_flags
	}
}

fn markdown_read_u16_le(data []u8) u16 {
	return u16(data[0]) | (u16(data[1]) << 8)
}
