module storage

import os
import rand
import time

pub struct Branch {
pub:
	name       string
	commit_cid string
}

pub struct Repository {
pub:
	default_branch string
mut:
	branches map[string]string
}

pub struct PersistentRepository {
pub:
	path              string
	node_store_path   string
	commit_store_path string
mut:
	repo                      Repository
	node_store                PersistentNodeStore
	commit_store              PersistentCommitStore
	meta_dirty                bool
	checkpoint_journal_bytes  u64
	branch_head_journal_bytes u64
}

pub struct PersistentRepositoryOpenTimings {
pub:
	replay_journal_ms  i64
	repository_meta_ms i64
	node_store_ms      i64
	commit_store_ms    i64
	total_ms           i64
}

pub struct PersistentRepositoryOpenResult {
pub:
	repository PersistentRepository
	timings    PersistentRepositoryOpenTimings
}

pub struct TypedTransactionOpenTimings {
pub:
	checkout_ms  i64
	tree_load_ms i64
	wrap_ms      i64
	total_ms     i64
}

pub struct TypedTransactionOpenResult {
pub:
	tx      TypedTransaction
	timings TypedTransactionOpenTimings
}

pub struct PersistentRepositoryCheckpointInfo {
pub:
	metadata_path     string
	node_store        PersistentNodeStoreCheckpointInfo
	commit_store      PersistentCommitStoreCheckpointInfo
	repository_exists bool
}

pub struct PersistentRepositoryCheckpointTimings {
pub:
	repo_meta_us          i64
	node_store_data_us    i64
	node_store_index_us   i64
	node_store_us         i64
	commit_store_data_us  i64
	commit_store_index_us i64
	commit_store_us       i64
	total_us              i64
}

pub struct PersistentRepositoryRecoveryStatus {
pub:
	metadata_path             string
	repository_exists         bool
	checkpoint_journal_exists bool
	node_store                PersistentNodeStoreRecoveryStatus
	commit_store              PersistentCommitStoreRecoveryStatus
}

pub struct BranchUpdate {
pub:
	branch   Branch
	snapshot Snapshot
}

pub struct BranchMutationResult {
pub:
	update      BranchUpdate
	tree_update TreeUpdate
}

pub struct BranchTransactionResult {
pub:
	update             BranchUpdate
	transaction_update TransactionResult
}

pub struct BranchTypedTransactionResult {
pub:
	update             BranchUpdate
	transaction_update TypedTransactionResult
	timings            BranchTypedTransactionTimings
}

pub struct BranchTypedTransactionTimings {
pub:
	tx_open_us           i64
	normalize_us         i64
	tx_apply_us          i64
	index_rebuild_us     i64
	commit_us            i64
	fts_us               i64
	fts_begin_us         i64
	fts_ensure_us        i64
	fts_backfill_us      i64
	fts_prepare_us       i64
	fts_docid_select_us  i64
	fts_delete_us        i64
	fts_text_us          i64
	fts_insert_us        i64
	fts_insert_fts_us    i64
	fts_insert_map_us    i64
	fts_commit_us        i64
	fts_ops              int
	fts_inserted         int
	fts_deleted          int
	snapshot_persist_us  i64
	branch_head_us       i64
	repo_meta_persist_us i64
}

pub struct BranchTypedWorkingSetResult {
pub:
	update             BranchUpdate
	transaction_update TypedTransactionResult
}

pub struct WorkingSetMergeResult {
pub:
	merge_result MergeResult
	resolution   MergeResolution
	staged_diff  TreeDiff
	timings      MergeStageTimings
}

pub struct MergeStageTimings {
pub:
	merge_ms        i64
	resolve_ms      i64
	changed_rows_ms i64
	reindex_ms      i64
	reindex         ReindexStageTimings
}

pub struct MergeConflict {
pub:
	key    []u8
	base   []u8
	ours   []u8
	theirs []u8
}

pub struct MergeResult {
pub:
	base_commit      Commit
	ours_commit      Commit
	theirs_commit    Commit
	tree             Tree
	conflicts        []MergeConflict
	changed_keys     []string
	changed_subtrees []ChangedSubtree
}

pub enum ConflictResolutionStrategy {
	ours
	theirs
	manual
	delete
}

pub struct ConflictResolution {
pub:
	key      []u8
	strategy ConflictResolutionStrategy
	value    []u8
}

pub struct MergeResolution {
pub:
	tree          Tree
	resolved_keys []string
}

struct RepositoryReader {
	data []u8
mut:
	cursor int
}

fn merge_progress_enabled() bool {
	return os.getenv('POLLYTREE_BENCH_PROGRESS') == '1'
}

fn merge_progress_log(message string) {
	if merge_progress_enabled() {
		println(message)
	}
}

fn repository_append_u32(mut out []u8, value u32) {
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
}

fn repository_append_field(mut out []u8, data []u8) {
	repository_append_u32(mut out, u32(data.len))
	out << data
}

fn write_repository_field(mut file os.File, data []u8) ! {
	mut header := []u8{cap: 4}
	repository_append_u32(mut header, u32(data.len))
	_ = file.write(header)!
	if data.len > 0 {
		_ = file.write(data)!
	}
}

fn open_repository_append_file(path string) !os.File {
	os.mkdir_all(os.dir(path))!
	return os.open_file(path, 'ab+', 0o666) or {
		os.mkdir_all(os.dir(path))!
		os.open_file(path, 'ab+', 0o666) or {
			return error('failed to open repository append file ${path}: ${err}')
		}
	}
}

fn write_checkpoint_journal(root_dir string, node_records []u8, commit_records []u8) ! {
	write_checkpoint_journal_with_branch(root_dir, node_records, commit_records, '', '', '')!
}

fn write_checkpoint_journal_with_branch(root_dir string, node_records []u8, commit_records []u8, branch_name string, old_commit_cid string, new_commit_cid string) ! {
	if node_records.len == 0 && commit_records.len == 0 {
		if branch_name.len > 0 {
			write_branch_head_journal(root_dir, branch_name, old_commit_cid, new_commit_cid)!
		}
		return
	}
	path := repository_checkpoint_journal_path(root_dir)
	os.mkdir_all(os.dir(path))!
	has_branch := branch_name.len > 0
	mut header := []u8{cap: 20}
	header << repository_checkpoint_journal_magic.bytes()
	repository_append_u32(mut header, repository_checkpoint_journal_version2)
	repository_append_u32(mut header, u32(node_records.len))
	repository_append_u32(mut header, u32(commit_records.len))
	repository_append_u32(mut header, if has_branch { u32(1) } else { u32(0) })
	mut file := open_repository_append_file(path)!
	_ = file.write(header)!
	if node_records.len > 0 {
		_ = file.write(node_records)!
	}
	if commit_records.len > 0 {
		_ = file.write(commit_records)!
	}
	if has_branch {
		write_repository_field(mut file, branch_name.bytes())!
		write_repository_field(mut file, old_commit_cid.bytes())!
		write_repository_field(mut file, new_commit_cid.bytes())!
	}
	file.flush()
	$if darwin {
		chunk_store_fsync_fd(file.fd)!
	}
	file.close()
}

fn replay_checkpoint_journal(root_dir string) ! {
	path := repository_checkpoint_journal_path(root_dir)
	if !os.exists(path) {
		return
	}
	data := os.read_bytes(path)!
	if data.len < 8 || data[..4].bytestr() != repository_checkpoint_journal_magic {
		os.rm(path) or {}
		return
	}
	mut node_store := PersistentNodeStore.open_high_throughput(repository_nodes_path(root_dir))!
	defer {
		node_store.close()
	}
	mut commit_store :=
		PersistentCommitStore.open_high_throughput(repository_commits_path(root_dir))!
	defer {
		commit_store.close()
	}
	mut cursor := 0
	mut replayed_any := false
	for cursor < data.len {
		if cursor + 8 > data.len {
			break
		}
		if data[cursor..cursor + 4].bytestr() != repository_checkpoint_journal_magic {
			if cursor == 0 {
				os.rm(path) or {}
				return
			}
			break
		}
		version := u32(data[cursor + 4]) | (u32(data[cursor + 5]) << 8) | (u32(data[cursor + 6]) << 16) | (u32(data[
			cursor + 7]) << 24)
		if version != repository_checkpoint_journal_version
			&& version != repository_checkpoint_journal_version2 {
			if cursor == 0 {
				os.rm(path) or {}
				return
			}
			break
		}
		mut reader := RepositoryReader{
			data: data[cursor + 8..]
		}
		node_record_len := int(reader.read_u32() or { break })
		commit_record_len := int(reader.read_u32() or { break })
		branch_record_count := if version >= repository_checkpoint_journal_version2 {
			int(reader.read_u32() or { break })
		} else {
			0
		}
		if reader.cursor + node_record_len + commit_record_len > reader.data.len {
			break
		}
		node_records := reader.data[reader.cursor..reader.cursor + node_record_len].clone()
		reader.cursor += node_record_len
		commit_records := reader.data[reader.cursor..reader.cursor + commit_record_len].clone()
		reader.cursor += commit_record_len
		replay_checkpoint_journal_records(mut node_store.chunks, node_records)!
		replay_checkpoint_journal_records(mut commit_store.chunks, commit_records)!
		for _ in 0 .. branch_record_count {
			branch_name := reader.read_field() or { break }.bytestr()
			old_commit_cid := reader.read_field() or { break }.bytestr()
			new_commit_cid := reader.read_field() or { break }.bytestr()
			write_branch_head_journal(root_dir, branch_name, old_commit_cid, new_commit_cid)!
		}
		replayed_any = true
		cursor += 8 + reader.cursor
	}
	if replayed_any {
		node_store.chunks.checkpoint_mode(.data_only)!
		commit_store.chunks.checkpoint_mode(.data_only)!
	}
	os.rm(path) or {}
}

