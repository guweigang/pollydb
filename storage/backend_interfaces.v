module storage

import os

pub interface VersionedNodeBackend {
mut:
	put_nodes(nodes []Node) !
	get_node(cid string) !Node
	has_node(cid string) bool
}

pub interface VersionedCommitBackend {
mut:
	put_commit(commit Commit) !
	get_commit(cid string) !Commit
	has_commit(cid string) bool
}

pub interface BranchHeadBackend {
mut:
	get_branch_head(branch string) !string
	list_branch_heads() []string
	compare_and_swap_branch_head(branch string, old_commit_cid string, new_commit_cid string) !bool
}

pub interface RepositoryMetaBackend {
mut:
	load_repository() !Repository
	save_repository(repo Repository) !
}

pub interface CatalogBackend {
mut:
	load_catalog() !(map[string]TypedTableSpec, map[string]AggregateProjectionDef, map[string]MemoryCapabilityDef)
	save_catalog(catalog map[string]TypedTableSpec, projectors map[string]AggregateProjectionDef, memory_capabilities map[string]MemoryCapabilityDef) !
}

pub interface DatabaseBackendProvider {
	paths() LocalBackendPaths
	default_branch() string
	open_backends() !LocalDatabaseBackends
	init_backends() !LocalDatabaseBackends
}

pub struct LocalNodeBackend {
mut:
	store PersistentNodeStore
}

pub fn LocalNodeBackend.open(path string) !LocalNodeBackend {
	return LocalNodeBackend{
		store: PersistentNodeStore.open(path)!
	}
}

pub fn LocalNodeBackend.open_high_throughput(path string) !LocalNodeBackend {
	return LocalNodeBackend{
		store: PersistentNodeStore.open_high_throughput(path)!
	}
}

pub fn (mut backend LocalNodeBackend) close() {
	backend.store.close()
}

pub fn (mut backend LocalNodeBackend) put_nodes(nodes []Node) ! {
	backend.store.put_many(nodes)!
}

pub fn (mut backend LocalNodeBackend) get_node(cid string) !Node {
	return backend.store.get(cid)
}

pub fn (backend LocalNodeBackend) has_node(cid string) bool {
	return backend.store.has(cid)
}

pub struct LocalCommitBackend {
mut:
	store PersistentCommitStore
}

pub fn LocalCommitBackend.open(path string) !LocalCommitBackend {
	return LocalCommitBackend{
		store: PersistentCommitStore.open(path)!
	}
}

pub fn LocalCommitBackend.open_high_throughput(path string) !LocalCommitBackend {
	return LocalCommitBackend{
		store: PersistentCommitStore.open_high_throughput(path)!
	}
}

pub fn (mut backend LocalCommitBackend) close() {
	backend.store.close()
}

pub fn (mut backend LocalCommitBackend) put_commit(commit Commit) ! {
	backend.store.put(commit)!
}

pub fn (mut backend LocalCommitBackend) get_commit(cid string) !Commit {
	return backend.store.get(cid)
}

pub fn (backend LocalCommitBackend) has_commit(cid string) bool {
	return backend.store.has(cid)
}

pub struct LocalRepositoryMetaBackend {
pub:
	path string
}

pub fn (mut backend LocalRepositoryMetaBackend) load_repository() !Repository {
	return Repository.open(backend.path)
}

pub fn (mut backend LocalRepositoryMetaBackend) save_repository(repo Repository) ! {
	repo.persist(backend.path)!
	fsync_repository_meta(backend.path)!
}

pub struct LocalBranchHeadBackend {
pub:
	path string
}

pub fn (backend LocalBranchHeadBackend) get_branch_head(branch string) !string {
	repo := Repository.open(backend.path)!
	return repo.branch(branch)!.commit_cid
}

pub fn (backend LocalBranchHeadBackend) list_branch_heads() []string {
	repo := Repository.open(backend.path) or { return []string{} }
	return repo.branch_names()
}

pub fn (mut backend LocalBranchHeadBackend) compare_and_swap_branch_head(branch string, old_commit_cid string, new_commit_cid string) !bool {
	mut repo := Repository.open(backend.path)!
	current := repo.branch(branch) or {
		if old_commit_cid.len > 0 {
			return false
		}
		repo.branches[branch] = new_commit_cid
		repo.persist(backend.path)!
		fsync_repository_meta(backend.path)!
		return true
	}
	if current.commit_cid != old_commit_cid {
		return false
	}
	repo.branches[branch] = new_commit_cid
	repo.persist(backend.path)!
	fsync_repository_meta(backend.path)!
	return true
}

