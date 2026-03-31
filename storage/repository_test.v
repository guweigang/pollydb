module storage

import os

fn repository_fixture_tree(cfg ChunkConfig) !Tree {
	mut items := []KVPair{}
	for idx in 0 .. 12 {
		items << KVPair{
			key: 'key-${idx:02}'.bytes()
			value: 'value-${idx:02}-payload'.bytes()
		}
	}
	return Tree.build(items, cfg)
}

fn repository_commit_fixture(mut repo Repository, branch_name string, tree Tree, timestamp i64, message string, mut node_store MemoryNodeStore, mut commit_store MemoryCommitStore) !BranchUpdate {
	return repo.commit_to_branch(branch_name, tree, CommitMeta{
		author: 'gwg'
		message: message
		timestamp: timestamp
	}, mut node_store, mut commit_store)
}

fn test_repository_commit_to_new_branch_persists_snapshot_and_head() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()

	update := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	assert repo.has_branch('main')
	assert update.branch.name == 'main'
	assert update.branch.commit_cid == update.snapshot.commit.cid
	assert node_store.has(tree.root.cid)
	assert commit_store.has(update.snapshot.commit.cid)
	head := repo.head() or { panic(err) }
	assert head.commit_cid == update.snapshot.commit.cid
}

fn test_repository_create_branch_from_existing_commit() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	main_update := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	feature := repo.create_branch('feature/login', main_update.snapshot.commit.cid) or { panic(err) }

	assert feature.commit_cid == main_update.snapshot.commit.cid
	assert repo.branch_names() == ['feature/login', 'main']
}

fn test_repository_commit_to_existing_branch_uses_parent_head() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree1 := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	first := repo.commit_to_branch('main', tree1, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	tree2 := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'value-05-updated'.bytes()
	}, cfg) or { panic(err) }
	second := repo.commit_to_branch('main', tree2, CommitMeta{
		author: 'gwg'
		message: 'update'
		timestamp: 2
	}, mut node_store, mut commit_store) or { panic(err) }

	assert second.snapshot.commit.parent_cids == [first.snapshot.commit.cid]
	checked_out := repo.checkout('main', mut commit_store) or { panic(err) }
	assert checked_out.cid == second.snapshot.commit.cid
}

fn test_repository_tree_at_branch_loads_reachable_tree() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	update := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	loaded := repo.tree_at_branch('main', mut node_store, mut commit_store) or { panic(err) }

	assert loaded.root.cid == update.snapshot.tree.root.cid
	assert loaded.reachable_cids() or { panic(err) } == update.snapshot.tree.reachable_cids() or { panic(err) }
}

fn test_repository_apply_mutations_to_branch_advances_head_and_returns_diff() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	first := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	result := repo.apply_mutations_to_branch('main', [
		Mutation.put('key-05'.bytes(), 'value-05-updated'.bytes()),
		Mutation.delete('key-08'.bytes()),
	], cfg, CommitMeta{
		author: 'gwg'
		message: 'apply mutations'
		timestamp: 2
	}, mut node_store, mut commit_store) or { panic(err) }

	assert result.update.snapshot.commit.parent_cids == [first.snapshot.commit.cid]
	assert result.tree_update.diff.old_root_cid == first.snapshot.tree.root.cid
	assert result.tree_update.diff.new_root_cid == result.update.snapshot.tree.root.cid
	assert result.tree_update.diff.added_cids.len > 0

	head := repo.head() or { panic(err) }
	assert head.commit_cid == result.update.snapshot.commit.cid

	loaded := repo.tree_at_branch('main', mut node_store, mut commit_store) or { panic(err) }
	assert loaded.root.cid == result.update.snapshot.tree.root.cid
}

fn test_repository_transaction_at_branch_rehydrates_registered_tables() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	user_codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut seed := RowData.new()
	seed.set('name', 'ada'.bytes())
	seed.set('email', 'ada@example.com'.bytes())
	tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: user_codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	_ = repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	tx := repo.transaction_at_branch('main', [
		TableSpec.new('users', user_codec, [
			SchemaIndexDef.new('email', 'email') or { panic(err) },
		]) or { panic(err) },
	], mut node_store, mut commit_store) or { panic(err) }
	view := tx.indexed_view('users') or { panic(err) }
	row := view.get('001'.bytes()) or { panic(err) }

	assert row.primary_key.bytestr() == '001'
	assert (row.data.get('email') or { panic(err) }).bytestr() == 'ada@example.com'
}

