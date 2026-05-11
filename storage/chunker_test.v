module storage

import os

fn test_generate_deterministic_gear_table_matches_const_values() {
	table := generate_deterministic_gear_table()
	assert table.len == 256
	assert table[0] == gear_table[0]
	assert table[64] == gear_table[64]
	assert table[255] == gear_table[255]
}

fn test_rolling_hash_uses_gear_table_update_rule() {
	first := rolling_hash(0, `A`)
	second := rolling_hash(first, `B`)

	assert first == gear_table[int(`A`)]
	assert second == ((gear_table[int(`A`)] << 1) + gear_table[int(`B`)])
}

fn test_chunk_bytes_splits_immediately_after_min_when_mask_matches() {
	cfg := ChunkConfig{
		min_size: 4
		max_size: 8
		mask: 0
	}
	data := []u8{len: 18, init: u8(index)}
	chunks := chunk_bytes(data, cfg) or { panic(err) }

	assert chunks.len == 5
	assert chunks[0].length == 4
	assert chunks[1].length == 4
	assert chunks[2].length == 4
	assert chunks[3].length == 4
	assert chunks[4].length == 2
}

fn test_chunk_bytes_forces_split_at_max_size() {
	cfg := ChunkConfig{
		min_size: 4
		max_size: 8
		mask: u64(0xffffffffffffffff)
	}
	data := []u8{len: 18, init: u8(index)}
	chunks := chunk_bytes(data, cfg) or { panic(err) }

	assert chunks.len == 3
	assert chunks[0].length == 8
	assert chunks[1].length == 8
	assert chunks[2].length == 2
}

fn test_chunk_bytes_uses_single_chunk_below_min_size() {
	data := []u8{len: 1024, init: `x`}
	chunks := chunk_bytes(data, ChunkConfig{}) or { panic(err) }

	assert chunks.len == 1
	assert chunks[0].length == 1024
}

fn test_buffer_manager_chunk_file_matches_in_memory_chunking() {
	cfg := ChunkConfig.default()
	data := []u8{len: 128 * 1024, init: u8(index % 251)}
	path := os.join_path(os.vtmp_dir(), 'pollytree-buffer-manager.bin')
	defer {
		os.rm(path) or {}
	}
	os.write_bytes(path, data) or { panic(err) }
	manager := BufferManager.new(path, 16 * 1024, cfg.max_size) or { panic(err) }

	file_chunks := manager.chunk_file(cfg) or { panic(err) }
	mem_chunks := cfg.chunk_bytes(data) or { panic(err) }

	assert file_chunks.len == mem_chunks.len
	for idx in 0 .. mem_chunks.len {
		assert file_chunks[idx].start == mem_chunks[idx].start
		assert file_chunks[idx].end == mem_chunks[idx].end
		assert file_chunks[idx].length == mem_chunks[idx].length
	}
}

fn test_buffer_manager_chunk_file_cids_match_in_memory_hashes() {
	cfg := ChunkConfig.default()
	data := []u8{len: 64 * 1024, init: u8(index % 251)}
	path := os.join_path(os.vtmp_dir(), 'pollytree-buffer-manager-cids.bin')
	defer {
		os.rm(path) or {}
	}
	os.write_bytes(path, data) or { panic(err) }
	manager := BufferManager.new(path, 16 * 1024, cfg.max_size) or { panic(err) }

	file_chunks := manager.chunk_file_cids(cfg) or { panic(err) }
	mem_chunks := cfg.chunk_bytes(data) or { panic(err) }

	assert file_chunks.len == mem_chunks.len
	for idx in 0 .. mem_chunks.len {
		assert file_chunks[idx].chunk.start == mem_chunks[idx].start
		assert file_chunks[idx].chunk.end == mem_chunks[idx].end
		assert file_chunks[idx].cid == chunk_cid_bytes(data[mem_chunks[idx].start..mem_chunks[idx].end])
	}
}

