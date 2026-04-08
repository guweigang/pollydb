module storage

import os
import sync
import time

pub const default_min_chunk_size = 2 * 1024
pub const default_max_chunk_size = 8 * 1024
pub const default_chunk_mask = u64(0x00000fff)
pub const default_chunk_read_size = 1024 * 1024
pub const default_cid_size = u64(16)

pub struct ChunkConfig {
pub:
	min_size int = default_min_chunk_size
	max_size int = default_max_chunk_size
	mask     u64 = default_chunk_mask
	detailed_timings bool
	enable_partitioned_rebuild bool = true
	force_partitioned_rebuild bool
	enable_split_backed_working_set bool
}

pub struct Chunk {
pub:
	start       int
	end         int
	length      int
	fingerprint u64
}

pub struct ChunkCid {
pub:
	chunk Chunk
	cid   []u8
}

pub struct ChunkIngestConfig {
pub:
	worker_count  int  = 1
	collect_chunks bool = true
}

pub struct ChunkIngestResult {
pub:
	chunk_cids []ChunkCid
	count      int
	chunk_ms   i64
	cid_ms     i64
	write_ms   i64
}

pub struct BufferManager {
pub:
	path         string
	read_size    int = default_chunk_read_size
	overlap_size int = default_max_chunk_size
}

struct ChunkBoundary {
	split_at    int
	fingerprint u64
}

