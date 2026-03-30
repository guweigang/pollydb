module storage

const scenario_chunk_size = 4 * 1024
const scenario_total_size = 10 * 1024 * 1024
const scenario_total_chunks = scenario_total_size / scenario_chunk_size
const scenario_insert_pos = 10
const scenario_insert_byte = u8(`X`)
const scenario_template_count = 8

struct ScenarioRng {
mut:
	state u64
}

fn ScenarioRng.new(seed u64) ScenarioRng {
	return ScenarioRng{
		state: seed
	}
}

fn (mut rng ScenarioRng) next_u64() u64 {
	mut x := rng.state
	x ^= x << 13
	x ^= x >> 7
	x ^= x << 17
	rng.state = x
	return x
}

fn (mut rng ScenarioRng) next_u8() u8 {
	return u8(rng.next_u64() & 0xff)
}

struct ScenarioChunkFactory {
	cfg         ChunkConfig
	target_size int
	insert_pos  int
	insert_byte u8
}

fn ScenarioChunkFactory.new(cfg ChunkConfig, target_size int, insert_pos int, insert_byte u8) ScenarioChunkFactory {
	return ScenarioChunkFactory{
		cfg: cfg
		target_size: target_size
		insert_pos: insert_pos
		insert_byte: insert_byte
	}
}

fn (factory ScenarioChunkFactory) regular_chunk(seed u64) ![]u8 {
	mut rng := ScenarioRng.new(seed)
	prefix_len := factory.target_size - 2
	for _ in 0 .. 128 {
		mut prefix := []u8{len: prefix_len}
		for idx in 0 .. prefix_len {
			prefix[idx] = rng.next_u8()
		}
		prefix_hash := factory.hash_without_split(prefix) or {
			continue
		}
		tail := factory.find_tail(prefix_hash, prefix.len, 0, false) or {
			continue
		}
		mut chunk := prefix.clone()
		chunk << tail
		return chunk
	}
	return error('unable to synthesize standalone chunk')
}

fn (factory ScenarioChunkFactory) insertion_stable_chunk(seed u64) !([]u8, []u8) {
	mut rng := ScenarioRng.new(seed)
	prefix_len := factory.target_size - 2
	for _ in 0 .. 256 {
		mut prefix := []u8{len: prefix_len}
		for idx in 0 .. prefix_len {
			prefix[idx] = rng.next_u8()
		}
		base_hash := factory.hash_without_split(prefix) or {
			continue
		}
		inserted_prefix := factory.insert_byte_at(prefix, factory.insert_pos, factory.insert_byte)
		inserted_hash := factory.hash_without_split(inserted_prefix) or {
			continue
		}
		tail := factory.find_tail(base_hash, prefix.len, inserted_hash, true) or {
			continue
		}
		mut base_chunk := prefix.clone()
		base_chunk << tail
		mut inserted_chunk := inserted_prefix.clone()
		inserted_chunk << tail
		return base_chunk, inserted_chunk
	}
	return error('unable to synthesize insertion-stable chunk')
}

fn (factory ScenarioChunkFactory) hash_without_split(data []u8) !u64 {
	mut hash := u64(0)
	for idx, b in data {
		hash = rolling_hash(hash, b)
		size := idx + 1
		if size >= factory.cfg.min_size && ((hash & factory.cfg.mask) == 0 || size >= factory.cfg.max_size) {
			return error('prefix split before target end')
		}
	}
	return hash
}

fn (factory ScenarioChunkFactory) find_tail(base_hash u64, base_prefix_len int, inserted_hash u64, require_inserted bool) ![]u8 {
	for first in 0 .. 256 {
		first_byte := u8(first)
		base_h1 := rolling_hash(base_hash, first_byte)
		base_size1 := base_prefix_len + 1
		if factory.should_cut(base_h1, base_size1) {
			continue
		}

		mut inserted_h1 := u64(0)
		inserted_size1 := base_prefix_len + 2
		if require_inserted {
			inserted_h1 = rolling_hash(inserted_hash, first_byte)
			if factory.should_cut(inserted_h1, inserted_size1) {
				continue
			}
		}

		for second in 0 .. 256 {
			second_byte := u8(second)
			base_h2 := rolling_hash(base_h1, second_byte)
			base_size2 := base_prefix_len + 2
			if !factory.should_cut(base_h2, base_size2) {
				continue
			}

			if require_inserted {
				inserted_h2 := rolling_hash(inserted_h1, second_byte)
				inserted_size2 := base_prefix_len + 3
				if !factory.should_cut(inserted_h2, inserted_size2) {
					continue
				}
			}

			return [first_byte, second_byte]
		}
	}
	return error('unable to find boundary tail')
}