fn test_chunk_store_roundtrip_from_streaming_cids() {
	cfg := ChunkConfig.default()
	data := []u8{len: 64 * 1024, init: u8(index % 251)}
	data_path := os.join_path(os.vtmp_dir(), 'pollytree-chunk-store-data.bin')
	store_path := os.join_path(os.vtmp_dir(), 'pollytree-chunk-store.bin')
	defer {
		os.rm(data_path) or {}
		os.rm(store_path) or {}
	}
	os.write_bytes(data_path, data) or { panic(err) }
	manager := BufferManager.new(data_path, 16 * 1024, cfg.max_size) or { panic(err) }
	mut store := ChunkStore.open(store_path) or { panic(err) }
	defer {
		store.close()
	}

	chunks := manager.chunk_file_cids_to_store(cfg, mut store) or { panic(err) }
	assert chunks.len > 0
	for chunk in chunks {
		assert store.has(chunk.cid)
		payload := store.get(chunk.cid) or { panic(err) }
		assert payload == data[chunk.chunk.start..chunk.chunk.end]
	}
}

fn test_chunk_store_get_rebuilds_stale_index_snapshot() {
	path := os.join_path(os.vtmp_dir(), 'pollytree-stale-index-rebuild.chunk')
	defer {
		os.rm(path) or {}
		os.rm('${path}.idx') or {}
	}
	first_cid := 'first-record'.bytes()
	second_cid := 'second-record'.bytes()
	first_data := 'alpha'.bytes()
	second_data := 'beta'.bytes()
	mut store := ChunkStore.open(path) or { panic(err) }
	store.put(first_cid, first_data) or { panic(err) }
	store.checkpoint() or { panic(err) }
	store.put(second_cid, second_data) or { panic(err) }
	store.checkpoint_mode(.data_only) or { panic(err) }
	store.close()

	mut reopened := ChunkStore.open(path) or { panic(err) }
	defer {
		reopened.close()
	}
	assert reopened.get(second_cid) or { panic(err) } == second_data
}

fn test_hash_chunks_parallel_matches_sequential() {
	cfg := ChunkConfig.default()
	data := []u8{len: 256 * 1024, init: u8(index % 251)}
	chunks := cfg.chunk_bytes(data) or { panic(err) }
	sequential := hash_chunks(data, chunks)
	parallel := hash_chunks_parallel(data, chunks, 4)

	assert parallel.len == sequential.len
	for idx in 0 .. sequential.len {
		assert parallel[idx].chunk.start == sequential[idx].chunk.start
		assert parallel[idx].chunk.end == sequential[idx].chunk.end
		assert parallel[idx].cid == sequential[idx].cid
	}
}

fn test_buffer_manager_chunk_file_cids_parallel_matches_streaming() {
	cfg := ChunkConfig.default()
	data := []u8{len: 128 * 1024, init: u8(index % 251)}
	path := os.join_path(os.vtmp_dir(), 'pollytree-buffer-manager-parallel-cids.bin')
	defer {
		os.rm(path) or {}
	}
	os.write_bytes(path, data) or { panic(err) }
	manager := BufferManager.new(path, 16 * 1024, cfg.max_size) or { panic(err) }

	sequential := manager.chunk_file_cids(cfg) or { panic(err) }
	parallel := manager.chunk_file_cids_parallel(cfg, 4) or { panic(err) }

	assert parallel.len == sequential.len
	for idx in 0 .. sequential.len {
		assert parallel[idx].chunk.start == sequential[idx].chunk.start
		assert parallel[idx].chunk.end == sequential[idx].chunk.end
		assert parallel[idx].cid == sequential[idx].cid
	}
}

fn test_buffer_manager_chunk_file_cids_to_store_with_workers_roundtrip() {
	cfg := ChunkConfig.default()
	data := []u8{len: 128 * 1024, init: u8(index % 251)}
	data_path := os.join_path(os.vtmp_dir(), 'pollytree-parallel-chunk-store-data.bin')
	store_path := os.join_path(os.vtmp_dir(), 'pollytree-parallel-chunk-store.bin')
	defer {
		os.rm(data_path) or {}
		os.rm(store_path) or {}
	}
	os.write_bytes(data_path, data) or { panic(err) }
	manager := BufferManager.new(data_path, 16 * 1024, cfg.max_size) or { panic(err) }
	mut store := ChunkStore.open(store_path) or { panic(err) }
	defer {
		store.close()
	}

	chunks := manager.chunk_file_cids_to_store_with_workers(cfg, mut store, 4) or { panic(err) }
	assert chunks.len > 0
	for chunk in chunks {
		assert store.has(chunk.cid)
		payload := store.get(chunk.cid) or { panic(err) }
		assert payload == data[chunk.chunk.start..chunk.chunk.end]
	}
}