fn write_branch_head_journal(root_dir string, branch_name string, old_commit_cid string, new_commit_cid string) ! {
	path := repository_branch_head_journal_path(root_dir)
	os.mkdir_all(os.dir(path))!
	mut payload := []u8{}
	repository_append_field(mut payload, branch_name.bytes())
	repository_append_field(mut payload, old_commit_cid.bytes())
	repository_append_field(mut payload, new_commit_cid.bytes())
	mut data := []u8{}
	data << repository_branch_head_journal_magic.bytes()
	repository_append_u32(mut data, repository_branch_head_journal_version)
	data << payload
	mut file := open_repository_append_file(path)!
	_ = file.write(data)!
	file.flush()
	$if darwin {
		chunk_store_fsync_fd(file.fd)!
	}
	file.close()
}

fn branch_head_journal_size(root_dir string) u64 {
	path := repository_branch_head_journal_path(root_dir)
	if !os.exists(path) {
		return 0
	}
	return os.file_size(path)
}

fn checkpoint_journal_size(root_dir string) u64 {
	path := repository_checkpoint_journal_path(root_dir)
	if !os.exists(path) {
		return 0
	}
	return os.file_size(path)
}

fn replay_branch_head_journal(root_dir string, mut repo Repository) ! {
	path := repository_branch_head_journal_path(root_dir)
	if !os.exists(path) {
		return
	}
	data := os.read_bytes(path)!
	mut cursor := 0
	for cursor < data.len {
		if cursor + 8 > data.len {
			break
		}
		if data[cursor..cursor + 4].bytestr() != repository_branch_head_journal_magic {
			if cursor == 0 {
				os.rm(path) or {}
				return
			}
			break
		}
		version := u32(data[cursor + 4]) | (u32(data[cursor + 5]) << 8) | (u32(data[cursor + 6]) << 16) | (u32(data[
			cursor + 7]) << 24)
		if version != repository_branch_head_journal_version {
			if cursor == 0 {
				os.rm(path) or {}
				return
			}
			break
		}
		mut reader := RepositoryReader{
			data: data[cursor + 8..]
		}
		branch_name := reader.read_field() or { break }.bytestr()
		_ = reader.read_field() or { break }
		new_commit_cid := reader.read_field() or { break }.bytestr()
		repo.branches[branch_name] = new_commit_cid
		cursor += 8 + reader.cursor
	}
}

fn replay_checkpoint_journal_records(mut store ChunkStore, records []u8) ! {
	if records.len == 0 {
		return
	}
	mut cursor := 0
	for cursor < records.len {
		if cursor + 8 > records.len {
			break
		}
		cid_len := int(chunk_store_read_u32_le(records[cursor..cursor + 4]))
		data_len := int(chunk_store_read_u32_le(records[cursor + 4..cursor + 8]))
		record_len := 8 + cid_len + data_len
		if cursor + record_len > records.len {
			break
		}
		cid := records[cursor + 8..cursor + 8 + cid_len]
		if !store.has(cid) {
			_ = store.file.write(records[cursor..cursor + record_len])!
			entry := ChunkStoreEntry{
				offset: store.write_offset
				length: data_len
			}
			store.write_offset += u64(record_len)
			store.data_dirty = true
			if store.maintain_index {
				store.index_add(cid, entry)
				store.index_dirty = true
			}
		}
		cursor += record_len
	}
}

fn repository_layout_dir(root_dir string) string {
	return os.join_path(root_dir, '.pollydb')
}

fn repository_metadata_path(root_dir string) string {
	return os.join_path(repository_layout_dir(root_dir), 'repo.meta')
}

fn repository_nodes_path(root_dir string) string {
	return os.join_path(repository_layout_dir(root_dir), 'nodes.chunk')
}

fn repository_commits_path(root_dir string) string {
	return os.join_path(repository_layout_dir(root_dir), 'commits.chunk')
}

fn repository_checkpoint_journal_path(root_dir string) string {
	return os.join_path(repository_layout_dir(root_dir), 'checkpoint.journal')
}

fn repository_branch_head_journal_path(root_dir string) string {
	return os.join_path(repository_layout_dir(root_dir), 'branch_heads.journal')
}

fn repository_root_dir_from_metadata_path(path string) string {
	return os.dir(os.dir(path))
}

const repository_checkpoint_journal_magic = 'pdj1'
const repository_checkpoint_journal_version = u32(1)
const repository_checkpoint_journal_version2 = u32(2)
const repository_branch_head_journal_magic = 'pbh1'
const repository_branch_head_journal_version = u32(1)

fn (mut reader RepositoryReader) read_u32() !u32 {
	if reader.cursor + 4 > reader.data.len {
		return error('repository metadata truncated')
	}
	value := u32(reader.data[reader.cursor]) | (u32(reader.data[reader.cursor + 1]) << 8) | (u32(reader.data[
		reader.cursor + 2]) << 16) | (u32(reader.data[reader.cursor + 3]) << 24)
	reader.cursor += 4
	return value
}

fn (mut reader RepositoryReader) read_field() ![]u8 {
	length := int(reader.read_u32()!)
	if reader.cursor + length > reader.data.len {
		return error('repository metadata field truncated')
	}
	field := reader.data[reader.cursor..reader.cursor + length].clone()
	reader.cursor += length
	return field
}

pub fn Repository.new(default_branch string) Repository {
	return Repository{
		default_branch: default_branch
		branches:       map[string]string{}
	}
}

pub fn PersistentRepository.open(path string, node_store_path string, commit_store_path string, default_branch string) !PersistentRepository {
	return (PersistentRepository.open_profiled(path, node_store_path, commit_store_path,
		default_branch)!).repository
}

pub fn PersistentRepository.open_profiled(path string, node_store_path string, commit_store_path string, default_branch string) !PersistentRepositoryOpenResult {
	mut total_sw := time.new_stopwatch()
	mut meta_sw := time.new_stopwatch()
	mut repo := if os.exists(path) {
		Repository.open(path)!
	} else {
		Repository.new(default_branch)
	}
	root_dir := repository_root_dir_from_metadata_path(path)
	checkpoint_journal_bytes := checkpoint_journal_size(root_dir)
	branch_head_journal_bytes := branch_head_journal_size(root_dir)
	branch_head_journal_exists := branch_head_journal_bytes > 0
	replay_branch_head_journal(root_dir, mut repo)!
	repository_meta_ms := meta_sw.elapsed().milliseconds()
	mut node_sw := time.new_stopwatch()
	node_store := PersistentNodeStore.open_high_throughput(node_store_path)!
	node_store_ms := node_sw.elapsed().milliseconds()
	mut commit_sw := time.new_stopwatch()
	commit_store := PersistentCommitStore.open_high_throughput(commit_store_path)!
	commit_store_ms := commit_sw.elapsed().milliseconds()
	repository := PersistentRepository{
		path:                      path
		node_store_path:           node_store_path
		commit_store_path:         commit_store_path
		repo:                      repo
		node_store:                node_store
		commit_store:              commit_store
		meta_dirty:                branch_head_journal_exists
		checkpoint_journal_bytes:  checkpoint_journal_bytes
		branch_head_journal_bytes: branch_head_journal_bytes
	}
	return PersistentRepositoryOpenResult{
		repository: repository
		timings:    PersistentRepositoryOpenTimings{
			repository_meta_ms: repository_meta_ms
			node_store_ms:      node_store_ms
			commit_store_ms:    commit_store_ms
			total_ms:           total_sw.elapsed().milliseconds()
		}
	}
}

pub fn PersistentRepository.init(dir string, default_branch string) !PersistentRepository {
	os.mkdir_all(repository_layout_dir(dir))!
	mut persistent := PersistentRepository.open_default(dir, default_branch)!
	persistent.meta_dirty = true
	persistent.persist()!
	return persistent
}

pub fn PersistentRepository.open_default(dir string, default_branch string) !PersistentRepository {
	return (PersistentRepository.open_default_profiled(dir, default_branch)!).repository
}

pub fn PersistentRepository.open_default_profiled(dir string, default_branch string) !PersistentRepositoryOpenResult {
	os.mkdir_all(repository_layout_dir(dir))!
	mut replay_sw := time.new_stopwatch()
	replay_checkpoint_journal(dir)!
	replay_journal_ms := replay_sw.elapsed().milliseconds()
	result := PersistentRepository.open_profiled(repository_metadata_path(dir),
		repository_nodes_path(dir), repository_commits_path(dir), default_branch)!
	return PersistentRepositoryOpenResult{
		repository: result.repository
		timings:    PersistentRepositoryOpenTimings{
			replay_journal_ms:  replay_journal_ms
			repository_meta_ms: result.timings.repository_meta_ms
			node_store_ms:      result.timings.node_store_ms
			commit_store_ms:    result.timings.commit_store_ms
			total_ms:           replay_journal_ms + result.timings.total_ms
		}
	}
}

pub fn Repository.open(path string) !Repository {
	data := os.read_bytes(path) or {
		if !os.exists(path) {
			return error('repository metadata not found: ${path}')
		}
		return err
	}
	return Repository.from_data(data)
}

pub fn (repo Repository) persist(path string) ! {
	tmp_path := '${path}.tmp.${os.getpid()}.${time.now().unix_micro()}.${rand.u64()}'
	mut tmp_file := os.open_file(tmp_path, 'wb', 0o666)!
	defer {
		tmp_file.close()
	}
	data := repo.data()
	tmp_file.write(data)!
	tmp_file.flush()
	$if darwin {
		chunk_store_fsync_fd(tmp_file.fd)!
	}
	os.mv(tmp_path, path) or {
		os.rm(tmp_path) or {}
		return err
	}
}

pub fn (repo Repository) data() []u8 {
	mut out := []u8{}
	repository_append_field(mut out, repo.default_branch.bytes())
	mut names := repo.branches.keys()
	names.sort()
	repository_append_u32(mut out, u32(names.len))
	for name in names {
		repository_append_field(mut out, name.bytes())
		repository_append_field(mut out, (repo.branches[name] or { '' }).bytes())
	}
	return out
}

pub fn Repository.from_data(data []u8) !Repository {
	mut reader := RepositoryReader{
		data: data
	}
	default_branch := reader.read_field()!.bytestr()
	branch_count := int(reader.read_u32()!)
	mut branches := map[string]string{}
	for _ in 0 .. branch_count {
		name := reader.read_field()!.bytestr()
		commit_cid := reader.read_field()!.bytestr()
		branches[name] = commit_cid
	}
	if reader.cursor != data.len {
		return error('repository metadata has trailing bytes')
	}
	return Repository{
		default_branch: default_branch
		branches:       branches
	}
}

