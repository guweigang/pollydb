module storage

import os

fn test_memory_node_store_put_tree_and_get() {
	items := [
		KVPair{key: 'id:1'.bytes(), value: 'hello'.bytes()},
		KVPair{key: 'id:2'.bytes(), value: 'world'.bytes()},
	]
	tree := Tree.build(items, ChunkConfig.default()) or { panic(err) }
	mut store := MemoryNodeStore.new()

	store.put_tree(tree) or { panic(err) }
	assert store.has(tree.root.cid)

	root := store.get(tree.root.cid) or { panic(err) }
	assert root.cid == tree.root.cid
	assert root.item_count == 2
}

fn test_persistent_node_store_put_tree_and_load() {
	items := [
		KVPair{key: 'id:1'.bytes(), value: 'hello'.bytes()},
		KVPair{key: 'id:2'.bytes(), value: 'world'.bytes()},
		KVPair{key: 'id:3'.bytes(), value: 'again'.bytes()},
	]
	tree := Tree.build(items, ChunkConfig.default()) or { panic(err) }
	path := os.join_path(os.vtmp_dir(), 'pollytree-persistent-node-store.bin')
	defer {
		os.rm(path) or {}
	}
	mut store := PersistentNodeStore.open_high_throughput(path) or { panic(err) }
	defer {
		store.close()
	}

	store.put_tree(tree) or { panic(err) }
	assert store.has(tree.root.cid)
	root := store.get(tree.root.cid) or { panic(err) }
	assert root.cid == tree.root.cid
	assert root.item_count == tree.root.item_count

	loaded := Tree.load(tree.root.cid, mut store) or { panic(err) }
	loaded_items := loaded.items() or { panic(err) }
	assert loaded.root.cid == tree.root.cid
	assert loaded_items.len == items.len
	for idx in 0 .. items.len {
		assert loaded_items[idx].key == items[idx].key
		assert loaded_items[idx].value == items[idx].value
	}
}