fn test_repository_apply_write_set_to_branch_commits_transaction_result() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	user_codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut seed := RowData.new()
	seed.set('name', 'ada'.bytes())
	seed.set('email', 'ada@example.com'.bytes())
	tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: user_codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	first := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	mut writes := WriteSet.new()
	mut second := RowData.new()
	second.set('name', 'grace'.bytes())
	second.set('email', 'grace@example.com'.bytes())
	writes.put('users', '002'.bytes(), second)
	result := repo.apply_write_set_to_branch('main', [
		TableSpec.new('users', user_codec, [
			SchemaIndexDef.new('email', 'email') or { panic(err) },
		]) or { panic(err) },
	], writes, cfg, CommitMeta{
		author: 'gwg'
		message: 'txn commit'
		timestamp: 2
	}, mut node_store, mut commit_store) or { panic(err) }

	assert result.update.snapshot.commit.parent_cids == [first.snapshot.commit.cid]
	assert result.transaction_update.diff.added_cids.len > 0
	head := repo.head() or { panic(err) }
	assert head.commit_cid == result.update.snapshot.commit.cid

	tx := repo.transaction_at_branch('main', [
		TableSpec.new('users', user_codec, [
			SchemaIndexDef.new('email', 'email') or { panic(err) },
		]) or { panic(err) },
	], mut node_store, mut commit_store) or { panic(err) }
	view := tx.indexed_view('users') or { panic(err) }
	rows := view.find_by_index('email', 'grace@example.com'.bytes(), 0) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '002'
}

fn test_repository_apply_typed_write_set_to_branch_commits_typed_rows() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('email', .string_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	spec := TypedTableSpec.new(table_def, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut seed := TypedRowData.new()
	seed.set('id', i64(1))
	seed.set('email', 'ada@example.com')
	tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	first := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	mut writes := TypedWriteSet.new()
	mut row := TypedRowData.new()
	row.set('id', i64(2))
	row.set('email', 'grace@example.com')
	writes.put('users', '002'.bytes(), row)
	result := repo.apply_typed_write_set_to_branch('main', [spec], writes, cfg, CommitMeta{
		author: 'gwg'
		message: 'typed txn'
		timestamp: 2
	}, mut node_store, mut commit_store) or { panic(err) }

	assert result.update.snapshot.commit.parent_cids == [first.snapshot.commit.cid]
	assert result.transaction_update.diff.added_cids.len > 0
	tx := repo.typed_transaction_at_branch('main', [spec], mut node_store, mut commit_store) or { panic(err) }
	view := tx.indexed_view('users') or { panic(err) }
	rows := view.find_by_index('email', 'grace@example.com', 0) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '002'
}

fn test_repository_persistent_stores_roundtrip_branch_tree() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree := repository_fixture_tree(cfg) or { panic(err) }
	node_path := os.join_path(os.vtmp_dir(), 'pollytree-persistent-repo-nodes.bin')
	commit_path := os.join_path(os.vtmp_dir(), 'pollytree-persistent-repo-commits.bin')
	defer {
		os.rm(node_path) or {}
		os.rm(commit_path) or {}
	}
	mut repo := Repository.new('main')
	mut node_store := PersistentNodeStore.open_high_throughput(node_path) or { panic(err) }
	defer {
		node_store.close()
	}
	mut commit_store := PersistentCommitStore.open_high_throughput(commit_path) or { panic(err) }
	defer {
		commit_store.close()
	}

	update := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'persisted init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	assert node_store.has(tree.root.cid)
	assert commit_store.has(update.snapshot.commit.cid)
	loaded := repo.tree_at_branch('main', mut node_store, mut commit_store) or { panic(err) }
	assert loaded.root.cid == tree.root.cid
	assert loaded.items() or { panic(err) } == tree.items() or { panic(err) }
}

fn test_repository_persist_and_open_roundtrip() {
	path := os.join_path(os.vtmp_dir(), 'pollytree-repository-meta.bin')
	defer {
		os.rm(path) or {}
	}
	mut repo := Repository.new('main')
	_ = repo.create_branch('main', 'commit-main') or { panic(err) }
	_ = repo.create_branch('feature', 'commit-feature') or { panic(err) }

	repo.persist(path) or { panic(err) }
	loaded := Repository.open(path) or { panic(err) }

	assert loaded.default_branch == 'main'
	assert loaded.branch_names() == ['feature', 'main']
	assert (loaded.branch('main') or { panic(err) }).commit_cid == 'commit-main'
	assert (loaded.branch('feature') or { panic(err) }).commit_cid == 'commit-feature'
}