pub fn ConflictResolution.use_ours(key []u8) ConflictResolution {
	return ConflictResolution{
		key:      key.clone()
		strategy: .ours
		value:    []u8{}
	}
}

pub fn ConflictResolution.use_theirs(key []u8) ConflictResolution {
	return ConflictResolution{
		key:      key.clone()
		strategy: .theirs
		value:    []u8{}
	}
}

pub fn ConflictResolution.use_manual(key []u8, value []u8) ConflictResolution {
	return ConflictResolution{
		key:      key.clone()
		strategy: .manual
		value:    value.clone()
	}
}

pub fn ConflictResolution.delete_key(key []u8) ConflictResolution {
	return ConflictResolution{
		key:      key.clone()
		strategy: .delete
		value:    []u8{}
	}
}

pub fn (repo Repository) has_branch(name string) bool {
	return name in repo.branches
}

pub fn (repo Repository) branch(name string) !Branch {
	commit_cid := repo.branches[name] or { return error('branch not found: ${name}') }
	return Branch{
		name:       name
		commit_cid: commit_cid
	}
}

pub fn (repo Repository) head() !Branch {
	return repo.branch(repo.default_branch)
}

pub fn (repo Repository) branch_names() []string {
	mut names := repo.branches.keys()
	names.sort()
	return names
}

pub fn (repo Repository) branch_names_committed() []string {
	mut names := repo.branches.keys().filter(repo.branches[it] or { '' }.len > 0)
	names.sort()
	return names
}

pub fn (mut repo Repository) create_branch(name string, from_commit_cid string) !Branch {
	if name.len == 0 {
		return error('branch name cannot be empty')
	}
	if repo.has_branch(name) {
		return error('branch already exists: ${name}')
	}
	repo.branches[name] = from_commit_cid
	return Branch{
		name:       name
		commit_cid: from_commit_cid
	}
}

pub fn (mut repo Repository) set_branch_head(name string, commit_cid string) !Branch {
	if !repo.has_branch(name) {
		return error('branch not found: ${name}')
	}
	repo.branches[name] = commit_cid
	return Branch{
		name:       name
		commit_cid: commit_cid
	}
}

pub fn (mut repo Repository) commit_to_branch(branch_name string, tree Tree, meta CommitMeta, mut node_store NodeStore, mut commit_store CommitStore) !BranchUpdate {
	parent_cids := repo.parent_cids_for_branch(branch_name)
	snapshot := Snapshot.new(tree, parent_cids, meta)
	return repo.commit_snapshot_to_branch(branch_name, snapshot, mut node_store, mut commit_store)
}

pub fn (mut repo Repository) commit_snapshot_to_branch(branch_name string, snapshot Snapshot, mut node_store NodeStore, mut commit_store CommitStore) !BranchUpdate {
	snapshot.persist(mut node_store, mut commit_store)!
	branch := if repo.has_branch(branch_name) {
		repo.set_branch_head(branch_name, snapshot.commit.cid)!
	} else {
		repo.create_branch(branch_name, snapshot.commit.cid)!
	}
	return BranchUpdate{
		branch:   branch
		snapshot: snapshot
	}
}

pub fn (repo Repository) parent_cids_for_branch(branch_name string) []string {
	if !repo.has_branch(branch_name) {
		return []string{}
	}
	parent := repo.branches[branch_name]
	if parent.len == 0 {
		return []string{}
	}
	return [parent]
}

pub fn (mut persistent PersistentRepository) close() ! {
	persistent.checkpoint() or {}
	persistent.node_store.close()
	persistent.commit_store.close()
}

fn (mut persistent PersistentRepository) persist_pending_records_to_journal() ! {
	write_checkpoint_journal(repository_root_dir_from_metadata_path(persistent.path),
		persistent.node_store.pending_journal_records(),
		persistent.commit_store.pending_journal_records())!
	persistent.node_store.mark_journal_records_persisted()
	persistent.commit_store.mark_journal_records_persisted()
	persistent.checkpoint_journal_bytes =
		checkpoint_journal_size(repository_root_dir_from_metadata_path(persistent.path))
}

fn (mut persistent PersistentRepository) persist_pending_records_and_branch_to_journal(branch_name string, old_commit_cid string, new_commit_cid string) ! {
	write_checkpoint_journal_with_branch(repository_root_dir_from_metadata_path(persistent.path),
		persistent.node_store.pending_journal_records(),
		persistent.commit_store.pending_journal_records(), branch_name, old_commit_cid,
		new_commit_cid)!
	persistent.node_store.mark_journal_records_persisted()
	persistent.commit_store.mark_journal_records_persisted()
	root_dir := repository_root_dir_from_metadata_path(persistent.path)
	persistent.checkpoint_journal_bytes = checkpoint_journal_size(root_dir)
	persistent.branch_head_journal_bytes = branch_head_journal_size(root_dir)
}

fn fsync_repository_meta(path string) ! {
	$if darwin {
		mut repo_file := os.open_file(path, 'rb', 0o666)!
		defer {
			repo_file.close()
		}
		repo_file.flush()
		chunk_store_fsync_fd(repo_file.fd)!
	}
}

fn (mut persistent PersistentRepository) mark_branch_head_journal_written() {
	persistent.branch_head_journal_bytes =
		branch_head_journal_size(repository_root_dir_from_metadata_path(persistent.path))
}

fn (mut persistent PersistentRepository) remove_branch_head_journal_if_unchanged() {
	root_dir := repository_root_dir_from_metadata_path(persistent.path)
	if branch_head_journal_size(root_dir) != persistent.branch_head_journal_bytes {
		return
	}
	os.rm(repository_branch_head_journal_path(root_dir)) or {}
	persistent.branch_head_journal_bytes = 0
}

fn (mut persistent PersistentRepository) remove_checkpoint_journal_if_unchanged() {
	root_dir := repository_root_dir_from_metadata_path(persistent.path)
	if checkpoint_journal_size(root_dir) != persistent.checkpoint_journal_bytes {
		return
	}
	os.rm(repository_checkpoint_journal_path(root_dir)) or {}
	persistent.checkpoint_journal_bytes = 0
}

fn (mut persistent PersistentRepository) write_branch_head_journal(branch_name string, old_commit_cid string, new_commit_cid string) ! {
	write_branch_head_journal(repository_root_dir_from_metadata_path(persistent.path), branch_name,
		old_commit_cid, new_commit_cid)!
	persistent.mark_branch_head_journal_written()
}

pub fn (mut persistent PersistentRepository) checkpoint() ! {
	persistent.node_store.checkpoint()!
	persistent.commit_store.checkpoint()!
	if persistent.meta_dirty {
		persistent.repo.persist(persistent.path)!
		fsync_repository_meta(persistent.path)!
		persistent.meta_dirty = false
	}
	persistent.node_store.clear_journal_records()
	persistent.commit_store.clear_journal_records()
	persistent.remove_checkpoint_journal_if_unchanged()
	persistent.remove_branch_head_journal_if_unchanged()
}

pub fn (mut persistent PersistentRepository) refresh_index_snapshots() ! {
	persistent.node_store.refresh_index_snapshot()!
	persistent.commit_store.refresh_index_snapshot()!
	persistent.node_store.clear_journal_records()
	persistent.commit_store.clear_journal_records()
	persistent.remove_checkpoint_journal_if_unchanged()
}

pub fn (mut persistent PersistentRepository) checkpoint_mode(mode CheckpointMode) ! {
	match mode {
		.full {
			persistent.node_store.checkpoint_mode(mode)!
			persistent.commit_store.checkpoint_mode(mode)!
			if persistent.meta_dirty {
				persistent.repo.persist(persistent.path)!
				fsync_repository_meta(persistent.path)!
				persistent.meta_dirty = false
			}
			persistent.node_store.clear_journal_records()
			persistent.commit_store.clear_journal_records()
			persistent.remove_checkpoint_journal_if_unchanged()
			persistent.remove_branch_head_journal_if_unchanged()
		}
		.data_only {
			persistent.persist_pending_records_to_journal()!
		}
	}
}

pub fn (mut persistent PersistentRepository) checkpoint_timed() !PersistentRepositoryCheckpointTimings {
	mut total_sw := time.new_stopwatch()
	mut repo_meta_us := i64(0)
	node_store_timings := persistent.node_store.checkpoint_timed()!
	commit_store_timings := persistent.commit_store.checkpoint_timed()!
	if persistent.meta_dirty {
		mut sw := time.new_stopwatch()
		persistent.repo.persist(persistent.path)!
		fsync_repository_meta(persistent.path)!
		persistent.meta_dirty = false
		repo_meta_us = sw.elapsed().microseconds()
	}
	persistent.remove_branch_head_journal_if_unchanged()
	return PersistentRepositoryCheckpointTimings{
		repo_meta_us:          repo_meta_us
		node_store_data_us:    node_store_timings.data_us
		node_store_index_us:   node_store_timings.index_us
		node_store_us:         node_store_timings.total_us
		commit_store_data_us:  commit_store_timings.data_us
		commit_store_index_us: commit_store_timings.index_us
		commit_store_us:       commit_store_timings.total_us
		total_us:              total_sw.elapsed().microseconds()
	}
}