fn test_buffer_manager_ingest_to_store_count_only() {
	cfg := ChunkConfig.default()
	data := []u8{len: 128 * 1024, init: u8(index % 251)}
	data_path := os.join_path(os.vtmp_dir(), 'pollytree-ingest-store-data.bin')
	store_path := os.join_path(os.vtmp_dir(), 'pollytree-ingest-store.bin')
	defer {
		os.rm(data_path) or {}
		os.rm(store_path) or {}
	}
	os.write_bytes(data_path, data) or { panic(err) }
	manager := BufferManager.new(data_path, 16 * 1024, cfg.max_size) or { panic(err) }
	mut store := ChunkStore.open(store_path) or { panic(err) }
	defer {
		store.close()
	}

	result := manager.ingest_to_store(cfg, ChunkIngestConfig{
		worker_count: 4
		collect_chunks: false
	}, mut store) or { panic(err) }
	assert result.count > 0
	assert result.chunk_cids.len == 0
}

fn test_buffer_manager_ingest_to_store_high_throughput_roundtrip() {
	cfg := ChunkConfig.default()
	data := []u8{len: 192 * 1024, init: u8(index % 251)}
	data_path := os.join_path(os.vtmp_dir(), 'pollytree-ingest-store-high-throughput-data.bin')
	store_path := os.join_path(os.vtmp_dir(), 'pollytree-ingest-store-high-throughput.bin')
	defer {
		os.rm(data_path) or {}
		os.rm(store_path) or {}
	}
	os.write_bytes(data_path, data) or { panic(err) }
	manager := BufferManager.new(data_path, 16 * 1024, cfg.max_size) or { panic(err) }
	mut store := ChunkStore.open_high_throughput(store_path) or { panic(err) }
	defer {
		store.close()
	}

	result := manager.ingest_to_store(cfg, ChunkIngestConfig.high_throughput(), mut store) or {
		panic(err)
	}
	assert result.count > 0
	chunks := manager.chunk_file_cids(cfg) or { panic(err) }
	assert chunks.len == result.count
	for chunk in chunks {
		assert store.has(chunk.cid)
		payload := store.get(chunk.cid) or { panic(err) }
		assert payload == data[chunk.chunk.start..chunk.chunk.end]
	}
}

fn test_chunk_store_reopen_rebuilds_index() {
	cfg := ChunkConfig.default()
	data := []u8{len: 128 * 1024, init: u8(index % 251)}
	data_path := os.join_path(os.vtmp_dir(), 'pollydb-reopen-data.bin')
	store_path := os.join_path(os.vtmp_dir(), 'pollydb-reopen-store.bin')
	defer {
		os.rm(data_path) or {}
		os.rm(store_path) or {}
	}
	os.write_bytes(data_path, data) or { panic(err) }
	manager := BufferManager.new(data_path, 16 * 1024, cfg.max_size) or { panic(err) }
	chunks := manager.chunk_file_cids(cfg) or { panic(err) }
	mut store := ChunkStore.open_high_throughput(store_path) or { panic(err) }
	manager.chunk_file_cids_to_store(cfg, mut store) or { panic(err) }
	store.close()

	mut reopened := ChunkStore.open_high_throughput(store_path) or { panic(err) }
	defer {
		reopened.close()
	}
	assert reopened.has(chunks[0].cid)
	payload := reopened.get(chunks[0].cid) or { panic(err) }
	assert payload == data[chunks[0].chunk.start..chunks[0].chunk.end]
}

fn test_chunk_store_persists_index_snapshot() {
	cfg := ChunkConfig.default()
	data := []u8{len: 96 * 1024, init: u8(index % 251)}
	data_path := os.join_path(os.vtmp_dir(), 'pollydb-index-snapshot-data.bin')
	store_path := os.join_path(os.vtmp_dir(), 'pollydb-index-snapshot-store.bin')
	defer {
		os.rm(data_path) or {}
		os.rm(store_path) or {}
		os.rm('${store_path}.idx') or {}
	}
	os.write_bytes(data_path, data) or { panic(err) }
	manager := BufferManager.new(data_path, 16 * 1024, cfg.max_size) or { panic(err) }
	chunks := manager.chunk_file_cids(cfg) or { panic(err) }
	mut store := ChunkStore.open(store_path) or { panic(err) }
	manager.chunk_file_cids_to_store(cfg, mut store) or { panic(err) }
	store.close()

	assert os.exists('${store_path}.idx')
	mut reopened := ChunkStore.open(store_path) or { panic(err) }
	defer {
		reopened.close()
	}
	assert reopened.has(chunks[0].cid)
}