const gear_table = [
	u64(0x37c59ca7bf06be52), 0x167a05ab294167ae, 0xaae6f93d9e7dcee1, 0xe5e54fba9996ad3c,
	0x3de881e3c2654f66, 0x8d373ae10dae9c78, 0xf07b2259c91ddf40, 0x6381776cefec34fe,
	0x2b7ea4066d8f1317, 0xd4c85480b11028f1, 0x3bab10ebd8a614e0, 0x5754cf34259c60c9,
	0x910e62bc32464a48, 0xf39972cfbb4154dc, 0xd522b95e1c136175, 0x535ef992bd33baf7,
	0x63a5309ba37d8042, 0x94c6dedbacd72bc2, 0x6fac066fa1163515, 0x8deccb5e0505fc3f,
	0x1f7c8a0777f91807, 0xb7435491b3be0bf7, 0x5c2dbc696a656a20, 0x4a78c959dd4728f4,
	0xf9dce146ed631ba5, 0xcc19628472af94d2, 0x1f9939635dc3bf7b, 0x4839008f91f286c5,
	0x2e51e60447b87288, 0x8ae912dbefa0a06d, 0xbe00434510805a6d, 0xd62b536372c86199,
	0xdbbfa74d6432b71a, 0x60b1eeb40d5c54f4, 0x1e5ed05b1a77515d, 0xf53aaf0b4ac248bf,
	0x42253a7ba20e03ee, 0xd1ecb7c85e652469, 0x696271475bdfd461, 0x3915bf2a7f035389,
	0xadba139aaf84976e, 0x47db06c1e29385c0, 0x5e8056f91099d2cb, 0xc0f0372999c933ae,
	0x9ba8139f8a518a49, 0x32c875cd26549b1d, 0x5942461f108b556b, 0x5f2e6ae294d07901,
	0x2b46098719a1b9b3, 0xe56e96f3a4caf600, 0x3083dc53e826e3ec, 0x2fb486723065d52b,
	0xd5f8da541f573441, 0xb5343554d0feaa69, 0x17d2b5644942ed7d, 0xc195d9bda30a97e7,
	0x2859b92c7e059b08, 0x8240e77db082523e, 0x800c4daf1304191a, 0xb08ac29e205717a8,
	0x803b62d74c295387, 0x7d30cd6ec35500e0, 0x3a08f8314e4d92e1, 0xbdf2d7882ee19184,
	0x4d2cbc21d3a6b3a7, 0x75ae88ea41d9f700, 0xeb5b1cdfd41b84ee, 0x46f15c0e8d014867,
	0xb4c19e3e9f2bb337, 0x0488fc7fcdbdc991, 0x0cb6c30e08e2f642, 0x8d52491bb4dae32e,
	0x7e060f2353be5d68, 0xfda1c3d8c6877bd2, 0x192d1de3bae4c1a5, 0x2b30f141de59c166,
	0xc34d1c6c2571eb64, 0x53e621a93f4951b2, 0xd6658ae74a77ef91, 0x452ad8bb6cf6c40e,
	0x829e30702b13ea06, 0x6ee9f0876a5b8c52, 0x8fb7e83b5c726fca, 0xb73115e208823995,
	0x081118045a63f8a6, 0x4b9ada151893d6d7, 0x831310ee25f9a4ba, 0x733faf61c1aa3973,
	0xe72a6f688c0b51c1, 0x4bba9bea1bbb1722, 0xb6aed07790b5e98c, 0xa832bd9b2d61615f,
	0x4970051747f2145d, 0xd924e6d459194735, 0x672caf14aeea18fb, 0xbe535ae15a3a920a,
	0x0a2fe7930f3725ae, 0x8dc23dd2c09fe065, 0xe1f9e8de732066e5, 0x18b5f4f175d33f68,
	0xbc9885cb02364316, 0xe1f405c685e02a10, 0xf82ea796a92b6e44, 0xb8288c82f05a2998,
	0xeeb2ef2b5195fbcb, 0xe616907158c942fc, 0x204dcaf17e85ef79, 0x1df6c333b5221ae7,
	0xede227d8d7b60712, 0xb6e399a19442ef9c, 0xcca3303b80a40d43, 0xbaafb6b3b43c7599,
	0x2b899640c49e4b32, 0x02ee5a095dabfb24, 0x96829a4a912ee5d2, 0x7bbf79e08a3d8c99,
	0x494685c59659f1c0, 0x0e0ca102d1773223, 0xdeac7c6006533487, 0x29245457925e532e,
	0x54493a47a89be408, 0xea7337afde32d1c0, 0x0e7d6ff4dfc4c463, 0x450c4c683590352b,
	0x5d8746e9f8513f81, 0x2e10fd2ca3625dbe, 0x36f2d19a040e3685, 0x486bf88fa20b2ba8,
	0xc6ba4d36f50ed7ff, 0xdb62a9edaa8ed590, 0xca49b33c50aaac3b, 0x3760cb14786197a3,
	0xaf7eb491c298dc4c, 0xd2a9ec9da14b7ef4, 0xb6ef62140d1ad509, 0x2af8ca593cd282e3,
	0x27e55eb7141bff26, 0x3bb3dd1d8198c158, 0xdb79c4f58934a6da, 0x9451cc90c9fa3917,
	0x0891f18e008f68a5, 0xd534d57d2c28ff34, 0xc337c14a043de3ca, 0x42f4faa6762e2a8d,
	0x340d9c399f297598, 0xf383ab718a1f4173, 0x05ec4cec80974331, 0xf3e6170697ce81f7,
	0xa18dba8bbb178134, 0xfe14473c5fcb6336, 0x20a758c9492af870, 0xd036911ead08b180,
	0xde7ce6ab4588c0e3, 0xf8200f597a6b89a2, 0x9490f0c6cf2b7631, 0xf97ef42cff948c9d,
	0x1da738bf975322c4, 0xacc71a1a33efb581, 0xe6a541755f812aaa, 0xb4b61d13f4dfc27f,
	0xe164725d18ff023b, 0x7231747258b712ff, 0xde32a62035a9231a, 0x104b3a07d451f7dc,
	0xd9fc35f2b7192333, 0x90538764cb33bdb5, 0x210313c696e0178e, 0x2ecc74eb497bf421,
	0xdeeec0dfe8822b89, 0xa990b2e5e994ed9e, 0x912222561d4563c5, 0xb4b8a8823cdbb842,
	0xdd654c4fc6205fb2, 0xafc0d979bd57b38d, 0xd79bea6e52e45faa, 0xb366f534c7893d95,
	0xb7273ae9bea7eaae, 0xa2948bcca483cefb, 0xb94e0cae4baa17a6, 0x9c8b0cc86b5e6a09,
	0xb7a9e7060869749d, 0xe2d1d52972df2134, 0xfcccf52cd7385276, 0x1885288cb4687f52,
	0x9214e697cead3b2c, 0x2822494ab9af2a5a, 0x714e4cf8e741a28e, 0x5cc117dc7620424b,
	0xa6927101ae8bf00f, 0xa9d1c20f7975042f, 0x8a4439fd918d05e7, 0xf4d62e7ca50b862c,
	0x222b55635a259a20, 0x28a17d3d149b5914, 0xa32a949c760aaaa6, 0x20895a5835fed673,
	0xbb6999838ed0d71f, 0x3e5b15bf85f95171, 0x25c061db11aedf93, 0xc27ada791a1006ec,
	0xbd954b39573a1de1, 0x1ee0d443cb9b319a, 0xfcb5e58c8e012179, 0xb9cc1a50898c5d7b,
	0x341c873936257b01, 0x08ce9251c119d1b7, 0x9d7d9e94c1716fd4, 0x9f9d6a126944f80b,
	0x00539e26a5df133b, 0xbb609e667a8d03dd, 0xbad6631328774e9a, 0xaa7a9a5f77294687,
	0xd46540df80d255ca, 0xe7cece5bc63dc3e1, 0x459b308b86f16026, 0x8a675795976c4b66,
	0xfd3112cbfadc8a70, 0xa4402bc0158daf64, 0x123cdf609955ed3a, 0x53660ca4207b4860,
	0x48a352715205a6f0, 0x672ba8eda66c11bd, 0xf222b83e69af06de, 0xdbac032dc0c02f53,
	0x0bf97503993a1bcd, 0x4d4293c6ea833cba, 0x6b137a1708885443, 0x743924386652342b,
	0xf958dd8e3190fa83, 0x703a64b161f11bb6, 0x1ce9a81bf400d401, 0x2fd4b18d328ff5e9,
	0x037036a6152eb042, 0x7e7834aabfe4bda2, 0x0b3db1903cb25c59, 0xeea15ec466950ea1,
	0x8796f42db337acfc, 0x903ec485296f7ca5, 0x32e81387c14e2b1c, 0x840b6a32b8b1f04a,
	0xa62238354de1c12a, 0x51b216f4777f0828, 0x911d03865926fc38, 0x1768946abc2cbfc0,
	0x153fe36ed8fd16bf, 0xd083adbcde7aa352, 0x18408416e82cc294, 0xb391709c2abcbe11,
	0x7cf9a428ec5e632d, 0xc94c8c270f2db4ab, 0xa24b848e76cfa502, 0x2ef9a41558fb3ac8,
	0xe867aeaed6a77ebd, 0x3cac8a96b3023f00, 0xec3b9258eff7fb7e, 0x423ed7cb4aa90b08,
]