pub fn (mut persistent PersistentRepository) checkpoint_timed_mode(mode CheckpointMode) !PersistentRepositoryCheckpointTimings {
	mut total_sw := time.new_stopwatch()
	mut repo_meta_us := i64(0)
	match mode {
		.full {
			node_store_timings := persistent.node_store.checkpoint_timed_mode(mode)!
			commit_store_timings := persistent.commit_store.checkpoint_timed_mode(mode)!
			if persistent.meta_dirty {
				mut sw := time.new_stopwatch()
				persistent.repo.persist(persistent.path)!
				fsync_repository_meta(persistent.path)!
				persistent.meta_dirty = false
				repo_meta_us = sw.elapsed().microseconds()
			}
			persistent.remove_branch_head_journal_if_unchanged()
			return PersistentRepositoryCheckpointTimings{
				repo_meta_us:          repo_meta_us
				node_store_data_us:    node_store_timings.data_us
				node_store_index_us:   node_store_timings.index_us
				node_store_us:         node_store_timings.total_us
				commit_store_data_us:  commit_store_timings.data_us
				commit_store_index_us: commit_store_timings.index_us
				commit_store_us:       commit_store_timings.total_us
				total_us:              total_sw.elapsed().microseconds()
			}
		}
		.data_only {
			mut journal_sw := time.new_stopwatch()
			persistent.persist_pending_records_to_journal()!
			journal_us := journal_sw.elapsed().microseconds()
			return PersistentRepositoryCheckpointTimings{
				repo_meta_us:          repo_meta_us
				node_store_data_us:    0
				node_store_index_us:   0
				node_store_us:         0
				commit_store_data_us:  0
				commit_store_index_us: 0
				commit_store_us:       0
				total_us:              repo_meta_us + journal_us
			}
		}
	}
}

pub fn (persistent PersistentRepository) checkpoint_info() PersistentRepositoryCheckpointInfo {
	return PersistentRepositoryCheckpointInfo{
		metadata_path:     persistent.path
		node_store:        persistent.node_store.checkpoint_info()
		commit_store:      persistent.commit_store.checkpoint_info()
		repository_exists: os.exists(persistent.path)
	}
}

pub fn PersistentRepository.recovery_status(root_dir string) !PersistentRepositoryRecoveryStatus {
	return PersistentRepositoryRecoveryStatus{
		metadata_path:             repository_metadata_path(root_dir)
		repository_exists:         os.exists(repository_metadata_path(root_dir))
		checkpoint_journal_exists: os.exists(repository_checkpoint_journal_path(root_dir))
		node_store:                PersistentNodeStore.recovery_status(repository_nodes_path(root_dir))!
		commit_store:              PersistentCommitStore.recovery_status(repository_commits_path(root_dir))!
	}
}

pub fn (mut persistent PersistentRepository) close_without_checkpoint() {
	persistent.node_store.close_without_checkpoint()
	persistent.commit_store.close_without_checkpoint()
}

pub fn (persistent PersistentRepository) repository() Repository {
	return persistent.repo
}

pub fn (mut persistent PersistentRepository) persist() ! {
	if !persistent.meta_dirty {
		return
	}
	persistent.persist_pending_records_to_journal()!
	persistent.repo.persist(persistent.path)!
	fsync_repository_meta(persistent.path)!
	persistent.meta_dirty = false
	persistent.remove_branch_head_journal_if_unchanged()
}

pub fn (mut persistent PersistentRepository) has_branch(name string) bool {
	return persistent.repo.has_branch(name)
}

pub fn (mut persistent PersistentRepository) head() !Branch {
	return persistent.repo.head()
}

pub fn (mut persistent PersistentRepository) branch(name string) !Branch {
	return persistent.repo.branch(name)
}

pub fn (mut persistent PersistentRepository) branch_names() []string {
	return persistent.repo.branch_names()
}

pub fn (mut persistent PersistentRepository) branch_names_committed() []string {
	return persistent.repo.branch_names_committed()
}

pub fn (mut persistent PersistentRepository) create_branch(name string, from_commit_cid string) !Branch {
	if persistent.repo.has_branch(name) {
		return error('branch already exists: ${name}')
	}
	return persistent.compare_and_swap_branch_head(name, '', from_commit_cid)
}

pub fn (mut persistent PersistentRepository) compare_and_swap_branch_head(name string, old_commit_cid string, new_commit_cid string) !Branch {
	memory_current := persistent.repo.branch(name) or {
		if old_commit_cid.len > 0 {
			Branch{}
		} else {
			persistent.repo.branches[name] = new_commit_cid
			persistent.persist_pending_records_and_branch_to_journal(name, old_commit_cid,
				new_commit_cid)!
			persistent.meta_dirty = true
			return persistent.repo.branch(name)
		}
	}
	if memory_current.name.len > 0 && memory_current.commit_cid == old_commit_cid {
		persistent.repo.branches[name] = new_commit_cid
		persistent.persist_pending_records_and_branch_to_journal(name, old_commit_cid,
			new_commit_cid)!
		persistent.meta_dirty = true
		return persistent.repo.branch(name)
	}
	persistent.persist_pending_records_to_journal()!
	mut repo := if os.exists(persistent.path) {
		Repository.open(persistent.path)!
	} else {
		Repository.new(persistent.repo.default_branch)
	}
	replay_branch_head_journal(repository_root_dir_from_metadata_path(persistent.path), mut repo)!
	current := repo.branch(name) or {
		if old_commit_cid.len > 0 {
			return error('branch head missing during compare-and-swap: ${name} expected=${old_commit_cid} new=${new_commit_cid}')
		}
		repo.branches[name] = new_commit_cid
		persistent.persist_pending_records_and_branch_to_journal(name, old_commit_cid,
			new_commit_cid)!
		persistent.repo = repo
		persistent.meta_dirty = true
		return persistent.repo.branch(name)
	}
	if current.commit_cid != old_commit_cid {
		return error('branch head changed during compare-and-swap: ${name} expected=${old_commit_cid} current=${current.commit_cid} new=${new_commit_cid}')
	}
	repo.branches[name] = new_commit_cid
	persistent.persist_pending_records_and_branch_to_journal(name, old_commit_cid, new_commit_cid)!
	persistent.repo = repo
	persistent.meta_dirty = true
	return persistent.repo.branch(name)
}

pub fn (mut persistent PersistentRepository) commit_to_branch(branch_name string, tree Tree, meta CommitMeta) !BranchUpdate {
	old_commit_cid := if persistent.repo.has_branch(branch_name) {
		(persistent.repo.branch(branch_name)!).commit_cid
	} else {
		''
	}
	update := persistent.repo.commit_to_branch(branch_name, tree, meta, mut persistent.node_store, mut
		persistent.commit_store)!
	persistent.persist_pending_records_and_branch_to_journal(branch_name, old_commit_cid,
		update.branch.commit_cid)!
	persistent.meta_dirty = true
	return update
}

pub fn (mut persistent PersistentRepository) tree_at_branch(branch_name string) !Tree {
	return persistent.repo.tree_at_branch(branch_name, mut persistent.node_store, mut
		persistent.commit_store)
}

pub fn (mut persistent PersistentRepository) checkout(branch_name string) !Commit {
	return persistent.repo.checkout(branch_name, mut persistent.commit_store)
}

pub fn (repo Repository) checkout(branch_name string, mut commit_store CommitStore) !Commit {
	branch := repo.branch(branch_name)!
	if branch.commit_cid.len == 0 {
		return Commit{
			cid:           ''
			root_cid:      ''
			parent_cids:   []string{}
			meta:          CommitMeta{}
			virtual_roots: []VirtualRootRef{}
		}
	}
	return commit_store.get(branch.commit_cid)!
}

pub fn (repo Repository) tree_at_branch(branch_name string, mut node_store NodeStore, mut commit_store CommitStore) !Tree {
	commit := repo.checkout(branch_name, mut commit_store)!
	if commit.root_cid.len == 0 {
		return Tree{}
	}
	return Tree.load(commit.root_cid, mut node_store)
}

pub fn (mut repo Repository) apply_mutations_to_branch(branch_name string, mutations []Mutation, cfg ChunkConfig, meta CommitMeta, mut node_store NodeStore, mut commit_store CommitStore) !BranchMutationResult {
	base_tree := repo.tree_at_branch(branch_name, mut node_store, mut commit_store)!
	tree_update := base_tree.apply_mutations(mutations, cfg)!
	update := repo.commit_to_branch(branch_name, tree_update.tree, meta, mut node_store, mut
		commit_store)!
	return BranchMutationResult{
		update:      update
		tree_update: tree_update
	}
}

pub fn (repo Repository) transaction_at_branch(branch_name string, specs []TableSpec, mut node_store NodeStore, mut commit_store CommitStore) !Transaction {
	tree := repo.tree_at_branch(branch_name, mut node_store, mut commit_store)!
	return new_transaction_with_specs(tree, specs)
}

pub fn (mut repo Repository) apply_write_set_to_branch(branch_name string, specs []TableSpec, write_set WriteSet, cfg ChunkConfig, meta CommitMeta, mut node_store NodeStore, mut commit_store CommitStore) !BranchTransactionResult {
	tx := repo.transaction_at_branch(branch_name, specs, mut node_store, mut commit_store)!
	transaction_update := tx.apply_write_set(write_set, cfg)!
	update := repo.commit_to_branch(branch_name, transaction_update.tx.current_tree(), meta, mut
		node_store, mut commit_store)!
	return BranchTransactionResult{
		update:             update
		transaction_update: transaction_update
	}
}

pub fn (repo Repository) typed_transaction_at_branch(branch_name string, specs []TypedTableSpec, mut node_store NodeStore, mut commit_store CommitStore) !TypedTransaction {
	return (repo.typed_transaction_at_branch_profiled(branch_name, specs, mut node_store, mut
		commit_store)!).tx
}

pub fn (repo Repository) typed_transaction_at_branch_profiled(branch_name string, specs []TypedTableSpec, mut node_store NodeStore, mut commit_store CommitStore) !TypedTransactionOpenResult {
	mut total_sw := time.new_stopwatch()
	mut checkout_sw := time.new_stopwatch()
	commit := repo.checkout(branch_name, mut commit_store)!
	checkout_ms := checkout_sw.elapsed().milliseconds()
	mut tree_sw := time.new_stopwatch()
	tree := if commit.root_cid.len == 0 {
		Tree{}
	} else {
		Tree.load(commit.root_cid, mut node_store)!
	}
	tree_load_ms := tree_sw.elapsed().milliseconds()
	mut wrap_sw := time.new_stopwatch()
	tx_tree := if split_tx := typed_split_transaction_from_commit(tree, commit, specs,
		ChunkConfig.default(), mut node_store)
	{
		split_tx.materialize_mixed_tree(ChunkConfig.default())!
	} else {
		tree
	}
	tx := new_typed_transaction_with_specs(tx_tree, specs)!
	wrap_ms := wrap_sw.elapsed().milliseconds()
	return TypedTransactionOpenResult{
		tx:      tx
		timings: TypedTransactionOpenTimings{
			checkout_ms:  checkout_ms
			tree_load_ms: tree_load_ms
			wrap_ms:      wrap_ms
			total_ms:     total_sw.elapsed().milliseconds()
		}
	}
}

