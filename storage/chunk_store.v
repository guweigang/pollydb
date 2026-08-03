module storage

import os
import hash.crc32
import rand
import time

pub struct ChunkStoreEntry {
pub:
	offset u64
	length int
}

pub struct ChunkPayload {
pub:
	cid  []u8
	data []u8
}

pub struct ChunkRecordMeta {
pub:
	cid    []u8
	length int
}

struct ChunkStoreIndexEntry {
	suffix u64
	entry  ChunkStoreEntry
}

pub struct ChunkStore {
pub:
	path string
mut:
	file         os.File
	index        map[u64][]ChunkStoreIndexEntry
	write_offset u64
	maintain_index bool
	defer_index_build bool
	data_dirty   bool
	index_dirty  bool
	index_snapshot_sync_pending bool
	index_snapshot_payload []u8
	index_snapshot_entries int
}

pub struct ChunkStoreCheckpointInfo {
pub:
	data_path        string
	index_path       string
	write_offset     u64
	index_entries    int
	index_snapshot_exists bool
}

pub struct ChunkStoreCheckpointTimings {
pub:
	data_us  i64
	index_us i64
	total_us i64
}

pub struct ChunkStoreRecoveryStatus {
pub:
	data_path            string
	index_path           string
	write_offset         u64
	index_snapshot_exists bool
	index_snapshot_valid bool
	index_entries        int
}

pub enum CheckpointMode {
	data_only
	full
}

const chunk_store_index_magic = 'pdx1'
const chunk_store_index_version = u32(2)

pub fn ChunkStore.open(path string) !ChunkStore {
	return ChunkStore.open_with_index(path, true)
}

pub fn ChunkStore.open_high_throughput(path string) !ChunkStore {
	return ChunkStore.open_deferred_index(path)
}

pub fn ChunkStore.open_without_index(path string) !ChunkStore {
	return ChunkStore.open_with_index(path, false)
}

pub fn ChunkStore.open_deferred_index(path string) !ChunkStore {
	return ChunkStore.open_with_modes(path, true, true)
}

fn chunk_store_index_path(path string) string {
	return '${path}.idx'
}

fn chunk_store_bucket_entry_count(index map[u64][]ChunkStoreIndexEntry) int {
	mut count := 0
	for _, bucket in index {
		count += bucket.len
	}
	return count
}

fn ChunkStore.open_with_index(path string, maintain_index bool) !ChunkStore {
	return ChunkStore.open_with_modes(path, maintain_index, false)
}

fn ChunkStore.open_with_modes(path string, maintain_index bool, defer_index_build bool) !ChunkStore {
	mut file := os.open_file(path, 'ab+', 0o666)!
	file.seek(0, .end)!
	write_offset := u64(file.tell()!)
	mut store := ChunkStore{
		path: path
		file: file
		index: map[u64][]ChunkStoreIndexEntry{}
		write_offset: write_offset
		maintain_index: maintain_index
		defer_index_build: defer_index_build
		data_dirty: false
		index_dirty: false
		index_snapshot_sync_pending: false
		index_snapshot_payload: []u8{}
		index_snapshot_entries: 0
	}
	if maintain_index && write_offset > 0 {
		if !store.load_index_snapshot()! {
			store.rebuild_index_from_file()!
		}
	}
	return store
}

pub fn (mut store ChunkStore) close() {
	store.checkpoint_internal(true, true) or {}
	store.file.close()
}

pub fn (mut store ChunkStore) close_without_checkpoint() {
	if store.data_dirty {
		store.file.flush()
	}
	store.file.close()
}

pub fn (mut store ChunkStore) checkpoint() ! {
	store.checkpoint_mode(.full)!
}

pub fn (mut store ChunkStore) refresh_index_snapshot() ! {
	if !store.maintain_index {
		return
	}
	if store.data_dirty {
		store.file.flush()
	}
	if store.index_dirty {
		store.persist_index_snapshot(true)!
		store.index_dirty = false
		store.index_snapshot_sync_pending = false
		return
	}
	if store.index_snapshot_sync_pending {
		store.sync_index_snapshot_file()!
		store.index_snapshot_sync_pending = false
	}
}