fn test_persistent_repository_roundtrip() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree := repository_fixture_tree(cfg) or { panic(err) }
	repo_path := os.join_path(os.vtmp_dir(), 'pollytree-persistent-repository.bin')
	node_path := os.join_path(os.vtmp_dir(), 'pollytree-persistent-repository-nodes.bin')
	commit_path := os.join_path(os.vtmp_dir(), 'pollytree-persistent-repository-commits.bin')
	defer {
		os.rm(repo_path) or {}
		os.rm(node_path) or {}
		os.rm(commit_path) or {}
	}

	mut persistent := PersistentRepository.open(repo_path, node_path, commit_path, 'main') or {
		panic(err)
	}
	update := persistent.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'persistent init'
		timestamp: 1
	}) or { panic(err) }
	persistent.close() or { panic(err) }

	mut reopened := PersistentRepository.open(repo_path, node_path, commit_path, 'main') or {
		panic(err)
	}
	defer {
		reopened.close() or {}
	}
	head := reopened.head() or { panic(err) }
	assert head.commit_cid == update.snapshot.commit.cid
	loaded := reopened.tree_at_branch('main') or { panic(err) }
	assert loaded.root.cid == tree.root.cid
	assert loaded.items() or { panic(err) } == tree.items() or { panic(err) }
}

fn test_persistent_repository_open_default_roundtrip() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree := repository_fixture_tree(cfg) or { panic(err) }
	dir := os.join_path(os.vtmp_dir(), 'pollytree-persistent-repository-default')
	defer {
		os.rmdir_all(dir) or {}
	}

	mut persistent := PersistentRepository.init(dir, 'main') or { panic(err) }
	update := persistent.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'default layout init'
		timestamp: 1
	}) or { panic(err) }
	persistent.close() or { panic(err) }

	mut reopened := PersistentRepository.open_default(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	head := reopened.head() or { panic(err) }
	assert head.commit_cid == update.snapshot.commit.cid
	assert os.exists(os.join_path(dir, '.pollydb', 'repo.meta'))
	assert os.exists(os.join_path(dir, '.pollydb', 'nodes.chunk'))
	assert os.exists(os.join_path(dir, '.pollydb', 'commits.chunk'))
}

fn test_persistent_repository_init_writes_repo_meta_on_close() {
	dir := os.join_path(os.vtmp_dir(), 'pollytree-persistent-repository-init-meta')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut persistent := PersistentRepository.init(dir, 'main') or { panic(err) }
	persistent.close() or { panic(err) }
	assert os.exists(os.join_path(dir, '.pollydb', 'repo.meta'))
}

fn test_repository_working_set_accumulates_uncommitted_changes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	user_codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut seed := RowData.new()
	seed.set('name', 'ada'.bytes())
	seed.set('email', 'ada@example.com'.bytes())
	tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: user_codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	first := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	mut set := repo.working_set_at_branch('main', [
		TableSpec.new('users', user_codec, [
			SchemaIndexDef.new('email', 'email') or { panic(err) },
		]) or { panic(err) },
	], mut node_store, mut commit_store) or { panic(err) }
	mut writes := WriteSet.new()
	mut second := RowData.new()
	second.set('name', 'grace'.bytes())
	second.set('email', 'grace@example.com'.bytes())
	writes.put('users', '002'.bytes(), second)
	_ = set.apply_write_set(writes, cfg) or { panic(err) }

	assert set.base_commit_cid == first.snapshot.commit.cid
	assert set.has_changes()
	assert set.staged_diff().added_cids.len > 0
	view := set.transaction().indexed_view('users') or { panic(err) }
	rows := view.find_by_index('email', 'grace@example.com'.bytes(), 0) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '002'
}

