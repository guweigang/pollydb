module storage

#include <sys/uio.h>
#include <unistd.h>

struct C.iovec {
mut:
	iov_base voidptr
	iov_len  usize
}

fn C.writev(fd int, iov &C.iovec, iovcnt int) int
fn C.fsync(fd int) int

const chunk_store_writev_batch_size = 256

pub fn chunk_store_fsync_fd(fd int) ! {
	if C.fsync(fd) != 0 {
		return error('fsync failed')
	}
}

fn (mut store ChunkStore) put_chunk_cids_writev(data []u8, chunk_cids []ChunkCid) ![]ChunkStoreEntry {
	if chunk_cids.len == 0 {
		return []ChunkStoreEntry{}
	}
	store.file.flush()
	mut entries := []ChunkStoreEntry{cap: chunk_cids.len}
	mut offset := store.write_offset
	unsafe {
		base := &u8(data.data)
		mut batch_start := 0
		for batch_start < chunk_cids.len {
			batch_end := if batch_start + chunk_store_writev_batch_size < chunk_cids.len {
				batch_start + chunk_store_writev_batch_size
			} else {
				chunk_cids.len
			}
			batch := chunk_cids[batch_start..batch_end]
			mut headers := [][8]u8{len: batch.len}
			mut iovecs := []C.iovec{cap: batch.len * 3}
			for idx, chunk_cid in batch {
				chunk_store_fill_header(mut headers[idx], chunk_cid.cid.len, chunk_cid.chunk.length)
				iovecs << C.iovec{
					iov_base: &u8(&headers[idx][0])
					iov_len: usize(8)
				}
				iovecs << C.iovec{
					iov_base: chunk_cid.cid.data
					iov_len: usize(chunk_cid.cid.len)
				}
				iovecs << C.iovec{
					iov_base: base + chunk_cid.chunk.start
					iov_len: usize(chunk_cid.chunk.length)
				}
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
			written := C.writev(store.file.fd, &iovecs[0], iovecs.len)
			expected := int(offset - store.write_offset)
			if written != expected {
				return error('writev wrote ${written} bytes, expected ${expected}')
			}
			store.write_offset = offset
				batch_start = batch_end
			}
	}
	store.data_dirty = true
	store.file.seek(0, .end) or {}
	return entries
}