pub fn (mut store ChunkStore) checkpoint_timed() !ChunkStoreCheckpointTimings {
	return store.checkpoint_timed_mode(.full)
}

pub fn (mut store ChunkStore) checkpoint_mode(mode CheckpointMode) ! {
	match mode {
		.data_only {
			store.checkpoint_internal(false, false)!
		}
		.full {
			store.checkpoint_internal(true, true)!
		}
	}
}

pub fn (mut store ChunkStore) checkpoint_timed_mode(mode CheckpointMode) !ChunkStoreCheckpointTimings {
	return match mode {
		.data_only { store.checkpoint_timed_internal(false, false) }
		.full { store.checkpoint_timed_internal(true, true) }
	}
}

fn (mut store ChunkStore) checkpoint_internal(persist_snapshot bool, sync_snapshot bool) ! {
	if store.data_dirty {
		store.file.flush()
		$if darwin || linux || windows {
			chunk_store_fsync_fd(store.file.fd)!
		}
		store.data_dirty = false
	}
	if persist_snapshot && store.maintain_index && store.index_dirty {
		store.persist_index_snapshot(sync_snapshot)!
		store.index_dirty = false
		store.index_snapshot_sync_pending = !sync_snapshot
	} else if persist_snapshot && sync_snapshot && store.index_snapshot_sync_pending {
		store.sync_index_snapshot_file()!
		store.index_snapshot_sync_pending = false
	}
}

fn (mut store ChunkStore) checkpoint_timed_internal(persist_snapshot bool, sync_snapshot bool) !ChunkStoreCheckpointTimings {
	mut total_sw := time.new_stopwatch()
	mut data_us := i64(0)
	mut index_us := i64(0)
	if store.data_dirty {
		mut sw := time.new_stopwatch()
		store.file.flush()
		$if darwin || linux || windows {
			chunk_store_fsync_fd(store.file.fd)!
		}
		store.data_dirty = false
		data_us = sw.elapsed().microseconds()
	}
	if persist_snapshot && store.maintain_index && store.index_dirty {
		mut sw := time.new_stopwatch()
		store.persist_index_snapshot(sync_snapshot)!
		store.index_dirty = false
		store.index_snapshot_sync_pending = !sync_snapshot
		index_us = sw.elapsed().microseconds()
	} else if persist_snapshot && sync_snapshot && store.index_snapshot_sync_pending {
		mut sw := time.new_stopwatch()
		store.sync_index_snapshot_file()!
		store.index_snapshot_sync_pending = false
		index_us = sw.elapsed().microseconds()
	}
	return ChunkStoreCheckpointTimings{
		data_us: data_us
		index_us: index_us
		total_us: total_sw.elapsed().microseconds()
	}
}

pub fn (store ChunkStore) checkpoint_info() ChunkStoreCheckpointInfo {
	index_path := chunk_store_index_path(store.path)
	return ChunkStoreCheckpointInfo{
		data_path: store.path
		index_path: index_path
		write_offset: store.write_offset
		index_entries: chunk_store_bucket_entry_count(store.index)
		index_snapshot_exists: os.exists(index_path)
	}
}