fn test_repository_commit_working_set_advances_head_and_resets_stage() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	user_codec := RowCodec.new(['name', 'email']) or { panic(err) }
	mut seed := RowData.new()
	seed.set('name', 'ada'.bytes())
	seed.set('email', 'ada@example.com'.bytes())
	tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: user_codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	first := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	mut set := repo.working_set_at_branch('main', [
		TableSpec.new('users', user_codec, [
			SchemaIndexDef.new('email', 'email') or { panic(err) },
		]) or { panic(err) },
	], mut node_store, mut commit_store) or { panic(err) }
	mut writes := WriteSet.new()
	mut second := RowData.new()
	second.set('name', 'grace'.bytes())
	second.set('email', 'grace@example.com'.bytes())
	writes.put('users', '002'.bytes(), second)
	_ = set.apply_write_set(writes, cfg) or { panic(err) }

	result := repo.commit_working_set(mut set, CommitMeta{
		author: 'gwg'
		message: 'commit working set'
		timestamp: 2
	}, mut node_store, mut commit_store) or { panic(err) }

	assert result.update.snapshot.commit.parent_cids == [first.snapshot.commit.cid]
	assert result.transaction_update.diff.added_cids.len > 0
	assert !set.has_changes()
	head := repo.head() or { panic(err) }
	assert head.commit_cid == result.update.snapshot.commit.cid
	assert set.base_commit_cid == result.update.snapshot.commit.cid
}