pub fn rolling_hash(prev u64, b u8) u64 {
	return (prev << 1) + gear_table[int(b)]
}

pub fn chunk_cid_bytes(data []u8) []u8 {
	if data.len == 0 {
		return xxh3_sum128_ptr(unsafe { nil }, 0)
	}
	unsafe {
		return xxh3_sum128_ptr(&u8(data.data), data.len)
	}
}

pub fn chunk_cid_hex(data []u8) string {
	return chunk_cid_bytes(data).hex()
}

fn chunk_cid_from_ptr(base &u8, start int, length int) []u8 {
	if length <= 0 {
		return xxh3_sum128_ptr(unsafe { nil }, 0)
	}
	unsafe {
		return xxh3_sum128_ptr(base + start, length)
	}
}

pub fn ChunkConfig.default() ChunkConfig {
	return ChunkConfig{}
}

pub fn (cfg ChunkConfig) with_detailed_timings(enabled bool) ChunkConfig {
	return ChunkConfig{
		min_size: cfg.min_size
		max_size: cfg.max_size
		mask: cfg.mask
		detailed_timings: enabled
		enable_partitioned_rebuild: cfg.enable_partitioned_rebuild
		force_partitioned_rebuild: cfg.force_partitioned_rebuild
		enable_split_backed_working_set: cfg.enable_split_backed_working_set
	}
}

pub fn (cfg ChunkConfig) with_partitioned_rebuild(enabled bool) ChunkConfig {
	return ChunkConfig{
		min_size: cfg.min_size
		max_size: cfg.max_size
		mask: cfg.mask
		detailed_timings: cfg.detailed_timings
		enable_partitioned_rebuild: enabled
		force_partitioned_rebuild: cfg.force_partitioned_rebuild
		enable_split_backed_working_set: cfg.enable_split_backed_working_set
	}
}