pub fn ChunkStore.recovery_status(path string) !ChunkStoreRecoveryStatus {
	index_path := chunk_store_index_path(path)
	if !os.exists(path) {
		return ChunkStoreRecoveryStatus{
			data_path: path
			index_path: index_path
			write_offset: 0
			index_snapshot_exists: os.exists(index_path)
			index_snapshot_valid: false
			index_entries: 0
		}
	}
	write_offset := u64(os.file_size(path))
	mut status := ChunkStoreRecoveryStatus{
		data_path: path
		index_path: index_path
		write_offset: write_offset
		index_snapshot_exists: os.exists(index_path)
		index_snapshot_valid: false
		index_entries: 0
	}
	if !status.index_snapshot_exists {
		return status
	}
	data := os.read_bytes(index_path) or {
		return status
	}
	if data.len < 20 || data[..4].bytestr() != chunk_store_index_magic {
		return status
	}
	version := chunk_store_read_u32_le(data[4..8])
	if version != chunk_store_index_version {
		return status
	}
	snapshot_offset := chunk_store_read_u64_le(data, 8)
	if snapshot_offset != write_offset {
		return status
	}
	expected_checksum := chunk_store_read_u32_le(data[16..20])
	payload := data[20..]
	if crc32.sum(payload) != expected_checksum {
		return status
	}
	mut cursor := 20
	if cursor + 4 > data.len {
		return status
	}
	entry_count := int(chunk_store_read_u32_le(data[cursor..cursor + 4]))
	cursor += 4
	for _ in 0 .. entry_count {
		if cursor + 28 > data.len {
			return status
		}
		cursor += 28
	}
	if cursor != data.len {
		return status
	}
	return ChunkStoreRecoveryStatus{
		data_path: status.data_path
		index_path: status.index_path
		write_offset: status.write_offset
		index_snapshot_exists: status.index_snapshot_exists
		index_snapshot_valid: true
		index_entries: entry_count
	}
}

pub fn (store ChunkStore) should_defer_index_build() bool {
	return store.maintain_index && store.defer_index_build
}

pub fn (store ChunkStore) has(cid []u8) bool {
	if !store.maintain_index {
		return false
	}
	prefix, suffix := chunk_store_index_parts(cid)
	bucket := store.index[prefix] or {
		return false
	}
	for item in bucket {
		if item.suffix == suffix {
			return true
		}
	}
	return false
}

pub fn (mut store ChunkStore) put(cid []u8, data []u8) !ChunkStoreEntry {
	offset := store.write_offset
	mut header := []u8{cap: 8}
	chunk_store_append_header(mut header, cid.len, data.len)
	_ = store.file.write(header)!
	_ = store.file.write(cid)!
	_ = store.file.write(data)!
	store.write_offset += u64(header.len + cid.len + data.len)
	store.data_dirty = true
	entry := ChunkStoreEntry{
		offset: offset
		length: data.len
	}
	if store.maintain_index {
		store.index_add(cid, entry)
		store.index_dirty = true
	}
	return entry
}

pub fn (mut store ChunkStore) put_many(payloads []ChunkPayload) ![]ChunkStoreEntry {
	if payloads.len == 0 {
		return []ChunkStoreEntry{}
	}
	mut entries := []ChunkStoreEntry{cap: payloads.len}
	mut total_len := 0
	for payload in payloads {
		total_len += 8 + payload.cid.len + payload.data.len
	}
	mut buf := []u8{cap: total_len}
	mut offset := store.write_offset
	for payload in payloads {
		chunk_store_append_header(mut buf, payload.cid.len, payload.data.len)
		buf << payload.cid
		buf << payload.data
		entry := ChunkStoreEntry{
			offset: offset
			length: payload.data.len
		}
		entries << entry
		if store.maintain_index {
			store.index_add(payload.cid, entry)
		}
		offset += u64(8 + payload.cid.len + payload.data.len)
	}
	_ = store.file.write(buf)!
	store.write_offset = offset
	store.data_dirty = true
	if store.maintain_index {
		store.index_dirty = true
	}
	return entries
}

pub fn (mut store ChunkStore) put_many_streaming(payloads []ChunkPayload) ![]ChunkStoreEntry {
	if payloads.len == 0 {
		return []ChunkStoreEntry{}
	}
	mut entries := []ChunkStoreEntry{cap: payloads.len}
	mut header := []u8{cap: 8}
	mut offset := store.write_offset
	for payload in payloads {
		header.clear()
		chunk_store_append_header(mut header, payload.cid.len, payload.data.len)
		_ = store.file.write(header)!
		_ = store.file.write(payload.cid)!
		_ = store.file.write(payload.data)!
		entry := ChunkStoreEntry{
			offset: offset
			length: payload.data.len
		}
		entries << entry
		if store.maintain_index {
			store.index_add(payload.cid, entry)
		}
		offset += u64(8 + payload.cid.len + payload.data.len)
	}
	store.write_offset = offset
	store.data_dirty = true
	if store.maintain_index {
		store.index_dirty = true
	}
	return entries
}