pub fn (mut repo Repository) apply_typed_write_set_to_branch(branch_name string, specs []TypedTableSpec, write_set TypedWriteSet, cfg ChunkConfig, meta CommitMeta, mut node_store NodeStore, mut commit_store CommitStore) !BranchTypedTransactionResult {
	tx := repo.typed_transaction_at_branch(branch_name, specs, mut node_store, mut commit_store)!
	mut sw := time.new_stopwatch()
	transaction_update := tx.apply_write_set(write_set, cfg)!
	tx_apply_us := sw.elapsed().microseconds()
	snapshot := Snapshot.new(transaction_update.tx.current_tree(),
		repo.parent_cids_for_branch(branch_name), meta)
	sw.restart()
	snapshot.persist(mut node_store, mut commit_store)!
	snapshot_persist_us := sw.elapsed().microseconds()
	sw.restart()
	branch := if repo.has_branch(branch_name) {
		repo.set_branch_head(branch_name, snapshot.commit.cid)!
	} else {
		repo.create_branch(branch_name, snapshot.commit.cid)!
	}
	branch_head_us := sw.elapsed().microseconds()
	return BranchTypedTransactionResult{
		update:             BranchUpdate{
			branch:   branch
			snapshot: snapshot
		}
		transaction_update: transaction_update
		timings:            BranchTypedTransactionTimings{
			tx_apply_us:          tx_apply_us
			snapshot_persist_us:  snapshot_persist_us
			branch_head_us:       branch_head_us
			repo_meta_persist_us: 0
		}
	}
}

pub fn (repo Repository) working_set_at_branch(branch_name string, specs []TableSpec, mut node_store NodeStore, mut commit_store CommitStore) !WorkingSet {
	commit := repo.checkout(branch_name, mut commit_store)!
	tree := if commit.root_cid.len == 0 {
		Tree{}
	} else {
		Tree.load(commit.root_cid, mut node_store)!
	}
	return WorkingSet.new(branch_name, commit.cid, tree, specs)
}

pub fn (repo Repository) typed_working_set_at_branch(branch_name string, specs []TypedTableSpec, mut node_store NodeStore, mut commit_store CommitStore) !TypedWorkingSet {
	commit := repo.checkout(branch_name, mut commit_store)!
	tree := if commit.root_cid.len == 0 {
		Tree{}
	} else {
		Tree.load(commit.root_cid, mut node_store)!
	}
	return TypedWorkingSet.new(branch_name, commit.cid, tree, specs)
}

pub fn (repo Repository) typed_split_working_set_at_branch(branch_name string, specs []TypedTableSpec, cfg ChunkConfig, mut node_store NodeStore, mut commit_store CommitStore) !TypedSplitWorkingSet {
	commit := repo.checkout(branch_name, mut commit_store)!
	tree := if commit.root_cid.len == 0 {
		Tree{}
	} else {
		Tree.load(commit.root_cid, mut node_store)!
	}
	if split_tx := typed_split_transaction_from_commit(tree, commit, specs, cfg, mut node_store) {
		return TypedSplitWorkingSet{
			branch_name:     branch_name
			base_commit_cid: commit.cid
			base_tree:       tree
			tx:              split_tx
			specs:           specs.clone()
		}
	}
	return TypedSplitWorkingSet.new(branch_name, commit.cid, tree, specs, cfg)
}

fn typed_split_transaction_from_commit(root_tree Tree, commit Commit, specs []TypedTableSpec, cfg ChunkConfig, mut node_store NodeStore) ?TypedSplitTransaction {
	mut root_by_name := map[string]string{}
	for virtual_root in commit.virtual_roots {
		if virtual_root.name.starts_with('typed_split:') && virtual_root.fresh {
			root_by_name[virtual_root.name] = virtual_root.root_cid
		}
	}
	if root_by_name.len == 0 {
		return none
	}
	mut tx := TypedSplitTransaction{
		tables: map[string]SplitTableView{}
		specs:  map[string]TypedTableSpec{}
	}
	for spec in specs {
		rows_root_name := typed_split_rows_virtual_root_name(spec.table.name)
		rows_root_cid := root_by_name[rows_root_name] or { return none }
		rows_tree := if rows_root_cid.len == 0 {
			Tree{}
		} else if rows_root_cid == commit.root_cid {
			root_tree
		} else {
			Tree.load(rows_root_cid, mut node_store) or { return none }
		}
		mut index_trees := map[string]Tree{}
		for index_name in spec.index_names() {
			index_root_name := typed_split_index_virtual_root_name(spec.table.name, index_name)
			index_root_cid := root_by_name[index_root_name] or { return none }
			index_trees[index_name] = if index_root_cid.len == 0 {
				Tree{}
			} else {
				Tree.load(index_root_cid, mut node_store) or { return none }
			}
		}
		tx.specs[spec.table.name] = spec
		tx.tables[spec.table.name] = SplitTableView.new(spec.table.name, rows_tree, index_trees)
	}
	_ = root_tree
	_ = cfg
	return tx
}

pub fn (mut repo Repository) commit_working_set(mut set WorkingSet, meta CommitMeta, mut node_store NodeStore, mut commit_store CommitStore) !BranchTransactionResult {
	transaction_update := TransactionResult{
		tx:   set.transaction()
		diff: set.staged_diff()
	}
	update := repo.commit_to_branch(set.branch_name, set.transaction().current_tree(), meta, mut
		node_store, mut commit_store)!
	set.sync_to_tree(update.snapshot.tree, update.snapshot.commit.cid)!
	return BranchTransactionResult{
		update:             update
		transaction_update: transaction_update
	}
}

pub fn (mut repo Repository) commit_typed_working_set(mut set TypedWorkingSet, meta CommitMeta, mut node_store NodeStore, mut commit_store CommitStore) !BranchTypedWorkingSetResult {
	transaction_update := TypedTransactionResult{
		tx:   set.transaction()
		diff: set.staged_diff()
	}
	update := repo.commit_to_branch(set.branch_name, set.transaction().current_tree(), meta, mut
		node_store, mut commit_store)!
	set.sync_to_tree(update.snapshot.tree, update.snapshot.commit.cid)!
	return BranchTypedWorkingSetResult{
		update:             update
		transaction_update: transaction_update
	}
}

pub fn (mut repo Repository) commit_typed_split_working_set(mut set TypedSplitWorkingSet, meta CommitMeta, cfg ChunkConfig, mut node_store NodeStore, mut commit_store CommitStore) !BranchTypedWorkingSetResult {
	data_tree := set.transaction().rows_tree(cfg)!
	virtual_roots := set.transaction().split_virtual_roots(data_tree.root.cid)
	mixed_tree := if cfg.enable_write_diff { set.current_tree(cfg)! } else { data_tree }
	mixed_tx := new_typed_transaction_with_specs(mixed_tree, set.specs)!
	transaction_update := TypedTransactionResult{
		tx:   mixed_tx
		diff: set.base_tree.diff_for_write(mixed_tree, cfg)
	}
	parent_cids := repo.parent_cids_for_branch(set.branch_name)
	snapshot := Snapshot.new_with_virtual_roots(data_tree, parent_cids, meta, virtual_roots)
	set.transaction().persist_split_roots(mut node_store)!
	update := repo.commit_snapshot_to_branch(set.branch_name, snapshot, mut node_store, mut
		commit_store)!
	set.base_tree = update.snapshot.tree
	set.base_commit_cid = update.snapshot.commit.cid
	return BranchTypedWorkingSetResult{
		update:             update
		transaction_update: TypedTransactionResult{
			tx:   mixed_tx
			diff: transaction_update.diff
		}
	}
}

pub fn (repo Repository) merge_branch_into_working_set(mut set WorkingSet, theirs_branch string, resolutions []ConflictResolution, cfg ChunkConfig, mut node_store NodeStore, mut commit_store CommitStore) !WorkingSetMergeResult {
	base_commit := repo.merge_base_commit(set.base_commit_cid,
		(repo.branch(theirs_branch)!).commit_cid, mut commit_store)!
	ours_commit := commit_store.get(set.base_commit_cid)!
	theirs_commit := repo.checkout(theirs_branch, mut commit_store)!
	base_tree := Tree.load(base_commit.root_cid, mut node_store)!
	ours_tree := set.transaction().current_tree()
	theirs_tree := Tree.load(theirs_commit.root_cid, mut node_store)!
	merge_result := three_way_merge(base_commit, ours_commit, theirs_commit, base_tree, ours_tree,
		theirs_tree, cfg)!
	resolution := merge_result.resolve_conflicts(resolutions, cfg)!
	set.replace_working_tree(resolution.tree)!
	return WorkingSetMergeResult{
		merge_result: merge_result
		resolution:   resolution
		staged_diff:  set.staged_diff()
	}
}