pub fn (cfg ChunkConfig) with_force_partitioned_rebuild(enabled bool) ChunkConfig {
	return ChunkConfig{
		min_size: cfg.min_size
		max_size: cfg.max_size
		mask: cfg.mask
		detailed_timings: cfg.detailed_timings
		enable_partitioned_rebuild: cfg.enable_partitioned_rebuild
		force_partitioned_rebuild: enabled
		enable_split_backed_working_set: cfg.enable_split_backed_working_set
	}
}

pub fn (cfg ChunkConfig) with_split_backed_working_set(enabled bool) ChunkConfig {
	return ChunkConfig{
		min_size: cfg.min_size
		max_size: cfg.max_size
		mask: cfg.mask
		detailed_timings: cfg.detailed_timings
		enable_partitioned_rebuild: cfg.enable_partitioned_rebuild
		force_partitioned_rebuild: cfg.force_partitioned_rebuild
		enable_split_backed_working_set: enabled
	}
}

pub fn BufferManager.new(path string, read_size int, overlap_size int) !BufferManager {
	if path.len == 0 {
		return error('buffer manager path cannot be empty')
	}
	if read_size <= 0 {
		return error('buffer manager read_size must be positive')
	}
	if overlap_size <= 0 {
		return error('buffer manager overlap_size must be positive')
	}
	return BufferManager{
		path: path
		read_size: read_size
		overlap_size: overlap_size
	}
}

pub fn BufferManager.default_for(path string) !BufferManager {
	return BufferManager.new(path, default_chunk_read_size, default_max_chunk_size)
}

pub fn ChunkIngestConfig.default() ChunkIngestConfig {
	return ChunkIngestConfig{}
}

pub fn ChunkIngestConfig.high_throughput() ChunkIngestConfig {
	return ChunkIngestConfig{
		worker_count: 1
		collect_chunks: false
	}
}

pub fn ChunkIngestConfig.recommended() ChunkIngestConfig {
	return ChunkIngestConfig.high_throughput()
}

pub fn ChunkIngestConfig.analysis(worker_count int) ChunkIngestConfig {
	return ChunkIngestConfig{
		worker_count: worker_count
		collect_chunks: true
	}
}

pub fn ChunkIngestConfig.parallel(worker_count int) ChunkIngestConfig {
	return ChunkIngestConfig{
		worker_count: worker_count
	}
}

pub fn (cfg ChunkIngestConfig) normalized() ChunkIngestConfig {
	return ChunkIngestConfig{
		worker_count: if cfg.worker_count > 0 { cfg.worker_count } else { 1 }
		collect_chunks: cfg.collect_chunks
	}
}

pub fn ChunkConfig.generate_deterministic_gear_table() []u64 {
	mut table := []u64{len: 256}
	mut state := u64(0xdeadbeef)
	for i in 0 .. 256 {
		state ^= state << 13
		state ^= state >> 7
		state ^= state << 17
		table[i] = state
	}
	return table
}

pub fn generate_deterministic_gear_table() []u64 {
	return ChunkConfig.generate_deterministic_gear_table()
}

pub fn (cfg ChunkConfig) validate() ! {
	if cfg.min_size <= 0 {
		return error('min_size must be positive')
	}
	if cfg.max_size < cfg.min_size {
		return error('max_size must be greater than or equal to min_size')
	}
}

pub fn validate_config(cfg ChunkConfig) ! {
	cfg.validate()!
}

@[direct_array_access]
fn fast_cdc_core(data &u8, len int, min_size int, max_size int, mask u64) ChunkBoundary {
	if len <= 0 {
		return ChunkBoundary{
			split_at: 0
			fingerprint: 0
		}
	}
	if len <= min_size {
		mut hash := u64(0)
		unsafe {
			mut p := data
			for _ in 0 .. len {
				hash = (hash << 1) + gear_table[*p]
				p++
			}
		}
		return ChunkBoundary{
			split_at: len
			fingerprint: hash
		}
	}
	mut hash := u64(0)
	mut idx := 0
	limit := if len < max_size { len } else { max_size }
	unsafe {
		mut p := data
		for idx < min_size {
			hash = (hash << 1) + gear_table[*p]
			idx++
			p++
		}
		if (hash & mask) == 0 {
			return ChunkBoundary{
				split_at: idx
				fingerprint: hash
			}
		}
		for idx < limit {
			hash = (hash << 1) + gear_table[*p]
			idx++
			if (hash & mask) == 0 {
				return ChunkBoundary{
					split_at: idx
					fingerprint: hash
				}
			}
			p++
		}
	}
	return ChunkBoundary{
		split_at: limit
		fingerprint: hash
	}
}