pub fn (mut store ChunkStore) put_encoded_batch(records []u8, metas []ChunkRecordMeta) ![]ChunkStoreEntry {
	if metas.len == 0 {
		return []ChunkStoreEntry{}
	}
	mut entries := []ChunkStoreEntry{cap: metas.len}
	mut offset := store.write_offset
	for meta in metas {
		entry := ChunkStoreEntry{
			offset: offset
			length: meta.length
		}
		entries << entry
		if store.maintain_index {
			store.index_add(meta.cid, entry)
		}
		offset += u64(8 + meta.cid.len + meta.length)
	}
	_ = store.file.write(records)!
	store.write_offset = offset
	store.data_dirty = true
	if store.maintain_index {
		store.index_dirty = true
	}
	return entries
}

fn (mut store ChunkStore) put_chunk_cids_scatter(data []u8, chunk_cids []ChunkCid) ![]ChunkStoreEntry {
	return store.put_chunk_cids_writev(data, chunk_cids)
}

pub fn (mut store ChunkStore) get(cid []u8) ![]u8 {
	if !store.maintain_index {
		return error('chunk store index disabled')
	}
	entry := store.index_get(cid) or {
		store.rebuild_index_from_file()!
		store.index_get(cid) or {
			return error('chunk not found: ${cid.hex()}')
		}
	}
	if store.data_dirty {
		store.file.flush()
	}
	mut record := []u8{len: 8 + cid.len + entry.length}
	_ = store.file.read_bytes_into(entry.offset, mut record)!
	cid_len := int(chunk_store_read_u32_le(record[..4]))
	data_len := int(chunk_store_read_u32_le(record[4..8]))
	if cid_len != cid.len || data_len != entry.length {
		return error('chunk header mismatch at offset ${entry.offset}')
	}
	cid_buf := unsafe { record[8..8 + cid_len] }
	if cid_buf != cid {
		return error('chunk cid mismatch at offset ${entry.offset}')
	}
	return record[8 + cid_len..].clone()
}

pub fn (mut store ChunkStore) finalize_deferred_index_build() ! {
	if !store.should_defer_index_build() {
		return
	}
	if store.index.len > 0 {
		return
	}
	store.rebuild_index_from_file()!
}

fn (store ChunkStore) persist_index_snapshot(sync_snapshot bool) ! {
	if store.path.len == 0 {
		return
	}
	index_path := chunk_store_index_path(store.path)
	tmp_path := '${index_path}.tmp.${os.getpid()}.${time.now().unix_micro()}.${rand.u64()}'
	mut out := []u8{}
	out << chunk_store_index_magic.bytes()
	chunk_store_append_u32_le(mut out, chunk_store_index_version)
	chunk_store_append_u64_le(mut out, store.write_offset)
	chunk_store_append_u32_le(mut out, u32(0))
	mut payload := []u8{cap: 4 + store.index_snapshot_payload.len}
	chunk_store_append_u32_le(mut payload, u32(store.index_snapshot_entries))
	payload << store.index_snapshot_payload
	checksum := crc32.sum(payload)
	chunk_store_write_u32_le(mut out, 16, checksum)
	out << payload
	mut tmp_file := os.open_file(tmp_path, 'wb', 0o666)!
	defer {
		tmp_file.close()
	}
	_ = tmp_file.write(out)!
	tmp_file.flush()
	if sync_snapshot {
		$if darwin || linux || windows {
			chunk_store_fsync_fd(tmp_file.fd)!
		}
	}
	os.mv(tmp_path, index_path) or {
		os.rm(tmp_path) or {}
		return err
	}
}

fn (store ChunkStore) sync_index_snapshot_file() ! {
	index_path := chunk_store_index_path(store.path)
	mut index_file := os.open_file(index_path, 'rb', 0o666)!
	defer {
		index_file.close()
	}
	index_file.flush()
	$if darwin || linux || windows {
		chunk_store_fsync_fd(index_file.fd)!
	}
}

