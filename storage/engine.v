module storage

import time

pub struct PersistentEngine {
pub:
	root_dir string
mut:
	repository PersistentRepository
}

pub struct PersistentEngineCheckpointInfo {
pub:
	root_dir    string
	repository  PersistentRepositoryCheckpointInfo
}

pub struct PersistentEngineCheckpointTimings {
pub:
	repository PersistentRepositoryCheckpointTimings
	total_us   i64
}

pub struct PersistentEngineRecoveryStatus {
pub:
	root_dir    string
	repository  PersistentRepositoryRecoveryStatus
}

pub fn PersistentEngine.open(root_dir string, default_branch string) !PersistentEngine {
	return PersistentEngine.open_with_provider(LocalDatabaseBackendProvider.new(root_dir, default_branch))
}

pub fn PersistentEngine.init(root_dir string, default_branch string) !PersistentEngine {
	return PersistentEngine.init_with_provider(LocalDatabaseBackendProvider.new(root_dir, default_branch))
}

pub fn PersistentEngine.open_with_provider(provider LocalDatabaseBackendProvider) !PersistentEngine {
	return PersistentEngine{
		root_dir: provider.root_dir
		repository: PersistentRepository.open_default(provider.root_dir, provider.default_branch())!
	}
}

pub fn PersistentEngine.init_with_provider(provider LocalDatabaseBackendProvider) !PersistentEngine {
	return PersistentEngine{
		root_dir: provider.root_dir
		repository: PersistentRepository.init(provider.root_dir, provider.default_branch())!
	}
}

pub fn (engine PersistentEngine) backend_paths() LocalBackendPaths {
	return local_backend_paths(engine.root_dir)
}

pub fn (engine PersistentEngine) backend_provider() LocalDatabaseBackendProvider {
	default_branch := if engine.repository.repo.default_branch.len > 0 {
		engine.repository.repo.default_branch
	} else {
		'main'
	}
	return LocalDatabaseBackendProvider.new(engine.root_dir, default_branch)
}

pub fn (engine PersistentEngine) open_local_backends() !LocalDatabaseBackends {
	return engine.backend_provider().open_backends()
}

pub fn (mut engine PersistentEngine) close() ! {
	engine.repository.close()!
}

pub fn (mut engine PersistentEngine) checkpoint() ! {
	engine.repository.checkpoint()!
}

pub fn (mut engine PersistentEngine) refresh_index_snapshots() ! {
	engine.repository.refresh_index_snapshots()!
}

pub fn (mut engine PersistentEngine) checkpoint_timed() !PersistentEngineCheckpointTimings {
	mut sw := time.new_stopwatch()
	repository := engine.repository.checkpoint_timed()!
	return PersistentEngineCheckpointTimings{
		repository: repository
		total_us: sw.elapsed().microseconds()
	}
}

pub fn (mut engine PersistentEngine) checkpoint_mode(mode CheckpointMode) ! {
	engine.repository.checkpoint_mode(mode)!
}

pub fn (mut engine PersistentEngine) checkpoint_timed_mode(mode CheckpointMode) !PersistentEngineCheckpointTimings {
	mut sw := time.new_stopwatch()
	repository := engine.repository.checkpoint_timed_mode(mode)!
	return PersistentEngineCheckpointTimings{
		repository: repository
		total_us: sw.elapsed().microseconds()
	}
}

pub fn (engine PersistentEngine) checkpoint_info() PersistentEngineCheckpointInfo {
	return PersistentEngineCheckpointInfo{
		root_dir: engine.root_dir
		repository: engine.repository.checkpoint_info()
	}
}

pub fn PersistentEngine.recovery_status(root_dir string) !PersistentEngineRecoveryStatus {
	return PersistentEngine.recovery_status_with_provider(LocalDatabaseBackendProvider.new(root_dir, 'main'))
}