pub fn (cfg ChunkConfig) chunk_bytes(data []u8) ![]Chunk {
	cfg.validate()!
	if data.len == 0 {
		return []Chunk{}
	}

	mut chunks := []Chunk{}
	mut start := 0
	unsafe {
		base := &u8(data.data)
		for start < data.len {
			boundary := fast_cdc_core(base + start, data.len - start, cfg.min_size, cfg.max_size, cfg.mask)
			length := boundary.split_at
			if length <= 0 {
				break
			}
			chunks << Chunk{
				start: start
				end: start + length
				length: length
				fingerprint: boundary.fingerprint
			}
			start += length
		}
	}

	return chunks
}

pub fn chunk_bytes(data []u8, cfg ChunkConfig) ![]Chunk {
	return cfg.chunk_bytes(data)
}

pub fn (mgr BufferManager) chunk_file(cfg ChunkConfig) ![]Chunk {
	cfg.validate()!
	mut file := os.open(mgr.path)!
	defer {
		file.close()
	}
	mut read_buf := []u8{len: mgr.read_size}
	mut chunks := []Chunk{}
	mut hash := u64(0)
	mut chunk_start := 0
	mut chunk_len := 0
	mut absolute_offset := 0
	for {
		nread := file.read(mut read_buf) or {
			if err is os.Eof {
				0
			} else {
				return err
			}
		}
		if nread <= 0 {
			break
		}
		unsafe {
			base := &u8(read_buf.data)
			for idx := 0; idx < nread; idx++ {
				hash = rolling_hash(hash, base[idx])
				chunk_len++
				if chunk_len < cfg.min_size {
					continue
				}
				if chunk_len >= cfg.max_size || (hash & cfg.mask) == 0 {
					end := absolute_offset + idx + 1
					chunks << Chunk{
						start: chunk_start
						end: end
						length: chunk_len
						fingerprint: hash
					}
					chunk_start = end
					chunk_len = 0
					hash = 0
				}
			}
		}
		absolute_offset += nread
	}
	if chunk_len > 0 {
		chunks << Chunk{
			start: chunk_start
			end: absolute_offset
			length: chunk_len
			fingerprint: hash
		}
	}
	return chunks
}

pub fn (mgr BufferManager) chunk_file_cids(cfg ChunkConfig) ![]ChunkCid {
	cfg.validate()!
	data := os.read_bytes(mgr.path)!
	return cfg.chunk_bytes_with_cids(data)
}

pub fn (mgr BufferManager) chunk_file_cids_with_workers(cfg ChunkConfig, worker_count int) ![]ChunkCid {
	if worker_count <= 1 {
		return mgr.chunk_file_cids(cfg)
	}
	return mgr.chunk_file_cids_parallel(cfg, worker_count)
}

pub fn (mgr BufferManager) chunk_file_cids_parallel(cfg ChunkConfig, worker_count int) ![]ChunkCid {
	cfg.validate()!
	data := os.read_bytes(mgr.path)!
	return chunk_bytes_async_hash(data, cfg, worker_count)
}

pub fn (mgr BufferManager) chunk_file_cids_to_store_with_workers(cfg ChunkConfig, mut store ChunkStore, worker_count int) ![]ChunkCid {
	if worker_count <= 1 {
		return mgr.chunk_file_cids_to_store(cfg, mut store)
	}
	cfg.validate()!
	data := os.read_bytes(mgr.path)!
	chunk_cids := chunk_bytes_async_hash(data, cfg, worker_count)!
	_ = store_chunk_cids(mut store, data, chunk_cids)!
	return chunk_cids
}