fn (mut store ChunkStore) load_index_snapshot() !bool {
	path := chunk_store_index_path(store.path)
	if !os.exists(path) {
		os.rm(path) or {}
		return false
	}
	data := os.read_bytes(path)!
	if data.len < 20 || data[..4].bytestr() != chunk_store_index_magic {
		os.rm(path) or {}
		return false
	}
	version := chunk_store_read_u32_le(data[4..8])
	if version != chunk_store_index_version {
		os.rm(path) or {}
		return false
	}
	snapshot_offset := chunk_store_read_u64_le(data, 8)
	if snapshot_offset != store.write_offset {
		os.rm(path) or {}
		return false
	}
	expected_checksum := chunk_store_read_u32_le(data[16..20])
	payload := data[20..]
	if crc32.sum(payload) != expected_checksum {
		os.rm(path) or {}
		return false
	}
	mut cursor := 20
	entry_count := int(chunk_store_read_u32_le(data[cursor..cursor + 4]))
	cursor += 4
	store.index = map[u64][]ChunkStoreIndexEntry{}
	for _ in 0 .. entry_count {
		if cursor + 28 > data.len {
			os.rm(path) or {}
			return false
		}
		prefix := chunk_store_read_u64_le(data, cursor)
		cursor += 8
		suffix := chunk_store_read_u64_le(data, cursor)
		cursor += 8
		offset := chunk_store_read_u64_le(data, cursor)
		cursor += 8
		length := int(chunk_store_read_u32_le(data[cursor..cursor + 4]))
		cursor += 4
		mut bucket := store.index[prefix] or { []ChunkStoreIndexEntry{} }
		bucket << ChunkStoreIndexEntry{
			suffix: suffix
			entry: ChunkStoreEntry{
				offset: offset
				length: length
			}
		}
		store.index[prefix] = bucket
	}
	if cursor != data.len {
		os.rm(path) or {}
		return false
	}
	store.index_snapshot_payload = data[24..].clone()
	store.index_snapshot_entries = entry_count
	return true
}

fn (mut store ChunkStore) index_add(cid []u8, entry ChunkStoreEntry) {
	prefix, suffix := chunk_store_index_parts(cid)
	store.index_add_parts(prefix, suffix, entry)
}

fn (mut store ChunkStore) index_add_parts(prefix u64, suffix u64, entry ChunkStoreEntry) {
	mut bucket := store.index[prefix] or { []ChunkStoreIndexEntry{} }
	bucket << ChunkStoreIndexEntry{
		suffix: suffix
		entry: entry
	}
	store.index[prefix] = bucket
	if store.maintain_index {
		chunk_store_append_u64_le(mut store.index_snapshot_payload, prefix)
		chunk_store_append_u64_le(mut store.index_snapshot_payload, suffix)
		chunk_store_append_u64_le(mut store.index_snapshot_payload, entry.offset)
		chunk_store_append_u32_le(mut store.index_snapshot_payload, u32(entry.length))
		store.index_snapshot_entries++
	}
}

fn (mut store ChunkStore) rebuild_index_from_entries(chunk_cids []ChunkCid, entries []ChunkStoreEntry) {
	if !store.maintain_index || chunk_cids.len == 0 || chunk_cids.len != entries.len {
		return
	}
	for idx, chunk_cid in chunk_cids {
		store.index_add(chunk_cid.cid, entries[idx])
	}
}

fn (mut store ChunkStore) rebuild_index_from_file() ! {
	if store.write_offset == 0 {
		return
	}
	store.index = map[u64][]ChunkStoreIndexEntry{}
	store.index_snapshot_payload = []u8{}
	store.index_snapshot_entries = 0
	$if darwin || linux {
		store.rebuild_index_from_mmap()!
	} $else {
		store.rebuild_index_from_file_reads()!
	}
	// A rebuilt in-memory index means the on-disk snapshot is stale or missing.
	store.index_dirty = true
	store.index_snapshot_sync_pending = false
}

