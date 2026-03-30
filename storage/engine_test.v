module storage

import os

fn test_persistent_engine_roundtrip() {
	cfg := ChunkConfig{
		min_size: 64
		max_size: 128
		mask: 0
	}
	tree := Tree.build([
		KVPair{key: 'key-01'.bytes(), value: 'value-01'.bytes()},
		KVPair{key: 'key-02'.bytes(), value: 'value-02'.bytes()},
	], cfg) or { panic(err) }
	dir := os.join_path(os.vtmp_dir(), 'pollytree-engine-roundtrip')
	defer {
		os.rmdir_all(dir) or {}
	}

	mut engine := PersistentEngine.init(dir, 'main') or { panic(err) }
	update := engine.commit_to_branch('main', tree, CommitMeta{
		author: 'gwg'
		message: 'engine init'
		timestamp: 1
	}) or { panic(err) }
	engine.close() or { panic(err) }

	mut reopened := PersistentEngine.open(dir, 'main') or { panic(err) }
	defer {
		reopened.close() or {}
	}
	assert os.exists(os.join_path(dir, '.pollydb', 'repo.meta'))
	assert os.exists(os.join_path(dir, '.pollydb', 'nodes.chunk'))
	assert os.exists(os.join_path(dir, '.pollydb', 'commits.chunk'))
	head := reopened.head() or { panic(err) }
	assert head.commit_cid == update.snapshot.commit.cid
	loaded := reopened.tree_at_branch('main') or { panic(err) }
	assert loaded.root.cid == tree.root.cid
	assert loaded.items() or { panic(err) } == tree.items() or { panic(err) }
}

fn test_persistent_engine_open_local_backends() {
	dir := os.join_path(os.vtmp_dir(), 'pollytree-engine-backends')
	defer {
		os.rmdir_all(dir) or {}
	}

	mut engine := PersistentEngine.init(dir, 'main') or { panic(err) }
	defer {
		engine.close() or {}
	}
	paths := engine.backend_paths()
	assert paths.root_dir == dir
	assert paths.repository_meta.ends_with('.pollydb/repo.meta')
	mut backends := engine.open_local_backends() or { panic(err) }
	defer {
		backends.close()
	}
	repo := backends.repository_meta_backend.load_repository() or { panic(err) }
	assert repo.default_branch == 'main'
}

fn test_persistent_engine_backend_provider() {
	dir := os.join_path(os.vtmp_dir(), 'pollytree-engine-provider')
	defer {
		os.rmdir_all(dir) or {}
	}

	mut engine := PersistentEngine.init(dir, 'main') or { panic(err) }
	defer {
		engine.close() or {}
	}
	provider := engine.backend_provider()
	assert provider.default_branch() == 'main'
	assert provider.paths().repository_meta.ends_with('.pollydb/repo.meta')
	mut backends := provider.open_backends() or { panic(err) }
	defer {
		backends.close()
	}
	assert backends.paths.root_dir == dir
}

fn test_persistent_engine_open_with_provider() {
	dir := os.join_path(os.vtmp_dir(), 'pollytree-engine-open-with-provider')
	defer {
		os.rmdir_all(dir) or {}
	}

	provider := LocalDatabaseBackendProvider.new(dir, 'main')
	mut engine := PersistentEngine.init_with_provider(provider) or { panic(err) }
	engine.close() or { panic(err) }
	mut reopened := PersistentEngine.open_with_provider(provider) or { panic(err) }
	defer {
		reopened.close() or {}
	}
	assert reopened.backend_provider().default_branch() == 'main'
}