fn test_repository_typed_working_set_accumulates_uncommitted_changes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('email', .string_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	spec := TypedTableSpec.new(table_def, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut seed := TypedRowData.new()
	seed.set('id', i64(1))
	seed.set('email', 'ada@example.com')
	tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	first := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	mut set := repo.typed_working_set_at_branch('main', [spec], mut node_store, mut commit_store) or {
		panic(err)
	}
	mut writes := TypedWriteSet.new()
	mut row := TypedRowData.new()
	row.set('id', i64(2))
	row.set('email', 'grace@example.com')
	writes.put('users', '002'.bytes(), row)
	_ = set.apply_write_set(writes, cfg) or { panic(err) }

	assert set.base_commit_cid == first.snapshot.commit.cid
	assert set.has_changes()
	assert set.staged_diff().added_cids.len > 0
	view := set.transaction().indexed_view('users') or { panic(err) }
	rows := view.find_by_index('email', 'grace@example.com', 0) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '002'
}

fn test_repository_commit_typed_working_set_advances_head_and_resets_stage() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('email', .string_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	spec := TypedTableSpec.new(table_def, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut seed := TypedRowData.new()
	seed.set('id', i64(1))
	seed.set('email', 'ada@example.com')
	tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	first := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	mut set := repo.typed_working_set_at_branch('main', [spec], mut node_store, mut commit_store) or {
		panic(err)
	}
	mut writes := TypedWriteSet.new()
	mut row := TypedRowData.new()
	row.set('id', i64(2))
	row.set('email', 'grace@example.com')
	writes.put('users', '002'.bytes(), row)
	_ = set.apply_write_set(writes, cfg) or { panic(err) }

	result := repo.commit_typed_working_set(mut set, CommitMeta{
		author: 'gwg'
		message: 'commit typed working set'
		timestamp: 2
	}, mut node_store, mut commit_store) or { panic(err) }

	assert result.update.snapshot.commit.parent_cids == [first.snapshot.commit.cid]
	assert result.transaction_update.diff.added_cids.len > 0
	assert !set.has_changes()
	head := repo.head() or { panic(err) }
	assert head.commit_cid == result.update.snapshot.commit.cid
	assert set.base_commit_cid == result.update.snapshot.commit.cid
}

fn test_repository_typed_working_set_status_summarizes_row_and_index_changes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('email', .string_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	spec := TypedTableSpec.new(table_def, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut seed := TypedRowData.new()
	seed.set('id', i64(1))
	seed.set('email', 'ada@example.com')
	tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	_ = repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }

	mut set := repo.typed_working_set_at_branch('main', [spec], mut node_store, mut commit_store) or {
		panic(err)
	}
	mut writes := TypedWriteSet.new()
	mut row := TypedRowData.new()
	row.set('id', i64(2))
	row.set('email', 'grace@example.com')
	writes.put('users', '002'.bytes(), row)
	_ = set.apply_write_set(writes, cfg) or { panic(err) }

	status := set.status() or { panic(err) }
	assert status.branch_name == 'main'
	assert status.has_changes
	assert status.tables.len == 1
	assert status.tables[0].table_name == 'users'
	assert status.tables[0].row_changes.len == 1
	assert status.tables[0].row_changes[0].kind == .added
	assert status.tables[0].index_entry_changes.len == 1
	assert status.tables[0].index_entry_changes[0].kind == .added
	assert status.tables[0].index_entry_changes[0].index_name == 'email'
}

fn test_repository_typed_merge_branch_into_working_set_stages_non_conflicting_merge() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('email', .string_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	spec := TypedTableSpec.new(table_def, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut seed := TypedRowData.new()
	seed.set('id', i64(1))
	seed.set('email', 'ada@example.com')
	tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	base := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }
	repo.create_branch('feature', base.snapshot.commit.cid) or { panic(err) }

	mut feature_row := TypedRowData.new()
	feature_row.set('id', i64(2))
	feature_row.set('email', 'grace@example.com')
	mut feature_writes := TypedWriteSet.new()
	feature_writes.put('users', '002'.bytes(), feature_row)
	_ = repo.apply_typed_write_set_to_branch('feature', [spec], feature_writes, cfg, CommitMeta{
		author: 'gwg'
		message: 'feature typed update'
		timestamp: 2
	}, mut node_store, mut commit_store) or { panic(err) }

	mut set := repo.typed_working_set_at_branch('main', [spec], mut node_store, mut commit_store) or {
		panic(err)
	}
	result := repo.typed_merge_branch_into_working_set(mut set, 'feature', []ConflictResolution{}, cfg,
		mut node_store, mut commit_store) or { panic(err) }

	assert result.merge_result.conflicts.len == 0
	assert set.has_changes()
	assert result.staged_diff.added_cids.len > 0
	view := set.transaction().indexed_view('users') or { panic(err) }
	rows := view.find_by_index('email', 'grace@example.com', 0) or { panic(err) }
	assert rows.len == 1
	assert rows[0].primary_key.bytestr() == '002'
}

fn test_repository_typed_merge_branch_into_working_set_applies_conflict_resolution() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	table_def := TableDef.new('users', [
		ColumnDef.new('id', .i64_, false) or { panic(err) },
		ColumnDef.new('email', .string_, false) or { panic(err) },
	], ['id']) or { panic(err) }
	spec := TypedTableSpec.new(table_def, [
		SchemaIndexDef.new('email', 'email') or { panic(err) },
	]) or { panic(err) }
	codec := TypedRowCodec.new(table_def)
	mut seed := TypedRowData.new()
	seed.set('id', i64(1))
	seed.set('email', 'ada@example.com')
	tree := Tree.build([
		KVPair{
			key: TableView.new(Tree{}, 'users').key_for('001'.bytes())
			value: codec.encode(seed) or { panic(err) }
		},
	], cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	base := repo.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'init'
		timestamp: 1
	}, mut node_store, mut commit_store) or { panic(err) }
	repo.create_branch('feature', base.snapshot.commit.cid) or { panic(err) }

	mut feature_row := TypedRowData.new()
	feature_row.set('id', i64(1))
	feature_row.set('email', 'feature@example.com')
	mut feature_writes := TypedWriteSet.new()
	feature_writes.put('users', '001'.bytes(), feature_row)
	_ = repo.apply_typed_write_set_to_branch('feature', [spec], feature_writes, cfg, CommitMeta{
		author: 'gwg'
		message: 'feature conflict update'
		timestamp: 2
	}, mut node_store, mut commit_store) or { panic(err) }

	mut set := repo.typed_working_set_at_branch('main', [spec], mut node_store, mut commit_store) or {
		panic(err)
	}
	mut main_row := TypedRowData.new()
	main_row.set('id', i64(1))
	main_row.set('email', 'main@example.com')
	mut main_writes := TypedWriteSet.new()
	main_writes.put('users', '001'.bytes(), main_row)
	_ = set.apply_write_set(main_writes, cfg) or { panic(err) }

	mut resolved_row := TypedRowData.new()
	resolved_row.set('id', i64(1))
	resolved_row.set('email', 'resolved@example.com')
	result := repo.typed_merge_branch_into_working_set(mut set, 'feature', [
		ConflictResolution.use_manual(TableView.new(Tree{}, 'users').key_for('001'.bytes()), codec.encode(
			resolved_row
		) or { panic(err) }),
	], cfg, mut node_store, mut commit_store) or { panic(err) }

	assert result.merge_result.conflicts.len == 1
	assert set.has_changes()
	view := set.transaction().indexed_view('users') or { panic(err) }
	row := view.get('001'.bytes()) or { panic(err) }
	email := row.data.get('email') or { panic(err) }
	assert email is string && email == 'resolved@example.com'
	assert (view.find_by_index('email', 'main@example.com', 0) or { panic(err) }).len == 0
	assert (view.find_by_index('email', 'feature@example.com', 0) or { panic(err) }).len == 0
	resolved_rows := view.find_by_index('email', 'resolved@example.com', 0) or { panic(err) }
	assert resolved_rows.len == 1
	assert resolved_rows[0].primary_key.bytestr() == '001'
}