fn test_chunk_store_checkpoint_persists_sidecar_before_close() {
	cfg := ChunkConfig.default()
	data := []u8{len: 96 * 1024, init: u8(index % 251)}
	data_path := os.join_path(os.vtmp_dir(), 'pollydb-checkpoint-data.bin')
	store_path := os.join_path(os.vtmp_dir(), 'pollydb-checkpoint-store.bin')
	index_path := '${store_path}.idx'
	defer {
		os.rm(data_path) or {}
		os.rm(store_path) or {}
		os.rm(index_path) or {}
	}
	os.write_bytes(data_path, data) or { panic(err) }
	manager := BufferManager.new(data_path, 16 * 1024, cfg.max_size) or { panic(err) }
	chunks := manager.chunk_file_cids(cfg) or { panic(err) }
	mut store := ChunkStore.open(store_path) or { panic(err) }
	manager.chunk_file_cids_to_store(cfg, mut store) or { panic(err) }
	store.checkpoint() or { panic(err) }
	assert os.exists(index_path)
	assert store.has(chunks[0].cid)
	store.close()
}

fn test_chunk_store_falls_back_when_index_snapshot_is_corrupt() {
	cfg := ChunkConfig.default()
	data := []u8{len: 96 * 1024, init: u8(index % 251)}
	data_path := os.join_path(os.vtmp_dir(), 'pollydb-index-corrupt-data.bin')
	store_path := os.join_path(os.vtmp_dir(), 'pollydb-index-corrupt-store.bin')
	index_path := '${store_path}.idx'
	defer {
		os.rm(data_path) or {}
		os.rm(store_path) or {}
		os.rm(index_path) or {}
	}
	os.write_bytes(data_path, data) or { panic(err) }
	manager := BufferManager.new(data_path, 16 * 1024, cfg.max_size) or { panic(err) }
	chunks := manager.chunk_file_cids(cfg) or { panic(err) }
	mut store := ChunkStore.open(store_path) or { panic(err) }
	manager.chunk_file_cids_to_store(cfg, mut store) or { panic(err) }
	store.close()

	os.write_file(index_path, 'corrupt sidecar') or { panic(err) }
	mut reopened := ChunkStore.open(store_path) or { panic(err) }
	defer {
		reopened.close()
	}
	assert reopened.has(chunks[0].cid)
	assert !os.exists(index_path)
}

fn test_chunk_store_falls_back_when_index_snapshot_checksum_mismatches() {
	cfg := ChunkConfig.default()
	data := []u8{len: 96 * 1024, init: u8(index % 251)}
	data_path := os.join_path(os.vtmp_dir(), 'pollydb-index-checksum-data.bin')
	store_path := os.join_path(os.vtmp_dir(), 'pollydb-index-checksum-store.bin')
	index_path := '${store_path}.idx'
	defer {
		os.rm(data_path) or {}
		os.rm(store_path) or {}
		os.rm(index_path) or {}
	}
	os.write_bytes(data_path, data) or { panic(err) }
	manager := BufferManager.new(data_path, 16 * 1024, cfg.max_size) or { panic(err) }
	chunks := manager.chunk_file_cids(cfg) or { panic(err) }
	mut store := ChunkStore.open(store_path) or { panic(err) }
	manager.chunk_file_cids_to_store(cfg, mut store) or { panic(err) }
	store.close()

	mut snapshot := os.read_bytes(index_path) or { panic(err) }
	assert snapshot.len > 24
	snapshot[24] = snapshot[24] ^ u8(0x01)
	os.write_bytes(index_path, snapshot) or { panic(err) }

	mut reopened := ChunkStore.open(store_path) or { panic(err) }
	defer {
		reopened.close()
	}
	assert reopened.has(chunks[0].cid)
	assert !os.exists(index_path)
}
