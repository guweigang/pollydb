module storage

pub struct TableSpec {
pub:
	name    string
	codec   RowCodec
	indexes []SchemaIndexDef
}

pub struct WriteOp {
pub:
	table_name  string
	primary_key []u8
	mutation    SchemaMutation
}

pub struct WriteSet {
mut:
	ops []WriteOp
}

pub struct Transaction {
mut:
	tree  Tree
	specs map[string]TableSpec
}

pub struct TransactionResult {
pub:
	tx   Transaction
	diff TreeDiff
}

pub struct WorkingSet {
pub:
	branch_name string
mut:
	base_commit_cid string
	base_tree       Tree
	tx              Transaction
	specs           []TableSpec
}

pub enum KeyChangeKind {
	added
	modified
	deleted
}

pub struct KeyChangeSummary {
pub:
	kind      KeyChangeKind
	key        []u8
	index_name string
}

pub struct TableChangeSummary {
pub:
	table_name         string
	row_changes        []KeyChangeSummary
	index_entry_changes []KeyChangeSummary
}

pub struct WorkingSetStatus {
pub:
	branch_name string
	has_changes bool
	tables      []TableChangeSummary
}

pub fn TableSpec.new(name string, codec RowCodec, indexes []SchemaIndexDef) !TableSpec {
	if name.len == 0 {
		return error('table spec name cannot be empty')
	}
	return TableSpec{
		name: name
		codec: codec
		indexes: indexes.clone()
	}
}

pub fn WriteSet.new() WriteSet {
	return WriteSet{
		ops: []WriteOp{}
	}
}

pub fn (mut set WriteSet) put(table_name string, primary_key []u8, row RowData) {
	set.ops << WriteOp{
		table_name: table_name
		primary_key: primary_key.clone()
		mutation: SchemaMutation.put(primary_key, row)
	}
}

pub fn (mut set WriteSet) delete(table_name string, primary_key []u8) {
	set.ops << WriteOp{
		table_name: table_name
		primary_key: primary_key.clone()
		mutation: SchemaMutation.delete(primary_key)
	}
}

pub fn (set WriteSet) len() int {
	return set.ops.len
}

pub fn (set WriteSet) operations() []WriteOp {
	return set.ops.clone()
}

pub fn Transaction.new(tree Tree) Transaction {
	return Transaction{
		tree: tree
		specs: map[string]TableSpec{}
	}
}

fn new_transaction_with_specs(tree Tree, specs []TableSpec) !Transaction {
	mut tx := Transaction.new(tree)
	for spec in specs {
		tx.register_table(spec)!
	}
	return tx
}

pub fn (mut tx Transaction) register_table(spec TableSpec) ! {
	if spec.name in tx.specs {
		return error('table already registered: ${spec.name}')
	}
	tx.specs[spec.name] = spec
}

pub fn (tx Transaction) has_table(name string) bool {
	return name in tx.specs
}

pub fn (tx Transaction) current_tree() Tree {
	return tx.tree
}

pub fn (tx Transaction) indexed_view(name string) !IndexedSchemaView {
	spec := tx.specs[name] or {
		return error('table not registered: ${name}')
	}
	table := TableView.new(tx.tree, spec.name)
	schema := SchemaView.new(table, spec.codec)
	return IndexedSchemaView.new(schema, spec.indexes)
}

pub fn (tx Transaction) apply_write_set(write_set WriteSet, cfg ChunkConfig) !TransactionResult {
	if write_set.len() == 0 {
		return TransactionResult{
			tx: tx
			diff: tx.tree.diff(tx.tree)
		}
	}
	mut next_tx := Transaction{
		tree: tx.tree
		specs: tx.specs.clone()
	}
	mut grouped := map[string][]SchemaMutation{}
	mut order := []string{}
	for op in write_set.operations() {
		if op.table_name !in next_tx.specs {
			return error('table not registered: ${op.table_name}')
		}
		if op.table_name !in grouped {
			grouped[op.table_name] = []SchemaMutation{}
			order << op.table_name
		}
		grouped[op.table_name] << op.mutation
	}
	for table_name in order {
		mut view := next_tx.indexed_view(table_name)!
		update := view.apply_mutations(grouped[table_name], cfg)!
		next_tx.tree = update.view.schema.table.tree
	}
	return TransactionResult{
		tx: next_tx
		diff: tx.tree.diff(next_tx.tree)
	}
}