pub fn (repo Repository) typed_merge_branch_into_working_set(mut set TypedWorkingSet, theirs_branch string, resolutions []ConflictResolution, cfg ChunkConfig, mut node_store NodeStore, mut commit_store CommitStore) !WorkingSetMergeResult {
	base_commit := repo.merge_base_commit(set.base_commit_cid,
		(repo.branch(theirs_branch)!).commit_cid, mut commit_store)!
	ours_commit := commit_store.get(set.base_commit_cid)!
	theirs_commit := repo.checkout(theirs_branch, mut commit_store)!
	base_tree := Tree.load(base_commit.root_cid, mut node_store)!
	ours_tree := set.transaction().current_tree()
	theirs_tree := Tree.load(theirs_commit.root_cid, mut node_store)!
	merge_progress_log('   -> merge stage: three_way_merge')
	mut merge_sw := time.new_stopwatch()
	merge_result := three_way_merge(base_commit, ours_commit, theirs_commit, base_tree, ours_tree,
		theirs_tree, cfg)!
	merge_ms := merge_sw.elapsed().milliseconds()
	merge_progress_log('   -> merge stage done: three_way_merge (${merge_ms} ms, changed_keys=${merge_result.changed_keys.len}, changed_subtrees=${merge_result.changed_subtrees.len}, conflicts=${merge_result.conflicts.len})')
	merge_progress_log('   -> merge stage: resolve_conflicts')
	mut resolve_sw := time.new_stopwatch()
	resolution := merge_result.resolve_conflicts(resolutions, cfg)!
	resolve_ms := resolve_sw.elapsed().milliseconds()
	merge_progress_log('   -> merge stage done: resolve_conflicts (${resolve_ms} ms, resolved_keys=${resolution.resolved_keys.len})')
	merge_progress_log('   -> merge stage: exact_changed_rows')
	mut changed_rows_sw := time.new_stopwatch()
	changed_rows := collect_changed_typed_rows_exact(set.specs, base_tree, resolution.tree)!
	changed_rows_ms := changed_rows_sw.elapsed().milliseconds()
	mut changed_row_count := 0
	for _, table_rows in changed_rows {
		changed_row_count += table_rows.len
	}
	merge_progress_log('   -> merge stage done: exact_changed_rows (${changed_rows_ms} ms, tables=${changed_rows.len}, rows=${changed_row_count})')
	merge_progress_log('   -> merge stage: reindex')
	mut reindex_sw := time.new_stopwatch()
	normalized_tree, reindex_timings := rebuild_typed_indexes_for_changed_rows(resolution.tree,
		set.specs, changed_rows, cfg)!
	reindex_ms := reindex_sw.elapsed().milliseconds()
	merge_progress_log('   -> merge stage done: reindex (${reindex_ms} ms, strategy=${reindex_timings.strategy}, items=${reindex_timings.item_count}, changed_rows=${reindex_timings.changed_rows})')
	set.replace_working_tree(normalized_tree)!
	return WorkingSetMergeResult{
		merge_result: merge_result
		resolution:   MergeResolution{
			tree:          normalized_tree
			resolved_keys: resolution.resolved_keys.clone()
		}
		staged_diff:  set.staged_diff()
		timings:      MergeStageTimings{
			merge_ms:        merge_ms
			resolve_ms:      resolve_ms
			changed_rows_ms: changed_rows_ms
			reindex_ms:      reindex_ms
			reindex:         reindex_timings
		}
	}
}

fn collect_changed_typed_rows(changed_keys []string, changed_subtrees []ChangedSubtree, resolved_keys []string, specs []TypedTableSpec, base_tree Tree, ours_tree Tree, theirs_tree Tree) !map[string]map[string][]u8 {
	mut changed := map[string]map[string][]u8{}
	mut all_keys := map[string]bool{}
	mut row_prefixes := []string{cap: specs.len}
	for key in changed_keys {
		all_keys[key] = true
	}
	for key in resolved_keys {
		all_keys[key] = true
	}
	for spec in specs {
		table_view := TableView.new(Tree{}, spec.table.name)
		row_prefixes << table_view.row_prefix().bytestr()
	}
	for subtree in changed_subtrees {
		source_tree := if subtree.source == .ours { ours_tree } else { theirs_tree }
		for key in changed_row_keys_for_subtree(base_tree, source_tree, subtree.base, subtree.node,
			row_prefixes)! {
			all_keys[key] = true
		}
	}
	for spec in specs {
		table_view := TableView.new(Tree{}, spec.table.name)
		row_prefix := table_view.row_prefix().bytestr()
		mut changed_for_table := map[string][]u8{}
		for key, _ in all_keys {
			if key.starts_with(row_prefix) {
				primary_key := key.bytes()[row_prefix.len..]
				key_id := primary_key.hex()
				changed_for_table[key_id] = primary_key.clone()
			}
		}
		if changed_for_table.len > 0 {
			changed[spec.table.name] = changed_for_table.clone()
		}
	}
	return changed
}

fn collect_changed_typed_rows_exact(specs []TypedTableSpec, base_tree Tree, resolved_tree Tree) !map[string]map[string][]u8 {
	mut changed := map[string]map[string][]u8{}
	for spec in specs {
		base_view := TableView.new(base_tree, spec.table.name)
		resolved_view := TableView.new(resolved_tree, spec.table.name)
		mut base_cursor := base_view.cursor([]u8{}, 0)!
		mut resolved_cursor := resolved_view.cursor([]u8{}, 0)!
		mut changed_for_table := map[string][]u8{}
		mut base_row, mut base_ok := next_table_row(mut base_cursor)
		mut resolved_row, mut resolved_ok := next_table_row(mut resolved_cursor)
		for base_ok || resolved_ok {
			if !base_ok {
				changed_for_table[resolved_row.primary_key.hex()] = resolved_row.primary_key.clone()
				resolved_row, resolved_ok = next_table_row(mut resolved_cursor)
				continue
			}
			if !resolved_ok {
				changed_for_table[base_row.primary_key.hex()] = base_row.primary_key.clone()
				base_row, base_ok = next_table_row(mut base_cursor)
				continue
			}
			cmp := compare_key_bytes(base_row.primary_key, resolved_row.primary_key)
			if cmp == 0 {
				if !bytes_equal(base_row.value, resolved_row.value) {
					changed_for_table[base_row.primary_key.hex()] = base_row.primary_key.clone()
				}
				base_row, base_ok = next_table_row(mut base_cursor)
				resolved_row, resolved_ok = next_table_row(mut resolved_cursor)
				continue
			}
			if cmp < 0 {
				changed_for_table[base_row.primary_key.hex()] = base_row.primary_key.clone()
				base_row, base_ok = next_table_row(mut base_cursor)
				continue
			}
			changed_for_table[resolved_row.primary_key.hex()] = resolved_row.primary_key.clone()
			resolved_row, resolved_ok = next_table_row(mut resolved_cursor)
		}
		if changed_for_table.len > 0 {
			changed[spec.table.name] = changed_for_table.clone()
		}
	}
	return changed
}

fn next_table_row(mut cursor TableCursor) (TableRow, bool) {
	row := cursor.next() or { return TableRow{}, false }
	return row, true
}

fn changed_row_keys_for_subtree(base_tree Tree, source_tree Tree, base_node Node, source_node Node, row_prefixes []string) ![]string {
	base_items := base_tree.collect_items(base_node)!
	source_items := source_tree.collect_items(source_node)!
	mut keys := []string{}
	mut base_idx := 0
	mut source_idx := 0
	for {
		base_has := base_idx < base_items.len
		source_has := source_idx < source_items.len
		if !base_has && !source_has {
			break
		}
		key := if base_has && (!source_has
			|| compare_key_bytes(base_items[base_idx].key, source_items[source_idx].key) <= 0) {
			base_items[base_idx].key
		} else {
			source_items[source_idx].key
		}
		base_val, base_present := merge_item_value_for_key(if base_has {
			base_items[base_idx]
		} else {
			KVPair{}
		}, base_has, key)
		source_val, source_present := merge_item_value_for_key(if source_has {
			source_items[source_idx]
		} else {
			KVPair{}
		}, source_has, key)
		if base_present {
			base_idx++
		}
		if source_present {
			source_idx++
		}
		if base_present == source_present && bytes_equal(base_val, source_val) {
			continue
		}
		key_str := key.bytestr()
		if has_any_prefix(key_str, row_prefixes) {
			keys << key_str
		}
	}
	return keys
}

fn has_any_prefix(value string, prefixes []string) bool {
	for prefix in prefixes {
		if value.starts_with(prefix) {
			return true
		}
	}
	return false
}

pub fn (repo Repository) merge_base_commit(left_commit_cid string, right_commit_cid string, mut commit_store CommitStore) !Commit {
	mut left_depth := map[string]int{}
	mut queue := [left_commit_cid]
	mut depth := 0
	for queue.len > 0 {
		mut next := []string{}
		for cid in queue {
			if cid in left_depth {
				continue
			}
			left_depth[cid] = depth
			commit := commit_store.get(cid)!
			next << commit.parent_cids
		}
		queue = next.clone()
		depth++
	}

	mut right_queue := [right_commit_cid]
	for right_queue.len > 0 {
		mut next := []string{}
		for cid in right_queue {
			if cid in left_depth {
				return commit_store.get(cid)!
			}
			commit := commit_store.get(cid)!
			next << commit.parent_cids
		}
		right_queue = next.clone()
	}
	return error('no merge base found')
}

pub fn (repo Repository) merge_base_branch(left_branch string, right_branch string, mut commit_store CommitStore) !Commit {
	left := repo.checkout(left_branch, mut commit_store)!
	right := repo.checkout(right_branch, mut commit_store)!
	return repo.merge_base_commit(left.cid, right.cid, mut commit_store)
}

pub fn (repo Repository) merge_branches(ours_branch string, theirs_branch string, cfg ChunkConfig, mut node_store NodeStore, mut commit_store CommitStore) !MergeResult {
	base_commit := repo.merge_base_branch(ours_branch, theirs_branch, mut commit_store)!
	ours_commit := repo.checkout(ours_branch, mut commit_store)!
	theirs_commit := repo.checkout(theirs_branch, mut commit_store)!
	base_tree := Tree.load(base_commit.root_cid, mut node_store)!
	ours_tree := Tree.load(ours_commit.root_cid, mut node_store)!
	theirs_tree := Tree.load(theirs_commit.root_cid, mut node_store)!
	return three_way_merge(base_commit, ours_commit, theirs_commit, base_tree, ours_tree,
		theirs_tree, cfg)
}

pub fn auto_merge_by_roots(base_root_cid string, ours_root_cid string, theirs_root_cid string, cfg ChunkConfig, mut node_store NodeStore) !MergeResult {
	base_tree := Tree.load(base_root_cid, mut node_store)!
	ours_tree := Tree.load(ours_root_cid, mut node_store)!
	theirs_tree := Tree.load(theirs_root_cid, mut node_store)!
	return three_way_merge(Commit{
		root_cid:      base_root_cid
		parent_cids:   []string{}
		meta:          CommitMeta{}
		virtual_roots: []VirtualRootRef{}
	}, Commit{
		root_cid:      ours_root_cid
		parent_cids:   []string{}
		meta:          CommitMeta{}
		virtual_roots: []VirtualRootRef{}
	}, Commit{
		root_cid:      theirs_root_cid
		parent_cids:   []string{}
		meta:          CommitMeta{}
		virtual_roots: []VirtualRootRef{}
	}, base_tree, ours_tree, theirs_tree, cfg)
}