fn (mut store ChunkStore) rebuild_index_from_file_reads() ! {
	mut offset := u64(0)
	mut header := []u8{len: 8}
	for offset < store.write_offset {
		_ = store.file.read_bytes_into(offset, mut header)!
		cid_len := int(chunk_store_read_u32_le(header[..4]))
		data_len := int(chunk_store_read_u32_le(header[4..8]))
		if cid_len <= 0 || data_len < 0 {
			return error('invalid chunk record at offset ${offset}')
		}
		mut cid := []u8{len: cid_len}
		_ = store.file.read_bytes_into(offset + 8, mut cid)!
		entry := ChunkStoreEntry{
			offset: offset
			length: data_len
		}
		store.index_add(cid, entry)
		offset += u64(8 + cid_len + data_len)
	}
}

fn (store ChunkStore) index_get(cid []u8) !ChunkStoreEntry {
	prefix, suffix := chunk_store_index_parts(cid)
	bucket := store.index[prefix] or {
		return error('chunk not found')
	}
	for item in bucket {
		if item.suffix == suffix {
			return item.entry
		}
	}
	return error('chunk not found')
}

fn chunk_store_record_header(cid_len int, data_len int) []u8 {
	mut out := []u8{cap: 8}
	chunk_store_append_header(mut out, cid_len, data_len)
	return out
}

fn chunk_store_append_header(mut out []u8, cid_len int, data_len int) {
	out << [
		u8(cid_len & 0xff),
		u8((cid_len >> 8) & 0xff),
		u8((cid_len >> 16) & 0xff),
		u8((cid_len >> 24) & 0xff),
		u8(data_len & 0xff),
		u8((data_len >> 8) & 0xff),
		u8((data_len >> 16) & 0xff),
		u8((data_len >> 24) & 0xff),
	]
}

fn chunk_store_append_record(mut out []u8, cid []u8, data []u8) {
	chunk_store_append_header(mut out, cid.len, data.len)
	out << cid
	out << data
}

fn chunk_store_fill_header(mut out [8]u8, cid_len int, data_len int) {
	out[0] = u8(cid_len & 0xff)
	out[1] = u8((cid_len >> 8) & 0xff)
	out[2] = u8((cid_len >> 16) & 0xff)
	out[3] = u8((cid_len >> 24) & 0xff)
	out[4] = u8(data_len & 0xff)
	out[5] = u8((data_len >> 8) & 0xff)
	out[6] = u8((data_len >> 16) & 0xff)
	out[7] = u8((data_len >> 24) & 0xff)
}

fn chunk_store_read_u32_le(data []u8) u32 {
	return u32(data[0]) | (u32(data[1]) << 8) | (u32(data[2]) << 16) | (u32(data[3]) << 24)
}

fn chunk_store_append_u32_le(mut out []u8, value u32) {
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
}

fn chunk_store_write_u32_le(mut out []u8, offset int, value u32) {
	out[offset + 0] = u8(value & 0xff)
	out[offset + 1] = u8((value >> 8) & 0xff)
	out[offset + 2] = u8((value >> 16) & 0xff)
	out[offset + 3] = u8((value >> 24) & 0xff)
}

fn chunk_store_append_u64_le(mut out []u8, value u64) {
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		out << u8((value >> shift) & 0xff)
	}
}

fn chunk_store_read_u64_le(data []u8, start int) u64 {
	mut value := u64(0)
	for idx in 0 .. 8 {
		value |= u64(data[start + idx]) << (idx * 8)
	}
	return value
}

fn chunk_store_index_parts(cid []u8) (u64, u64) {
	return chunk_store_read_u64_be(cid, 0), chunk_store_read_u64_be(cid, 8)
}

fn chunk_store_read_u64_be(data []u8, start int) u64 {
	mut value := u64(0)
	for idx in 0 .. 8 {
		pos := start + idx
		byte := if pos < data.len { data[pos] } else { u8(0) }
		value = (value << 8) | u64(byte)
	}
	return value
}
