module storage

#include <sys/mman.h>

fn C.mmap(addr voidptr, len usize, prot int, flags int, fd int, offset i64) voidptr
fn C.munmap(addr voidptr, len usize) int

fn chunk_store_read_u64_be_ptr(base &u8, cid_len int, start int) u64 {
	mut value := u64(0)
	for idx in 0 .. 8 {
		pos := start + idx
		byte := if pos < cid_len { unsafe { *(base + pos) } } else { u8(0) }
		value = (value << 8) | u64(byte)
	}
	return value
}

fn (mut store ChunkStore) rebuild_index_from_mmap() ! {
	if store.write_offset == 0 {
		return
	}
	unsafe {
		mapped :=
			C.mmap(nil, usize(store.write_offset), C.PROT_READ, C.MAP_SHARED, store.file.fd, 0)
		if mapped == voidptr(-1) {
			return error('mmap failed for chunk store index rebuild')
		}
		defer {
			C.munmap(mapped, usize(store.write_offset))
		}
		base := &u8(mapped)
		mut offset := u64(0)
		for offset < store.write_offset {
			if store.write_offset - offset < 8 {
				return error('truncated chunk header at offset ${offset}')
			}
			header := base + int(offset)
			cid_len := int(*header) | (int(*(header + 1)) << 8) | (int(*(header + 2)) << 16) | (int(*(
				header + 3)) << 24)
			data_len := int(*(header + 4)) | (int(*(header + 5)) << 8) | (int(*(header + 6)) << 16) | (int(*(
				header + 7)) << 24)
			if cid_len <= 0 || data_len < 0 {
				return error('invalid chunk record at offset ${offset}')
			}
			record_len := u64(8) + u64(cid_len) + u64(data_len)
			if record_len > store.write_offset - offset {
				return error('truncated chunk record at offset ${offset}')
			}
			cid_ptr := header + 8
			entry := ChunkStoreEntry{
				offset: offset
				length: data_len
			}
			prefix := chunk_store_read_u64_be_ptr(cid_ptr, cid_len, 0)
			suffix := chunk_store_read_u64_be_ptr(cid_ptr, cid_len, 8)
			store.index_add_parts(prefix, suffix, entry)
			offset += record_len
		}
	}
}
