module storage

import crypto.sha256

pub struct CommitMeta {
pub:
	author    string
	message   string
	timestamp i64
}

pub struct VirtualRootRef {
pub:
	name                 string
	root_cid             string
	source_data_root_cid string
	fresh                bool
	stale_reason         string
}

pub struct Commit {
pub:
	cid         string
	root_cid    string
	parent_cids []string
	meta        CommitMeta
	virtual_roots []VirtualRootRef
}

pub struct Snapshot {
pub:
	commit Commit
	tree   Tree
}

struct CommitReader {
	data   []u8
mut:
	cursor int
}

pub interface CommitStore {
mut:
	put(commit Commit) !
	get(cid string) !Commit
	has(cid string) bool
}

pub struct MemoryCommitStore {
mut:
	commits map[string]Commit
}

pub struct PersistentCommitStore {
mut:
	chunks                ChunkStore
	journal_records       []u8
	journaled_record_size int
	pending               map[string][]u8
}

pub struct PersistentCommitStoreCheckpointInfo {
pub:
	chunk_store ChunkStoreCheckpointInfo
}

pub struct PersistentCommitStoreCheckpointTimings {
pub:
	data_us  i64
	index_us i64
	total_us i64
}

pub struct PersistentCommitStoreRecoveryStatus {
pub:
	chunk_store ChunkStoreRecoveryStatus
}

pub fn MemoryCommitStore.new() MemoryCommitStore {
	return MemoryCommitStore{
		commits: map[string]Commit{}
	}
}

pub fn PersistentCommitStore.open(path string) !PersistentCommitStore {
	return PersistentCommitStore{
		chunks: ChunkStore.open(path)!
		journal_records: []u8{}
		journaled_record_size: 0
		pending: map[string][]u8{}
	}
}

pub fn PersistentCommitStore.open_high_throughput(path string) !PersistentCommitStore {
	return PersistentCommitStore{
		chunks: ChunkStore.open_high_throughput(path)!
		journal_records: []u8{}
		journaled_record_size: 0
		pending: map[string][]u8{}
	}
}

pub fn (mut store MemoryCommitStore) put(commit Commit) ! {
	store.commits[commit.cid] = commit
}

pub fn (store MemoryCommitStore) get(cid string) !Commit {
	commit := store.commits[cid] or {
		return error('commit not found: ${cid}')
	}
	return commit
}

pub fn (store MemoryCommitStore) has(cid string) bool {
	return cid in store.commits
}

pub fn (mut store PersistentCommitStore) close() {
	store.flush_pending() or {}
	store.chunks.close()
}

pub fn (mut store PersistentCommitStore) checkpoint() ! {
	store.flush_pending()!
	store.chunks.checkpoint()!
}

pub fn (mut store PersistentCommitStore) refresh_index_snapshot() ! {
	store.flush_pending()!
	store.chunks.checkpoint_mode(.data_only)!
	store.chunks.refresh_index_snapshot()!
}

pub fn (mut store PersistentCommitStore) checkpoint_timed() !PersistentCommitStoreCheckpointTimings {
	store.flush_pending()!
	timings := store.chunks.checkpoint_timed()!
	return PersistentCommitStoreCheckpointTimings{
		data_us: timings.data_us
		index_us: timings.index_us
		total_us: timings.total_us
	}
}

pub fn (mut store PersistentCommitStore) checkpoint_mode(mode CheckpointMode) ! {
	if mode == .full {
		store.flush_pending()!
	}
	store.chunks.checkpoint_mode(mode)!
}

pub fn (mut store PersistentCommitStore) checkpoint_timed_mode(mode CheckpointMode) !PersistentCommitStoreCheckpointTimings {
	if mode == .full {
		store.flush_pending()!
	}
	timings := store.chunks.checkpoint_timed_mode(mode)!
	return PersistentCommitStoreCheckpointTimings{
		data_us: timings.data_us
		index_us: timings.index_us
		total_us: timings.total_us
	}
}

pub fn (store PersistentCommitStore) checkpoint_info() PersistentCommitStoreCheckpointInfo {
	return PersistentCommitStoreCheckpointInfo{
		chunk_store: store.chunks.checkpoint_info()
	}
}

pub fn PersistentCommitStore.recovery_status(path string) !PersistentCommitStoreRecoveryStatus {
	return PersistentCommitStoreRecoveryStatus{
		chunk_store: ChunkStore.recovery_status(path)!
	}
}

pub fn (mut store PersistentCommitStore) put(commit Commit) ! {
	if store.chunks.has(commit.cid.bytes()) || commit.cid in store.pending {
		return
	}
	data := commit.data()
	store.pending[commit.cid] = data.clone()
	chunk_store_append_record(mut store.journal_records, commit.cid.bytes(), data)
}

pub fn (mut store PersistentCommitStore) get(cid string) !Commit {
	if cid in store.pending {
		return Commit.from_data(store.pending[cid] or { []u8{} })
	}
	data := store.chunks.get(cid.bytes())!
	return Commit.from_data(data)
}

pub fn (store PersistentCommitStore) has(cid string) bool {
	return cid in store.pending || store.chunks.has(cid.bytes())
}