pub fn (result MergeResult) resolve_conflicts(resolutions []ConflictResolution, cfg ChunkConfig) !MergeResolution {
	mut resolution_map := map[string]ConflictResolution{}
	for resolution in resolutions {
		resolution_map[resolution.key.bytestr()] = resolution
	}

	mut resolved_keys := []string{}
	mut mutations := []Mutation{}
	for conflict in result.conflicts {
		key := conflict.key.bytestr()
		resolution := resolution_map[key] or {
			return error('missing resolution for conflict key: ${key}')
		}
		match resolution.strategy {
			.ours {
				if conflict.ours.len == 0 {
					mutations << Mutation.delete(conflict.key)
				} else {
					mutations << Mutation.put(conflict.key, conflict.ours)
				}
			}
			.theirs {
				if conflict.theirs.len == 0 {
					mutations << Mutation.delete(conflict.key)
				} else {
					mutations << Mutation.put(conflict.key, conflict.theirs)
				}
			}
			.manual {
				mutations << Mutation.put(conflict.key, resolution.value)
			}
			.delete {
				mutations << Mutation.delete(conflict.key)
			}
		}

		resolved_keys << key
	}
	resolved_tree := result.tree.apply_mutations(mutations, cfg)!.tree
	return MergeResolution{
		tree:          resolved_tree
		resolved_keys: resolved_keys
	}
}

pub fn (mut repo Repository) merge_branch_into(ours_branch string, theirs_branch string, resolutions []ConflictResolution, cfg ChunkConfig, meta CommitMeta, mut node_store NodeStore, mut commit_store CommitStore) !BranchUpdate {
	result :=
		repo.merge_branches(ours_branch, theirs_branch, cfg, mut node_store, mut commit_store)!
	resolution := result.resolve_conflicts(resolutions, cfg)!
	return repo.commit_to_branch(ours_branch, resolution.tree, meta, mut node_store, mut
		commit_store)!
}

fn tree_items_map(tree Tree) !map[string][]u8 {
	mut out := map[string][]u8{}
	for item in tree.items()! {
		out[item.key.bytestr()] = item.value.clone()
	}
	return out
}

fn bytes_equal(a []u8, b []u8) bool {
	return a == b
}

fn three_way_merge(base_commit Commit, ours_commit Commit, theirs_commit Commit, base_tree Tree, ours_tree Tree, theirs_tree Tree, cfg ChunkConfig) !MergeResult {
	base_root := base_tree.root_node()!
	ours_root := ours_tree.root_node()!
	theirs_root := theirs_tree.root_node()!
	mut builder := TreeBuilder{
		cfg:   cfg
		nodes: merge_node_maps(base_tree.nodes, ours_tree.nodes, theirs_tree.nodes)
	}
	merged_result := merge_subtree_refs(mut builder, base_tree, ours_tree, theirs_tree, base_root,
		ours_root, theirs_root)!
	mut refs := merged_result.refs.clone()
	mut level := merged_result.level + 1
	if refs.len == 0 {
		return MergeResult{
			base_commit:      base_commit
			ours_commit:      ours_commit
			theirs_commit:    theirs_commit
			tree:             base_tree
			conflicts:        merged_result.conflicts
			changed_keys:     merged_result.changed_keys
			changed_subtrees: merged_result.changed_subtrees
		}
	}
	for refs.len > 1 {
		refs = builder.build_internal_level(level, refs)!
		level++
	}
	tree := Tree{
		root:  refs[0]
		nodes: builder.nodes.clone()
	}
	return MergeResult{
		base_commit:      base_commit
		ours_commit:      ours_commit
		theirs_commit:    theirs_commit
		tree:             tree
		conflicts:        merged_result.conflicts
		changed_keys:     merged_result.changed_keys
		changed_subtrees: merged_result.changed_subtrees
	}
}

struct MergeSliceResult {
	items        []KVPair
	conflicts    []MergeConflict
	changed_keys []string
}

struct MergeRefResult {
	refs             []NodeRef
	level            int
	conflicts        []MergeConflict
	changed_keys     []string
	changed_subtrees []ChangedSubtree
}

enum MergeTreeSource {
	ours
	theirs
}

pub struct ChangedSubtree {
pub:
	source MergeTreeSource
	base   Node
	node   Node
}

fn common_leaf_prefix_len(base []NodeRef, ours []NodeRef, theirs []NodeRef) int {
	limit := min3_int(base.len, ours.len, theirs.len)
	mut count := 0
	for count < limit {
		if base[count].cid != ours[count].cid || base[count].cid != theirs[count].cid {
			break
		}
		count++
	}
	return count
}

fn common_child_prefix_len(base []NodeRef, ours []NodeRef, theirs []NodeRef) int {
	return common_leaf_prefix_len(base, ours, theirs)
}

fn common_leaf_suffix_len(base []NodeRef, ours []NodeRef, theirs []NodeRef, prefix_len int) int {
	base_rem := base.len - prefix_len
	ours_rem := ours.len - prefix_len
	theirs_rem := theirs.len - prefix_len
	limit := min3_int(base_rem, ours_rem, theirs_rem)
	mut count := 0
	for count < limit {
		base_idx := base.len - 1 - count
		ours_idx := ours.len - 1 - count
		theirs_idx := theirs.len - 1 - count
		if base_idx < prefix_len || ours_idx < prefix_len || theirs_idx < prefix_len {
			break
		}
		if base[base_idx].cid != ours[ours_idx].cid || base[base_idx].cid != theirs[theirs_idx].cid {
			break
		}
		count++
	}
	return count
}

fn common_child_suffix_len(base []NodeRef, ours []NodeRef, theirs []NodeRef, prefix_len int) int {
	return common_leaf_suffix_len(base, ours, theirs, prefix_len)
}

fn merge_subtree_refs(mut builder TreeBuilder, base_tree Tree, ours_tree Tree, theirs_tree Tree, base_node Node, ours_node Node, theirs_node Node) !MergeRefResult {
	if base_node.cid == ours_node.cid && base_node.cid == theirs_node.cid {
		return MergeRefResult{
			refs:             [base_node.to_ref()]
			level:            base_node.level
			conflicts:        []MergeConflict{}
			changed_keys:     []string{}
			changed_subtrees: []ChangedSubtree{}
		}
	}

	if base_node.cid == ours_node.cid {
		theirs_changed_keys := diff_subtree_keys(base_tree, theirs_tree, base_node, theirs_node)!
		return MergeRefResult{
			refs:             [theirs_node.to_ref()]
			level:            theirs_node.level
			conflicts:        []MergeConflict{}
			changed_keys:     theirs_changed_keys
			changed_subtrees: []ChangedSubtree{}
		}
	}

	if base_node.cid == theirs_node.cid {
		ours_changed_keys := diff_subtree_keys(base_tree, ours_tree, base_node, ours_node)!
		return MergeRefResult{
			refs:             [ours_node.to_ref()]
			level:            ours_node.level
			conflicts:        []MergeConflict{}
			changed_keys:     ours_changed_keys
			changed_subtrees: []ChangedSubtree{}
		}
	}

	if ours_node.cid == theirs_node.cid {
		shared_changed_keys := diff_subtree_keys(base_tree, ours_tree, base_node, ours_node)!
		return MergeRefResult{
			refs:             [ours_node.to_ref()]
			level:            ours_node.level
			conflicts:        []MergeConflict{}
			changed_keys:     shared_changed_keys
			changed_subtrees: []ChangedSubtree{}
		}
	}

	if base_node.kind == .internal && ours_node.kind == .internal && theirs_node.kind == .internal {
		base_children := base_node.child_refs()!
		ours_children := ours_node.child_refs()!
		theirs_children := theirs_node.child_refs()!
		prefix_len := common_child_prefix_len(base_children, ours_children, theirs_children)
		suffix_len := common_child_suffix_len(base_children, ours_children, theirs_children,
			prefix_len)
		mut merged_child_refs := []NodeRef{}
		mut conflicts := []MergeConflict{}
		mut changed_keys := []string{}
		mut changed_subtrees := []ChangedSubtree{}

		if prefix_len > 0 {
			merged_child_refs << base_children[..prefix_len]
		}

		base_mid_start := prefix_len
		base_mid_end := base_children.len - suffix_len
		ours_mid_end := ours_children.len - suffix_len
		theirs_mid_end := theirs_children.len - suffix_len
		base_mid_len := base_mid_end - base_mid_start
		ours_mid_len := ours_mid_end - prefix_len
		theirs_mid_len := theirs_mid_end - prefix_len

		if base_mid_len >= 0 && base_mid_len == ours_mid_len && base_mid_len == theirs_mid_len {
			for idx in 0 .. base_mid_len {
				base_child_ref := base_children[base_mid_start + idx]
				ours_child_ref := ours_children[prefix_len + idx]
				theirs_child_ref := theirs_children[prefix_len + idx]
				base_child := base_tree.nodes[base_child_ref.cid] or {
					return error('subtree node not found: ${base_child_ref.cid}')
				}
				ours_child := ours_tree.nodes[ours_child_ref.cid] or {
					return error('subtree node not found: ${ours_child_ref.cid}')
				}
				theirs_child := theirs_tree.nodes[theirs_child_ref.cid] or {
					return error('subtree node not found: ${theirs_child_ref.cid}')
				}
				child_result := merge_subtree_refs(mut builder, base_tree, ours_tree, theirs_tree,
					base_child, ours_child, theirs_child)!
				merged_child_refs << child_result.refs
				conflicts << child_result.conflicts
				changed_keys << child_result.changed_keys
				changed_subtrees << child_result.changed_subtrees
			}
		} else {
			base_mid := subtree_items_range(base_tree, base_children, prefix_len, base_mid_end)!
			ours_mid := subtree_items_range(ours_tree, ours_children, prefix_len, ours_mid_end)!
			theirs_mid := subtree_items_range(theirs_tree, theirs_children, prefix_len,
				theirs_mid_end)!
			middle := merge_item_slices(base_mid, ours_mid, theirs_mid)!
			mut mid_refs := builder.build_leaf_level(middle.items)!
			mut level := 1
			for mid_refs.len > 1 && level < base_node.level {
				mid_refs = builder.build_internal_level(level, mid_refs)!
				level++
			}
			merged_child_refs << mid_refs
			conflicts << middle.conflicts
			changed_keys << middle.changed_keys
		}

		if suffix_len > 0 {
			merged_child_refs << base_children[base_children.len - suffix_len..]
		}

		mut refs := merged_child_refs.clone()
		if refs.len > 1 {
			refs = builder.build_internal_level(base_node.level, refs)!
		}
		return MergeRefResult{
			refs:             refs
			level:            base_node.level
			conflicts:        conflicts
			changed_keys:     changed_keys
			changed_subtrees: changed_subtrees
		}
	}

	base_items := base_tree.collect_items(base_node)!
	ours_items := ours_tree.collect_items(ours_node)!
	theirs_items := theirs_tree.collect_items(theirs_node)!
	slice_result := merge_item_slices(base_items, ours_items, theirs_items)!
	return MergeRefResult{
		refs:             builder.build_leaf_level(slice_result.items)!
		level:            0
		conflicts:        slice_result.conflicts
		changed_keys:     slice_result.changed_keys
		changed_subtrees: []ChangedSubtree{}
	}
}

