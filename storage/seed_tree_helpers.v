module storage

pub fn build_single_row_seed_tree(spec TypedTableSpec, primary_key []u8, row TypedRowData, cfg ChunkConfig) !Tree {
	codec := TypedRowCodec.new(spec.table)
	table_view := TableView.new(Tree{}, spec.table.name)
	mut tree := Tree.build([
		KVPair{
			key: table_view.key_for(primary_key)
			value: codec.encode(row)!
		},
	], cfg)!
	tree = rebuild_typed_indexes_for_specs(tree, [spec], cfg)!
	return tree
}