fn test_repository_merge_branch_into_working_set_stages_non_conflicting_merge() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree1 := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	base := repository_commit_fixture(mut repo, 'main', tree1, 1, 'init', mut node_store, mut commit_store) or { panic(err) }
	repo.create_branch('feature', base.snapshot.commit.cid) or { panic(err) }

	tree_feature := tree1.put(KVPair{
		key: 'key-06'.bytes()
		value: 'feature-update'.bytes()
	}, cfg) or { panic(err) }
	_ = repository_commit_fixture(mut repo, 'feature', tree_feature, 2, 'feature update', mut node_store, mut commit_store) or { panic(err) }

	mut set := repo.working_set_at_branch('main', []TableSpec{}, mut node_store, mut commit_store) or { panic(err) }
	mut writes := WriteSet.new()
	mut row := RowData.new()
	row.set('noop', 'value'.bytes())
	_ = row
	_ = set.apply_write_set(WriteSet.new(), cfg) or { panic(err) }

	result := repo.merge_branch_into_working_set(mut set, 'feature', []ConflictResolution{}, cfg, mut node_store, mut commit_store) or { panic(err) }

	assert result.merge_result.conflicts.len == 0
	assert set.has_changes()
	assert result.staged_diff.added_cids.len > 0
	merged_item := set.transaction().current_tree().get('key-06'.bytes()) or { panic(err) }
	assert merged_item.value.bytestr() == 'feature-update'
}

fn test_repository_merge_branch_into_working_set_applies_conflict_resolution() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree1 := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	base := repository_commit_fixture(mut repo, 'main', tree1, 1, 'init', mut node_store, mut commit_store) or { panic(err) }
	repo.create_branch('feature', base.snapshot.commit.cid) or { panic(err) }

	tree_feature := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'feature-update'.bytes()
	}, cfg) or { panic(err) }
	_ = repository_commit_fixture(mut repo, 'feature', tree_feature, 2, 'feature update', mut node_store, mut commit_store) or { panic(err) }

	mut set := repo.working_set_at_branch('main', []TableSpec{}, mut node_store, mut commit_store) or { panic(err) }
	mut main_tree := set.transaction().current_tree().put(KVPair{
		key: 'key-05'.bytes()
		value: 'main-working-update'.bytes()
	}, cfg) or { panic(err) }
	set.replace_working_tree(main_tree) or { panic(err) }

	result := repo.merge_branch_into_working_set(mut set, 'feature', [
		ConflictResolution.use_manual('key-05'.bytes(), 'resolved-update'.bytes()),
	], cfg, mut node_store, mut commit_store) or { panic(err) }

	assert result.merge_result.conflicts.len == 1
	resolved_item := set.transaction().current_tree().get('key-05'.bytes()) or { panic(err) }
	assert resolved_item.value.bytestr() == 'resolved-update'
	assert set.has_changes()
}

fn test_repository_merge_base_branch_finds_common_ancestor() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree1 := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	base := repository_commit_fixture(mut repo, 'main', tree1, 1, 'init', mut node_store, mut commit_store) or { panic(err) }
	repo.create_branch('feature', base.snapshot.commit.cid) or { panic(err) }

	tree2 := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'main-update'.bytes()
	}, cfg) or { panic(err) }
	_ = repository_commit_fixture(mut repo, 'main', tree2, 2, 'main update', mut node_store, mut commit_store) or { panic(err) }

	tree3 := tree1.put(KVPair{
		key: 'key-06'.bytes()
		value: 'feature-update'.bytes()
	}, cfg) or { panic(err) }
	_ = repository_commit_fixture(mut repo, 'feature', tree3, 3, 'feature update', mut node_store, mut commit_store) or { panic(err) }

	merge_base := repo.merge_base_branch('main', 'feature', mut commit_store) or { panic(err) }
	assert merge_base.cid == base.snapshot.commit.cid
}

