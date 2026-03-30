module storage

pub interface NodeStore {
mut:
	put(node Node) !
	get(cid string) !Node
	has(cid string) bool
}

pub interface NodeByteStore {
mut:
	get_bytes(cid []u8) ![]u8
}

pub struct MemoryNodeStore {
mut:
	nodes map[string]Node
}

pub struct PersistentNodeStore {
mut:
	chunks                ChunkStore
	journal_records       []u8
	journaled_record_size int
	pending               map[string][]u8
}

pub struct PersistentNodeStoreCheckpointInfo {
pub:
	chunk_store ChunkStoreCheckpointInfo
}

pub struct PersistentNodeStoreCheckpointTimings {
pub:
	data_us  i64
	index_us i64
	total_us i64
}

pub struct PersistentNodeStoreRecoveryStatus {
pub:
	chunk_store ChunkStoreRecoveryStatus
}

pub fn MemoryNodeStore.new() MemoryNodeStore {
	return MemoryNodeStore{
		nodes: map[string]Node{}
	}
}

pub fn PersistentNodeStore.open(path string) !PersistentNodeStore {
	return PersistentNodeStore{
		chunks: ChunkStore.open(path)!
		journal_records: []u8{}
		journaled_record_size: 0
		pending: map[string][]u8{}
	}
}

pub fn PersistentNodeStore.open_high_throughput(path string) !PersistentNodeStore {
	return PersistentNodeStore{
		chunks: ChunkStore.open_high_throughput(path)!
		journal_records: []u8{}
		journaled_record_size: 0
		pending: map[string][]u8{}
	}
}

pub fn (mut store MemoryNodeStore) put(node Node) ! {
	store.nodes[node.cid] = node
}

pub fn (store MemoryNodeStore) get(cid string) !Node {
	node := store.nodes[cid] or {
		return error('node not found: ${cid}')
	}
	return node
}

pub fn (store MemoryNodeStore) has(cid string) bool {
	return cid in store.nodes
}

pub fn (mut store MemoryNodeStore) get_bytes(cid []u8) ![]u8 {
	node := store.nodes[cid.bytestr()] or {
		return error('node not found: ${cid.bytestr()}')
	}
	return node.data
}

pub fn (mut store MemoryNodeStore) put_tree(tree Tree) ! {
	for _, node in tree.nodes {
		store.put(node)!
	}
}

pub fn (mut store PersistentNodeStore) close() {
	store.flush_pending() or {}
	store.chunks.close()
}

pub fn (mut store PersistentNodeStore) checkpoint() ! {
	store.flush_pending()!
	store.chunks.checkpoint()!
}

pub fn (mut store PersistentNodeStore) refresh_index_snapshot() ! {
	store.flush_pending()!
	store.chunks.checkpoint_mode(.data_only)!
	store.chunks.refresh_index_snapshot()!
}

pub fn (mut store PersistentNodeStore) checkpoint_timed() !PersistentNodeStoreCheckpointTimings {
	store.flush_pending()!
	timings := store.chunks.checkpoint_timed()!
	return PersistentNodeStoreCheckpointTimings{
		data_us: timings.data_us
		index_us: timings.index_us
		total_us: timings.total_us
	}
}

pub fn (mut store PersistentNodeStore) checkpoint_mode(mode CheckpointMode) ! {
	if mode == .full {
		store.flush_pending()!
	}
	store.chunks.checkpoint_mode(mode)!
}

pub fn (mut store PersistentNodeStore) checkpoint_timed_mode(mode CheckpointMode) !PersistentNodeStoreCheckpointTimings {
	if mode == .full {
		store.flush_pending()!
	}
	timings := store.chunks.checkpoint_timed_mode(mode)!
	return PersistentNodeStoreCheckpointTimings{
		data_us: timings.data_us
		index_us: timings.index_us
		total_us: timings.total_us
	}
}

pub fn (store PersistentNodeStore) checkpoint_info() PersistentNodeStoreCheckpointInfo {
	return PersistentNodeStoreCheckpointInfo{
		chunk_store: store.chunks.checkpoint_info()
	}
}

pub fn PersistentNodeStore.recovery_status(path string) !PersistentNodeStoreRecoveryStatus {
	return PersistentNodeStoreRecoveryStatus{
		chunk_store: ChunkStore.recovery_status(path)!
	}
}

pub fn (mut store PersistentNodeStore) put(node Node) ! {
	if store.chunks.has(node.cid.bytes()) || node.cid in store.pending {
		return
	}
	store.pending[node.cid] = node.data.clone()
	chunk_store_append_record(mut store.journal_records, node.cid.bytes(), node.data)
}

pub fn (mut store PersistentNodeStore) put_many(nodes []Node) ! {
	for node in nodes {
		if store.chunks.has(node.cid.bytes()) || node.cid in store.pending {
			continue
		}
		store.pending[node.cid] = node.data.clone()
		chunk_store_append_record(mut store.journal_records, node.cid.bytes(), node.data)
	}
}

pub fn (mut store PersistentNodeStore) get(cid string) !Node {
	if cid in store.pending {
		return Node.from_data_with_cid(store.pending[cid] or { []u8{} }, cid)
	}
	data := store.chunks.get(cid.bytes())!
	return Node.from_data_with_cid(data, cid)
}

pub fn (mut store PersistentNodeStore) get_bytes(cid []u8) ![]u8 {
	key := cid.bytestr()
	if key in store.pending {
		return (store.pending[key] or { []u8{} }).clone()
	}
	return store.chunks.get(cid)
}

pub fn (store PersistentNodeStore) has(cid string) bool {
	return cid in store.pending || store.chunks.has(cid.bytes())
}

pub fn (mut store PersistentNodeStore) put_tree(tree Tree) ! {
	for _, node in tree.nodes {
		store.put(node)!
	}
}

pub fn (store PersistentNodeStore) pending_journal_records() []u8 {
	return store.journal_records[store.journaled_record_size..].clone()
}

pub fn (mut store PersistentNodeStore) mark_journal_records_persisted() {
	store.journaled_record_size = store.journal_records.len
}

pub fn (mut store PersistentNodeStore) clear_journal_records() {
	store.journal_records = []u8{}
	store.journaled_record_size = 0
}

fn (mut store PersistentNodeStore) flush_pending() ! {
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