pub fn (store PersistentCommitStore) pending_journal_records() []u8 {
	return store.journal_records[store.journaled_record_size..].clone()
}

pub fn (mut store PersistentCommitStore) mark_journal_records_persisted() {
	store.journaled_record_size = store.journal_records.len
}

pub fn (mut store PersistentCommitStore) clear_journal_records() {
	store.journal_records = []u8{}
	store.journaled_record_size = 0
}

fn (mut store PersistentCommitStore) flush_pending() ! {
	if store.pending.len == 0 {
		return
	}
	mut payloads := []ChunkPayload{cap: store.pending.len}
	for cid, data in store.pending {
		payloads << ChunkPayload{
			cid: cid.bytes()
			data: data
		}
	}
	_ = store.chunks.put_many(payloads)!
	store.pending = map[string][]u8{}
}

pub fn Commit.new(root_cid string, parent_cids []string, meta CommitMeta) Commit {
	return Commit.new_with_virtual_roots(root_cid, parent_cids, meta, [])
}

pub fn Commit.new_with_virtual_roots(root_cid string, parent_cids []string, meta CommitMeta, virtual_roots []VirtualRootRef) Commit {
	cid := commit_cid_for(root_cid, parent_cids, meta, virtual_roots)
	return Commit{
		cid: cid
		root_cid: root_cid
		parent_cids: parent_cids.clone()
		meta: meta
		virtual_roots: virtual_roots.clone()
	}
}

pub fn Snapshot.new(tree Tree, parent_cids []string, meta CommitMeta) Snapshot {
	return Snapshot.new_with_virtual_roots(tree, parent_cids, meta, [])
}

pub fn Snapshot.new_with_virtual_roots(tree Tree, parent_cids []string, meta CommitMeta, virtual_roots []VirtualRootRef) Snapshot {
	return Snapshot{
		commit: Commit.new_with_virtual_roots(tree.root.cid, parent_cids, meta, virtual_roots)
		tree: tree
	}
}

pub fn (snapshot Snapshot) persist(mut node_store NodeStore, mut commit_store CommitStore) ! {
	for _, node in snapshot.tree.nodes {
		node_store.put(node)!
	}
	commit_store.put(snapshot.commit)!
}

pub fn (snapshot Snapshot) persist_to_persistent(mut node_store PersistentNodeStore, mut commit_store PersistentCommitStore) ! {
	mut nodes := []Node{cap: snapshot.tree.nodes.len}
	for _, node in snapshot.tree.nodes {
		nodes << node
	}
	node_store.put_many(nodes)!
	commit_store.put(snapshot.commit)!
}

pub fn (commit Commit) is_root() bool {
	return commit.parent_cids.len == 0
}

pub fn (commit Commit) short_id() string {
	return if commit.cid.len >= 12 { commit.cid[..12] } else { commit.cid }
}

pub fn (commit Commit) data() []u8 {
	mut out := []u8{}
	commit_append_field(mut out, commit.root_cid.bytes())
	commit_append_u32(mut out, u32(commit.parent_cids.len))
	for parent_cid in commit.parent_cids {
		commit_append_field(mut out, parent_cid.bytes())
	}
	commit_append_field(mut out, commit.meta.author.bytes())
	commit_append_field(mut out, commit.meta.message.bytes())
	commit_append_i64(mut out, commit.meta.timestamp)
	commit_append_u32(mut out, u32(commit.virtual_roots.len))
	for virtual_root in commit.virtual_roots {
		commit_append_field(mut out, virtual_root.name.bytes())
		commit_append_field(mut out, virtual_root.root_cid.bytes())
		commit_append_field(mut out, virtual_root.source_data_root_cid.bytes())
		out << if virtual_root.fresh { u8(1) } else { u8(0) }
	}
	commit_append_field(mut out, 'virtual_root_stale_reasons_v1'.bytes())
	commit_append_u32(mut out, u32(commit.virtual_roots.len))
	for virtual_root in commit.virtual_roots {
		commit_append_field(mut out, virtual_root.name.bytes())
		commit_append_field(mut out, virtual_root.stale_reason.bytes())
	}
	return out
}