pub fn WorkingSet.new(branch_name string, base_commit_cid string, tree Tree, specs []TableSpec) !WorkingSet {
	return WorkingSet{
		branch_name: branch_name
		base_commit_cid: base_commit_cid
		base_tree: tree
		tx: new_transaction_with_specs(tree, specs)!
		specs: specs.clone()
	}
}

pub fn (set WorkingSet) has_changes() bool {
	return set.base_tree.root.cid != set.tx.current_tree().root.cid
}

pub fn (set WorkingSet) staged_diff() TreeDiff {
	return set.base_tree.diff(set.tx.current_tree())
}

pub fn (set WorkingSet) transaction() Transaction {
	return set.tx
}

pub fn (set WorkingSet) status() !WorkingSetStatus {
	return build_working_set_status(set.branch_name, set.specs, set.base_tree, set.tx.current_tree())
}

pub fn (mut set WorkingSet) apply_write_set(write_set WriteSet, cfg ChunkConfig) !TransactionResult {
	result := set.tx.apply_write_set(write_set, cfg)!
	set.tx = result.tx
	return result
}

pub fn (mut set WorkingSet) reset() ! {
	set.tx = new_transaction_with_specs(set.base_tree, set.specs)!
}

pub fn (mut set WorkingSet) replace_working_tree(tree Tree) ! {
	set.tx = new_transaction_with_specs(tree, set.specs)!
}

pub fn (mut set WorkingSet) sync_to_tree(tree Tree, commit_cid string) ! {
	set.base_tree = tree
	set.base_commit_cid = commit_cid
	set.tx = new_transaction_with_specs(tree, set.specs)!
}

fn build_working_set_status(branch_name string, specs []TableSpec, base_tree Tree, current_tree Tree) !WorkingSetStatus {
	base_items := base_tree.items()!
	current_items := current_tree.items()!
	mut base_map := map[string][]u8{}
	mut current_map := map[string][]u8{}
	for item in base_items {
		base_map[item.key.bytestr()] = item.value.clone()
	}
	for item in current_items {
		current_map[item.key.bytestr()] = item.value.clone()
	}
	mut table_summaries := []TableChangeSummary{}
	for spec in specs {
		summary := summarize_table_changes(spec, base_map, current_map)
		if summary.row_changes.len > 0 || summary.index_entry_changes.len > 0 {
			table_summaries << summary
		}
	}
	return WorkingSetStatus{
		branch_name: branch_name
		has_changes: table_summaries.len > 0
		tables: table_summaries
	}
}

fn summarize_table_changes(spec TableSpec, base_map map[string][]u8, current_map map[string][]u8) TableChangeSummary {
	table_view := TableView.new(Tree{}, spec.name)
	row_prefix := table_view.row_prefix().bytestr()
	mut row_changes := []KeyChangeSummary{}
	row_changes << collect_prefixed_changes(row_prefix, '', base_map, current_map)

	mut index_changes := []KeyChangeSummary{}
	for index in spec.indexes {
		index_view := IndexView.new(Tree{}, spec.name, index.name)
		index_changes << collect_prefixed_changes(index_view.entry_prefix().bytestr(), index.name, base_map, current_map)
	}

	return TableChangeSummary{
		table_name: spec.name
		row_changes: row_changes
		index_entry_changes: index_changes
	}
}

fn collect_prefixed_changes(prefix string, index_name string, base_map map[string][]u8, current_map map[string][]u8) []KeyChangeSummary {
	mut keys := map[string]bool{}
	for key in base_map.keys() {
		if key.starts_with(prefix) {
			keys[key] = true
		}
	}
	for key in current_map.keys() {
		if key.starts_with(prefix) {
			keys[key] = true
		}
	}
	mut sorted_keys := keys.keys()
	sorted_keys.sort()
	mut changes := []KeyChangeSummary{}
	for key in sorted_keys {
		in_base := key in base_map
		in_current := key in current_map
		if in_base && in_current && base_map[key] == current_map[key] {
			continue
		}
		kind := if !in_base && in_current {
			KeyChangeKind.added
		} else if in_base && !in_current {
			KeyChangeKind.deleted
		} else {
			KeyChangeKind.modified
		}
		changes << KeyChangeSummary{
			kind: kind
			key: key.bytes()
			index_name: index_name
		}
	}
	return changes
}