pub fn PersistentEngine.recovery_status_with_provider(provider LocalDatabaseBackendProvider) !PersistentEngineRecoveryStatus {
	return PersistentEngineRecoveryStatus{
		root_dir: provider.root_dir
		repository: PersistentRepository.recovery_status(provider.root_dir)!
	}
}

pub fn (engine PersistentEngine) repository_view() Repository {
	return engine.repository.repository()
}

pub fn (mut engine PersistentEngine) head() !Branch {
	return engine.repository.head()
}

pub fn (mut engine PersistentEngine) branch(name string) !Branch {
	return engine.repository.branch(name)
}

pub fn (mut engine PersistentEngine) branch_names() []string {
	return engine.repository.branch_names()
}

pub fn (mut engine PersistentEngine) create_branch(name string, from_commit_cid string) !Branch {
	return engine.repository.create_branch(name, from_commit_cid)
}

pub fn (mut engine PersistentEngine) merge_base_branch(left_branch string, right_branch string) !Commit {
	return engine.repository.repo.merge_base_branch(left_branch, right_branch, mut engine.repository.commit_store)
}

pub fn (mut engine PersistentEngine) merge_branches(ours_branch string, theirs_branch string, cfg ChunkConfig) !MergeResult {
	return engine.repository.repo.merge_branches(
		ours_branch,
		theirs_branch,
		cfg,
		mut engine.repository.node_store,
		mut engine.repository.commit_store,
	)
}

pub fn (mut engine PersistentEngine) merge_branch_into(ours_branch string, theirs_branch string, resolutions []ConflictResolution, cfg ChunkConfig, meta CommitMeta) !BranchUpdate {
	result := engine.repository.repo.merge_branches(
		ours_branch,
		theirs_branch,
		cfg,
		mut engine.repository.node_store,
		mut engine.repository.commit_store,
	)!
	resolution := result.resolve_conflicts(resolutions, cfg)!
	update := engine.commit_to_branch(ours_branch, resolution.tree, meta)!
	return update
}

pub fn (mut engine PersistentEngine) commit_to_branch(branch_name string, tree Tree, meta CommitMeta) !BranchUpdate {
	return engine.commit_to_branch_with_virtual_roots(branch_name, tree, meta, [])
}

fn (mut engine PersistentEngine) advance_branch_head_with_backend(branch_name string, new_commit_cid string) !Branch {
	old_commit_cid := if engine.repository.repo.has_branch(branch_name) {
		(engine.repository.repo.branch(branch_name)!).commit_cid
	} else {
		''
	}
	return engine.repository.compare_and_swap_branch_head(branch_name, old_commit_cid, new_commit_cid)
}

pub fn (mut engine PersistentEngine) commit_to_branch_with_virtual_roots(branch_name string, tree Tree, meta CommitMeta, virtual_roots []VirtualRootRef) !BranchUpdate {
	parent_cids := engine.repository.repo.parent_cids_for_branch(branch_name)
	snapshot := Snapshot.new_with_virtual_roots(tree, parent_cids, meta, virtual_roots)
	snapshot.persist_to_persistent(mut engine.repository.node_store, mut engine.repository.commit_store)!
	branch := engine.advance_branch_head_with_backend(branch_name, snapshot.commit.cid)!
	return BranchUpdate{
		branch: branch
		snapshot: snapshot
	}
}

pub fn (mut engine PersistentEngine) tree_at_branch(branch_name string) !Tree {
	return engine.repository.tree_at_branch(branch_name)
}

pub fn (mut engine PersistentEngine) root_cid_at_branch(branch_name string) !string {
	commit := engine.repository.checkout(branch_name)!
	return commit.root_cid
}

pub fn (mut engine PersistentEngine) commit_by_cid(commit_cid string) !Commit {
	return engine.repository.commit_store.get(commit_cid)
}

pub fn (mut engine PersistentEngine) root_cid_at_commit(commit_cid string) !string {
	commit := engine.commit_by_cid(commit_cid)!
	return commit.root_cid
}