fn test_repository_merge_branches_merges_non_conflicting_changes() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree1 := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	base := repository_commit_fixture(mut repo, 'main', tree1, 1, 'init', mut node_store, mut commit_store) or { panic(err) }
	repo.create_branch('feature', base.snapshot.commit.cid) or { panic(err) }

	tree_main := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'main-update'.bytes()
	}, cfg) or { panic(err) }
	main_update := repository_commit_fixture(mut repo, 'main', tree_main, 2, 'main update', mut node_store, mut commit_store) or { panic(err) }

	tree_feature := tree1.put(KVPair{
		key: 'key-06'.bytes()
		value: 'feature-update'.bytes()
	}, cfg) or { panic(err) }
	feature_update := repository_commit_fixture(mut repo, 'feature', tree_feature, 3, 'feature update', mut node_store, mut commit_store) or { panic(err) }

	result := repo.merge_branches('main', 'feature', cfg, mut node_store, mut commit_store) or { panic(err) }
	assert result.base_commit.cid == base.snapshot.commit.cid
	assert result.ours_commit.cid == main_update.snapshot.commit.cid
	assert result.theirs_commit.cid == feature_update.snapshot.commit.cid
	assert result.conflicts.len == 0

	mut found_main := false
	mut found_feature := false
	for item in result.tree.items() or { panic(err) } {
		if item.key.bytestr() == 'key-05' && item.value.bytestr() == 'main-update' {
			found_main = true
		}
		if item.key.bytestr() == 'key-06' && item.value.bytestr() == 'feature-update' {
			found_feature = true
		}
	}
	assert found_main
	assert found_feature
}

fn test_repository_merge_branches_reports_conflicts() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree1 := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	base := repository_commit_fixture(mut repo, 'main', tree1, 1, 'init', mut node_store, mut commit_store) or { panic(err) }
	repo.create_branch('feature', base.snapshot.commit.cid) or { panic(err) }

	tree_main := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'main-update'.bytes()
	}, cfg) or { panic(err) }
	_ = repository_commit_fixture(mut repo, 'main', tree_main, 2, 'main update', mut node_store, mut commit_store) or { panic(err) }

	tree_feature := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'feature-update'.bytes()
	}, cfg) or { panic(err) }
	_ = repository_commit_fixture(mut repo, 'feature', tree_feature, 3, 'feature update', mut node_store, mut commit_store) or { panic(err) }

	result := repo.merge_branches('main', 'feature', cfg, mut node_store, mut commit_store) or { panic(err) }
	assert result.base_commit.cid == base.snapshot.commit.cid
	assert result.conflicts.len == 1
	assert result.conflicts[0].key.bytestr() == 'key-05'
	assert result.conflicts[0].ours.bytestr() == 'main-update'
	assert result.conflicts[0].theirs.bytestr() == 'feature-update'
}

fn test_merge_result_resolve_conflicts_with_ours() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree1 := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	base := repository_commit_fixture(mut repo, 'main', tree1, 1, 'init', mut node_store, mut commit_store) or { panic(err) }
	repo.create_branch('feature', base.snapshot.commit.cid) or { panic(err) }

	tree_main := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'main-update'.bytes()
	}, cfg) or { panic(err) }
	_ = repository_commit_fixture(mut repo, 'main', tree_main, 2, 'main update', mut node_store, mut commit_store) or { panic(err) }

	tree_feature := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'feature-update'.bytes()
	}, cfg) or { panic(err) }
	_ = repository_commit_fixture(mut repo, 'feature', tree_feature, 3, 'feature update', mut node_store, mut commit_store) or { panic(err) }

	result := repo.merge_branches('main', 'feature', cfg, mut node_store, mut commit_store) or { panic(err) }
	resolution := result.resolve_conflicts([
		ConflictResolution.use_ours('key-05'.bytes()),
	], cfg) or { panic(err) }

	mut found := false
	for item in resolution.tree.items() or { panic(err) } {
		if item.key.bytestr() == 'key-05' {
			assert item.value.bytestr() == 'main-update'
			found = true
		}
	}
	assert found
	assert resolution.resolved_keys == ['key-05']
}