pub fn Commit.from_data(data []u8) !Commit {
	mut reader := CommitReader{
		data: data
	}
	root_cid := reader.read_field()!.bytestr()
	parent_count := int(reader.read_u32()!)
	mut parent_cids := []string{cap: parent_count}
	for _ in 0 .. parent_count {
		parent_cids << reader.read_field()!.bytestr()
	}
	author := reader.read_field()!.bytestr()
	message := reader.read_field()!.bytestr()
	timestamp := reader.read_i64()!
	mut virtual_roots := []VirtualRootRef{}
	if reader.cursor < data.len {
		virtual_root_count := int(reader.read_u32()!)
		virtual_roots = []VirtualRootRef{cap: virtual_root_count}
		for _ in 0 .. virtual_root_count {
			name := reader.read_field()!.bytestr()
			virtual_root_cid := reader.read_field()!.bytestr()
			source_data_root_cid := reader.read_field()!.bytestr()
			fresh := reader.read_u8()! == 1
			virtual_roots << VirtualRootRef{
				name: name
				root_cid: virtual_root_cid
				source_data_root_cid: source_data_root_cid
				fresh: fresh
				stale_reason: ''
			}
		}
	}
	if reader.cursor < data.len {
		section := reader.read_field()!.bytestr()
		if section != 'virtual_root_stale_reasons_v1' {
			return error('unknown commit extension section: ${section}')
		}
		reason_count := int(reader.read_u32()!)
		mut reason_by_name := map[string]string{}
		for _ in 0 .. reason_count {
			name := reader.read_field()!.bytestr()
			reason_by_name[name] = reader.read_field()!.bytestr()
		}
		for idx, virtual_root in virtual_roots {
			if virtual_root.name in reason_by_name {
				virtual_roots[idx] = VirtualRootRef{
					...virtual_root
					stale_reason: reason_by_name[virtual_root.name]
				}
			}
		}
	}
	commit := Commit.new_with_virtual_roots(root_cid, parent_cids, CommitMeta{
		author: author
		message: message
		timestamp: timestamp
	}, virtual_roots)
	if reader.cursor != data.len {
		return error('commit record has trailing bytes')
	}
	return commit
}

pub fn (store MemoryCommitStore) lineage(head_cid string) ![]Commit {
	mut commits := []Commit{}
	mut current_cid := head_cid
	for current_cid.len > 0 {
		commit := store.get(current_cid)!
		commits << commit
		if commit.parent_cids.len == 0 {
			break
		}
		current_cid = commit.parent_cids[0]
	}
	return commits
}

pub fn (mut store PersistentCommitStore) lineage(head_cid string) ![]Commit {
	mut commits := []Commit{}
	mut current_cid := head_cid
	for current_cid.len > 0 {
		commit := store.get(current_cid)!
		commits << commit
		if commit.parent_cids.len == 0 {
			break
		}
		current_cid = commit.parent_cids[0]
	}
	return commits
}

pub fn (store MemoryCommitStore) latest() !Commit {
	if store.commits.len == 0 {
		return error('commit store is empty')
	}
	mut commits := []Commit{}
	for _, commit in store.commits {
		commits << commit
	}
	commits.sort_with_compare(fn (a &Commit, b &Commit) int {
		if a.meta.timestamp < b.meta.timestamp {
			return -1
		}
		if a.meta.timestamp > b.meta.timestamp {
			return 1
		}
		if a.cid < b.cid {
			return -1
		}
		if a.cid > b.cid {
			return 1
		}
		return 0
	})
	return commits[commits.len - 1]
}

fn commit_cid_for(root_cid string, parent_cids []string, meta CommitMeta, virtual_roots []VirtualRootRef) string {
	mut material := []u8{}
	material << root_cid.bytes()
	material << `\n`
	for parent_cid in parent_cids {
		material << parent_cid.bytes()
		material << `\n`
	}
	material << meta.author.bytes()
	material << `\n`
	material << meta.message.bytes()
	material << `\n`
	material << meta.timestamp.str().bytes()
	material << `\n`
	for virtual_root in virtual_roots {
		material << virtual_root.name.bytes()
		material << `|`
		material << virtual_root.root_cid.bytes()
		material << `|`
		material << virtual_root.source_data_root_cid.bytes()
		material << `|`
		material << if virtual_root.fresh { `1` } else { `0` }
		material << `|`
		material << virtual_root.stale_reason.bytes()
		material << `\n`
	}
	return sha256.sum(material).hex()
}

fn commit_append_u32(mut out []u8, value u32) {
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
}

fn commit_append_i64(mut out []u8, value i64) {
	mut v := u64(value)
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		out << u8((v >> shift) & 0xff)
	}
}

fn commit_append_field(mut out []u8, data []u8) {
	commit_append_u32(mut out, u32(data.len))
	out << data
}

fn (mut reader CommitReader) read_u32() !u32 {
	if reader.cursor + 4 > reader.data.len {
		return error('commit record truncated')
	}
	value := u32(reader.data[reader.cursor]) | (u32(reader.data[reader.cursor + 1]) << 8) | (u32(reader.data[reader.cursor + 2]) << 16) | (u32(reader.data[reader.cursor + 3]) << 24)
	reader.cursor += 4
	return value
}

fn (mut reader CommitReader) read_i64() !i64 {
	if reader.cursor + 8 > reader.data.len {
		return error('commit record truncated')
	}
	mut value := u64(0)
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		value |= u64(reader.data[reader.cursor + shift / 8]) << shift
	}
	reader.cursor += 8
	return i64(value)
}

fn (mut reader CommitReader) read_u8() !u8 {
	if reader.cursor + 1 > reader.data.len {
		return error('commit record truncated')
	}
	value := reader.data[reader.cursor]
	reader.cursor++
	return value
}

fn (mut reader CommitReader) read_field() ![]u8 {
	length := int(reader.read_u32()!)
	if reader.cursor + length > reader.data.len {
		return error('commit field truncated')
	}
	field := reader.data[reader.cursor..reader.cursor + length].clone()
	reader.cursor += length
	return field
}