pub fn (mut engine PersistentEngine) checkout(branch_name string) !Commit {
	return engine.repository.checkout(branch_name)
}

pub fn (mut engine PersistentEngine) branch_log(branch_name string, limit int) ![]Commit {
	branch := engine.repository.branch(branch_name)!
	mut commits := engine.repository.commit_store.lineage(branch.commit_cid)!
	if limit > 0 && commits.len > limit {
		commits = commits[..limit].clone()
	}
	return commits
}

pub fn (mut engine PersistentEngine) typed_transaction_at_branch(branch_name string, specs []TypedTableSpec) !TypedTransaction {
	return engine.repository.repo.typed_transaction_at_branch(branch_name, specs, mut engine.repository.node_store, mut engine.repository.commit_store)
}

pub fn (mut engine PersistentEngine) typed_working_set_at_branch(branch_name string, specs []TypedTableSpec) !TypedWorkingSet {
	return engine.repository.repo.typed_working_set_at_branch(branch_name, specs, mut engine.repository.node_store, mut engine.repository.commit_store)
}

pub fn (mut engine PersistentEngine) apply_typed_write_set_to_branch(branch_name string, specs []TypedTableSpec, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	return engine.apply_typed_write_set_to_branch_with_virtual_roots(branch_name, specs, write_set, cfg, meta, [])
}

pub fn (mut engine PersistentEngine) apply_typed_write_set_to_branch_with_virtual_roots(branch_name string, specs []TypedTableSpec, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta, virtual_roots []VirtualRootRef) !BranchTypedTransactionResult {
	tx := engine.repository.repo.typed_transaction_at_branch(branch_name, specs, mut engine.repository.node_store, mut engine.repository.commit_store)!
	mut sw := time.new_stopwatch()
	transaction_update := tx.apply_write_set(write_set, cfg)!
	tx_apply_us := sw.elapsed().microseconds()
	snapshot := Snapshot.new_with_virtual_roots(transaction_update.tx.current_tree(), engine.repository.repo.parent_cids_for_branch(branch_name), meta, virtual_roots)
	sw.restart()
	snapshot.persist_to_persistent(mut engine.repository.node_store, mut engine.repository.commit_store)!
	snapshot_persist_us := sw.elapsed().microseconds()
	sw.restart()
	branch := engine.advance_branch_head_with_backend(branch_name, snapshot.commit.cid)!
	branch_head_us := sw.elapsed().microseconds()
	repo_meta_persist_us := branch_head_us
	return BranchTypedTransactionResult{
		update: BranchUpdate{
			branch: branch
			snapshot: snapshot
		}
		transaction_update: transaction_update
		timings: BranchTypedTransactionTimings{
			tx_apply_us: tx_apply_us
			snapshot_persist_us: snapshot_persist_us
			branch_head_us: branch_head_us
			repo_meta_persist_us: repo_meta_persist_us
		}
	}
}

pub fn (mut engine PersistentEngine) apply_typed_write_set_to_branch_buffered(branch_name string, specs []TypedTableSpec, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta) !BranchTypedTransactionResult {
	return engine.apply_typed_write_set_to_branch_buffered_with_virtual_roots(branch_name, specs, write_set, cfg, meta, [])
}