fn test_merge_result_resolve_conflicts_with_manual_value() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree1 := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	base := repository_commit_fixture(mut repo, 'main', tree1, 1, 'init', mut node_store, mut commit_store) or { panic(err) }
	repo.create_branch('feature', base.snapshot.commit.cid) or { panic(err) }

	tree_main := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'main-update'.bytes()
	}, cfg) or { panic(err) }
	_ = repository_commit_fixture(mut repo, 'main', tree_main, 2, 'main update', mut node_store, mut commit_store) or { panic(err) }

	tree_feature := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'feature-update'.bytes()
	}, cfg) or { panic(err) }
	_ = repository_commit_fixture(mut repo, 'feature', tree_feature, 3, 'feature update', mut node_store, mut commit_store) or { panic(err) }

	result := repo.merge_branches('main', 'feature', cfg, mut node_store, mut commit_store) or { panic(err) }
	resolution := result.resolve_conflicts([
		ConflictResolution.use_manual('key-05'.bytes(), 'resolved-value'.bytes()),
	], cfg) or { panic(err) }

	mut found := false
	for item in resolution.tree.items() or { panic(err) } {
		if item.key.bytestr() == 'key-05' {
			assert item.value.bytestr() == 'resolved-value'
			found = true
		}
	}
	assert found
}

fn test_repository_merge_branch_into_commits_resolved_tree() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree1 := repository_fixture_tree(cfg) or { panic(err) }
	mut repo := Repository.new('main')
	mut node_store := MemoryNodeStore.new()
	mut commit_store := MemoryCommitStore.new()
	base := repository_commit_fixture(mut repo, 'main', tree1, 1, 'init', mut node_store, mut commit_store) or { panic(err) }
	repo.create_branch('feature', base.snapshot.commit.cid) or { panic(err) }

	tree_main := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'main-update'.bytes()
	}, cfg) or { panic(err) }
	main_update := repository_commit_fixture(mut repo, 'main', tree_main, 2, 'main update', mut node_store, mut commit_store) or { panic(err) }

	tree_feature := tree1.put(KVPair{
		key: 'key-05'.bytes()
		value: 'feature-update'.bytes()
	}, cfg) or { panic(err) }
	feature_update := repository_commit_fixture(mut repo, 'feature', tree_feature, 3, 'feature update', mut node_store, mut commit_store) or { panic(err) }

	merge_commit := repo.merge_branch_into('main', 'feature', [
		ConflictResolution.use_theirs('key-05'.bytes()),
	], cfg, CommitMeta{
		author: 'gwg'
		message: 'merge feature'
		timestamp: 4
	}, mut node_store, mut commit_store) or { panic(err) }

	assert merge_commit.snapshot.commit.parent_cids == [main_update.snapshot.commit.cid]
	head := repo.head() or { panic(err) }
	assert head.commit_cid == merge_commit.snapshot.commit.cid

	loaded := repo.tree_at_branch('main', mut node_store, mut commit_store) or { panic(err) }
	mut found := false
	for item in loaded.items() or { panic(err) } {
		if item.key.bytestr() == 'key-05' {
			assert item.value.bytestr() == 'feature-update'
			found = true
		}
	}
	assert found
	_ = feature_update
}

fn test_auto_merge_by_roots_merges_non_conflicting_changes() {
	cfg := ChunkConfig.default()
	base_tree := Tree.build([
		KVPair{key: 'k1'.bytes(), value: 'base-1'.bytes()},
		KVPair{key: 'k2'.bytes(), value: 'base-2'.bytes()},
	], cfg) or { panic(err) }
	ours_tree := base_tree.put(KVPair{
		key: 'k1'.bytes()
		value: 'ours-1'.bytes()
	}, cfg) or { panic(err) }
	theirs_tree := base_tree.put(KVPair{
		key: 'k2'.bytes()
		value: 'theirs-2'.bytes()
	}, cfg) or { panic(err) }
	mut store := MemoryNodeStore.new()
	store.put_tree(base_tree) or { panic(err) }
	store.put_tree(ours_tree) or { panic(err) }
	store.put_tree(theirs_tree) or { panic(err) }
	result := auto_merge_by_roots(base_tree.root.cid, ours_tree.root.cid, theirs_tree.root.cid, cfg, mut store) or {
		panic(err)
	}
	assert result.conflicts.len == 0
	items := result.tree.items() or { panic(err) }
	mut values := map[string]string{}
	for item in items {
		values[item.key.bytestr()] = item.value.bytestr()
	}
	assert values['k1'] == 'ours-1'
	assert values['k2'] == 'theirs-2'
}