pub fn (mgr BufferManager) ingest_to_store(cfg ChunkConfig, ingest_cfg ChunkIngestConfig, mut store ChunkStore) !ChunkIngestResult {
	normalized := ingest_cfg.normalized()
	if normalized.collect_chunks {
		chunk_cids := mgr.chunk_file_cids_to_store_with_workers(cfg, mut store, normalized.worker_count)!
		return ChunkIngestResult{
			chunk_cids: chunk_cids
			count: chunk_cids.len
		}
	}
	count := mgr.chunk_file_to_store_with_workers(cfg, mut store, normalized.worker_count)!
	return ChunkIngestResult{
		count: count
	}
}

pub fn (mgr BufferManager) chunk_file_to_store_parallel(cfg ChunkConfig, mut store ChunkStore, worker_count int) !int {
	cfg.validate()!
	data := os.read_bytes(mgr.path)!
	chunk_cids := chunk_bytes_async_hash(data, cfg, worker_count)!
	return store_chunk_cids(mut store, data, chunk_cids)!
}

pub fn (mgr BufferManager) chunk_file_to_store_with_workers(cfg ChunkConfig, mut store ChunkStore, worker_count int) !int {
	if worker_count <= 1 {
		return mgr.chunk_file_to_store(cfg, mut store)
	}
	return mgr.chunk_file_to_store_parallel(cfg, mut store, worker_count)
}

pub fn hash_chunks(data []u8, chunks []Chunk) []ChunkCid {
	mut out := []ChunkCid{cap: chunks.len}
	unsafe {
		base := &u8(data.data)
		for chunk in chunks {
			out << ChunkCid{
				chunk: chunk
				cid: chunk_cid_from_ptr(base, chunk.start, chunk.length)
			}
		}
	}
	return out
}

pub fn (cfg ChunkConfig) chunk_bytes_with_cids(data []u8) ![]ChunkCid {
	cfg.validate()!
	if data.len == 0 {
		return []ChunkCid{}
	}
	mut out := []ChunkCid{}
	mut start := 0
	unsafe {
		base := &u8(data.data)
		for start < data.len {
			boundary := fast_cdc_core(base + start, data.len - start, cfg.min_size, cfg.max_size, cfg.mask)
			length := boundary.split_at
			if length <= 0 {
				break
			}
			out << ChunkCid{
				chunk: Chunk{
					start: start
					end: start + length
					length: length
					fingerprint: boundary.fingerprint
				}
				cid: chunk_cid_from_ptr(base, start, length)
			}
			start += length
		}
	}
	return out
}

pub fn hash_chunks_parallel(data []u8, chunks []Chunk, worker_count int) []ChunkCid {
	if worker_count <= 1 || chunks.len <= 1 {
		return hash_chunks(data, chunks)
	}
	actual_workers := if worker_count < chunks.len { worker_count } else { chunks.len }
	batch_size := (chunks.len + actual_workers - 1) / actual_workers
	mut results := [][]ChunkCid{len: actual_workers}
	mut wg := sync.new_waitgroup()
	for start in 0 .. actual_workers {
		batch_start := start * batch_size
		if batch_start >= chunks.len {
			break
		}
		batch_end := if batch_start + batch_size < chunks.len { batch_start + batch_size } else { chunks.len }
		batch := chunks[batch_start..batch_end].clone()
		wg.add(1)
		spawn hash_chunk_batch_into_slot(data, batch, start, voidptr(&results), mut wg)
	}
	wg.wait()
	mut out := []ChunkCid{cap: chunks.len}
	for batch in results {
		out << batch
	}
	return out
}

fn hash_chunk_batch_async(data []u8, chunks []Chunk) []ChunkCid {
	mut out := []ChunkCid{cap: chunks.len}
	unsafe {
		base := &u8(data.data)
		for chunk in chunks {
			out << ChunkCid{
				chunk: chunk
				cid: chunk_cid_from_ptr(base, chunk.start, chunk.length)
			}
		}
	}
	return out
}

fn hash_chunk_batch_into_slot(data []u8, chunks []Chunk, slot int, results voidptr, mut wg sync.WaitGroup) {
	defer {
		wg.done()
	}
	computed := hash_chunk_batch_async(data, chunks)
	unsafe {
		mut batches := &[][]ChunkCid(results)
		(*batches)[slot] = computed
	}
}

