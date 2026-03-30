module storage

import os

fn test_snapshot_persist_stores_tree_and_commit() {
	cfg := ChunkConfig.default()
	tree := Tree.build([
		KVPair{key: 'id:1'.bytes(), value: 'hello'.bytes()},
		KVPair{key: 'id:2'.bytes(), value: 'world'.bytes()},
	], cfg) or { panic(err) }
	snapshot := Snapshot.new(tree, []string{}, CommitMeta{
		author: 'gwg'
		message: 'initial import'
		timestamp: 1
	})
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()

	snapshot.persist(mut node_store, mut commit_store) or { panic(err) }

	assert node_store.has(tree.root.cid)
	assert commit_store.has(snapshot.commit.cid)
	stored := commit_store.get(snapshot.commit.cid) or { panic(err) }
	assert stored.root_cid == tree.root.cid
	assert stored.is_root()
}

fn test_commit_lineage_tracks_parent_chain() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}
	tree1 := Tree.build(items, cfg) or { panic(err) }
	commit1 := Snapshot.new(tree1, []string{}, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}).commit

	tree2 := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'value-05-updated'.bytes()
	}, cfg) or { panic(err) }
	commit2 := Snapshot.new(tree2, [commit1.cid], CommitMeta{
		author: 'gwg'
		message: 'update key-05'
		timestamp: 2
	}).commit

	tree3 := tree2.delete('key-08'.bytes(), cfg) or { panic(err) }
	commit3 := Snapshot.new(tree3, [commit2.cid], CommitMeta{
		author: 'gwg'
		message: 'delete key-08'
		timestamp: 3
	}).commit

	mut store := MemoryCommitStore.new()
	store.put(commit1) or { panic(err) }
	store.put(commit2) or { panic(err) }
	store.put(commit3) or { panic(err) }

	lineage := store.lineage(commit3.cid) or { panic(err) }
	assert lineage.len == 3
	assert lineage[0].cid == commit3.cid
	assert lineage[1].cid == commit2.cid
	assert lineage[2].cid == commit1.cid
	assert !lineage[0].is_root()
	assert lineage[2].is_root()
}

fn test_memory_commit_store_latest_uses_timestamp_order() {
	mut store := MemoryCommitStore.new()
	commit1 := Commit.new('root-a', []string{}, CommitMeta{
		author: 'gwg'
		message: 'a'
		timestamp: 10
	})
	commit2 := Commit.new('root-b', [commit1.cid], CommitMeta{
		author: 'gwg'
		message: 'b'
		timestamp: 20
	})
	store.put(commit1) or { panic(err) }
	store.put(commit2) or { panic(err) }

	latest := store.latest() or { panic(err) }
	assert latest.cid == commit2.cid
}

fn test_persistent_commit_store_put_and_get() {
	path := os.join_path(os.vtmp_dir(), 'pollytree-persistent-commit-store.bin')
	defer {
		os.rm(path) or {}
	}
	mut store := PersistentCommitStore.open_high_throughput(path) or { panic(err) }
	defer {
		store.close()
	}
	commit := Commit.new('root-a', ['parent-a', 'parent-b'], CommitMeta{
		author: 'gwg'
		message: 'persist'
		timestamp: 42
	})

	store.put(commit) or { panic(err) }
	assert store.has(commit.cid)
	loaded := store.get(commit.cid) or { panic(err) }
	assert loaded.cid == commit.cid
	assert loaded.root_cid == commit.root_cid
	assert loaded.parent_cids == commit.parent_cids
	assert loaded.meta.author == commit.meta.author
	assert loaded.meta.message == commit.meta.message
	assert loaded.meta.timestamp == commit.meta.timestamp
}

fn test_commit_roundtrip_preserves_virtual_roots() {
	commit := Commit.new_with_virtual_roots('root-a', ['parent-a'], CommitMeta{
		author: 'gwg'
		message: 'persist virtual roots'
		timestamp: 43
	}, [
		VirtualRootRef{
			name: 'sum(metrics.id)'
			root_cid: 'virtual-root-a'
			source_data_root_cid: 'root-a'
			fresh: true
		},
		VirtualRootRef{
			name: 'sum(events.payload.amount)'
			root_cid: 'virtual-root-b'
			source_data_root_cid: 'root-prev'
			fresh: false
		},
	])

	loaded := Commit.from_data(commit.data()) or { panic(err) }
	assert loaded.cid == commit.cid
	assert loaded.virtual_roots.len == 2
	assert loaded.virtual_roots[0].name == 'sum(metrics.id)'
	assert loaded.virtual_roots[0].root_cid == 'virtual-root-a'
	assert loaded.virtual_roots[0].source_data_root_cid == 'root-a'
	assert loaded.virtual_roots[0].fresh
	assert loaded.virtual_roots[1].name == 'sum(events.payload.amount)'
	assert !loaded.virtual_roots[1].fresh
}