pub struct LocalCatalogBackend {
pub:
	root_dir string
}

pub fn (mut backend LocalCatalogBackend) load_catalog() !(map[string]TypedTableSpec, map[string]AggregateProjectionDef, map[string]MemoryCapabilityDef) {
	return load_database_catalog(backend.root_dir)
}

pub fn (mut backend LocalCatalogBackend) save_catalog(catalog map[string]TypedTableSpec, projectors map[string]AggregateProjectionDef, memory_capabilities map[string]MemoryCapabilityDef) ! {
	catalog_path := database_catalog_path(backend.root_dir)
	os.mkdir_all(os.dir(catalog_path))!
	os.write_file(catalog_path, catalog_data(catalog, projectors, memory_capabilities).bytestr())!
}

pub struct LocalBackendPaths {
pub:
	root_dir        string
	repository_meta string
	nodes_chunk     string
	commits_chunk   string
	catalog_meta    string
}

pub fn local_backend_paths(root_dir string) LocalBackendPaths {
	return LocalBackendPaths{
		root_dir:        root_dir
		repository_meta: repository_metadata_path(root_dir)
		nodes_chunk:     repository_nodes_path(root_dir)
		commits_chunk:   repository_commits_path(root_dir)
		catalog_meta:    database_catalog_path(root_dir)
	}
}

pub struct LocalDatabaseBackends {
pub:
	paths LocalBackendPaths
mut:
	node_backend            LocalNodeBackend
	commit_backend          LocalCommitBackend
	branch_head_backend     LocalBranchHeadBackend
	repository_meta_backend LocalRepositoryMetaBackend
	catalog_backend         LocalCatalogBackend
}

pub fn open_local_database_backends(root_dir string, default_branch string) !LocalDatabaseBackends {
	os.mkdir_all(repository_layout_dir(root_dir))!
	replay_checkpoint_journal(root_dir)!
	paths := local_backend_paths(root_dir)
	if !os.exists(paths.repository_meta) {
		Repository.new(default_branch).persist(paths.repository_meta)!
	}
	return LocalDatabaseBackends{
		paths:                   paths
		node_backend:            LocalNodeBackend.open_high_throughput(paths.nodes_chunk)!
		commit_backend:          LocalCommitBackend.open_high_throughput(paths.commits_chunk)!
		branch_head_backend:     LocalBranchHeadBackend{
			path: paths.repository_meta
		}
		repository_meta_backend: LocalRepositoryMetaBackend{
			path: paths.repository_meta
		}
		catalog_backend:         LocalCatalogBackend{
			root_dir: root_dir
		}
	}
}

pub fn init_local_database_backends(root_dir string, default_branch string) !LocalDatabaseBackends {
	os.mkdir_all(repository_layout_dir(root_dir))!
	paths := local_backend_paths(root_dir)
	if !os.exists(paths.repository_meta) {
		Repository.new(default_branch).persist(paths.repository_meta)!
	}
	return open_local_database_backends(root_dir, default_branch)
}

pub fn (mut backends LocalDatabaseBackends) close() {
	backends.node_backend.close()
	backends.commit_backend.close()
}

pub struct LocalDatabaseBackendProvider {
pub:
	root_dir              string
	config_default_branch string
}

pub fn LocalDatabaseBackendProvider.new(root_dir string, default_branch string) LocalDatabaseBackendProvider {
	return LocalDatabaseBackendProvider{
		root_dir:              root_dir
		config_default_branch: default_branch
	}
}

pub fn (provider LocalDatabaseBackendProvider) paths() LocalBackendPaths {
	return local_backend_paths(provider.root_dir)
}

pub fn (provider LocalDatabaseBackendProvider) default_branch() string {
	return provider.config_default_branch
}

pub fn (provider LocalDatabaseBackendProvider) open_backends() !LocalDatabaseBackends {
	return open_local_database_backends(provider.root_dir, provider.config_default_branch)
}

pub fn (provider LocalDatabaseBackendProvider) init_backends() !LocalDatabaseBackends {
	return init_local_database_backends(provider.root_dir, provider.config_default_branch)
}