fn merge_node_maps(base map[string]Node, ours map[string]Node, theirs map[string]Node) map[string]Node {
	mut nodes := map[string]Node{}
	for cid, node in base {
		nodes[cid] = node
	}
	for cid, node in ours {
		nodes[cid] = node
	}
	for cid, node in theirs {
		nodes[cid] = node
	}
	return nodes
}

fn leaf_items_range(tree Tree, refs []NodeRef, start int, end int) ![]KVPair {
	if start >= end {
		return []KVPair{}
	}
	mut items := []KVPair{}
	for idx in start .. end {
		node := tree.nodes[refs[idx].cid] or {
			return error('leaf node not found: ${refs[idx].cid}')
		}
		items << node.leaf_items()!
	}
	return items
}

fn subtree_items_range(tree Tree, refs []NodeRef, start int, end int) ![]KVPair {
	if start >= end {
		return []KVPair{}
	}
	mut items := []KVPair{}
	for idx in start .. end {
		node := tree.nodes[refs[idx].cid] or {
			return error('subtree node not found: ${refs[idx].cid}')
		}
		items << tree.collect_items(node)!
	}
	return items
}

fn subtree_keys(tree Tree, node Node) ![]string {
	items := tree.collect_items(node)!
	mut keys := []string{cap: items.len}
	for item in items {
		keys << item.key.bytestr()
	}
	return keys
}

fn diff_subtree_keys(base_tree Tree, source_tree Tree, base_node Node, source_node Node) ![]string {
	if base_node.cid == source_node.cid {
		return []string{}
	}
	if base_node.kind == .internal && source_node.kind == .internal {
		base_children := base_node.child_refs()!
		source_children := source_node.child_refs()!
		prefix_len := common_pair_prefix_len(base_children, source_children)
		suffix_len := common_pair_suffix_len(base_children, source_children, prefix_len)
		base_mid_start := prefix_len
		base_mid_end := base_children.len - suffix_len
		source_mid_end := source_children.len - suffix_len
		base_mid_len := base_mid_end - base_mid_start
		source_mid_len := source_mid_end - prefix_len
		if base_mid_len >= 0 && base_mid_len == source_mid_len {
			mut changed_keys := []string{}
			for idx in 0 .. base_mid_len {
				base_child_ref := base_children[base_mid_start + idx]
				source_child_ref := source_children[prefix_len + idx]
				base_child := base_tree.nodes[base_child_ref.cid] or {
					return error('subtree node not found: ${base_child_ref.cid}')
				}
				source_child := source_tree.nodes[source_child_ref.cid] or {
					return error('subtree node not found: ${source_child_ref.cid}')
				}
				changed_keys << diff_subtree_keys(base_tree, source_tree, base_child, source_child)!
			}
			return changed_keys
		}
	}
	base_items := base_tree.collect_items(base_node)!
	source_items := source_tree.collect_items(source_node)!
	return diff_item_keys(base_items, source_items)
}

fn diff_item_keys(base_items []KVPair, source_items []KVPair) []string {
	mut changed_keys := []string{}
	mut base_idx := 0
	mut source_idx := 0
	for {
		base_has := base_idx < base_items.len
		source_has := source_idx < source_items.len
		if !base_has && !source_has {
			break
		}
		key := if base_has && (!source_has
			|| compare_key_bytes(base_items[base_idx].key, source_items[source_idx].key) <= 0) {
			base_items[base_idx].key
		} else {
			source_items[source_idx].key
		}
		base_val, base_present := merge_item_value_for_key(if base_has {
			base_items[base_idx]
		} else {
			KVPair{}
		}, base_has, key)
		source_val, source_present := merge_item_value_for_key(if source_has {
			source_items[source_idx]
		} else {
			KVPair{}
		}, source_has, key)
		if base_present {
			base_idx++
		}
		if source_present {
			source_idx++
		}
		if base_present == source_present && bytes_equal(base_val, source_val) {
			continue
		}
		changed_keys << key.bytestr()
	}
	return changed_keys
}

fn common_pair_prefix_len(left []NodeRef, right []NodeRef) int {
	limit := if left.len < right.len { left.len } else { right.len }
	mut count := 0
	for count < limit {
		if left[count].cid != right[count].cid {
			break
		}
		count++
	}
	return count
}

fn common_pair_suffix_len(left []NodeRef, right []NodeRef, prefix_len int) int {
	left_rem := left.len - prefix_len
	right_rem := right.len - prefix_len
	limit := if left_rem < right_rem { left_rem } else { right_rem }
	mut count := 0
	for count < limit {
		left_idx := left.len - 1 - count
		right_idx := right.len - 1 - count
		if left_idx < prefix_len || right_idx < prefix_len {
			break
		}
		if left[left_idx].cid != right[right_idx].cid {
			break
		}
		count++
	}
	return count
}

fn merge_item_slices(base_items []KVPair, ours_items []KVPair, theirs_items []KVPair) !MergeSliceResult {
	mut merged := []KVPair{}
	mut conflicts := []MergeConflict{}
	mut changed_keys := []string{}
	mut base_idx := 0
	mut ours_idx := 0
	mut theirs_idx := 0

	for {
		base_has := base_idx < base_items.len
		ours_has := ours_idx < ours_items.len
		theirs_has := theirs_idx < theirs_items.len
		if !base_has && !ours_has && !theirs_has {
			break
		}
		key := merge_min_key(if base_has { base_items[base_idx] } else { KVPair{} }, base_has, if ours_has {
			ours_items[ours_idx]
		} else {
			KVPair{}
		}, ours_has, if theirs_has { theirs_items[theirs_idx] } else { KVPair{} }, theirs_has)
		base_val, base_present := merge_item_value_for_key(if base_has {
			base_items[base_idx]
		} else {
			KVPair{}
		}, base_has, key)
		ours_val, ours_present := merge_item_value_for_key(if ours_has {
			ours_items[ours_idx]
		} else {
			KVPair{}
		}, ours_has, key)
		theirs_val, theirs_present := merge_item_value_for_key(if theirs_has {
			theirs_items[theirs_idx]
		} else {
			KVPair{}
		}, theirs_has, key)
		if base_present {
			base_idx++
		}
		if ours_present {
			ours_idx++
		}
		if theirs_present {
			theirs_idx++
		}

		ours_same_as_base := base_present == ours_present && bytes_equal(base_val, ours_val)
		theirs_same_as_base := base_present == theirs_present && bytes_equal(base_val, theirs_val)

		if ours_same_as_base && theirs_same_as_base {
			if base_present {
				merged << KVPair{
					key:   key.clone()
					value: base_val
				}
			}
			continue
		}
		if ours_same_as_base {
			if theirs_present {
				merged << KVPair{
					key:   key.clone()
					value: theirs_val
				}
			}
			changed_keys << key.bytestr()
			continue
		}
		if theirs_same_as_base {
			if ours_present {
				merged << KVPair{
					key:   key.clone()
					value: ours_val
				}
			}
			changed_keys << key.bytestr()
			continue
		}
		if ours_present == theirs_present && bytes_equal(ours_val, theirs_val) {
			if ours_present {
				merged << KVPair{
					key:   key.clone()
					value: ours_val
				}
			}
			changed_keys << key.bytestr()
			continue
		}

		conflicts << MergeConflict{
			key:    key.clone()
			base:   base_val
			ours:   ours_val
			theirs: theirs_val
		}
	}

	return MergeSliceResult{
		items:        merged
		conflicts:    conflicts
		changed_keys: changed_keys
	}
}

fn merge_min_key(base_item KVPair, base_has bool, ours_item KVPair, ours_has bool, theirs_item KVPair, theirs_has bool) []u8 {
	mut key := []u8{}
	mut initialized := false
	if base_has {
		key = base_item.key.clone()
		initialized = true
	}
	if ours_has && (!initialized || compare_key_bytes(ours_item.key, key) < 0) {
		key = ours_item.key.clone()
		initialized = true
	}
	if theirs_has && (!initialized || compare_key_bytes(theirs_item.key, key) < 0) {
		key = theirs_item.key.clone()
	}
	return key
}

fn merge_item_value_for_key(item KVPair, has_item bool, key []u8) ([]u8, bool) {
	if !has_item || compare_key_bytes(item.key, key) != 0 {
		return []u8{}, false
	}
	return item.value.clone(), true
}

fn min3_int(a int, b int, c int) int {
	mut out := a
	if b < out {
		out = b
	}
	if c < out {
		out = c
	}
	return out
}
