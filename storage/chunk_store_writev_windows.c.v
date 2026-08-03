module storage

#include <io.h>
#include <windows.h>
#define pollytree_flush_fd(fd) FlushFileBuffers((HANDLE)_get_osfhandle(fd))

fn C.pollytree_flush_fd(fd int) int
fn C.GetLastError() u32

const chunk_store_writev_batch_size = 256

pub fn chunk_store_fsync_fd(fd int) ! {
	if C.pollytree_flush_fd(fd) == 0 {
		return error('failed to flush Windows file buffers: ${C.GetLastError()}')
	}
}

// Windows WriteFileGather requires page-aligned buffers and overlapped I/O.
// A bounded coalescing buffer gives the same append format with one write per batch.
fn (mut store ChunkStore) put_chunk_cids_writev(data []u8, chunk_cids []ChunkCid) ![]ChunkStoreEntry {
	if chunk_cids.len == 0 {
		return []ChunkStoreEntry{}
	}
	store.file.seek(0, .end)!
	mut entries := []ChunkStoreEntry{cap: chunk_cids.len}
	mut offset := store.write_offset
	mut batch_start := 0
	for batch_start < chunk_cids.len {
		batch_end := if batch_start + chunk_store_writev_batch_size < chunk_cids.len {
			batch_start + chunk_store_writev_batch_size
		} else {
			chunk_cids.len
		}
		batch := chunk_cids[batch_start..batch_end]
		mut batch_len := 0
		for chunk_cid in batch {
			batch_len += 8 + chunk_cid.cid.len + chunk_cid.chunk.length
		}
		mut records := []u8{cap: batch_len}
		for chunk_cid in batch {
			chunk_store_append_header(mut records, chunk_cid.cid.len, chunk_cid.chunk.length)
			records << chunk_cid.cid
			records << data[chunk_cid.chunk.start..chunk_cid.chunk.end]
			entry := ChunkStoreEntry{
				offset: offset
				length: chunk_cid.chunk.length
			}
			entries << entry
			if store.maintain_index && !store.defer_index_build {
				store.index_add(chunk_cid.cid, entry)
				store.index_dirty = true
			}
			offset += u64(8 + chunk_cid.cid.len + chunk_cid.chunk.length)
		}
		written := store.file.write(records)!
		if written != records.len {
			return error('batch write wrote ${written} bytes, expected ${records.len}')
		}
		store.write_offset = offset
		batch_start = batch_end
	}
	store.data_dirty = true
	return entries
}