pub fn (mut engine PersistentEngine) apply_typed_write_set_to_branch_buffered_with_virtual_roots(branch_name string, specs []TypedTableSpec, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta, virtual_roots []VirtualRootRef) !BranchTypedTransactionResult {
	tx := engine.repository.repo.typed_transaction_at_branch(branch_name, specs, mut engine.repository.node_store, mut engine.repository.commit_store)!
	mut sw := time.new_stopwatch()
	transaction_update := tx.apply_write_set(write_set, cfg)!
	tx_apply_us := sw.elapsed().microseconds()
	snapshot := Snapshot.new_with_virtual_roots(transaction_update.tx.current_tree(), engine.repository.repo.parent_cids_for_branch(branch_name), meta, virtual_roots)
	sw.restart()
	snapshot.persist_to_persistent(mut engine.repository.node_store, mut engine.repository.commit_store)!
	snapshot_persist_us := sw.elapsed().microseconds()
	sw.restart()
	branch := engine.advance_branch_head_with_backend(branch_name, snapshot.commit.cid)!
	branch_head_us := sw.elapsed().microseconds()
	return BranchTypedTransactionResult{
		update: BranchUpdate{
			branch: branch
			snapshot: snapshot
		}
		transaction_update: transaction_update
		timings: BranchTypedTransactionTimings{
			tx_apply_us: tx_apply_us
			snapshot_persist_us: snapshot_persist_us
			branch_head_us: branch_head_us
			repo_meta_persist_us: 0
		}
	}
}

pub fn (mut engine PersistentEngine) commit_typed_working_set(mut set TypedWorkingSet, meta CommitMeta) !BranchTypedWorkingSetResult {
	return engine.commit_typed_working_set_with_virtual_roots(mut set, meta, [])
}

pub fn (mut engine PersistentEngine) commit_typed_working_set_with_virtual_roots(mut set TypedWorkingSet, meta CommitMeta, virtual_roots []VirtualRootRef) !BranchTypedWorkingSetResult {
	snapshot := Snapshot.new_with_virtual_roots(set.transaction().current_tree(), engine.repository.repo.parent_cids_for_branch(set.branch_name), meta, virtual_roots)
	snapshot.persist_to_persistent(mut engine.repository.node_store, mut engine.repository.commit_store)!
	branch := engine.advance_branch_head_with_backend(set.branch_name, snapshot.commit.cid)!
	update := BranchUpdate{
		branch: branch
		snapshot: snapshot
	}
	set.sync_to_tree(update.snapshot.tree, update.snapshot.commit.cid)!
	return BranchTypedWorkingSetResult{
		update: update
		transaction_update: TypedTransactionResult{
			tx: set.transaction()
			diff: set.staged_diff()
		}
	}
}

pub fn (mut engine PersistentEngine) commit_typed_working_set_buffered(mut set TypedWorkingSet, meta CommitMeta) !BranchTypedWorkingSetResult {
	return engine.commit_typed_working_set_buffered_with_virtual_roots(mut set, meta, [])
}

pub fn (mut engine PersistentEngine) commit_typed_working_set_buffered_with_virtual_roots(mut set TypedWorkingSet, meta CommitMeta, virtual_roots []VirtualRootRef) !BranchTypedWorkingSetResult {
	diff := set.staged_diff()
	tx := set.transaction()
	snapshot := Snapshot.new_with_virtual_roots(tx.current_tree(), engine.repository.repo.parent_cids_for_branch(set.branch_name), meta, virtual_roots)
	snapshot.persist_to_persistent(mut engine.repository.node_store, mut engine.repository.commit_store)!
	branch := engine.advance_branch_head_with_backend(set.branch_name, snapshot.commit.cid)!
	update := BranchUpdate{
		branch: branch
		snapshot: snapshot
	}
	set.sync_to_tree(update.snapshot.tree, update.snapshot.commit.cid)!
	return BranchTypedWorkingSetResult{
		update: update
		transaction_update: TypedTransactionResult{
			tx: set.transaction()
			diff: diff
		}
	}
}

pub fn (mut engine PersistentEngine) commit_virtual_roots_for_branch(branch_name string, virtual_roots []VirtualRootRef, meta CommitMeta) !Commit {
	current := engine.repository.checkout(branch_name)!
	commit := Commit.new_with_virtual_roots(current.root_cid, [current.cid], meta, virtual_roots)
	engine.repository.commit_store.put(commit)!
	_ = engine.repository.compare_and_swap_branch_head(branch_name, current.cid, commit.cid)!
	return commit
}