fn (factory ScenarioChunkFactory) should_cut(hash u64, size int) bool {
	if size < factory.cfg.min_size {
		return false
	}
	return size >= factory.cfg.max_size || (hash & factory.cfg.mask) == 0
}

fn (factory ScenarioChunkFactory) insert_byte_at(data []u8, offset int, b u8) []u8 {
	mut out := []u8{cap: data.len + 1}
	out << data[..offset]
	out << b
	out << data[offset..]
	return out
}

struct ScenarioDataset {
	base          []u8
	inserted      []u8
	deleted       []u8
	base_hashes   []string
	inserted_hashes []string
	deleted_hashes []string
	delete_at     int
	delete_count  int
}

fn ScenarioDataset.build() !ScenarioDataset {
	cfg := ChunkConfig.default()
	factory := ScenarioChunkFactory.new(cfg, scenario_chunk_size, scenario_insert_pos, scenario_insert_byte)
	first_chunk, first_chunk_inserted := factory.insertion_stable_chunk(0x13579bdf)!

	mut templates := [][]u8{cap: scenario_template_count}
	for idx in 0 .. scenario_template_count {
		templates << factory.regular_chunk(u64(0x2468ace0 + idx))!
	}

	mut base := []u8{cap: scenario_total_size}
	mut inserted := []u8{cap: scenario_total_size + 1}
	base << first_chunk
	inserted << first_chunk_inserted
	for idx in 1 .. scenario_total_chunks {
		template := templates[(idx - 1) % templates.len]
		base << template
		inserted << template
	}

	delete_at := scenario_total_chunks / 2
	delete_count := 3
	delete_start := delete_at * scenario_chunk_size
	delete_end := (delete_at + delete_count) * scenario_chunk_size
	mut deleted := []u8{cap: base.len - (delete_end - delete_start)}
	deleted << base[..delete_start]
	deleted << base[delete_end..]

	return ScenarioDataset{
		base: base
		inserted: inserted
		deleted: deleted
		base_hashes: chunk_content_hashes(base, cfg)!
		inserted_hashes: chunk_content_hashes(inserted, cfg)!
		deleted_hashes: chunk_content_hashes(deleted, cfg)!
		delete_at: delete_at
		delete_count: delete_count
	}
}

fn chunk_content_hashes(data []u8, cfg ChunkConfig) ![]string {
	chunks := cfg.chunk_bytes(data)!
	mut hashes := []string{cap: chunks.len}
	for chunk in chunks {
		hashes << chunk_cid_hex(data[chunk.start..chunk.end])
	}
	return hashes
}

fn test_scenario_a_chunks_10mib_into_about_2500_blocks() {
	scenario := ScenarioDataset.build() or { panic(err) }

	assert scenario.base.len == scenario_total_size
	assert scenario.base_hashes.len == scenario_total_chunks
	assert scenario.base_hashes.len >= 2400
	assert scenario.base_hashes.len <= 2700
}

fn test_scenario_b_insert_at_byte_10_only_changes_first_chunk_hash() {
	scenario := ScenarioDataset.build() or { panic(err) }

	assert scenario.inserted_hashes.len == scenario.base_hashes.len
	assert scenario.inserted_hashes[0] != scenario.base_hashes[0]
	assert scenario.inserted_hashes[1..] == scenario.base_hashes[1..]
}

fn test_scenario_c_delete_middle_paragraph_only_changes_local_chunks() {
	scenario := ScenarioDataset.build() or { panic(err) }

	assert scenario.deleted_hashes.len == scenario.base_hashes.len - scenario.delete_count
	assert scenario.deleted_hashes[..scenario.delete_at] == scenario.base_hashes[..scenario.delete_at]
	assert scenario.deleted_hashes[scenario.delete_at..] == scenario.base_hashes[scenario.delete_at + scenario.delete_count..]
}