fn chunk_bytes_async_hash(data []u8, cfg ChunkConfig, worker_count int) ![]ChunkCid {
	cfg.validate()!
	if data.len == 0 {
		return []ChunkCid{}
	}
	if worker_count <= 1 {
		chunks := cfg.chunk_bytes(data)!
		return hash_chunks(data, chunks)
	}
	unsafe {
		base := &u8(data.data)
		batch_size := if worker_count > 0 { worker_count * 32 } else { 128 }
		mut batches := [][]ChunkCid{}
		mut wg := sync.new_waitgroup()
		mut batch := []Chunk{cap: batch_size}
		mut start := 0
		mut slot := 0
		for start < data.len {
			boundary := fast_cdc_core(base + start, data.len - start, cfg.min_size, cfg.max_size, cfg.mask)
			length := boundary.split_at
			if length <= 0 {
				break
			}
			batch << Chunk{
				start: start
				end: start + length
				length: length
				fingerprint: boundary.fingerprint
			}
			if batch.len >= batch_size {
				batches << []ChunkCid{}
				wg.add(1)
				spawn hash_chunk_batch_into_slot(data, batch.clone(), slot, voidptr(&batches), mut wg)
				slot++
				batch = []Chunk{cap: batch_size}
			}
			start += length
		}
		if batch.len > 0 {
			batches << []ChunkCid{}
			wg.add(1)
			spawn hash_chunk_batch_into_slot(data, batch.clone(), slot, voidptr(&batches), mut wg)
		}
		wg.wait()
		mut out := []ChunkCid{}
		for hashed_batch in batches {
			out << hashed_batch
		}
		return out
	}
}

fn store_chunk_cids(mut store ChunkStore, data []u8, chunk_cids []ChunkCid) !int {
	if chunk_cids.len == 0 {
		return 0
	}
	_ = store.put_chunk_cids_scatter(data, chunk_cids)!
	store.finalize_deferred_index_build()!
	return chunk_cids.len
}

pub fn (mgr BufferManager) ingest_to_store_profiled(cfg ChunkConfig, ingest_cfg ChunkIngestConfig, mut store ChunkStore) !ChunkIngestResult {
	normalized := ingest_cfg.normalized()
	if normalized.worker_count <= 1 {
		data := os.read_bytes(mgr.path)!
		mut cid_sw := time.new_stopwatch()
		chunk_cids := cfg.chunk_bytes_with_cids(data)!
		cid_ms := cid_sw.elapsed().milliseconds()
		mut write_sw := time.new_stopwatch()
		count := store_chunk_cids(mut store, data, chunk_cids)!
		write_ms := write_sw.elapsed().milliseconds()
		return ChunkIngestResult{
			chunk_cids: if normalized.collect_chunks { chunk_cids } else { []ChunkCid{} }
			count: count
			cid_ms: cid_ms
			write_ms: write_ms
		}
	}
	cfg.validate()!
	data := os.read_bytes(mgr.path)!
	mut cid_sw := time.new_stopwatch()
	chunk_cids := chunk_bytes_async_hash(data, cfg, normalized.worker_count)!
	cid_ms := cid_sw.elapsed().milliseconds()
	mut write_sw := time.new_stopwatch()
	count := store_chunk_cids(mut store, data, chunk_cids)!
	write_ms := write_sw.elapsed().milliseconds()
	return ChunkIngestResult{
		chunk_cids: if normalized.collect_chunks { chunk_cids } else { []ChunkCid{} }
		count: count
		cid_ms: cid_ms
		write_ms: write_ms
	}
}

pub fn (mgr BufferManager) chunk_file_cids_to_store(cfg ChunkConfig, mut store ChunkStore) ![]ChunkCid {
	data := os.read_bytes(mgr.path)!
	chunk_cids := cfg.chunk_bytes_with_cids(data)!
	_ = store_chunk_cids(mut store, data, chunk_cids)!
	return chunk_cids
}

pub fn (mgr BufferManager) chunk_file_to_store(cfg ChunkConfig, mut store ChunkStore) !int {
	data := os.read_bytes(mgr.path)!
	chunk_cids := cfg.chunk_bytes_with_cids(data)!
	return store_chunk_cids(mut store, data, chunk_cids)!
}
