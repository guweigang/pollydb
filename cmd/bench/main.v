module main

import agentview
import flag
import compress.zlib
import os
import pollylink as _
import time
import storage

struct BenchConfig {
pub:
	rows              int = 100_000
	batch_size        int = 2_000
	lookups           int = 10_000
	range_size        int = 1_000
	updates           int = 10_000
	merge_writes      int = 5_000
	chunk_bytes       int = 10 * 1024 * 1024
	chunk_buffer_kb   int = 256
	chunk_workers     int = 4
	sync_rtt_ms       int = 40
	small_patch_limit int = 128
	content_bytes     int
	split_backed      bool
	write_diff        bool
	mode              string = 'all'
}

struct BenchResult {
	name        string
	duration_ms i64
	ops         int
	bytes       int
	note        string
}

struct BenchSuite {
	cfg       BenchConfig
	chunk_cfg storage.ChunkConfig
}

struct BenchState {
pub:
	spec storage.TypedTableSpec
mut:
	repo         storage.Repository
	node_store   storage.MemoryNodeStore
	commit_store storage.MemoryCommitStore
}

struct PersistentBenchState {
	root_dir string
mut:
	db storage.PersistentDatabase
}

struct SnapshotPersistentBenchState {
	root_dir  string
	v1_commit string
	v2_commit string
mut:
	db storage.PersistentDatabase
}

struct AggregateWorkerResult {
	ok    bool
	err   string
	count int
	sum   i64
}

struct AggregateWorkerHandle {
mut:
	worker thread AggregateWorkerResult
}

struct AggregateWorkerSpec {
	root_cid    string
	nodes_path  string
	start_key   []u8
	end_key     []u8
	sum_column  string
	table_codec storage.TypedRowCodec
}

fn (mut handle AggregateWorkerHandle) wait() !AggregateWorkerResult {
	result := handle.worker.wait()
	if !result.ok {
		return error(result.err)
	}
	return result
}

struct AggregatePartition {
	start []u8
	end   []u8
}

struct CodexEntrySchemaBenchSpec {
	name                 string
	schema               storage.DatabaseSchema
	materialize_markdown bool
	markdown_source_only bool
}

struct CodexEntrySchemaBenchState {
	root_dir string
	target   CodexEntrySchemaBenchSpec
	inserted int
mut:
	db storage.PersistentDatabase
}

fn BenchConfig.from_args() BenchConfig {
	defaults := BenchConfig{}
	mut fp := flag.new_flag_parser(os.args)
	fp.application('pollydb-bench')
	fp.description('Repeatable performance harness for prollytree storage scenarios')
	fp.skip_executable()
	rows := fp.int('rows', `r`, defaults.rows, 'row count for the typed dataset')
	batch_size := fp.int('batch-size', `b`, defaults.batch_size, 'typed write batch size')
	lookups := fp.int('lookups', `l`, defaults.lookups, 'point and secondary-index lookups')
	range_size := fp.int('range-size', `s`, defaults.range_size, 'primary-key scan size')
	updates := fp.int('updates', `u`, defaults.updates, 'working-set updates')
	merge_writes := fp.int('merge-writes', `m`, defaults.merge_writes,
		'feature/main writes before merge')
	chunk_bytes := fp.int('chunk-bytes', `c`, defaults.chunk_bytes,
		'payload size for CDC benchmark')
	chunk_buffer_kb := fp.int('chunk-buffer-kb', 0, defaults.chunk_buffer_kb,
		'streaming CDC file buffer size in KiB')
	chunk_workers := fp.int('chunk-workers', 0, defaults.chunk_workers,
		'worker count for parallel CDC hashing benchmarks')
	sync_rtt_ms := fp.int('sync-rtt-ms', 0, defaults.sync_rtt_ms,
		'simulated one-way sync negotiation RTT in milliseconds')
	small_patch_limit := fp.int('small-patch-limit', 0, defaults.small_patch_limit,
		'max ops for the schema small-patch write path; 0 disables it')
	content_bytes := fp.int('content-bytes', 0, defaults.content_bytes,
		'target synthetic Codex entry content_text bytes; 0 keeps the short default')
	split_backed := fp.bool('split-backed', 0, defaults.split_backed,
		'use split-backed typed working sets for schema write benchmarks')
	write_diff := fp.bool('write-diff', 0, defaults.write_diff,
		'compute full TreeDiff added/removed/reused cid lists during schema writes')
	mode := fp.string('mode', 0, defaults.mode,
		'benchmark mode: all, cdc, typed, aggregate, sync, schema, or schema-write')
	fp.finalize() or { panic(err) }
	return BenchConfig{
		rows:              rows
		batch_size:        batch_size
		lookups:           lookups
		range_size:        range_size
		updates:           updates
		merge_writes:      merge_writes
		chunk_bytes:       chunk_bytes
		chunk_buffer_kb:   chunk_buffer_kb
		chunk_workers:     chunk_workers
		sync_rtt_ms:       sync_rtt_ms
		small_patch_limit: small_patch_limit
		content_bytes:     content_bytes
		split_backed:      split_backed
		write_diff:        write_diff
		mode:              mode
	}
}

fn BenchSuite.new(cfg BenchConfig) BenchSuite {
	return BenchSuite{
		cfg:       cfg
		chunk_cfg: storage.ChunkConfig.default()
	}
}

fn (suite BenchSuite) run() ![]BenchResult {
	mut results := []BenchResult{}
	if suite.cfg.mode == 'all' || suite.cfg.mode == 'cdc' {
		eprintln('==> running pure cdc core benchmark')
		results << suite.run_chunker_core_bench()!
		eprintln('==> running streaming cdc benchmark')
		results << suite.run_chunker_file_bench()!
		eprintln('==> running streaming cdc+cid benchmark')
		results << suite.run_chunker_file_cid_bench()!
		eprintln('==> running file-backed parallel cdc+cid benchmark')
		results << suite.run_chunker_file_cid_parallel_bench()!
		eprintln('==> running parallel cdc hash benchmark')
		results << suite.run_parallel_hash_bench()!
		eprintln('==> running streaming cdc+cid+store benchmark')
		results << suite.run_chunker_file_store_bench()!
		eprintln('==> running file-backed parallel cdc+cid+store benchmark')
		results << suite.run_chunker_file_store_parallel_bench()!
		eprintln('==> running streaming cdc+cid+store (no index) benchmark')
		results << suite.run_chunker_file_store_no_index_bench()!
		eprintln('==> running streaming cdc+cid+store (deferred index) benchmark')
		results << suite.run_chunker_file_store_deferred_index_bench()!
		eprintln('==> running chunk store reopen benchmark')
		results << suite.run_chunk_store_reopen_bench()!
		eprintln('==> running cdc chunker benchmark')
		results << suite.run_chunker_bench()!
	}
	if suite.cfg.mode == 'aggregate' {
		eprintln('==> building aggregate dataset')
		eprintln('==> running aggregate count benchmark')
		results << suite.run_database_table_count_bench()!
		eprintln('==> running aggregate count-range benchmark')
		results << suite.run_database_table_count_range_bench()!
		eprintln('==> running aggregate sum benchmark')
		results << suite.run_database_table_sum_bench()!
		eprintln('==> running aggregate sum-range benchmark')
		results << suite.run_database_table_sum_range_bench()!
		eprintln('==> running aggregate parallel count benchmark')
		results << suite.run_database_table_count_parallel_bench()!
		eprintln('==> running aggregate parallel sum benchmark')
		results << suite.run_database_table_sum_parallel_bench()!
	}
	if suite.cfg.mode == 'all' || suite.cfg.mode == 'schema' || suite.cfg.mode == 'schema-write' {
		eprintln('==> running codex entries rows-only schema benchmark')
		results << suite.run_codex_entries_schema_bench(suite.codex_entries_rows_only_bench_spec()!)!
		eprintln('==> running codex entries secondary-index schema benchmark')
		results << suite.run_codex_entries_schema_bench(suite.codex_entries_secondary_index_bench_spec()!)!
		eprintln('==> running codex entries secondary-index no-cover schema benchmark')
		results << suite.run_codex_entries_schema_bench(suite.codex_entries_secondary_no_cover_bench_spec()!)!
		eprintln('==> running codex entries secondary-index cover-only schema benchmark')
		results << suite.run_codex_entries_schema_bench(suite.codex_entries_secondary_cover_only_bench_spec()!)!
		eprintln('==> running codex entries fts schema benchmark')
		results << suite.run_codex_entries_schema_bench(suite.codex_entries_fts_bench_spec()!)!
		eprintln('==> running codex entries fts no-cover schema benchmark')
		results << suite.run_codex_entries_schema_bench(suite.codex_entries_fts_no_cover_bench_spec()!)!
		eprintln('==> running codex entries markdown fts schema benchmark')
		results << suite.run_codex_entries_schema_bench(suite.codex_entries_markdown_fts_bench_spec()!)!
		if suite.cfg.mode == 'schema-write' {
			eprintln('==> running codex entries grouped fts write benchmark')
			results << suite.run_codex_entries_grouped_write_bench(suite.codex_entries_fts_bench_spec()!)!
			return results
		}
		eprintln('==> running codex entries rows-only update benchmark')
		results << suite.run_codex_entries_update_bench(suite.codex_entries_rows_only_bench_spec()!, true)!
		eprintln('==> running codex entries secondary-index update benchmark')
		results << suite.run_codex_entries_update_bench(suite.codex_entries_secondary_index_bench_spec()!, true)!
		eprintln('==> running codex entries fts update benchmark')
		results << suite.run_codex_entries_update_bench(suite.codex_entries_fts_bench_spec()!, true)!
		eprintln('==> running codex entries fts metadata-only update benchmark')
		results << suite.run_codex_entries_update_bench(suite.codex_entries_fts_bench_spec()!,
			false)!
		eprintln('==> running codex entries rows-only delete benchmark')
		results << suite.run_codex_entries_delete_bench(suite.codex_entries_rows_only_bench_spec()!)!
		eprintln('==> running codex entries secondary-index delete benchmark')
		results << suite.run_codex_entries_delete_bench(suite.codex_entries_secondary_index_bench_spec()!)!
		eprintln('==> running codex entries fts delete benchmark')
		results << suite.run_codex_entries_delete_bench(suite.codex_entries_fts_bench_spec()!)!
		eprintln('==> running codex entries secondary-index lookup benchmark')
		results << suite.run_codex_entries_secondary_lookup_bench(suite.codex_entries_secondary_index_bench_spec()!)!
		eprintln('==> running codex entries secondary-index no-cover lookup benchmark')
		results << suite.run_codex_entries_secondary_lookup_bench(suite.codex_entries_secondary_no_cover_bench_spec()!)!
		eprintln('==> running codex entries fts secondary-index lookup benchmark')
		results << suite.run_codex_entries_secondary_lookup_bench(suite.codex_entries_fts_bench_spec()!)!
		eprintln('==> running codex entries fts no-cover secondary-index lookup benchmark')
		results << suite.run_codex_entries_secondary_lookup_bench(suite.codex_entries_fts_no_cover_bench_spec()!)!
		eprintln('==> running codex entries fts query benchmark')
		results << suite.run_codex_entries_fts_query_bench(suite.codex_entries_fts_bench_spec()!)!
		eprintln('==> running codex entries grouped fts write benchmark')
		results << suite.run_codex_entries_grouped_write_bench(suite.codex_entries_fts_bench_spec()!)!
	}
	if suite.cfg.mode == 'all' || suite.cfg.mode == 'sync' {
		eprintln('==> running polly-sync full push benchmark')
		results << suite.run_sync_push_full_bench()!
		eprintln('==> running polly-sync full push benchmark (manifest)')
		results << suite.run_sync_push_full_manifest_bench()!
		eprintln('==> running polly-sync tiny-change push benchmark')
		results << suite.run_sync_push_tiny_change_bench()!
		eprintln('==> running polly-sync tiny-change push benchmark (manifest)')
		results << suite.run_sync_push_tiny_change_manifest_bench()!
		eprintln('==> running polly-sync tiny-change push benchmark (manifest depth=2)')
		results << suite.run_sync_push_tiny_change_manifest_depth2_bench()!
		eprintln('==> running polly-sync json-field tiny-change push benchmark')
		results << suite.run_sync_push_json_tiny_change_bench()!
		eprintln('==> running polly-sync repeated micro-change push benchmark')
		results << suite.run_sync_push_repeated_tiny_change_bench()!
		eprintln('==> running polly-sync divergence auto-merge push benchmark')
		results << suite.run_sync_push_divergence_auto_merge_bench()!
		eprintln('==> running polly-sync full pull benchmark')
		results << suite.run_sync_pull_full_bench()!
		eprintln('==> running polly-sync full pull benchmark (manifest)')
		results << suite.run_sync_pull_full_manifest_bench()!
		eprintln('==> running polly-sync tiny-change pull benchmark')
		results << suite.run_sync_pull_tiny_change_bench()!
		eprintln('==> running polly-sync tiny-change pull benchmark (manifest)')
		results << suite.run_sync_pull_tiny_change_manifest_bench()!
		eprintln('==> running polly-sync tiny-change pull benchmark (manifest depth=2)')
		results << suite.run_sync_pull_tiny_change_manifest_depth2_bench()!
		eprintln('==> sweeping polly-sync tiny-change RTT crossover')
		results << suite.run_sync_tiny_change_rtt_sweep_bench()!
	}
	if suite.cfg.mode == 'all' || suite.cfg.mode == 'typed' {
		eprintln('==> building prolly random-update dataset')
		results << suite.run_prolly_random_update_bench()!
		eprintln('==> building prolly random-insert dataset')
		results << suite.run_prolly_random_insert_bench()!
		eprintln('==> building prolly random-delete dataset')
		results << suite.run_prolly_random_delete_bench()!
		eprintln('==> sampling prolly mutation distributions')
		results << suite.run_prolly_random_update_distribution_bench()!
		results << suite.run_prolly_random_insert_distribution_bench()!
		results << suite.run_prolly_random_delete_distribution_bench()!
		eprintln('==> measuring prolly root lookup latency')
		results << suite.run_prolly_root_lookup_latency_bench()!
		eprintln('==> building typed dataset')
		mut state := suite.build_typed_state()!
		eprintln('==> running typed point lookup benchmark')
		results << suite.run_point_lookup_bench(mut state)!
		eprintln('==> running database row lookup latency benchmark')
		results << suite.run_database_row_lookup_latency_bench()!
		eprintln('==> running typed primary-key scan benchmark')
		results << suite.run_range_scan_bench(mut state)!
		eprintln('==> running typed secondary-index benchmark')
		results << suite.run_secondary_index_bench(mut state)!
		eprintln('==> running database index lookup latency benchmark')
		results << suite.run_database_index_lookup_latency_bench()!
		eprintln('==> running database covering-index lookup latency benchmark')
		results << suite.run_database_covering_index_lookup_latency_bench()!
		eprintln('==> running database index prefix lookup latency benchmark')
		results << suite.run_database_index_prefix_lookup_latency_bench()!
		eprintln('==> running database table count aggregation benchmark')
		results << suite.run_database_table_count_bench()!
		eprintln('==> running database table count-range aggregation benchmark')
		results << suite.run_database_table_count_range_bench()!
		eprintln('==> running database table sum aggregation benchmark')
		results << suite.run_database_table_sum_bench()!
		eprintln('==> running database table sum-range aggregation benchmark')
		results << suite.run_database_table_sum_range_bench()!
		eprintln('==> running database table parallel count aggregation benchmark')
		results << suite.run_database_table_count_parallel_bench()!
		eprintln('==> running database table parallel sum aggregation benchmark')
		results << suite.run_database_table_sum_parallel_bench()!
		eprintln('==> running snapshot table scan latency benchmark')
		results << suite.run_snapshot_table_scan_latency_bench()!
		eprintln('==> running snapshot covering index lookup latency benchmark')
		results << suite.run_snapshot_index_lookup_latency_bench()!
		eprintln('==> running snapshot index prefix lookup latency benchmark')
		results << suite.run_snapshot_index_prefix_lookup_latency_bench()!
		eprintln('==> running snapshot index prefix primary-key latency benchmark')
		results << suite.run_snapshot_index_prefix_primary_keys_latency_bench()!
		eprintln('==> running snapshot index prefix count latency benchmark')
		results << suite.run_snapshot_index_prefix_count_latency_bench()!
		eprintln('==> running snapshot index prefix projected latency benchmark')
		results << suite.run_snapshot_index_prefix_projected_latency_bench()!
		eprintln('==> running snapshot non-covering index prefix lookup latency benchmark')
		results << suite.run_snapshot_index_prefix_non_covering_latency_bench()!
		eprintln('==> running prolly durable write-path latency benchmark')
		results << suite.run_prolly_write_path_latency_bench()!
		eprintln('==> running prolly data-only write-path latency benchmark')
		results << suite.run_prolly_write_path_data_only_latency_bench()!
		eprintln('==> running prolly group-commit write-path latency benchmark')
		results << suite.run_prolly_write_path_group_commit_latency_bench()!
		eprintln('==> running prolly group-commit data-only async-refresh latency benchmark')
		results << suite.run_prolly_write_path_group_commit_data_only_async_latency_bench()!
		eprintln('==> sweeping aggregate projector refresh policy')
		results << suite.run_aggregate_projector_refresh_policy_sweep_bench()!
		eprintln('==> sweeping prolly group-commit checkpoint_every')
		results << suite.run_prolly_write_path_group_commit_sweep_bench()!
		eprintln('==> running typed working-set update benchmark')
		results << suite.run_working_set_update_bench(mut state)!
		eprintln('==> running typed merge benchmark')
		results << suite.run_merge_bench(mut state)!
	}
	return results
}

fn packet_bytes(packets []storage.DataPacket) int {
	mut total := 0
	for packet in packets {
		total += packet.data.len
	}
	return total
}

fn packet_compressed_bytes(packets []storage.DataPacket) !int {
	mut total := 0
	for packet in packets {
		compressed := zlib.compress(packet.data)!
		total += compressed.len
	}
	return total
}

fn packet_kind_counts(packets []storage.DataPacket) (int, int) {
	mut commit_count := 0
	mut node_count := 0
	for packet in packets {
		match packet.kind {
			.commit { commit_count++ }
			.node { node_count++ }
		}
	}
	return commit_count, node_count
}

fn sync_tree_depth(tree storage.Tree) !int {
	root := tree.root_node()!
	return root.level + 1
}

fn regular_negotiation_rtts(tree_depth int) int {
	return if tree_depth < 1 { 1 } else { tree_depth }
}

fn manifest_negotiation_rtts(tree_depth int, prediction_depth int) int {
	if tree_depth < 1 {
		return 1
	}
	depth := if prediction_depth < 1 { 1 } else { prediction_depth }
	remaining := tree_depth - depth
	return if remaining > 1 { remaining } else { 1 }
}

fn effective_sync_total_ms(duration_ms i64, negotiation_rtts int, rtt_ms int) i64 {
	return duration_ms + i64(negotiation_rtts * rtt_ms)
}

fn sync_note(rows int, duration_ms i64, tree_depth int, prediction_depth int, negotiation_rtts int, rtt_ms int, commit_packets int, node_packets int, missing_commits int, missing_nodes int, compressed_bytes int) string {
	mut parts := []string{}
	parts << 'rows=${rows}'
	if tree_depth > 0 {
		parts << 'tree_depth=${tree_depth}'
	}
	if prediction_depth > 0 {
		parts << 'prediction_depth=${prediction_depth}'
	}
	if negotiation_rtts > 0 {
		parts << 'negotiation_rtts=${negotiation_rtts}'
		parts << 'simulated_rtt_ms=${negotiation_rtts * rtt_ms}'
	}
	parts << 'effective_total_ms=${effective_sync_total_ms(duration_ms, negotiation_rtts, rtt_ms)}'
	parts << 'commit_packets=${commit_packets}'
	parts << 'node_packets=${node_packets}'
	parts << 'missing_commits=${missing_commits}'
	parts << 'missing_nodes=${missing_nodes}'
	parts << 'compressed_bytes=${compressed_bytes}'
	return parts.join(' ')
}

fn (suite BenchSuite) sync_bench_items() []storage.KVPair {
	mut items := []storage.KVPair{cap: suite.cfg.rows}
	for idx in 0 .. suite.cfg.rows {
		items << storage.KVPair{
			key:   'sync-${idx:08}'.bytes()
			value: suite.prolly_bench_value(idx)
		}
	}
	return items
}

fn (suite BenchSuite) sync_json_items() []storage.KVPair {
	mut items := []storage.KVPair{cap: suite.cfg.rows}
	for idx in 0 .. suite.cfg.rows {
		value :=
			'{"id":"sync-${idx:08}","title":"Document ${idx:08}","status":"draft","meta":{"kind":"note","version":1,"flag":false},"body":"${suite.prolly_bench_value(idx).bytestr()}"}'.bytes()
		items << storage.KVPair{
			key:   'json-${idx:08}'.bytes()
			value: value
		}
	}
	return items
}

fn (suite BenchSuite) sync_mutated_tree(base storage.Tree) !storage.Tree {
	idx := if suite.cfg.rows > 0 { suite.cfg.rows / 2 } else { 0 }
	key := 'sync-${idx:08}'.bytes()
	mut value := suite.prolly_bench_value(idx)
	if value.len == 0 {
		value = [u8(`X`)]
	} else {
		mid := value.len / 2
		value[mid] = value[mid] ^ u8(0x01)
	}
	return base.put(storage.KVPair{
		key:   key
		value: value
	}, suite.chunk_cfg)
}

fn (suite BenchSuite) sync_mutated_json_tree(base storage.Tree) !storage.Tree {
	idx := if suite.cfg.rows > 0 { suite.cfg.rows / 2 } else { 0 }
	key := 'json-${idx:08}'.bytes()
	value :=
		'{"id":"json-${idx:08}","title":"Document ${idx:08}","status":"published","meta":{"kind":"note","version":2,"flag":true},"body":"${suite.prolly_bench_value(idx).bytestr()}"}'.bytes()
	return base.put(storage.KVPair{
		key:   key
		value: value
	}, suite.chunk_cfg)
}

fn (suite BenchSuite) init_sync_repo(prefix string) !storage.PersistentRepository {
	root_dir := os.join_path(os.temp_dir(), '${prefix}-${os.getpid()}-${time.now().unix_micro()}')
	return storage.PersistentRepository.init(root_dir, 'main')
}

fn sync_branch_tree_depth(mut repo storage.PersistentRepository, branch_name string) !int {
	tree := repo.tree_at_branch(branch_name)!
	return sync_tree_depth(tree)
}

fn (suite BenchSuite) run_sync_push_full_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-push-full-source')!
	mut target := suite.init_sync_repo('polly-sync-push-full-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync full push'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.push_branch_to_repo(mut source, mut target, 'main')!
	duration_ms := sw.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	negotiation_rtts := regular_negotiation_rtts(tree_depth)
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_push_full'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        sync_note(suite.cfg.rows, duration_ms, tree_depth, 0, negotiation_rtts,
			suite.cfg.sync_rtt_ms, commit_packets, node_packets,
			result.exchange.plan.missing_commit_cids.len,
			result.exchange.plan.missing_node_cids.len, compressed_bytes)
	}
}

fn (suite BenchSuite) run_sync_push_full_manifest_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-push-full-manifest-source')!
	mut target := suite.init_sync_repo('polly-sync-push-full-manifest-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync full push manifest'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.push_branch_to_repo_with_manifest(mut source, mut target, 'main')!
	duration_ms := sw.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	negotiation_rtts := manifest_negotiation_rtts(tree_depth, 1)
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_push_full_manifest'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        sync_note(suite.cfg.rows, duration_ms, tree_depth, 1, negotiation_rtts,
			suite.cfg.sync_rtt_ms, commit_packets, node_packets,
			result.exchange.plan.missing_commit_cids.len,
			result.exchange.plan.missing_node_cids.len, compressed_bytes)
	}
}

fn (suite BenchSuite) run_sync_push_tiny_change_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-push-tiny-source')!
	mut target := suite.init_sync_repo('polly-sync-push-tiny-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	base_tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync base push'
		timestamp: time.now().unix()
	})!
	_ = storage.push_branch_to_repo(mut source, mut target, 'main')!
	next_tree := suite.sync_mutated_tree(base_tree)!
	_ = source.commit_to_branch('main', next_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync tiny push'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.push_branch_to_repo(mut source, mut target, 'main')!
	duration_ms := sw.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	negotiation_rtts := regular_negotiation_rtts(tree_depth)
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_push_tiny_change'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        sync_note(suite.cfg.rows, duration_ms, tree_depth, 0, negotiation_rtts,
			suite.cfg.sync_rtt_ms, commit_packets, node_packets,
			result.exchange.plan.missing_commit_cids.len,
			result.exchange.plan.missing_node_cids.len, compressed_bytes)
	}
}

fn (suite BenchSuite) run_sync_push_tiny_change_manifest_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-push-tiny-manifest-source')!
	mut target := suite.init_sync_repo('polly-sync-push-tiny-manifest-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	base_tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync base push manifest'
		timestamp: time.now().unix()
	})!
	_ = storage.push_branch_to_repo_with_manifest(mut source, mut target, 'main')!
	next_tree := suite.sync_mutated_tree(base_tree)!
	_ = source.commit_to_branch('main', next_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync tiny push manifest'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.push_branch_to_repo_with_manifest(mut source, mut target, 'main')!
	duration_ms := sw.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	negotiation_rtts := manifest_negotiation_rtts(tree_depth, 1)
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_push_tiny_change_manifest'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        sync_note(suite.cfg.rows, duration_ms, tree_depth, 1, negotiation_rtts,
			suite.cfg.sync_rtt_ms, commit_packets, node_packets,
			result.exchange.plan.missing_commit_cids.len,
			result.exchange.plan.missing_node_cids.len, compressed_bytes)
	}
}

fn (suite BenchSuite) run_sync_push_tiny_change_manifest_depth2_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-push-tiny-manifest2-source')!
	mut target := suite.init_sync_repo('polly-sync-push-tiny-manifest2-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	base_tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync base push manifest depth2'
		timestamp: time.now().unix()
	})!
	_ = storage.push_branch_to_repo_with_manifest_depth(mut source, mut target, 'main', 2)!
	next_tree := suite.sync_mutated_tree(base_tree)!
	_ = source.commit_to_branch('main', next_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync tiny push manifest depth2'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.push_branch_to_repo_with_manifest_depth(mut source, mut target, 'main', 2)!
	duration_ms := sw.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	negotiation_rtts := manifest_negotiation_rtts(tree_depth, 2)
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_push_tiny_change_manifest_depth2'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        sync_note(suite.cfg.rows, duration_ms, tree_depth, 2, negotiation_rtts,
			suite.cfg.sync_rtt_ms, commit_packets, node_packets,
			result.exchange.plan.missing_commit_cids.len,
			result.exchange.plan.missing_node_cids.len, compressed_bytes)
	}
}

fn (suite BenchSuite) run_sync_push_json_tiny_change_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-push-json-source')!
	mut target := suite.init_sync_repo('polly-sync-push-json-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	base_tree := storage.Tree.build(suite.sync_json_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync json base push'
		timestamp: time.now().unix()
	})!
	_ = storage.push_branch_to_repo(mut source, mut target, 'main')!
	next_tree := suite.sync_mutated_json_tree(base_tree)!
	_ = source.commit_to_branch('main', next_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync json tiny push'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.push_branch_to_repo(mut source, mut target, 'main')!
	duration_ms := sw.elapsed().milliseconds()
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_push_json_tiny_change'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        'rows=${suite.cfg.rows} commit_packets=${commit_packets} node_packets=${node_packets} missing_commits=${result.exchange.plan.missing_commit_cids.len} missing_nodes=${result.exchange.plan.missing_node_cids.len} compressed_bytes=${compressed_bytes}'
	}
}

fn (suite BenchSuite) run_sync_push_repeated_tiny_change_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-push-repeat-source')!
	mut target := suite.init_sync_repo('polly-sync-push-repeat-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	mut tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync repeated base'
		timestamp: time.now().unix()
	})!
	_ = storage.push_branch_to_repo(mut source, mut target, 'main')!
	mut total_packets := 0
	mut total_bytes := 0
	mut total_compressed_bytes := 0
	mut total_commits := 0
	mut total_nodes := 0
	mut sw := time.new_stopwatch()
	for idx in 0 .. 10 {
		mut value := suite.prolly_bench_value(suite.cfg.rows / 2 + idx)
		if value.len > 0 {
			value[idx % value.len] = value[idx % value.len] ^ u8(idx + 1)
		}
		tree = tree.put(storage.KVPair{
			key:   'sync-${(suite.cfg.rows / 2 + idx):08}'.bytes()
			value: value
		}, suite.chunk_cfg)!
		_ = source.commit_to_branch('main', tree, storage.CommitMeta{
			author:    'bench'
			message:   'sync repeated ${idx}'
			timestamp: time.now().unix()
		})!
		result := storage.push_branch_to_repo(mut source, mut target, 'main')!
		commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
		total_packets += result.exchange.packets.len
		total_bytes += packet_bytes(result.exchange.packets)
		total_compressed_bytes += packet_compressed_bytes(result.exchange.packets)!
		total_commits += commit_packets
		total_nodes += node_packets
	}
	duration_ms := sw.elapsed().milliseconds()
	return BenchResult{
		name:        'sync_push_repeated_tiny_change'
		duration_ms: duration_ms
		ops:         total_packets
		bytes:       total_bytes
		note:        'iterations=10 commit_packets=${total_commits} node_packets=${total_nodes} compressed_bytes=${total_compressed_bytes}'
	}
}

fn (suite BenchSuite) run_sync_push_divergence_auto_merge_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-diverge-source')!
	mut remote := suite.init_sync_repo('polly-sync-diverge-remote')!
	defer {
		source.close() or {}
		remote.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(remote.path) or {}
	}
	base_tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync divergence base'
		timestamp: time.now().unix()
	})!
	_ = storage.push_branch_to_repo(mut source, mut remote, 'main')!
	source_tree := base_tree.put(storage.KVPair{
		key:   'sync-00000010'.bytes()
		value: 'ours-${suite.prolly_bench_value(10).bytestr()}'.bytes()
	}, suite.chunk_cfg)!
	source_update := source.commit_to_branch('main', source_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync divergence ours'
		timestamp: time.now().unix()
	})!
	remote_tree := base_tree.put(storage.KVPair{
		key:   'sync-00000020'.bytes()
		value: 'theirs-${suite.prolly_bench_value(20).bytestr()}'.bytes()
	}, suite.chunk_cfg)!
	remote_update := remote.commit_to_branch('main', remote_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync divergence theirs'
		timestamp: time.now().unix()
	})!
	remote_offer := storage.sync_offer_for_branch(mut remote, 'main')!
	remote_exchange := storage.full_sync_exchange_for_offer(mut remote, remote_offer)!
	storage.import_sync_exchange_objects(mut source, remote_exchange)!
	mut sw := time.new_stopwatch()
	merged_offer := storage.build_auto_merge_offer_for_remote_offer(mut source, 'main', 'main',
		remote_offer)!
	merged_exchange := storage.full_sync_exchange_for_offer(mut source, merged_offer)!
	_ = storage.apply_exchange_to_repo(mut remote, merged_exchange)!
	duration_ms := sw.elapsed().milliseconds()
	merged_tree := remote.tree_at_branch('main')!
	merged_left := merged_tree.get('sync-00000010'.bytes()) or { return error(err.msg()) }
	if !merged_left.value.bytestr().starts_with('ours-') {
		return error('divergence merge lost local change')
	}
	merged_right := merged_tree.get('sync-00000020'.bytes()) or { return error(err.msg()) }
	if !merged_right.value.bytestr().starts_with('theirs-') {
		return error('divergence merge lost remote change')
	}
	merged_commit := remote.checkout('main')!
	if merged_commit.parent_cids.len != 2 {
		return error('divergence merge expected 2 parents, got ${merged_commit.parent_cids.len}')
	}
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	commit_packets, node_packets := packet_kind_counts(merged_exchange.packets)
	raw_bytes := packet_bytes(merged_exchange.packets)
	compressed_bytes := packet_compressed_bytes(merged_exchange.packets)!
	return BenchResult{
		name:        'sync_push_divergence_auto_merge'
		duration_ms: duration_ms
		ops:         merged_exchange.packets.len
		bytes:       raw_bytes
		note:        'rows=${suite.cfg.rows} auto_merged=true tree_depth=${tree_depth} commit_packets=${commit_packets} node_packets=${node_packets} missing_commits=${merged_exchange.plan.missing_commit_cids.len} missing_nodes=${merged_exchange.plan.missing_node_cids.len} compressed_bytes=${compressed_bytes} source_commit=${source_update.snapshot.commit.cid} remote_commit=${remote_update.snapshot.commit.cid}'
	}
}

fn (suite BenchSuite) run_sync_pull_full_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-pull-full-source')!
	mut target := suite.init_sync_repo('polly-sync-pull-full-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync full pull'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.pull_branch_to_repo(mut target, mut source, 'main')!
	duration_ms := sw.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	negotiation_rtts := regular_negotiation_rtts(tree_depth)
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_pull_full'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        sync_note(suite.cfg.rows, duration_ms, tree_depth, 0, negotiation_rtts,
			suite.cfg.sync_rtt_ms, commit_packets, node_packets,
			result.exchange.plan.missing_commit_cids.len,
			result.exchange.plan.missing_node_cids.len, compressed_bytes)
	}
}

fn (suite BenchSuite) run_sync_pull_full_manifest_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-pull-full-manifest-source')!
	mut target := suite.init_sync_repo('polly-sync-pull-full-manifest-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync full pull manifest'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.pull_branch_to_repo_with_manifest(mut target, mut source, 'main')!
	duration_ms := sw.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	negotiation_rtts := manifest_negotiation_rtts(tree_depth, 1)
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_pull_full_manifest'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        sync_note(suite.cfg.rows, duration_ms, tree_depth, 1, negotiation_rtts,
			suite.cfg.sync_rtt_ms, commit_packets, node_packets,
			result.exchange.plan.missing_commit_cids.len,
			result.exchange.plan.missing_node_cids.len, compressed_bytes)
	}
}

fn (suite BenchSuite) run_sync_pull_tiny_change_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-pull-tiny-source')!
	mut target := suite.init_sync_repo('polly-sync-pull-tiny-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	base_tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync base pull'
		timestamp: time.now().unix()
	})!
	_ = storage.pull_branch_to_repo(mut target, mut source, 'main')!
	next_tree := suite.sync_mutated_tree(base_tree)!
	_ = source.commit_to_branch('main', next_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync tiny pull'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.pull_branch_to_repo(mut target, mut source, 'main')!
	duration_ms := sw.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	negotiation_rtts := regular_negotiation_rtts(tree_depth)
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_pull_tiny_change'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        sync_note(suite.cfg.rows, duration_ms, tree_depth, 0, negotiation_rtts,
			suite.cfg.sync_rtt_ms, commit_packets, node_packets,
			result.exchange.plan.missing_commit_cids.len,
			result.exchange.plan.missing_node_cids.len, compressed_bytes)
	}
}

fn (suite BenchSuite) run_sync_pull_tiny_change_manifest_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-pull-tiny-manifest-source')!
	mut target := suite.init_sync_repo('polly-sync-pull-tiny-manifest-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	base_tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync base pull manifest'
		timestamp: time.now().unix()
	})!
	_ = storage.pull_branch_to_repo_with_manifest(mut target, mut source, 'main')!
	next_tree := suite.sync_mutated_tree(base_tree)!
	_ = source.commit_to_branch('main', next_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync tiny pull manifest'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.pull_branch_to_repo_with_manifest(mut target, mut source, 'main')!
	duration_ms := sw.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	negotiation_rtts := manifest_negotiation_rtts(tree_depth, 1)
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_pull_tiny_change_manifest'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        sync_note(suite.cfg.rows, duration_ms, tree_depth, 1, negotiation_rtts,
			suite.cfg.sync_rtt_ms, commit_packets, node_packets,
			result.exchange.plan.missing_commit_cids.len,
			result.exchange.plan.missing_node_cids.len, compressed_bytes)
	}
}

fn (suite BenchSuite) run_sync_pull_tiny_change_manifest_depth2_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-pull-tiny-manifest2-source')!
	mut target := suite.init_sync_repo('polly-sync-pull-tiny-manifest2-target')!
	defer {
		source.close() or {}
		target.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target.path) or {}
	}
	base_tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync base pull manifest depth2'
		timestamp: time.now().unix()
	})!
	_ = storage.pull_branch_to_repo_with_manifest_depth(mut target, mut source, 'main', 2)!
	next_tree := suite.sync_mutated_tree(base_tree)!
	_ = source.commit_to_branch('main', next_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync tiny pull manifest depth2'
		timestamp: time.now().unix()
	})!
	mut sw := time.new_stopwatch()
	result := storage.pull_branch_to_repo_with_manifest_depth(mut target, mut source, 'main', 2)!
	duration_ms := sw.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	negotiation_rtts := manifest_negotiation_rtts(tree_depth, 2)
	commit_packets, node_packets := packet_kind_counts(result.exchange.packets)
	raw_bytes := packet_bytes(result.exchange.packets)
	compressed_bytes := packet_compressed_bytes(result.exchange.packets)!
	return BenchResult{
		name:        'sync_pull_tiny_change_manifest_depth2'
		duration_ms: duration_ms
		ops:         result.exchange.packets.len
		bytes:       raw_bytes
		note:        sync_note(suite.cfg.rows, duration_ms, tree_depth, 2, negotiation_rtts,
			suite.cfg.sync_rtt_ms, commit_packets, node_packets,
			result.exchange.plan.missing_commit_cids.len,
			result.exchange.plan.missing_node_cids.len, compressed_bytes)
	}
}

fn (suite BenchSuite) run_sync_tiny_change_rtt_sweep_bench() !BenchResult {
	mut source := suite.init_sync_repo('polly-sync-rtt-sweep-source')!
	mut target_regular := suite.init_sync_repo('polly-sync-rtt-sweep-target-regular')!
	mut target_manifest1 := suite.init_sync_repo('polly-sync-rtt-sweep-target-manifest1')!
	mut target_manifest2 := suite.init_sync_repo('polly-sync-rtt-sweep-target-manifest2')!
	defer {
		source.close() or {}
		target_regular.close() or {}
		target_manifest1.close() or {}
		target_manifest2.close() or {}
		os.rmdir_all(source.path) or {}
		os.rmdir_all(target_regular.path) or {}
		os.rmdir_all(target_manifest1.path) or {}
		os.rmdir_all(target_manifest2.path) or {}
	}
	base_tree := storage.Tree.build(suite.sync_bench_items(), suite.chunk_cfg)!
	_ = source.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync rtt sweep base'
		timestamp: time.now().unix()
	})!
	_ = storage.push_branch_to_repo(mut source, mut target_regular, 'main')!
	_ = storage.push_branch_to_repo_with_manifest(mut source, mut target_manifest1, 'main')!
	_ =
		storage.push_branch_to_repo_with_manifest_depth(mut source, mut target_manifest2, 'main', 2)!
	next_tree := suite.sync_mutated_tree(base_tree)!
	_ = source.commit_to_branch('main', next_tree, storage.CommitMeta{
		author:    'bench'
		message:   'sync rtt sweep tiny'
		timestamp: time.now().unix()
	})!
	mut sw_regular := time.new_stopwatch()
	regular := storage.push_branch_to_repo(mut source, mut target_regular, 'main')!
	regular_ms := sw_regular.elapsed().milliseconds()
	mut sw_manifest1 := time.new_stopwatch()
	manifest1 :=
		storage.push_branch_to_repo_with_manifest(mut source, mut target_manifest1, 'main')!
	manifest1_ms := sw_manifest1.elapsed().milliseconds()
	mut sw_manifest2 := time.new_stopwatch()
	manifest2 := storage.push_branch_to_repo_with_manifest_depth(mut source, mut target_manifest2,
		'main', 2)!
	manifest2_ms := sw_manifest2.elapsed().milliseconds()
	tree_depth := sync_branch_tree_depth(mut source, 'main')!
	regular_rtts := regular_negotiation_rtts(tree_depth)
	manifest1_rtts := manifest_negotiation_rtts(tree_depth, 1)
	manifest2_rtts := manifest_negotiation_rtts(tree_depth, 2)
	rtt_values := [0, 20, 40, 80, 120, 200]
	mut sweep_parts := []string{}
	for rtt in rtt_values {
		decision := storage.recommend_sync_negotiation_policy(tree_depth, rtt, regular_ms,
			manifest1_ms, manifest2_ms)
		winner_ms := match decision.policy {
			.regular { effective_sync_total_ms(regular_ms, regular_rtts, rtt) }
			.manifest_depth1 { effective_sync_total_ms(manifest1_ms, manifest1_rtts, rtt) }
			.manifest_depth2 { effective_sync_total_ms(manifest2_ms, manifest2_rtts, rtt) }
			.auto { effective_sync_total_ms(manifest1_ms, manifest1_rtts, rtt) }
		}

		winner := match decision.policy {
			.regular { 'regular' }
			.manifest_depth1 { 'manifest1' }
			.manifest_depth2 { 'manifest2' }
			.auto { 'auto' }
		}

		sweep_parts << 'rtt${rtt}=${winner}:${winner_ms}'
	}
	regular_commit_packets, regular_node_packets := packet_kind_counts(regular.exchange.packets)
	_ = manifest1
	_ = manifest2
	recommended := storage.recommend_sync_negotiation_policy(tree_depth, suite.cfg.sync_rtt_ms,
		regular_ms, manifest1_ms, manifest2_ms)
	recommended_name := match recommended.policy {
		.regular { 'regular' }
		.manifest_depth1 { 'manifest1' }
		.manifest_depth2 { 'manifest2' }
		.auto { 'auto' }
	}

	return BenchResult{
		name:        'sync_tiny_change_rtt_sweep'
		duration_ms: regular_ms
		ops:         regular.exchange.packets.len
		bytes:       packet_bytes(regular.exchange.packets)
		note:        'rows=${suite.cfg.rows} tree_depth=${tree_depth} configured_rtt_ms=${suite.cfg.sync_rtt_ms} recommended_policy=${recommended_name} regular_local_ms=${regular_ms} manifest1_local_ms=${manifest1_ms} manifest2_local_ms=${manifest2_ms} regular_packets=${
			regular_commit_packets + regular_node_packets} ${sweep_parts.join(' ')}'
	}
}

fn (suite BenchSuite) run_chunker_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	mut sw := time.new_stopwatch()
	chunks := suite.chunk_cfg.chunk_bytes(data)!
	base_hashes := suite.chunk_hashes(data, chunks)
	mut shifted := []u8{cap: data.len + 1}
	shifted << `X`
	shifted << data
	shifted_chunks := suite.chunk_cfg.chunk_bytes(shifted)!
	shifted_hashes := suite.chunk_hashes(shifted, shifted_chunks)
	mut reused := 0
	limit := if base_hashes.len < shifted_hashes.len { base_hashes.len } else { shifted_hashes.len }
	for idx in 1 .. limit {
		if base_hashes[idx] == shifted_hashes[idx] {
			reused++
		}
	}
	return BenchResult{
		name:        'cdc_chunker_10m'
		duration_ms: sw.elapsed().milliseconds()
		ops:         chunks.len
		bytes:       data.len
		note:        'chunks=${chunks.len} reused_after_head_insert=${reused}/${if limit > 0 {
			limit - 1
		} else {
			0
		}}'
	}
}

fn (suite BenchSuite) run_chunker_core_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	mut sw := time.new_stopwatch()
	chunks := suite.chunk_cfg.chunk_bytes(data)!
	duration_ms := sw.elapsed().milliseconds()
	mb_per_sec := if duration_ms > 0 {
		(f64(data.len) / (1024.0 * 1024.0)) / (f64(duration_ms) / 1000.0)
	} else {
		0.0
	}
	return BenchResult{
		name:        'cdc_core_10m'
		duration_ms: duration_ms
		ops:         chunks.len
		bytes:       data.len
		note:        'chunks=${chunks.len} throughput_mb_s=${mb_per_sec:.2f}'
	}
}

fn (suite BenchSuite) run_chunker_file_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	tmp_path := os.join_path(os.temp_dir(), 'pollytree-cdc-bench-${os.getpid()}.bin')
	os.write_bytes(tmp_path, data)!
	defer {
		os.rm(tmp_path) or {}
	}
	manager := storage.BufferManager.new(tmp_path, suite.cfg.chunk_buffer_kb * 1024,
		suite.chunk_cfg.max_size)!
	mut sw := time.new_stopwatch()
	chunks := manager.chunk_file(suite.chunk_cfg)!
	duration_ms := sw.elapsed().milliseconds()
	mb_per_sec := if duration_ms > 0 {
		(f64(data.len) / (1024.0 * 1024.0)) / (f64(duration_ms) / 1000.0)
	} else {
		0.0
	}
	return BenchResult{
		name:        'cdc_file_10m'
		duration_ms: duration_ms
		ops:         chunks.len
		bytes:       data.len
		note:        'chunks=${chunks.len} throughput_mb_s=${mb_per_sec:.2f} buffer_kb=${suite.cfg.chunk_buffer_kb}'
	}
}

fn (suite BenchSuite) run_chunker_file_cid_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	tmp_path := os.join_path(os.temp_dir(), 'pollytree-cdc-cid-bench-${os.getpid()}.bin')
	os.write_bytes(tmp_path, data)!
	defer {
		os.rm(tmp_path) or {}
	}
	manager := storage.BufferManager.new(tmp_path, suite.cfg.chunk_buffer_kb * 1024,
		suite.chunk_cfg.max_size)!
	mut sw := time.new_stopwatch()
	chunks := manager.chunk_file_cids(suite.chunk_cfg)!
	duration_ms := sw.elapsed().milliseconds()
	mb_per_sec := if duration_ms > 0 {
		(f64(data.len) / (1024.0 * 1024.0)) / (f64(duration_ms) / 1000.0)
	} else {
		0.0
	}
	return BenchResult{
		name:        'cdc_file_cid_10m'
		duration_ms: duration_ms
		ops:         chunks.len
		bytes:       data.len
		note:        'chunks=${chunks.len} throughput_mb_s=${mb_per_sec:.2f} buffer_kb=${suite.cfg.chunk_buffer_kb}'
	}
}

fn (suite BenchSuite) run_chunker_file_cid_parallel_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	tmp_path := os.join_path(os.temp_dir(), 'pollytree-cdc-parallel-cid-bench-${os.getpid()}.bin')
	os.write_bytes(tmp_path, data)!
	defer {
		os.rm(tmp_path) or {}
	}
	manager := storage.BufferManager.new(tmp_path, suite.cfg.chunk_buffer_kb * 1024,
		suite.chunk_cfg.max_size)!
	mut sw := time.new_stopwatch()
	chunks := manager.chunk_file_cids_with_workers(suite.chunk_cfg, suite.cfg.chunk_workers)!
	duration_ms := sw.elapsed().milliseconds()
	mb_per_sec := if duration_ms > 0 {
		(f64(data.len) / (1024.0 * 1024.0)) / (f64(duration_ms) / 1000.0)
	} else {
		0.0
	}
	return BenchResult{
		name:        'cdc_file_cid_parallel_10m'
		duration_ms: duration_ms
		ops:         chunks.len
		bytes:       data.len
		note:        'chunks=${chunks.len} throughput_mb_s=${mb_per_sec:.2f} buffer_kb=${suite.cfg.chunk_buffer_kb} workers=${suite.cfg.chunk_workers}'
	}
}

fn (suite BenchSuite) run_chunker_file_store_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	tmp_path := os.join_path(os.temp_dir(), 'pollytree-cdc-store-bench-${os.getpid()}.bin')
	store_path := os.join_path(os.temp_dir(), 'pollytree-cdc-store-bench-${os.getpid()}.chunks')
	os.write_bytes(tmp_path, data)!
	defer {
		os.rm(tmp_path) or {}
		os.rm(store_path) or {}
	}
	manager := storage.BufferManager.new(tmp_path, suite.cfg.chunk_buffer_kb * 1024,
		suite.chunk_cfg.max_size)!
	mut store := storage.ChunkStore.open(store_path)!
	defer {
		store.close()
	}
	mut sw := time.new_stopwatch()
	result := manager.ingest_to_store_profiled(suite.chunk_cfg,
		storage.ChunkIngestConfig.recommended(), mut store)!
	duration_ms := sw.elapsed().milliseconds()
	mb_per_sec := if duration_ms > 0 {
		(f64(data.len) / (1024.0 * 1024.0)) / (f64(duration_ms) / 1000.0)
	} else {
		0.0
	}
	return BenchResult{
		name:        'cdc_file_store_10m'
		duration_ms: duration_ms
		ops:         result.count
		bytes:       data.len
		note:        'chunks=${result.count} throughput_mb_s=${mb_per_sec:.2f} buffer_kb=${suite.cfg.chunk_buffer_kb} chunk_ms=${result.chunk_ms} cid_ms=${result.cid_ms} write_ms=${result.write_ms}'
	}
}

fn (suite BenchSuite) run_chunker_file_store_parallel_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	tmp_path := os.join_path(os.temp_dir(), 'pollytree-cdc-store-parallel-bench-${os.getpid()}.bin')
	store_path := os.join_path(os.temp_dir(),
		'pollytree-cdc-store-parallel-bench-${os.getpid()}.chunks')
	os.write_bytes(tmp_path, data)!
	defer {
		os.rm(tmp_path) or {}
		os.rm(store_path) or {}
	}
	manager := storage.BufferManager.new(tmp_path, suite.cfg.chunk_buffer_kb * 1024,
		suite.chunk_cfg.max_size)!
	mut store := storage.ChunkStore.open(store_path)!
	defer {
		store.close()
	}
	mut sw := time.new_stopwatch()
	result := manager.ingest_to_store_profiled(suite.chunk_cfg, storage.ChunkIngestConfig{
		worker_count:   suite.cfg.chunk_workers
		collect_chunks: false
	}, mut store)!
	duration_ms := sw.elapsed().milliseconds()
	mb_per_sec := if duration_ms > 0 {
		(f64(data.len) / (1024.0 * 1024.0)) / (f64(duration_ms) / 1000.0)
	} else {
		0.0
	}
	return BenchResult{
		name:        'cdc_file_store_parallel_10m'
		duration_ms: duration_ms
		ops:         result.count
		bytes:       data.len
		note:        'chunks=${result.count} throughput_mb_s=${mb_per_sec:.2f} buffer_kb=${suite.cfg.chunk_buffer_kb} workers=${suite.cfg.chunk_workers} chunk_ms=${result.chunk_ms} cid_ms=${result.cid_ms} write_ms=${result.write_ms}'
	}
}

fn (suite BenchSuite) run_parallel_hash_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	chunks := suite.chunk_cfg.chunk_bytes(data)!
	mut sw := time.new_stopwatch()
	chunk_cids := storage.hash_chunks_parallel(data, chunks, suite.cfg.chunk_workers)
	duration_ms := sw.elapsed().milliseconds()
	mb_per_sec := if duration_ms > 0 {
		(f64(data.len) / (1024.0 * 1024.0)) / (f64(duration_ms) / 1000.0)
	} else {
		0.0
	}
	return BenchResult{
		name:        'cdc_parallel_hash_10m'
		duration_ms: duration_ms
		ops:         chunk_cids.len
		bytes:       data.len
		note:        'chunks=${chunk_cids.len} throughput_mb_s=${mb_per_sec:.2f} workers=${suite.cfg.chunk_workers}'
	}
}

fn (suite BenchSuite) run_chunker_file_store_no_index_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	tmp_path := os.join_path(os.temp_dir(), 'pollytree-cdc-store-noindex-bench-${os.getpid()}.bin')
	store_path := os.join_path(os.temp_dir(),
		'pollytree-cdc-store-noindex-bench-${os.getpid()}.chunks')
	os.write_bytes(tmp_path, data)!
	defer {
		os.rm(tmp_path) or {}
		os.rm(store_path) or {}
	}
	manager := storage.BufferManager.new(tmp_path, suite.cfg.chunk_buffer_kb * 1024,
		suite.chunk_cfg.max_size)!
	mut store := storage.ChunkStore.open_without_index(store_path)!
	defer {
		store.close()
	}
	mut sw := time.new_stopwatch()
	result := manager.ingest_to_store_profiled(suite.chunk_cfg,
		storage.ChunkIngestConfig.recommended(), mut store)!
	duration_ms := sw.elapsed().milliseconds()
	mb_per_sec := if duration_ms > 0 {
		(f64(data.len) / (1024.0 * 1024.0)) / (f64(duration_ms) / 1000.0)
	} else {
		0.0
	}
	return BenchResult{
		name:        'cdc_file_store_no_index_10m'
		duration_ms: duration_ms
		ops:         result.count
		bytes:       data.len
		note:        'chunks=${result.count} throughput_mb_s=${mb_per_sec:.2f} buffer_kb=${suite.cfg.chunk_buffer_kb} chunk_ms=${result.chunk_ms} cid_ms=${result.cid_ms} write_ms=${result.write_ms}'
	}
}

fn (suite BenchSuite) run_chunker_file_store_deferred_index_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	tmp_path := os.join_path(os.temp_dir(), 'pollytree-cdc-store-deferred-bench-${os.getpid()}.bin')
	store_path := os.join_path(os.temp_dir(),
		'pollytree-cdc-store-deferred-bench-${os.getpid()}.chunks')
	os.write_bytes(tmp_path, data)!
	defer {
		os.rm(tmp_path) or {}
		os.rm(store_path) or {}
	}
	manager := storage.BufferManager.new(tmp_path, suite.cfg.chunk_buffer_kb * 1024,
		suite.chunk_cfg.max_size)!
	mut store := storage.ChunkStore.open_high_throughput(store_path)!
	defer {
		store.close()
	}
	mut sw := time.new_stopwatch()
	result := manager.ingest_to_store_profiled(suite.chunk_cfg,
		storage.ChunkIngestConfig.recommended(), mut store)!
	duration_ms := sw.elapsed().milliseconds()
	mb_per_sec := if duration_ms > 0 {
		(f64(data.len) / (1024.0 * 1024.0)) / (f64(duration_ms) / 1000.0)
	} else {
		0.0
	}
	return BenchResult{
		name:        'cdc_file_store_deferred_index_10m'
		duration_ms: duration_ms
		ops:         result.count
		bytes:       data.len
		note:        'chunks=${result.count} throughput_mb_s=${mb_per_sec:.2f} buffer_kb=${suite.cfg.chunk_buffer_kb} chunk_ms=${result.chunk_ms} cid_ms=${result.cid_ms} write_ms=${result.write_ms}'
	}
}

fn (suite BenchSuite) run_chunk_store_reopen_bench() !BenchResult {
	data := suite.large_payload(suite.cfg.chunk_bytes)
	tmp_path := os.join_path(os.temp_dir(), 'pollydb-cdc-store-reopen-bench-${os.getpid()}.bin')
	store_path := os.join_path(os.temp_dir(),
		'pollydb-cdc-store-reopen-bench-${os.getpid()}.chunks')
	os.write_bytes(tmp_path, data)!
	defer {
		os.rm(tmp_path) or {}
		os.rm(store_path) or {}
	}
	manager := storage.BufferManager.new(tmp_path, suite.cfg.chunk_buffer_kb * 1024,
		suite.chunk_cfg.max_size)!
	mut store := storage.ChunkStore.open_high_throughput(store_path)!
	manager.ingest_to_store(suite.chunk_cfg, storage.ChunkIngestConfig.high_throughput(), mut store)!
	store.close()

	mut sw := time.new_stopwatch()
	mut reopened := storage.ChunkStore.open_high_throughput(store_path)!
	duration_ms := sw.elapsed().milliseconds()
	defer {
		reopened.close()
	}
	mb_per_sec := if duration_ms > 0 {
		(f64(data.len) / (1024.0 * 1024.0)) / (f64(duration_ms) / 1000.0)
	} else {
		0.0
	}
	return BenchResult{
		name:        'cdc_store_reopen_10m'
		duration_ms: duration_ms
		ops:         1
		bytes:       data.len
		note:        'throughput_mb_s=${mb_per_sec:.2f} buffer_kb=${suite.cfg.chunk_buffer_kb}'
	}
}

fn (suite BenchSuite) run_prolly_random_update_bench() !BenchResult {
	target_bytes := if suite.cfg.chunk_bytes > 0 { suite.cfg.chunk_bytes } else { 100 * 1024 * 1024 }
	items := suite.prolly_bench_items(target_bytes)
	base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	target_idx := items.len / 2
	target_item := items[target_idx]
	mut next_value := target_item.value.clone()
	if next_value.len == 0 {
		next_value = [u8(`X`)]
	} else {
		mid := next_value.len / 2
		next_value[mid] = next_value[mid] ^ u8(0x01)
	}
	mut sw := time.new_stopwatch()
	next_tree := base_tree.put(storage.KVPair{
		key:   target_item.key.clone()
		value: next_value
	}, suite.chunk_cfg)!
	elapsed := sw.elapsed()
	duration_ms := elapsed.milliseconds()
	duration_us := elapsed.microseconds()
	diff := base_tree.diff(next_tree)
	added_bytes := next_tree.bytes_for_cids(diff.added_cids)
	reused_bytes := next_tree.bytes_for_cids(diff.reused_cids)
	base_nodes := base_tree.reachable_node_count()!
	next_nodes := next_tree.reachable_node_count()!
	base_bytes := base_tree.reachable_node_bytes()!
	next_bytes := next_tree.reachable_node_bytes()!
	reuse_ratio := if base_nodes > 0 {
		f64(diff.reused_cids.len) / f64(base_nodes)
	} else {
		0.0
	}
	return BenchResult{
		name:        'prolly_random_update'
		duration_ms: duration_ms
		ops:         1
		bytes:       target_bytes
		note:        'items=${items.len} root_us=${duration_us} base_nodes=${base_nodes} next_nodes=${next_nodes} added_nodes=${diff.added_cids.len} removed_nodes=${diff.removed_cids.len} reused_nodes=${diff.reused_cids.len} base_bytes=${base_bytes} next_bytes=${next_bytes} added_bytes=${added_bytes} reused_bytes=${reused_bytes} reuse_ratio=${reuse_ratio:.4f} root_changed=${base_tree.root.cid != next_tree.root.cid}'
	}
}

fn (suite BenchSuite) run_prolly_random_insert_bench() !BenchResult {
	target_bytes := if suite.cfg.chunk_bytes > 0 { suite.cfg.chunk_bytes } else { 100 * 1024 * 1024 }
	items := suite.prolly_bench_items(target_bytes)
	base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	insert_idx := items.len / 2
	insert_key := 'bench-${insert_idx:08}-insert'.bytes()
	insert_value := suite.prolly_bench_value(items.len + insert_idx)
	elapsed, next_tree := suite.measure_tree_put(base_tree, storage.KVPair{
		key:   insert_key
		value: insert_value
	})!
	diff := base_tree.diff(next_tree)
	return suite.prolly_bench_result('prolly_random_insert', target_bytes, items.len, base_tree,
		next_tree, diff, elapsed)
}

fn (suite BenchSuite) run_prolly_random_delete_bench() !BenchResult {
	target_bytes := if suite.cfg.chunk_bytes > 0 { suite.cfg.chunk_bytes } else { 100 * 1024 * 1024 }
	items := suite.prolly_bench_items(target_bytes)
	base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	delete_idx := items.len / 2
	delete_key := items[delete_idx].key.clone()
	mut sw := time.new_stopwatch()
	next_tree := base_tree.delete(delete_key, suite.chunk_cfg)!
	elapsed := sw.elapsed()
	diff := base_tree.diff(next_tree)
	return suite.prolly_bench_result('prolly_random_delete', target_bytes, items.len, base_tree,
		next_tree, diff, elapsed)
}

fn (suite BenchSuite) run_prolly_random_update_distribution_bench() !BenchResult {
	target_bytes := if suite.cfg.chunk_bytes > 0 { suite.cfg.chunk_bytes } else { 100 * 1024 * 1024 }
	items := suite.prolly_bench_items(target_bytes)
	base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	samples := suite.prolly_sample_count()
	mut root_us := []i64{cap: samples}
	mut added_bytes := []int{cap: samples}
	mut added_nodes := []int{cap: samples}
	mut path_depths := []int{cap: samples}
	mut leaf_item_counts := []int{cap: samples}
	suite.prolly_distribution_warmup(base_tree, items)!
	for sample_idx in 0 .. samples {
		item_idx := suite.prolly_sample_index(items.len, sample_idx)
		item := items[item_idx]
		stats := base_tree.key_stats(item.key)!
		mut next_value := item.value.clone()
		if next_value.len == 0 {
			next_value = [u8(`X`)]
		} else {
			pos := (sample_idx * 131 + next_value.len / 2) % next_value.len
			next_value[pos] = next_value[pos] ^ u8(0x01)
		}
		elapsed, next_tree := suite.measure_tree_put(base_tree, storage.KVPair{
			key:   item.key.clone()
			value: next_value
		})!
		diff := base_tree.diff(next_tree)
		root_us << elapsed.microseconds()
		added_bytes << next_tree.bytes_for_cids(diff.added_cids)
		added_nodes << diff.added_cids.len
		path_depths << stats.path_depth
		leaf_item_counts << stats.leaf_item_count
	}
	return suite.prolly_distribution_result('prolly_random_update_dist', target_bytes, items.len,
		samples, root_us, added_bytes, added_nodes, path_depths, leaf_item_counts)
}

fn (suite BenchSuite) run_prolly_random_insert_distribution_bench() !BenchResult {
	target_bytes := if suite.cfg.chunk_bytes > 0 { suite.cfg.chunk_bytes } else { 100 * 1024 * 1024 }
	items := suite.prolly_bench_items(target_bytes)
	base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	samples := suite.prolly_sample_count()
	mut root_us := []i64{cap: samples}
	mut added_bytes := []int{cap: samples}
	mut added_nodes := []int{cap: samples}
	mut path_depths := []int{cap: samples}
	mut leaf_item_counts := []int{cap: samples}
	suite.prolly_distribution_warmup(base_tree, items)!
	for sample_idx in 0 .. samples {
		insert_idx := suite.prolly_sample_index(items.len, sample_idx)
		insert_key := 'bench-${insert_idx:08}-insert-${sample_idx:04}'.bytes()
		insert_value := suite.prolly_bench_value(items.len + insert_idx + sample_idx)
		stats := base_tree.key_stats(items[insert_idx].key)!
		elapsed, next_tree := suite.measure_tree_put(base_tree, storage.KVPair{
			key:   insert_key
			value: insert_value
		})!
		diff := base_tree.diff(next_tree)
		root_us << elapsed.microseconds()
		added_bytes << next_tree.bytes_for_cids(diff.added_cids)
		added_nodes << diff.added_cids.len
		path_depths << stats.path_depth
		leaf_item_counts << stats.leaf_item_count
	}
	return suite.prolly_distribution_result('prolly_random_insert_dist', target_bytes, items.len,
		samples, root_us, added_bytes, added_nodes, path_depths, leaf_item_counts)
}

fn (suite BenchSuite) run_prolly_random_delete_distribution_bench() !BenchResult {
	target_bytes := if suite.cfg.chunk_bytes > 0 { suite.cfg.chunk_bytes } else { 100 * 1024 * 1024 }
	items := suite.prolly_bench_items(target_bytes)
	base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	samples := suite.prolly_sample_count()
	mut root_us := []i64{cap: samples}
	mut added_bytes := []int{cap: samples}
	mut added_nodes := []int{cap: samples}
	mut path_depths := []int{cap: samples}
	mut leaf_item_counts := []int{cap: samples}
	suite.prolly_distribution_warmup(base_tree, items)!
	for sample_idx in 0 .. samples {
		delete_idx := suite.prolly_sample_index(items.len, sample_idx)
		delete_key := items[delete_idx].key.clone()
		stats := base_tree.key_stats(delete_key)!
		mut sw := time.new_stopwatch()
		next_tree := base_tree.delete(delete_key, suite.chunk_cfg)!
		elapsed := sw.elapsed()
		diff := base_tree.diff(next_tree)
		root_us << elapsed.microseconds()
		added_bytes << next_tree.bytes_for_cids(diff.added_cids)
		added_nodes << diff.added_cids.len
		path_depths << stats.path_depth
		leaf_item_counts << stats.leaf_item_count
	}
	return suite.prolly_distribution_result('prolly_random_delete_dist', target_bytes, items.len,
		samples, root_us, added_bytes, added_nodes, path_depths, leaf_item_counts)
}

fn (suite BenchSuite) run_prolly_root_lookup_latency_bench() !BenchResult {
	target_bytes := if suite.cfg.chunk_bytes > 0 { suite.cfg.chunk_bytes } else { 100 * 1024 * 1024 }
	items := suite.prolly_bench_items(target_bytes)
	tree := storage.Tree.build(items, suite.chunk_cfg)!
	temp_dir := os.join_path(os.vtmp_dir(), 'pollydb-prolly-latency-${time.now().unix_micro()}')
	os.mkdir_all(temp_dir)!
	defer {
		os.rmdir_all(temp_dir) or {}
	}
	store_path := os.join_path(temp_dir, 'nodes.chunk')
	mut writer := storage.PersistentNodeStore.open_high_throughput(store_path)!
	writer.put_tree(tree)!
	writer.checkpoint()!
	writer.close()
	mut store := storage.PersistentNodeStore.open(store_path)!
	defer {
		store.close()
	}
	samples := max_int(1, suite.cfg.lookups)
	mut lookup_us := []i64{cap: samples}
	mut path_depths := []int{cap: samples}
	mut nodes_read := []int{cap: samples}
	mut leaf_items := []int{cap: samples}
	mut total_us := i64(0)
	for sample_idx in 0 .. samples {
		item_idx := suite.prolly_sample_index(items.len, sample_idx)
		key := items[item_idx].key
		mut sw := time.new_stopwatch()
		result := storage.Tree.lookup_in_byte_store_with_stats(tree.root.cid, key, mut store)!
		elapsed := sw.elapsed().microseconds()
		lookup_us << elapsed
		total_us += elapsed
		path_depths << result.stats.path_depth
		nodes_read << result.stats.nodes_read
		leaf_items << result.stats.leaf_item_count
	}
	avg_us := f64(total_us) / f64(samples)
	return BenchResult{
		name:        'prolly_root_lookup_latency'
		duration_ms: total_us / 1000
		ops:         samples
		bytes:       target_bytes
		note:        'items=${items.len} root=${tree.root.cid} avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us,
			50)} p95_us=${percentile_i64(lookup_us, 95)} max_us=${max_i64(lookup_us)} path_depth_p50=${percentile_int(path_depths,
			50)} path_depth_p95=${percentile_int(path_depths, 95)} nodes_read_p50=${percentile_int(nodes_read,
			50)} nodes_read_p95=${percentile_int(nodes_read, 95)} leaf_items_p50=${percentile_int(leaf_items,
			50)} leaf_items_p95=${percentile_int(leaf_items, 95)}'
	}
}

fn (suite BenchSuite) build_typed_state() !BenchState {
	spec := suite.users_spec()!
	return suite.build_typed_state_for_spec(spec)
}

fn (suite BenchSuite) build_typed_state_for_spec(spec storage.TypedTableSpec) !BenchState {
	mut repo := storage.Repository.new('main')
	mut node_store := storage.MemoryNodeStore.new()
	mut commit_store := storage.MemoryCommitStore.new()
	codec := storage.TypedRowCodec.new(spec.table)
	email_column := spec.table.column('email')!
	mut items := []storage.KVPair{cap: suite.cfg.rows * 2}

	for row_id in 0 .. suite.cfg.rows {
		if row_id == 0 || row_id == suite.cfg.rows - 1
			|| row_id % max_int(1, suite.cfg.batch_size * 10) == 0 {
			end := min_int(row_id + suite.cfg.batch_size, suite.cfg.rows)
			eprintln('   -> synthesize rows ${row_id}..${end}')
		}
		row := suite.user_row(row_id)
		pk := row_key(row_id)
		items << storage.KVPair{
			key:   encode_table_row_key(spec.table.name, pk)
			value: codec.encode(row)!
		}
		email := row.get('email')!
		items << storage.KVPair{
			key:   encode_index_entry_key(spec.table.name, 'email', storage.TypedValueEncoder.encode_index_value(email,
				email_column)!, pk)
			value: []u8{}
		}
	}
	base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	_ = repo.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'synthetic bulk load'
		timestamp: 1
	}, mut node_store, mut commit_store)!

	return BenchState{
		repo:         repo
		spec:         spec
		node_store:   node_store
		commit_store: commit_store
	}
}

fn (suite BenchSuite) build_persistent_typed_state() !PersistentBenchState {
	return suite.build_persistent_typed_state_with_covering(false)
}

fn (suite BenchSuite) codex_entries_rows_only_bench_spec() !CodexEntrySchemaBenchSpec {
	base := agentview.default_codex_session_schema().schema()!
	entry_spec := base.table('entries')!
	return CodexEntrySchemaBenchSpec{
		name:   'codex_entries_write_rows_only'
		schema: storage.DatabaseSchema{
			name:    'codex_entries_rows_only'
			version: 'v1'
			tables:  [
				storage.TypedTableSpec.new(entry_spec.table, []storage.SchemaIndexDef{})!,
			]
		}
	}
}

fn (suite BenchSuite) codex_entries_secondary_index_bench_spec() !CodexEntrySchemaBenchSpec {
	base := agentview.default_codex_session_schema().schema()!
	return CodexEntrySchemaBenchSpec{
		name:   'codex_entries_write_secondary_indexes'
		schema: storage.DatabaseSchema{
			name:    'codex_entries_secondary_indexes'
			version: base.version
			tables:  [base.table('entries')!]
		}
	}
}

fn codex_entries_spec_with_index_filter(base storage.DatabaseSchema, name string, keep fn (storage.SchemaIndexDef) bool) !CodexEntrySchemaBenchSpec {
	entry_spec := base.table('entries')!
	mut indexes := []storage.SchemaIndexDef{}
	for index in entry_spec.indexes {
		if keep(index) {
			indexes << index
		}
	}
	return CodexEntrySchemaBenchSpec{
		name:   name
		schema: storage.DatabaseSchema{
			name:    name
			version: base.version
			tables:  [storage.TypedTableSpec.new(entry_spec.table, indexes)!]
		}
	}
}

fn (suite BenchSuite) codex_entries_secondary_no_cover_bench_spec() !CodexEntrySchemaBenchSpec {
	base := agentview.default_codex_session_schema().schema()!
	return codex_entries_spec_with_index_filter(base, 'codex_entries_write_secondary_no_cover', fn (index storage.SchemaIndexDef) bool {
		return index.name != 'entries_session_cover_idx'
	})!
}

fn (suite BenchSuite) codex_entries_secondary_cover_only_bench_spec() !CodexEntrySchemaBenchSpec {
	base := agentview.default_codex_session_schema().schema()!
	return codex_entries_spec_with_index_filter(base, 'codex_entries_write_secondary_cover_only', fn (index storage.SchemaIndexDef) bool {
		return index.name != 'entries_session_idx'
	})!
}

fn (suite BenchSuite) codex_entries_fts_bench_spec() !CodexEntrySchemaBenchSpec {
	search := agentview.codex_session_search_schema().schema()!
	return CodexEntrySchemaBenchSpec{
		name:   'codex_entries_write_fts'
		schema: storage.DatabaseSchema{
			name:    'codex_entries_fts'
			version: search.version
			tables:  [search.table('entries')!]
		}
	}
}

fn (suite BenchSuite) codex_entries_fts_no_cover_bench_spec() !CodexEntrySchemaBenchSpec {
	search := agentview.codex_session_search_schema().schema()!
	return codex_entries_spec_with_index_filter(search, 'codex_entries_write_fts_no_cover', fn (index storage.SchemaIndexDef) bool {
		return index.name != 'entries_session_cover_idx'
	})!
}

fn (suite BenchSuite) codex_entries_markdown_fts_bench_spec() !CodexEntrySchemaBenchSpec {
	base := agentview.default_codex_session_schema().schema()!
	entry_spec := base.table('entries')!
	mut indexes := entry_spec.indexes.clone()
	indexes << storage.SchemaIndexDef.fts_markdown_with_options('entries_content_md_fts_idx',
		'content_md', .visible_text_with_code, storage.FtsIndexOptions{
		tokenizer:      'unicode61 remove_diacritics 2'
		prefix_lengths: [2, 3, 4]
	})!
	return CodexEntrySchemaBenchSpec{
		name:                 'codex_entries_write_markdown_fts'
		schema:               storage.DatabaseSchema{
			name:    'codex_entries_markdown_fts'
			version: base.version
			tables:  [storage.TypedTableSpec.new(entry_spec.table, indexes)!]
		}
		materialize_markdown: true
		markdown_source_only: true
	}
}

fn (suite BenchSuite) schema_bench_chunk_cfg() storage.ChunkConfig {
	return suite.chunk_cfg.with_detailed_timings(true).with_small_patch_limit(suite.cfg.small_patch_limit).with_split_backed_working_set(suite.cfg.split_backed).with_write_diff(suite.cfg.write_diff)
}

fn (suite BenchSuite) codex_entry_row(id int) storage.TypedRowData {
	session_idx := id / 64
	role := if id % 5 == 0 { 'user' } else { 'assistant' }
	kind := if id % 7 == 0 { 'tool_call' } else { 'message' }
	tool_name := if kind == 'tool_call' { 'shell' } else { '' }
	title := if kind == 'tool_call' { 'tool ${id}' } else { '' }
	call_id := if kind == 'tool_call' { 'call_${id:08}' } else { '' }
	phase := if role == 'assistant' { 'response' } else { '' }
	mut row := storage.TypedRowData.new()
	row.set('id', 'session-${session_idx:06}:${id:08}')
	row.set('agent', 'codex')
	row.set('session_id', 'session-${session_idx:06}')
	row.set('session_title', 'Synthetic session ${session_idx:06}')
	row.set('seq', i64(id % 64))
	row.set('timestamp', '2026-07-10T12:${(id / 60) % 60:02}:${id % 60:02}.000000Z')
	row.set('role', role)
	row.set('kind', kind)
	row.set('tool_name', tool_name)
	row.set('call_id', call_id)
	row.set('title', title)
	row.set('content_text', suite.codex_entry_content_text(id, session_idx,
		'patch review retrieval throughput fts path'))
	row.set('content_md', storage.MarkdownRef{})
	row.set('raw_type', if kind == 'tool_call' { 'function_call' } else { 'message' })
	row.set('phase', phase)
	return row
}

fn (suite BenchSuite) codex_entry_markdown(id int, session_idx int, suffix string) string {
	text := suite.codex_entry_content_text(id, session_idx, suffix)
	return '# Entry ${id}\n\n${text}\n\n```sh\nagentview search --session session-${session_idx:06} --token ${(id % 97):02}\n```\n'
}

fn (suite BenchSuite) codex_entry_row_for_target(mut db storage.PersistentDatabase, target CodexEntrySchemaBenchSpec, id int) !storage.TypedRowData {
	session_idx := id / 64
	mut row := suite.codex_entry_row(id)
	if target.materialize_markdown {
		raw := suite.codex_entry_markdown(id, session_idx,
			'markdown fts path visible searchable token')
		ref := if target.markdown_source_only {
			db.ingest_markdown_source_only(raw)!
		} else {
			db.ingest_markdown(raw)!
		}
		row.set('content_md', ref)
	}
	return row
}

fn (suite BenchSuite) codex_entry_row_for_target_timed(mut db storage.PersistentDatabase, target CodexEntrySchemaBenchSpec, id int, mut markdown_ingest_us []i64) !storage.TypedRowData {
	session_idx := id / 64
	mut row := suite.codex_entry_row(id)
	if target.materialize_markdown {
		mut ingest_sw := time.new_stopwatch()
		raw := suite.codex_entry_markdown(id, session_idx,
			'markdown fts path visible searchable token')
		ref := if target.markdown_source_only {
			db.ingest_markdown_source_only(raw)!
		} else {
			db.ingest_markdown(raw)!
		}
		row.set('content_md', ref)
		markdown_ingest_us << ingest_sw.elapsed().microseconds()
	}
	return row
}

fn (suite BenchSuite) codex_entry_content_text(id int, session_idx int, suffix string) string {
	base := 'entry ${id} session ${session_idx} codex benchmark searchable token ${(id % 97):02} ${suffix}'
	if suite.cfg.content_bytes <= 0 || base.len >= suite.cfg.content_bytes {
		return base
	}
	mut text := base
	filler := ' markdown code block terminal output reasoning trace searchable context'
	for text.len < suite.cfg.content_bytes {
		text += filler
	}
	return text[..suite.cfg.content_bytes]
}

fn codex_entry_pk(row_id int) []u8 {
	return 'session-${row_id / 64:06}:${row_id:08}'.bytes()
}

fn codex_schema_scenario_name(base string, action string) string {
	prefix := 'codex_entries_write_'
	if base.starts_with(prefix) {
		return 'codex_entries_${action}_${base[prefix.len..]}'
	}
	return '${base}_${action}'
}

fn codex_entries_first_fts_sidecar_table_name(target CodexEntrySchemaBenchSpec) string {
	entry_spec := target.schema.table('entries') or { return '' }
	for index in entry_spec.indexes {
		if index.is_fts() {
			return 'fts_entries_${index.name}'
		}
	}
	return ''
}

fn (suite BenchSuite) build_codex_entries_schema_state(target CodexEntrySchemaBenchSpec) !CodexEntrySchemaBenchState {
	root_dir := os.join_path(os.temp_dir(),
		'pollydb-bench-${target.name}-${os.getpid()}-${time.now().unix_micro()}')
	bench_cfg := suite.schema_bench_chunk_cfg()
	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	for table in target.schema.tables {
		db.register_table(table)!
	}
	mut inserted := 0
	mut batch_start := 0
	for batch_start < suite.cfg.rows {
		batch_end := min_int(batch_start + suite.cfg.batch_size, suite.cfg.rows)
		mut write_set := storage.TypedWriteSet.new()
		for row_id in batch_start .. batch_end {
			write_set.put('entries', codex_entry_pk(row_id), suite.codex_entry_row_for_target(mut db,
				target, row_id)!)
		}
		_ = db.apply_typed_write_set_with_specs('main', target.schema.tables, write_set, bench_cfg, storage.CommitMeta{
			author:    'bench'
			message:   '${target.name} seed ${batch_start}-${batch_end}'
			timestamp: batch_end
		})!
		inserted += batch_end - batch_start
		batch_start = batch_end
	}
	db.checkpoint()!
	return CodexEntrySchemaBenchState{
		root_dir: root_dir
		target:   target
		inserted: inserted
		db:       db
	}
}

fn (suite BenchSuite) run_codex_entries_schema_bench(target CodexEntrySchemaBenchSpec) !BenchResult {
	root_dir := os.join_path(os.temp_dir(),
		'pollydb-bench-${target.name}-${os.getpid()}-${time.now().unix_micro()}')
	bench_cfg := suite.schema_bench_chunk_cfg()
	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	defer {
		db.close() or {}
		os.rmdir_all(root_dir) or {}
	}
	for table in target.schema.tables {
		db.register_table(table)!
	}
	mut write_set_us := []i64{}
	mut tx_apply_us := []i64{}
	mut index_rebuild_us := []i64{}
	mut commit_us := []i64{}
	mut snapshot_persist_us := []i64{}
	mut branch_head_us := []i64{}
	mut repo_meta_persist_us := []i64{}
	mut fts_us := []i64{}
	mut fts_begin_us := []i64{}
	mut fts_ensure_us := []i64{}
	mut fts_backfill_us := []i64{}
	mut fts_prepare_us := []i64{}
	mut fts_docid_select_us := []i64{}
	mut fts_delete_us := []i64{}
	mut fts_text_us := []i64{}
	mut fts_insert_us := []i64{}
	mut fts_insert_fts_us := []i64{}
	mut fts_insert_map_us := []i64{}
	mut fts_commit_us := []i64{}
	mut fts_ops_per_batch := []int{}
	mut fts_inserted_per_batch := []int{}
	mut markdown_ingest_us := []i64{}
	mut fallback_ms := []i64{}
	mut fallback_build_ms := []i64{}
	mut fallback_items_ms := []i64{}
	mut fallback_ops_ms := []i64{}
	mut fallback_ops_lookup_ms := []i64{}
	mut fallback_ops_encode_ms := []i64{}
	mut fallback_ops_state_ms := []i64{}
	mut fallback_ops_index_ms := []i64{}
	mut fallback_prepare_ms := []i64{}
	mut fallback_prepare_keys_ms := []i64{}
	mut fallback_prepare_rows_ms := []i64{}
	mut fallback_prepare_rows_key_ms := []i64{}
	mut fallback_prepare_rows_value_ms := []i64{}
	mut fallback_leaf_ms := []i64{}
	mut fallback_leaf_chunk_ms := []i64{}
	mut fallback_leaf_node_ms := []i64{}
	mut fallback_leaf_node_serialize_ms := []i64{}
	mut fallback_leaf_node_cid_ms := []i64{}
	mut fallback_leaf_node_add_ms := []i64{}
	mut fallback_internal_ms := []i64{}
	mut fallback_ops := []int{}
	mut checkpoint_us := []i64{}
	mut added_nodes := []int{}
	mut total_added_bytes := 0
	mut inserted := 0
	mut batch_start := 0
	mut total_sw := time.new_stopwatch()
	for batch_start < suite.cfg.rows {
		batch_end := min_int(batch_start + suite.cfg.batch_size, suite.cfg.rows)
		mut write_set := storage.TypedWriteSet.new()
		for row_id in batch_start .. batch_end {
			row := suite.codex_entry_row_for_target_timed(mut db, target, row_id, mut
				markdown_ingest_us)!
			write_set.put('entries', 'session-${row_id / 64:06}:${row_id:08}'.bytes(), row)
		}
		mut sw := time.new_stopwatch()
		result := db.apply_typed_write_set_with_specs('main', target.schema.tables, write_set,
			bench_cfg, storage.CommitMeta{
			author:    'bench'
			message:   '${target.name} batch ${batch_start}-${batch_end}'
			timestamp: batch_end
		})!
		elapsed := sw.elapsed().microseconds()
		write_set_us << elapsed
		tx_apply_us << result.timings.tx_apply_us
		index_rebuild_us << result.timings.index_rebuild_us
		commit_us << result.timings.commit_us
		snapshot_persist_us << result.timings.snapshot_persist_us
		branch_head_us << result.timings.branch_head_us
		repo_meta_persist_us << result.timings.repo_meta_persist_us
		fts_us << result.timings.fts_us
		fts_begin_us << result.timings.fts_begin_us
		fts_ensure_us << result.timings.fts_ensure_us
		fts_backfill_us << result.timings.fts_backfill_us
		fts_prepare_us << result.timings.fts_prepare_us
		fts_docid_select_us << result.timings.fts_docid_select_us
		fts_delete_us << result.timings.fts_delete_us
		fts_text_us << result.timings.fts_text_us
		fts_insert_us << result.timings.fts_insert_us
		fts_insert_fts_us << result.timings.fts_insert_fts_us
		fts_insert_map_us << result.timings.fts_insert_map_us
		fts_commit_us << result.timings.fts_commit_us
		fts_ops_per_batch << result.timings.fts_ops
		fts_inserted_per_batch << result.timings.fts_inserted
		fallback_ms << result.transaction_update.timings.fallback_ms
		fallback_items_ms << result.transaction_update.timings.fallback_items_ms
		fallback_ops_ms << result.transaction_update.timings.fallback_ops_ms
		fallback_ops_lookup_ms << result.transaction_update.timings.fallback_ops_lookup_ms
		fallback_ops_encode_ms << result.transaction_update.timings.fallback_ops_encode_ms
		fallback_ops_state_ms << result.transaction_update.timings.fallback_ops_state_ms
		fallback_ops_index_ms << result.transaction_update.timings.fallback_ops_index_ms
		fallback_build_ms << result.transaction_update.timings.fallback_build_ms
		fallback_prepare_ms << result.transaction_update.timings.fallback_build_prepare_ms
		fallback_prepare_keys_ms << result.transaction_update.timings.fallback_build_prepare_keys_ms
		fallback_prepare_rows_ms << result.transaction_update.timings.fallback_build_prepare_rows_ms
		fallback_prepare_rows_key_ms << result.transaction_update.timings.fallback_build_prepare_rows_key_ms
		fallback_prepare_rows_value_ms << result.transaction_update.timings.fallback_build_prepare_rows_value_ms
		fallback_leaf_ms << result.transaction_update.timings.fallback_build_leaf_ms
		fallback_leaf_chunk_ms << result.transaction_update.timings.fallback_build_leaf_chunk_ms
		fallback_leaf_node_ms << result.transaction_update.timings.fallback_build_leaf_node_ms
		fallback_leaf_node_serialize_ms << result.transaction_update.timings.fallback_build_leaf_node_serialize_ms
		fallback_leaf_node_cid_ms << result.transaction_update.timings.fallback_build_leaf_node_cid_ms
		fallback_leaf_node_add_ms << result.transaction_update.timings.fallback_build_leaf_node_add_ms
		fallback_internal_ms << result.transaction_update.timings.fallback_build_internal_ms
		fallback_ops << result.transaction_update.timings.fallback_ops
		added_nodes << result.transaction_update.diff.added_cids.len
		total_added_bytes +=
			result.update.snapshot.tree.bytes_for_cids(result.transaction_update.diff.added_cids)
		inserted += batch_end - batch_start
		batch_start = batch_end
	}
	checkpoint_timings := db.checkpoint_timed()!
	checkpoint_us << checkpoint_timings.total_us
	total_ms := total_sw.elapsed().milliseconds()
	fts_table_name := codex_entries_first_fts_sidecar_table_name(target)
	fts_rows := if fts_table_name.len > 0 {
		storage.fts_sidecar_branch_row_count(root_dir, fts_table_name, 'main') or { 0 }
	} else {
		0
	}
	return BenchResult{
		name:        target.name
		duration_ms: total_ms
		ops:         inserted
		bytes:       total_added_bytes
		note:        'tables=${target.schema.table_names().join(',')} indexes=${target.schema.table('entries')!.indexes.len} fts=${target.schema.table('entries')!.indexes.any(it.is_fts())} markdown=${target.materialize_markdown} markdown_source_only=${target.markdown_source_only} rows=${inserted} batch_size=${suite.cfg.batch_size} small_patch_limit=${suite.cfg.small_patch_limit} content_bytes=${suite.cfg.content_bytes} write_set_p50_us=${percentile_i64(write_set_us,
			50)} write_set_p95_us=${percentile_i64(write_set_us, 95)} tx_apply_p50_us=${percentile_i64(tx_apply_us,
			50)} tx_apply_p95_us=${percentile_i64(tx_apply_us, 95)} fallback_p50_ms=${percentile_i64(fallback_ms,
			50)} fallback_items_p50_ms=${percentile_i64(fallback_items_ms, 50)} fallback_ops_p50_ms=${percentile_i64(fallback_ops_ms,
			50)} fallback_ops_lookup_p50_ms=${percentile_i64(fallback_ops_lookup_ms, 50)} fallback_ops_encode_p50_ms=${percentile_i64(fallback_ops_encode_ms,
			50)} fallback_ops_state_p50_ms=${percentile_i64(fallback_ops_state_ms, 50)} fallback_ops_index_p50_ms=${percentile_i64(fallback_ops_index_ms,
			50)} fallback_build_p50_ms=${percentile_i64(fallback_build_ms, 50)} fallback_prepare_p50_ms=${percentile_i64(fallback_prepare_ms,
			50)} fallback_prepare_keys_p50_ms=${percentile_i64(fallback_prepare_keys_ms, 50)} fallback_prepare_rows_p50_ms=${percentile_i64(fallback_prepare_rows_ms,
			50)} fallback_prepare_rows_key_p50_ms=${percentile_i64(fallback_prepare_rows_key_ms, 50)} fallback_prepare_rows_value_p50_ms=${percentile_i64(fallback_prepare_rows_value_ms,
			50)} fallback_leaf_p50_ms=${percentile_i64(fallback_leaf_ms, 50)} fallback_leaf_chunk_p50_ms=${percentile_i64(fallback_leaf_chunk_ms,
			50)} fallback_leaf_node_p50_ms=${percentile_i64(fallback_leaf_node_ms, 50)} fallback_leaf_node_serialize_p50_ms=${percentile_i64(fallback_leaf_node_serialize_ms,
			50)} fallback_leaf_node_cid_p50_ms=${percentile_i64(fallback_leaf_node_cid_ms, 50)} fallback_leaf_node_add_p50_ms=${percentile_i64(fallback_leaf_node_add_ms,
			50)} fallback_internal_p50_ms=${percentile_i64(fallback_internal_ms, 50)} fallback_ops_p50=${percentile_int(fallback_ops,
			50)} index_p50_us=${percentile_i64(index_rebuild_us, 50)} index_p95_us=${percentile_i64(index_rebuild_us,
			95)} commit_p50_us=${percentile_i64(commit_us, 50)} snapshot_p50_us=${percentile_i64(snapshot_persist_us,
			50)} branch_head_p50_us=${percentile_i64(branch_head_us, 50)} repo_meta_p50_us=${percentile_i64(repo_meta_persist_us,
			50)} fts_p50_us=${percentile_i64(fts_us, 50)} fts_p95_us=${percentile_i64(fts_us, 95)} fts_begin_p50_us=${percentile_i64(fts_begin_us,
			50)} fts_ensure_p50_us=${percentile_i64(fts_ensure_us, 50)} fts_backfill_p50_us=${percentile_i64(fts_backfill_us,
			50)} fts_prepare_p50_us=${percentile_i64(fts_prepare_us, 50)} fts_docid_select_p50_us=${percentile_i64(fts_docid_select_us,
			50)} fts_delete_p50_us=${percentile_i64(fts_delete_us, 50)} fts_text_p50_us=${percentile_i64(fts_text_us,
			50)} fts_insert_p50_us=${percentile_i64(fts_insert_us, 50)} fts_commit_p50_us=${percentile_i64(fts_commit_us,
			50)} fts_insert_fts_p50_us=${percentile_i64(fts_insert_fts_us, 50)} fts_insert_map_p50_us=${percentile_i64(fts_insert_map_us,
			50)} fts_ops_p50=${percentile_int(fts_ops_per_batch, 50)} fts_inserted_p50=${percentile_int(fts_inserted_per_batch,
			50)} markdown_ingest_p50_us=${percentile_i64(markdown_ingest_us, 50)} markdown_ingest_p95_us=${percentile_i64(markdown_ingest_us,
			95)} checkpoint_us=${percentile_i64(checkpoint_us, 50)} added_nodes_p50=${percentile_int(added_nodes,
			50)} added_nodes_p95=${percentile_int(added_nodes, 95)} fts_rows=${fts_rows}'
	}
}

fn (suite BenchSuite) run_codex_entries_update_bench(target CodexEntrySchemaBenchSpec, update_content bool) !BenchResult {
	mut state := suite.build_codex_entries_schema_state(target)!
	bench_cfg := suite.schema_bench_chunk_cfg()
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	ops := min_int(suite.cfg.updates, state.inserted)
	mut write_set_us := []i64{}
	mut tx_apply_us := []i64{}
	mut index_rebuild_us := []i64{}
	mut commit_us := []i64{}
	mut snapshot_persist_us := []i64{}
	mut branch_head_us := []i64{}
	mut repo_meta_persist_us := []i64{}
	mut fts_us := []i64{}
	mut fts_docid_select_us := []i64{}
	mut fts_delete_us := []i64{}
	mut fts_text_us := []i64{}
	mut fts_insert_us := []i64{}
	mut fts_commit_us := []i64{}
	mut fallback_ms := []i64{}
	mut fallback_build_ms := []i64{}
	mut fallback_items_ms := []i64{}
	mut fallback_ops_ms := []i64{}
	mut fallback_ops_lookup_ms := []i64{}
	mut fallback_ops_encode_ms := []i64{}
	mut fallback_ops_state_ms := []i64{}
	mut fallback_ops_index_ms := []i64{}
	mut fallback_prepare_ms := []i64{}
	mut fallback_prepare_keys_ms := []i64{}
	mut fallback_prepare_rows_ms := []i64{}
	mut fallback_prepare_rows_key_ms := []i64{}
	mut fallback_prepare_rows_value_ms := []i64{}
	mut fallback_leaf_ms := []i64{}
	mut fallback_leaf_chunk_ms := []i64{}
	mut fallback_leaf_node_ms := []i64{}
	mut fallback_leaf_node_serialize_ms := []i64{}
	mut fallback_leaf_node_cid_ms := []i64{}
	mut fallback_leaf_node_add_ms := []i64{}
	mut fallback_internal_ms := []i64{}
	mut fallback_ops := []int{}
	mut batch_start := 0
	mut total_sw := time.new_stopwatch()
	for batch_start < ops {
		batch_end := min_int(batch_start + suite.cfg.batch_size, ops)
		mut write_set := storage.TypedWriteSet.new()
		for op_idx in batch_start .. batch_end {
			mut row := suite.codex_entry_row_for_target(mut state.db, target, op_idx)!
			row.set('title', 'updated ${op_idx}')
			if update_content {
				row.set('content_text', suite.codex_entry_content_text(op_idx, op_idx / 64,
					'updated mutation throughput fts query'))
				if target.materialize_markdown {
					raw := suite.codex_entry_markdown(op_idx, op_idx / 64,
						'updated markdown mutation throughput fts query')
					ref := if target.markdown_source_only {
						state.db.ingest_markdown_source_only(raw)!
					} else {
						state.db.ingest_markdown(raw)!
					}
					row.set('content_md', ref)
				}
			}
			write_set.put('entries', codex_entry_pk(op_idx), row)
		}
		mut sw := time.new_stopwatch()
		result := state.db.apply_typed_write_set_with_specs('main', target.schema.tables,
			write_set, bench_cfg, storage.CommitMeta{
			author:    'bench'
			message:   '${target.name} update ${batch_start}-${batch_end}'
			timestamp: state.inserted + batch_end
		})!
		write_set_us << sw.elapsed().microseconds()
		tx_apply_us << result.timings.tx_apply_us
		index_rebuild_us << result.timings.index_rebuild_us
		commit_us << result.timings.commit_us
		snapshot_persist_us << result.timings.snapshot_persist_us
		branch_head_us << result.timings.branch_head_us
		repo_meta_persist_us << result.timings.repo_meta_persist_us
		fts_us << result.timings.fts_us
		fts_docid_select_us << result.timings.fts_docid_select_us
		fts_delete_us << result.timings.fts_delete_us
		fts_text_us << result.timings.fts_text_us
		fts_insert_us << result.timings.fts_insert_us
		fts_commit_us << result.timings.fts_commit_us
		fallback_ms << result.transaction_update.timings.fallback_ms
		fallback_items_ms << result.transaction_update.timings.fallback_items_ms
		fallback_ops_ms << result.transaction_update.timings.fallback_ops_ms
		fallback_ops_lookup_ms << result.transaction_update.timings.fallback_ops_lookup_ms
		fallback_ops_encode_ms << result.transaction_update.timings.fallback_ops_encode_ms
		fallback_ops_state_ms << result.transaction_update.timings.fallback_ops_state_ms
		fallback_ops_index_ms << result.transaction_update.timings.fallback_ops_index_ms
		fallback_build_ms << result.transaction_update.timings.fallback_build_ms
		fallback_prepare_ms << result.transaction_update.timings.fallback_build_prepare_ms
		fallback_prepare_keys_ms << result.transaction_update.timings.fallback_build_prepare_keys_ms
		fallback_prepare_rows_ms << result.transaction_update.timings.fallback_build_prepare_rows_ms
		fallback_prepare_rows_key_ms << result.transaction_update.timings.fallback_build_prepare_rows_key_ms
		fallback_prepare_rows_value_ms << result.transaction_update.timings.fallback_build_prepare_rows_value_ms
		fallback_leaf_ms << result.transaction_update.timings.fallback_build_leaf_ms
		fallback_leaf_chunk_ms << result.transaction_update.timings.fallback_build_leaf_chunk_ms
		fallback_leaf_node_ms << result.transaction_update.timings.fallback_build_leaf_node_ms
		fallback_leaf_node_serialize_ms << result.transaction_update.timings.fallback_build_leaf_node_serialize_ms
		fallback_leaf_node_cid_ms << result.transaction_update.timings.fallback_build_leaf_node_cid_ms
		fallback_leaf_node_add_ms << result.transaction_update.timings.fallback_build_leaf_node_add_ms
		fallback_internal_ms << result.transaction_update.timings.fallback_build_internal_ms
		fallback_ops << result.transaction_update.timings.fallback_ops
		batch_start = batch_end
	}
	action := if update_content { 'update' } else { 'update_metadata' }
	return BenchResult{
		name:        codex_schema_scenario_name(target.name, action)
		duration_ms: total_sw.elapsed().milliseconds()
		ops:         ops
		note:        'indexes=${target.schema.table('entries')!.indexes.len} fts=${target.schema.table('entries')!.indexes.any(it.is_fts())} batch_size=${suite.cfg.batch_size} small_patch_limit=${suite.cfg.small_patch_limit} content_bytes=${suite.cfg.content_bytes} write_set_p50_us=${percentile_i64(write_set_us,
			50)} write_set_p95_us=${percentile_i64(write_set_us, 95)} tx_apply_p50_us=${percentile_i64(tx_apply_us,
			50)} tx_apply_p95_us=${percentile_i64(tx_apply_us, 95)} fallback_p50_ms=${percentile_i64(fallback_ms,
			50)} fallback_items_p50_ms=${percentile_i64(fallback_items_ms, 50)} fallback_ops_p50_ms=${percentile_i64(fallback_ops_ms,
			50)} fallback_ops_lookup_p50_ms=${percentile_i64(fallback_ops_lookup_ms, 50)} fallback_ops_encode_p50_ms=${percentile_i64(fallback_ops_encode_ms,
			50)} fallback_ops_state_p50_ms=${percentile_i64(fallback_ops_state_ms, 50)} fallback_ops_index_p50_ms=${percentile_i64(fallback_ops_index_ms,
			50)} fallback_build_p50_ms=${percentile_i64(fallback_build_ms, 50)} fallback_prepare_p50_ms=${percentile_i64(fallback_prepare_ms,
			50)} fallback_prepare_keys_p50_ms=${percentile_i64(fallback_prepare_keys_ms, 50)} fallback_prepare_rows_p50_ms=${percentile_i64(fallback_prepare_rows_ms,
			50)} fallback_prepare_rows_key_p50_ms=${percentile_i64(fallback_prepare_rows_key_ms, 50)} fallback_prepare_rows_value_p50_ms=${percentile_i64(fallback_prepare_rows_value_ms,
			50)} fallback_leaf_p50_ms=${percentile_i64(fallback_leaf_ms, 50)} fallback_leaf_chunk_p50_ms=${percentile_i64(fallback_leaf_chunk_ms,
			50)} fallback_leaf_node_p50_ms=${percentile_i64(fallback_leaf_node_ms, 50)} fallback_leaf_node_serialize_p50_ms=${percentile_i64(fallback_leaf_node_serialize_ms,
			50)} fallback_leaf_node_cid_p50_ms=${percentile_i64(fallback_leaf_node_cid_ms, 50)} fallback_leaf_node_add_p50_ms=${percentile_i64(fallback_leaf_node_add_ms,
			50)} fallback_internal_p50_ms=${percentile_i64(fallback_internal_ms, 50)} fallback_ops_p50=${percentile_int(fallback_ops,
			50)} index_p50_us=${percentile_i64(index_rebuild_us, 50)} index_p95_us=${percentile_i64(index_rebuild_us,
			95)} commit_p50_us=${percentile_i64(commit_us, 50)} snapshot_p50_us=${percentile_i64(snapshot_persist_us,
			50)} branch_head_p50_us=${percentile_i64(branch_head_us, 50)} repo_meta_p50_us=${percentile_i64(repo_meta_persist_us,
			50)} fts_p50_us=${percentile_i64(fts_us, 50)} fts_p95_us=${percentile_i64(fts_us, 95)} fts_docid_select_p50_us=${percentile_i64(fts_docid_select_us,
			50)} fts_delete_p50_us=${percentile_i64(fts_delete_us, 50)} fts_text_p50_us=${percentile_i64(fts_text_us,
			50)} fts_insert_p50_us=${percentile_i64(fts_insert_us, 50)} fts_commit_p50_us=${percentile_i64(fts_commit_us,
			50)}'
	}
}

fn (suite BenchSuite) run_codex_entries_delete_bench(target CodexEntrySchemaBenchSpec) !BenchResult {
	mut state := suite.build_codex_entries_schema_state(target)!
	bench_cfg := suite.schema_bench_chunk_cfg()
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	ops := min_int(suite.cfg.updates, state.inserted)
	mut write_set_us := []i64{}
	mut tx_apply_us := []i64{}
	mut index_rebuild_us := []i64{}
	mut commit_us := []i64{}
	mut snapshot_persist_us := []i64{}
	mut branch_head_us := []i64{}
	mut repo_meta_persist_us := []i64{}
	mut fts_us := []i64{}
	mut fts_docid_select_us := []i64{}
	mut fts_delete_us := []i64{}
	mut fts_text_us := []i64{}
	mut fts_insert_us := []i64{}
	mut fts_commit_us := []i64{}
	mut fallback_ms := []i64{}
	mut fallback_build_ms := []i64{}
	mut fallback_items_ms := []i64{}
	mut fallback_ops_ms := []i64{}
	mut fallback_ops_lookup_ms := []i64{}
	mut fallback_ops_encode_ms := []i64{}
	mut fallback_ops_state_ms := []i64{}
	mut fallback_ops_index_ms := []i64{}
	mut fallback_prepare_ms := []i64{}
	mut fallback_prepare_keys_ms := []i64{}
	mut fallback_prepare_rows_ms := []i64{}
	mut fallback_prepare_rows_key_ms := []i64{}
	mut fallback_prepare_rows_value_ms := []i64{}
	mut fallback_leaf_ms := []i64{}
	mut fallback_leaf_chunk_ms := []i64{}
	mut fallback_leaf_node_ms := []i64{}
	mut fallback_leaf_node_serialize_ms := []i64{}
	mut fallback_leaf_node_cid_ms := []i64{}
	mut fallback_leaf_node_add_ms := []i64{}
	mut fallback_internal_ms := []i64{}
	mut fallback_ops := []int{}
	mut batch_start := 0
	mut total_sw := time.new_stopwatch()
	for batch_start < ops {
		batch_end := min_int(batch_start + suite.cfg.batch_size, ops)
		mut write_set := storage.TypedWriteSet.new()
		for op_idx in batch_start .. batch_end {
			write_set.delete('entries', codex_entry_pk(op_idx))
		}
		mut sw := time.new_stopwatch()
		result := state.db.apply_typed_write_set_with_specs('main', target.schema.tables,
			write_set, bench_cfg, storage.CommitMeta{
			author:    'bench'
			message:   '${target.name} delete ${batch_start}-${batch_end}'
			timestamp: state.inserted + batch_end
		})!
		write_set_us << sw.elapsed().microseconds()
		tx_apply_us << result.timings.tx_apply_us
		index_rebuild_us << result.timings.index_rebuild_us
		commit_us << result.timings.commit_us
		snapshot_persist_us << result.timings.snapshot_persist_us
		branch_head_us << result.timings.branch_head_us
		repo_meta_persist_us << result.timings.repo_meta_persist_us
		fts_us << result.timings.fts_us
		fts_docid_select_us << result.timings.fts_docid_select_us
		fts_delete_us << result.timings.fts_delete_us
		fts_text_us << result.timings.fts_text_us
		fts_insert_us << result.timings.fts_insert_us
		fts_commit_us << result.timings.fts_commit_us
		fallback_ms << result.transaction_update.timings.fallback_ms
		fallback_items_ms << result.transaction_update.timings.fallback_items_ms
		fallback_ops_ms << result.transaction_update.timings.fallback_ops_ms
		fallback_ops_lookup_ms << result.transaction_update.timings.fallback_ops_lookup_ms
		fallback_ops_encode_ms << result.transaction_update.timings.fallback_ops_encode_ms
		fallback_ops_state_ms << result.transaction_update.timings.fallback_ops_state_ms
		fallback_ops_index_ms << result.transaction_update.timings.fallback_ops_index_ms
		fallback_build_ms << result.transaction_update.timings.fallback_build_ms
		fallback_prepare_ms << result.transaction_update.timings.fallback_build_prepare_ms
		fallback_prepare_keys_ms << result.transaction_update.timings.fallback_build_prepare_keys_ms
		fallback_prepare_rows_ms << result.transaction_update.timings.fallback_build_prepare_rows_ms
		fallback_prepare_rows_key_ms << result.transaction_update.timings.fallback_build_prepare_rows_key_ms
		fallback_prepare_rows_value_ms << result.transaction_update.timings.fallback_build_prepare_rows_value_ms
		fallback_leaf_ms << result.transaction_update.timings.fallback_build_leaf_ms
		fallback_leaf_chunk_ms << result.transaction_update.timings.fallback_build_leaf_chunk_ms
		fallback_leaf_node_ms << result.transaction_update.timings.fallback_build_leaf_node_ms
		fallback_leaf_node_serialize_ms << result.transaction_update.timings.fallback_build_leaf_node_serialize_ms
		fallback_leaf_node_cid_ms << result.transaction_update.timings.fallback_build_leaf_node_cid_ms
		fallback_leaf_node_add_ms << result.transaction_update.timings.fallback_build_leaf_node_add_ms
		fallback_internal_ms << result.transaction_update.timings.fallback_build_internal_ms
		fallback_ops << result.transaction_update.timings.fallback_ops
		batch_start = batch_end
	}
	return BenchResult{
		name:        codex_schema_scenario_name(target.name, 'delete')
		duration_ms: total_sw.elapsed().milliseconds()
		ops:         ops
		note:        'indexes=${target.schema.table('entries')!.indexes.len} fts=${target.schema.table('entries')!.indexes.any(it.is_fts())} batch_size=${suite.cfg.batch_size} small_patch_limit=${suite.cfg.small_patch_limit} content_bytes=${suite.cfg.content_bytes} write_set_p50_us=${percentile_i64(write_set_us,
			50)} write_set_p95_us=${percentile_i64(write_set_us, 95)} tx_apply_p50_us=${percentile_i64(tx_apply_us,
			50)} tx_apply_p95_us=${percentile_i64(tx_apply_us, 95)} fallback_p50_ms=${percentile_i64(fallback_ms,
			50)} fallback_items_p50_ms=${percentile_i64(fallback_items_ms, 50)} fallback_ops_p50_ms=${percentile_i64(fallback_ops_ms,
			50)} fallback_ops_lookup_p50_ms=${percentile_i64(fallback_ops_lookup_ms, 50)} fallback_ops_encode_p50_ms=${percentile_i64(fallback_ops_encode_ms,
			50)} fallback_ops_state_p50_ms=${percentile_i64(fallback_ops_state_ms, 50)} fallback_ops_index_p50_ms=${percentile_i64(fallback_ops_index_ms,
			50)} fallback_build_p50_ms=${percentile_i64(fallback_build_ms, 50)} fallback_prepare_p50_ms=${percentile_i64(fallback_prepare_ms,
			50)} fallback_prepare_keys_p50_ms=${percentile_i64(fallback_prepare_keys_ms, 50)} fallback_prepare_rows_p50_ms=${percentile_i64(fallback_prepare_rows_ms,
			50)} fallback_prepare_rows_key_p50_ms=${percentile_i64(fallback_prepare_rows_key_ms, 50)} fallback_prepare_rows_value_p50_ms=${percentile_i64(fallback_prepare_rows_value_ms,
			50)} fallback_leaf_p50_ms=${percentile_i64(fallback_leaf_ms, 50)} fallback_leaf_chunk_p50_ms=${percentile_i64(fallback_leaf_chunk_ms,
			50)} fallback_leaf_node_p50_ms=${percentile_i64(fallback_leaf_node_ms, 50)} fallback_leaf_node_serialize_p50_ms=${percentile_i64(fallback_leaf_node_serialize_ms,
			50)} fallback_leaf_node_cid_p50_ms=${percentile_i64(fallback_leaf_node_cid_ms, 50)} fallback_leaf_node_add_p50_ms=${percentile_i64(fallback_leaf_node_add_ms,
			50)} fallback_internal_p50_ms=${percentile_i64(fallback_internal_ms, 50)} fallback_ops_p50=${percentile_int(fallback_ops,
			50)} index_p50_us=${percentile_i64(index_rebuild_us, 50)} index_p95_us=${percentile_i64(index_rebuild_us,
			95)} commit_p50_us=${percentile_i64(commit_us, 50)} snapshot_p50_us=${percentile_i64(snapshot_persist_us,
			50)} branch_head_p50_us=${percentile_i64(branch_head_us, 50)} repo_meta_p50_us=${percentile_i64(repo_meta_persist_us,
			50)} fts_p50_us=${percentile_i64(fts_us, 50)} fts_p95_us=${percentile_i64(fts_us, 95)} fts_docid_select_p50_us=${percentile_i64(fts_docid_select_us,
			50)} fts_delete_p50_us=${percentile_i64(fts_delete_us, 50)} fts_text_p50_us=${percentile_i64(fts_text_us,
			50)} fts_insert_p50_us=${percentile_i64(fts_insert_us, 50)} fts_commit_p50_us=${percentile_i64(fts_commit_us,
			50)}'
	}
}

fn (suite BenchSuite) run_codex_entries_secondary_lookup_bench(target CodexEntrySchemaBenchSpec) !BenchResult {
	mut state := suite.build_codex_entries_schema_state(target)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	session := state.db.begin_session(storage.SessionOptions.for_branch('main'))!
	ops := max_int(1, suite.cfg.lookups)
	index_name := if target.schema.table('entries')!.indexes.any(it.name == 'entries_session_cover_idx') {
		'entries_session_cover_idx'
	} else {
		'entries_session_idx'
	}
	session_count := max_int(1, (state.inserted + 63) / 64)
	mut lookup_us := []i64{}
	mut total_rows := 0
	mut total_sw := time.new_stopwatch()
	for sample_idx in 0 .. ops {
		session_id := 'session-${sample_idx % session_count:06}'
		mut sw := time.new_stopwatch()
		rows := session.lookup_index_projected(mut state.db, 'entries', index_name, session_id, 64, [
			'id',
			'timestamp',
		])!
		lookup_us << sw.elapsed().microseconds()
		total_rows += rows.len
	}
	return BenchResult{
		name:        codex_schema_scenario_name(target.name, 'secondary_lookup')
		duration_ms: total_sw.elapsed().milliseconds()
		ops:         ops
		note:        'index=${index_name} avg_rows=${f64(total_rows) / f64(ops):.2f} lookup_p50_us=${percentile_i64(lookup_us,
			50)} lookup_p95_us=${percentile_i64(lookup_us, 95)}'
	}
}

fn (suite BenchSuite) run_codex_entries_fts_query_bench(target CodexEntrySchemaBenchSpec) !BenchResult {
	mut state := suite.build_codex_entries_schema_state(target)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	ops := max_int(1, suite.cfg.lookups)
	mut query_us := []i64{}
	mut total_hits := 0
	mut total_sw := time.new_stopwatch()
	for sample_idx in 0 .. ops {
		term := 'token ${(sample_idx % 97):02}'
		mut sw := time.new_stopwatch()
		hits := storage.fts_sidecar_query_hits(state.root_dir,
			'fts_entries_entries_content_text_fts_idx', 'main', term, 20) or {
			[]storage.FtsSidecarHit{}
		}
		query_us << sw.elapsed().microseconds()
		total_hits += hits.len
	}
	return BenchResult{
		name:        codex_schema_scenario_name(target.name, 'fts_query')
		duration_ms: total_sw.elapsed().milliseconds()
		ops:         ops
		note:        'avg_hits=${f64(total_hits) / f64(ops):.2f} query_p50_us=${percentile_i64(query_us,
			50)} query_p95_us=${percentile_i64(query_us, 95)}'
	}
}

fn (suite BenchSuite) run_codex_entries_grouped_write_bench(target CodexEntrySchemaBenchSpec) !BenchResult {
	root_dir := os.join_path(os.temp_dir(),
		'pollydb-bench-${target.name}-grouped-${os.getpid()}-${time.now().unix_micro()}')
	bench_cfg := suite.schema_bench_chunk_cfg()
	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	defer {
		db.close() or {}
		os.rmdir_all(root_dir) or {}
	}
	for table in target.schema.tables {
		db.register_table(table)!
	}
	group_every := max_int(1, suite.cfg.batch_size)
	mut seed := storage.TypedWriteSet.new()
	seed.put('entries', 'seed'.bytes(), suite.codex_entry_row_for_target(mut db, target, 0)!)
	_ = db.apply_typed_write_set_with_specs('main', target.schema.tables, seed, bench_cfg, storage.CommitMeta{
		author:    'bench'
		message:   '${target.name} grouped seed'
		timestamp: 0
	})!
	group := storage.GroupCommitOptions.high_throughput().with_checkpoint_every(group_every)
	mut session := db.begin_default_group_commit_session(group)!
	mut call_us := []i64{cap: suite.cfg.rows}
	mut non_flush_us := []i64{}
	mut flush_us := []i64{}
	mut tx_apply_us := []i64{}
	mut commit_us := []i64{}
	mut fts_us := []i64{}
	mut fts_docid_select_us := []i64{}
	mut fts_text_us := []i64{}
	mut fts_insert_us := []i64{}
	mut fts_insert_fts_us := []i64{}
	mut fts_insert_map_us := []i64{}
	mut fts_commit_us := []i64{}
	mut fts_ops_per_flush := []int{}
	mut fallback_ms := []i64{}
	mut fallback_ops_ms := []i64{}
	mut fallback_build_ms := []i64{}
	mut flushes := 0
	mut total_sw := time.new_stopwatch()
	for row_id in 0 .. suite.cfg.rows {
		mut sw := time.new_stopwatch()
		result := session.put_row(mut db, 'entries', codex_entry_pk(row_id), suite.codex_entry_row_for_target(mut db,
			target, row_id)!, bench_cfg, storage.CommitMeta{
			author:    'bench'
			message:   '${target.name} grouped row ${row_id}'
			timestamp: row_id + 1
		})!
		tx_apply_us << result.group_commit.transaction_ms * 1000
		fallback_ms << result.timings.fallback_ms
		fallback_ops_ms << result.timings.fallback_ops_ms
		fallback_build_ms << result.timings.fallback_build_ms
		elapsed := sw.elapsed().microseconds()
		call_us << elapsed
		if result.group_commit.flushed {
			flushes++
			flush_us << elapsed
			commit_us << result.group_commit.commit_ms * 1000
			fts_us << result.group_commit.fts_ms * 1000
			fts_docid_select_us << result.group_commit.fts_docid_select_us
			fts_text_us << result.group_commit.fts_text_us
			fts_insert_us << result.group_commit.fts_insert_us
			fts_insert_fts_us << result.group_commit.fts_insert_fts_us
			fts_insert_map_us << result.group_commit.fts_insert_map_us
			fts_commit_us << result.group_commit.fts_commit_us
			fts_ops_per_flush << result.group_commit.fts_ops
		} else {
			non_flush_us << elapsed
		}
	}
	if session.has_changes() {
		mut sw := time.new_stopwatch()
		session.flush(mut db)!
		elapsed := sw.elapsed().microseconds()
		flush_us << elapsed
		flushes++
	}
	session.wait_refreshes()!
	checkpoint_timings := db.checkpoint_timed()!
	total_ms := total_sw.elapsed().milliseconds()
	fts_table_name := codex_entries_first_fts_sidecar_table_name(target)
	fts_rows := if fts_table_name.len > 0 {
		storage.fts_sidecar_branch_row_count(root_dir, fts_table_name, 'main') or { 0 }
	} else {
		0
	}
	return BenchResult{
		name:        codex_schema_scenario_name(target.name, 'grouped_write')
		duration_ms: total_ms
		ops:         suite.cfg.rows
		note:        'group_every=${group_every} seed_rows=1 flushes=${flushes} fts=${target.schema.table('entries')!.indexes.any(it.is_fts())} call_p50_us=${percentile_i64(call_us,
			50)} call_p95_us=${percentile_i64(call_us, 95)} non_flush_p50_us=${percentile_i64(non_flush_us,
			50)} non_flush_p95_us=${percentile_i64(non_flush_us, 95)} flush_p50_us=${percentile_i64(flush_us,
			50)} flush_p95_us=${percentile_i64(flush_us, 95)} tx_apply_p50_us=${percentile_i64(tx_apply_us,
			50)} commit_p50_us=${percentile_i64(commit_us, 50)} fts_p50_us=${percentile_i64(fts_us,
			50)} fts_docid_select_p50_us=${percentile_i64(fts_docid_select_us, 50)} fts_text_p50_us=${percentile_i64(fts_text_us,
			50)} fts_insert_p50_us=${percentile_i64(fts_insert_us, 50)} fts_insert_fts_p50_us=${percentile_i64(fts_insert_fts_us,
			50)} fts_insert_map_p50_us=${percentile_i64(fts_insert_map_us, 50)} fts_commit_p50_us=${percentile_i64(fts_commit_us,
			50)} fts_ops_p50=${percentile_int(fts_ops_per_flush, 50)} fallback_p50_ms=${percentile_i64(fallback_ms,
			50)} fallback_ops_p50_ms=${percentile_i64(fallback_ops_ms, 50)} fallback_build_p50_ms=${percentile_i64(fallback_build_ms,
			50)} checkpoint_us=${checkpoint_timings.total_us} fts_rows=${fts_rows}'
	}
}

fn (suite BenchSuite) aggregate_metrics_spec() !storage.TypedTableSpec {
	table_def := storage.TableDef.new('metrics', [
		storage.ColumnDef.new('pk', .string_, false)!,
		storage.ColumnDef.sum_i64('total', false)!,
	], ['pk'])!
	return storage.TypedTableSpec.new(table_def, [])
}

fn (suite BenchSuite) projector_items_spec() !storage.TypedTableSpec {
	table_def := storage.TableDef.new('items', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('status', .string_, false)!,
		storage.ColumnDef.new('meta', .json_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table_def, [])
}

fn (suite BenchSuite) projector_item_row(id int) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('id', 'item-${id:08}')
	row.set('status', if id % 2 == 0 { 'active' } else { 'draft' })
	row.set('meta', '{"amount":${id},"kind":"k${id % 8}"}')
	return row
}

fn (suite BenchSuite) build_persistent_projector_state() !PersistentBenchState {
	spec := suite.projector_items_spec()!
	root_dir := os.join_path(os.temp_dir(),
		'pollydb-bench-projector-${os.getpid()}-${time.now().unix_micro()}')
	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	db.register_table(spec)!
	db.register_aggregate_projection(storage.AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).high_fast',
		'items', 'meta', 'amount')!.with_priority(500).with_cost_hint(.low))!
	db.register_aggregate_projection(storage.AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).high_slow',
		'items', 'meta', 'amount')!.with_priority(500).with_cost_hint(.high))!
	db.register_aggregate_projection(storage.AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).low_fast',
		'items', 'meta', 'amount')!.with_priority(100).with_cost_hint(.low))!
	db.register_aggregate_projection(storage.AggregateProjectionDef.sum_json_i64('sum(items.meta.amount).low_slow',
		'items', 'meta', 'amount')!.with_priority(100).with_cost_hint(.high))!
	codec := storage.TypedRowCodec.new(spec.table)
	mut items := []storage.KVPair{cap: suite.cfg.rows}
	for row_id in 0 .. suite.cfg.rows {
		row := suite.projector_item_row(row_id)
		pk := 'item-${row_id:08}'.bytes()
		items << storage.KVPair{
			key:   encode_table_row_key(spec.table.name, pk)
			value: codec.encode(row)!
		}
	}
	base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	_ = db.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'projector base load'
		timestamp: 1
	})!
	db.checkpoint()!
	return PersistentBenchState{
		root_dir: root_dir
		db:       db
	}
}

fn (suite BenchSuite) build_persistent_aggregate_range_state() !PersistentBenchState {
	spec := suite.aggregate_metrics_spec()!
	root_dir := os.join_path(os.temp_dir(),
		'pollydb-bench-range-db-${os.getpid()}-${time.now().unix_micro()}')
	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	db.register_table(spec)!
	codec := storage.TypedRowCodec.new(spec.table)
	mut items := []storage.KVPair{cap: suite.cfg.rows}
	for row_id in 0 .. suite.cfg.rows {
		pk := metric_row_key(row_id, suite.cfg.rows)
		mut row := storage.TypedRowData.new()
		row.set('pk', pk.bytestr())
		row.set('total', i64(row_id))
		items << storage.KVPair{
			key:   encode_table_row_key(spec.table.name, pk)
			value: codec.encode(row)!
		}
	}
	mut base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	base_tree = storage.rebuild_typed_aggregates_for_specs(base_tree, [spec], suite.chunk_cfg)!
	_ = db.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'persistent synthetic aggregate range load'
		timestamp: 1
	})!
	db.checkpoint()!
	return PersistentBenchState{
		root_dir: root_dir
		db:       db
	}
}

fn (suite BenchSuite) build_persistent_typed_state_with_covering(covering_index bool) !PersistentBenchState {
	spec := suite.users_spec()!
	root_dir := os.join_path(os.temp_dir(),
		'pollydb-bench-db-${os.getpid()}-${time.now().unix_micro()}')
	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	db.register_table(spec)!
	codec := storage.TypedRowCodec.new(spec.table)
	email_column := spec.table.column('email')!
	mut items := []storage.KVPair{cap: suite.cfg.rows * 2}
	for row_id in 0 .. suite.cfg.rows {
		row := suite.user_row(row_id)
		pk := row_key(row_id)
		items << storage.KVPair{
			key:   encode_table_row_key(spec.table.name, pk)
			value: codec.encode(row)!
		}
		email := row.get('email')!
		items << storage.KVPair{
			key:   encode_index_entry_key(spec.table.name, 'email', storage.TypedValueEncoder.encode_index_value(email,
				email_column)!, pk)
			value: if covering_index { codec.encode(row)! } else { []u8{} }
		}
	}
	mut base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	base_tree = storage.rebuild_typed_aggregates_for_specs(base_tree, [spec], suite.chunk_cfg)!
	_ = db.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'persistent synthetic bulk load'
		timestamp: 1
	})!
	db.checkpoint()!
	return PersistentBenchState{
		root_dir: root_dir
		db:       db
	}
}

fn (suite BenchSuite) build_persistent_snapshot_state_with_covering(covering_index bool) !SnapshotPersistentBenchState {
	spec := suite.users_spec()!
	root_dir := os.join_path(os.temp_dir(),
		'pollydb-bench-snapshot-${os.getpid()}-${time.now().unix_micro()}')
	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	db.register_table(spec)!
	codec := storage.TypedRowCodec.new(spec.table)
	email_column := spec.table.column('email')!
	mut items := []storage.KVPair{cap: suite.cfg.rows * 2}
	for row_id in 0 .. suite.cfg.rows {
		row := suite.user_row(row_id)
		pk := row_key(row_id)
		items << storage.KVPair{
			key:   encode_table_row_key(spec.table.name, pk)
			value: codec.encode(row)!
		}
		email := row.get('email')!
		items << storage.KVPair{
			key:   encode_index_entry_key(spec.table.name, 'email', storage.TypedValueEncoder.encode_index_value(email,
				email_column)!, pk)
			value: if covering_index { codec.encode(row)! } else { []u8{} }
		}
	}
	mut base_tree := storage.Tree.build(items, suite.chunk_cfg)!
	base_tree = storage.rebuild_typed_aggregates_for_specs(base_tree, [spec], suite.chunk_cfg)!
	_ = db.commit_to_branch('main', base_tree, storage.CommitMeta{
		author:    'bench'
		message:   'snapshot v1'
		timestamp: 1
	})!
	db.checkpoint()!
	v1 := db.branch('main')!
	session := db.begin_default_session()!
	target_idx := suite.cfg.rows / 2
	target_id := row_key(target_idx)
	mut updated := suite.user_row(target_idx)
	updated.set('email', 'snapshot-${target_idx}@example.com')
	updated.set('bio', suite.large_payload(768))
	_ = session.put_row(mut db, 'users', target_id, updated, suite.chunk_cfg, storage.CommitMeta{
		author:    'bench'
		message:   'snapshot v2 update'
		timestamp: 2
	})!
	db.checkpoint()!
	v2 := db.branch('main')!
	return SnapshotPersistentBenchState{
		root_dir:  root_dir
		db:        db
		v1_commit: v1.commit_cid
		v2_commit: v2.commit_cid
	}
}

fn (suite BenchSuite) run_point_lookup_bench(mut state BenchState) !BenchResult {
	tx := state.repo.typed_transaction_at_branch('main', [state.spec], mut state.node_store, mut
		state.commit_store)!
	view := tx.indexed_view('users')!
	mut sw := time.new_stopwatch()
	for idx in 0 .. suite.cfg.lookups {
		key := row_key((idx * 7919) % suite.cfg.rows)
		_ = view.get(key)!
	}
	return BenchResult{
		name:        'typed_point_lookup'
		duration_ms: sw.elapsed().milliseconds()
		ops:         suite.cfg.lookups
		bytes:       0
		note:        'branch=main'
	}
}

fn (suite BenchSuite) run_database_row_lookup_latency_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	session := state.db.begin_default_session()!
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		key := row_key((idx * 7919) % suite.cfg.rows)
		mut sw := time.new_stopwatch()
		_ = session.get_row(mut state.db, 'users', key)!
		lookup_us << sw.elapsed().microseconds()
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'db_row_lookup_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} branch=main'
	}
}

fn (suite BenchSuite) run_range_scan_bench(mut state BenchState) !BenchResult {
	tx := state.repo.typed_transaction_at_branch('main', [state.spec], mut state.node_store, mut
		state.commit_store)!
	view := tx.indexed_view('users')!
	start := row_key(suite.cfg.rows / 3)
	mut cursor := view.schema.table.cursor(start, suite.cfg.range_size)!
	mut sw := time.new_stopwatch()
	rows := cursor.collect(suite.cfg.range_size)!
	return BenchResult{
		name:        'typed_primary_key_scan'
		duration_ms: sw.elapsed().milliseconds()
		ops:         rows.len
		bytes:       0
		note:        'start=${start.bytestr()}'
	}
}

fn (suite BenchSuite) run_secondary_index_bench(mut state BenchState) !BenchResult {
	tx := state.repo.typed_transaction_at_branch('main', [state.spec], mut state.node_store, mut
		state.commit_store)!
	view := tx.indexed_view('users')!
	mut sw := time.new_stopwatch()
	for idx in 0 .. suite.cfg.lookups {
		email := row_email((idx * 3571) % suite.cfg.rows)
		rows := view.find_by_index('email', email, 1)!
		if rows.len != 1 {
			return error('secondary-index benchmark expected exactly one row')
		}
	}
	return BenchResult{
		name:        'typed_secondary_index_lookup'
		duration_ms: sw.elapsed().milliseconds()
		ops:         suite.cfg.lookups
		bytes:       0
		note:        'index=email'
	}
}

fn (suite BenchSuite) run_database_index_lookup_latency_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	session := state.db.begin_default_session()!
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		email := row_email((idx * 3571) % suite.cfg.rows)
		mut sw := time.new_stopwatch()
		rows := session.lookup_index(mut state.db, 'users', 'email', email, 1)!
		lookup_us << sw.elapsed().microseconds()
		if rows.len != 1 {
			return error('database index benchmark expected exactly one row')
		}
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'db_index_lookup_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} branch=main index=email'
	}
}

fn (suite BenchSuite) run_database_covering_index_lookup_latency_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state_with_covering(true)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	session := state.db.begin_default_session()!
	mut reader := session.index_reader(mut state.db, 'users', 'email')!
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		email := row_email((idx * 3571) % suite.cfg.rows)
		mut sw := time.new_stopwatch()
		rows := reader.find_rows_covering(email, 1)!
		lookup_us << sw.elapsed().microseconds()
		if rows.len != 1 {
			return error('database covering-index benchmark expected exactly one row')
		}
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'db_covering_index_lookup_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} branch=main index=email'
	}
}

fn (suite BenchSuite) run_database_index_prefix_lookup_latency_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state_with_covering(true)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	session := state.db.begin_default_session()!
	mut reader := session.index_reader(mut state.db, 'users', 'email')!
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		email := row_email((idx * 3571) % suite.cfg.rows)
		prefix := email[..if email.len < 11 { email.len } else { 11 }]
		mut sw := time.new_stopwatch()
		rows := reader.find_rows_covering_prefix(prefix, 10)!
		lookup_us << sw.elapsed().microseconds()
		if rows.len == 0 {
			return error('database index prefix benchmark expected at least one row')
		}
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'db_index_prefix_lookup_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} branch=main index=email limit=10'
	}
}

fn (suite BenchSuite) run_database_table_count_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	session := state.db.begin_default_session()!
	mut sw := time.new_stopwatch()
	counted := session.count_rows(mut state.db, 'users')!
	duration_ms := sw.elapsed().milliseconds()
	if counted != suite.cfg.rows {
		return error('count benchmark mismatch: expected ${suite.cfg.rows}, got ${counted}')
	}
	rows_per_sec := if duration_ms > 0 {
		f64(counted) / (f64(duration_ms) / 1000.0)
	} else {
		f64(counted)
	}
	return BenchResult{
		name:        'db_table_count_aggregate'
		duration_ms: duration_ms
		ops:         counted
		bytes:       0
		note:        'count=${counted} rows_per_sec=${rows_per_sec:.2f} aggregate=subtree_count'
	}
}

fn (suite BenchSuite) run_database_table_count_range_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	session := state.db.begin_default_session()!
	start := suite.cfg.rows / 4
	end := (suite.cfg.rows * 3) / 4
	mut sw := time.new_stopwatch()
	counted := session.count_rows_range(mut state.db, 'users', row_key(start), row_key(end))!
	duration_ms := sw.elapsed().milliseconds()
	expected_count := end - start
	if counted != expected_count {
		return error('count range benchmark mismatch: expected ${expected_count}, got ${counted}')
	}
	rows_per_sec := if duration_ms > 0 {
		f64(counted) / (f64(duration_ms) / 1000.0)
	} else {
		f64(counted)
	}
	return BenchResult{
		name:        'db_table_count_range_aggregate'
		duration_ms: duration_ms
		ops:         counted
		bytes:       0
		note:        'start=${start} end=${end} count=${counted} rows_per_sec=${rows_per_sec:.2f} aggregate=subtree_count_range'
	}
}

fn (suite BenchSuite) run_database_table_sum_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	session := state.db.begin_default_session()!
	mut sw := time.new_stopwatch()
	sum_ids := session.sum_i64_column(mut state.db, 'users', 'id')!
	duration_ms := sw.elapsed().milliseconds()
	counted := suite.cfg.rows
	expected_sum := i64(suite.cfg.rows) * i64(suite.cfg.rows - 1) / 2
	if counted != suite.cfg.rows {
		return error('sum benchmark row mismatch: expected ${suite.cfg.rows}, got ${counted}')
	}
	if sum_ids != expected_sum {
		return error('sum benchmark mismatch: expected ${expected_sum}, got ${sum_ids}')
	}
	rows_per_sec := if duration_ms > 0 {
		f64(counted) / (f64(duration_ms) / 1000.0)
	} else {
		f64(counted)
	}
	return BenchResult{
		name:        'db_table_sum_aggregate'
		duration_ms: duration_ms
		ops:         counted
		bytes:       0
		note:        'sum_id=${sum_ids} rows_per_sec=${rows_per_sec:.2f} aggregate=declared_sum'
	}
}

fn (suite BenchSuite) run_database_table_sum_range_bench() !BenchResult {
	mut state := suite.build_persistent_aggregate_range_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	session := state.db.begin_default_session()!
	start := suite.cfg.rows / 4
	end := (suite.cfg.rows * 3) / 4
	start_pk := metric_row_key(start, suite.cfg.rows)
	end_pk := metric_row_key(end, suite.cfg.rows)
	mut sw := time.new_stopwatch()
	sum_ids := session.sum_i64_column_range(mut state.db, 'metrics', 'total', start_pk, end_pk)!
	duration_ms := sw.elapsed().milliseconds()
	range_count := end - start
	expected_sum := (i64(end - 1) * i64(end) / 2) - (i64(start - 1) * i64(start) / 2)
	if sum_ids != expected_sum {
		return error('sum range benchmark mismatch: expected ${expected_sum}, got ${sum_ids}')
	}
	rows_per_sec := if duration_ms > 0 {
		f64(range_count) / (f64(duration_ms) / 1000.0)
	} else {
		f64(range_count)
	}
	return BenchResult{
		name:        'db_table_sum_range_aggregate'
		duration_ms: duration_ms
		ops:         range_count
		bytes:       0
		note:        'start=${start} end=${end} start_pk=${start_pk.bytestr()} end_pk=${end_pk.bytestr()} sum_total=${sum_ids} rows_per_sec=${rows_per_sec:.2f} aggregate=declared_sum_bucketed'
	}
}

fn aggregate_range_worker(spec AggregateWorkerSpec) AggregateWorkerResult {
	mut node_store := storage.PersistentNodeStore.open_high_throughput(spec.nodes_path) or {
		return AggregateWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	defer {
		node_store.close()
	}
	if spec.sum_column.len == 0 {
		count := storage.Tree.count_range_in_byte_store(spec.root_cid, spec.start_key,
			spec.end_key, mut node_store) or {
			return AggregateWorkerResult{
				ok:  false
				err: err.msg()
			}
		}
		return AggregateWorkerResult{
			ok:    true
			count: count
		}
	}
	sum := storage.Tree.sum_i64_column_range_in_byte_store(spec.root_cid, spec.start_key,
		spec.end_key, spec.table_codec, spec.sum_column, mut node_store) or {
		return AggregateWorkerResult{
			ok:  false
			err: err.msg()
		}
	}
	return AggregateWorkerResult{
		ok:  true
		sum: sum
	}
}

fn (suite BenchSuite) aggregate_partitions() []AggregatePartition {
	workers := min_int(max_int(1, suite.cfg.chunk_workers), suite.cfg.rows)
	mut partitions := []AggregatePartition{cap: workers}
	base := suite.cfg.rows / workers
	rem := suite.cfg.rows % workers
	mut start := 0
	for idx in 0 .. workers {
		width := base + if idx < rem { 1 } else { 0 }
		end := start + width
		partitions << AggregatePartition{
			start: row_key(start)
			end:   if end >= suite.cfg.rows { []u8{} } else { row_key(end) }
		}
		start = end
	}
	return partitions
}

fn (suite BenchSuite) aggregate_leaf_partitions(root_cid string, table_name string, nodes_path string) ![]AggregatePartition {
	workers := min_int(max_int(1, suite.cfg.chunk_workers), suite.cfg.rows)
	start_key := storage.encode_table_row_key(table_name, []u8{})
	end_key := storage.encode_table_range_end(table_name)!
	mut node_store := storage.PersistentNodeStore.open_high_throughput(nodes_path)!
	defer {
		node_store.close()
	}
	leaf_starts := storage.Tree.next_leaf_start_keys_in_byte_store(root_cid, start_key, end_key, mut
		node_store)!
	if leaf_starts.len == 0 || workers <= 1 {
		return [
			AggregatePartition{
				start: start_key
				end:   end_key
			},
		]
	}
	actual_workers := min_int(workers, leaf_starts.len + 1)
	mut boundaries := [][]u8{cap: actual_workers + 1}
	boundaries << start_key
	for idx in 1 .. actual_workers {
		boundary_idx := (leaf_starts.len * idx) / actual_workers
		boundaries << leaf_starts[boundary_idx].clone()
	}
	boundaries << end_key
	mut partitions := []AggregatePartition{cap: actual_workers}
	for idx in 0 .. actual_workers {
		partitions << AggregatePartition{
			start: boundaries[idx].clone()
			end:   boundaries[idx + 1].clone()
		}
	}
	return partitions
}

fn (suite BenchSuite) run_database_table_count_parallel_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	workers := min_int(max_int(1, suite.cfg.chunk_workers), suite.cfg.rows)
	if workers <= 1 {
		return BenchResult{
			name:        'db_table_count_parallel_aggregate'
			duration_ms: 0
			ops:         suite.cfg.rows
			bytes:       0
			note:        'workers=1 skipped=true'
		}
	}
	reader := state.db.snapshot_table_reader_for_branch('main', 'users')!
	table_codec := storage.TypedRowCodec.new(reader.spec.table)
	nodes_path := os.join_path(state.root_dir, '.pollydb', 'nodes.chunk')
	partitions := suite.aggregate_leaf_partitions(reader.root_cid, 'users', nodes_path)!
	mut handles := []AggregateWorkerHandle{cap: partitions.len}
	mut sw := time.new_stopwatch()
	for partition in partitions {
		handles << AggregateWorkerHandle{
			worker: spawn aggregate_range_worker(AggregateWorkerSpec{
				root_cid:    reader.root_cid
				nodes_path:  nodes_path
				start_key:   partition.start.clone()
				end_key:     partition.end.clone()
				sum_column:  ''
				table_codec: table_codec
			})
		}
	}
	mut counted := 0
	for mut handle in handles {
		result := handle.wait()!
		counted += result.count
	}
	duration_ms := sw.elapsed().milliseconds()
	if counted != suite.cfg.rows {
		return error('parallel count benchmark mismatch: expected ${suite.cfg.rows}, got ${counted}')
	}
	rows_per_sec := if duration_ms > 0 {
		f64(counted) / (f64(duration_ms) / 1000.0)
	} else {
		f64(counted)
	}
	return BenchResult{
		name:        'db_table_count_parallel_aggregate'
		duration_ms: duration_ms
		ops:         counted
		bytes:       0
		note:        'count=${counted} rows_per_sec=${rows_per_sec:.2f} workers=${workers} partitions=${partitions.len} split=leaf'
	}
}

fn (suite BenchSuite) run_database_table_sum_parallel_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	workers := min_int(max_int(1, suite.cfg.chunk_workers), suite.cfg.rows)
	if workers <= 1 {
		return BenchResult{
			name:        'db_table_sum_parallel_aggregate'
			duration_ms: 0
			ops:         suite.cfg.rows
			bytes:       0
			note:        'workers=1 skipped=true'
		}
	}
	reader := state.db.snapshot_table_reader_for_branch('main', 'users')!
	table_codec := storage.TypedRowCodec.new(reader.spec.table)
	nodes_path := os.join_path(state.root_dir, '.pollydb', 'nodes.chunk')
	partitions := suite.aggregate_leaf_partitions(reader.root_cid, 'users', nodes_path)!
	mut handles := []AggregateWorkerHandle{cap: partitions.len}
	mut sw := time.new_stopwatch()
	for partition in partitions {
		handles << AggregateWorkerHandle{
			worker: spawn aggregate_range_worker(AggregateWorkerSpec{
				root_cid:    reader.root_cid
				nodes_path:  nodes_path
				start_key:   partition.start.clone()
				end_key:     partition.end.clone()
				sum_column:  'id'
				table_codec: table_codec
			})
		}
	}
	mut counted := 0
	mut sum_ids := i64(0)
	for mut handle in handles {
		result := handle.wait()!
		sum_ids += result.sum
	}
	duration_ms := sw.elapsed().milliseconds()
	expected_sum := i64(suite.cfg.rows) * i64(suite.cfg.rows - 1) / 2
	counted = suite.cfg.rows
	if counted != suite.cfg.rows {
		return error('parallel sum benchmark row mismatch: expected ${suite.cfg.rows}, got ${counted}')
	}
	if sum_ids != expected_sum {
		return error('parallel sum benchmark mismatch: expected ${expected_sum}, got ${sum_ids}')
	}
	rows_per_sec := if duration_ms > 0 {
		f64(counted) / (f64(duration_ms) / 1000.0)
	} else {
		f64(counted)
	}
	return BenchResult{
		name:        'db_table_sum_parallel_aggregate'
		duration_ms: duration_ms
		ops:         counted
		bytes:       0
		note:        'sum_id=${sum_ids} rows_per_sec=${rows_per_sec:.2f} workers=${workers} partitions=${partitions.len} projected=id split=leaf'
	}
}

fn (suite BenchSuite) run_snapshot_table_scan_latency_bench() !BenchResult {
	mut state := suite.build_persistent_snapshot_state_with_covering(false)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	mut reader := state.db.snapshot_table_pair_reader_for_commits(state.v1_commit, state.v2_commit,
		'users')!
	limit := min_int(max_int(1, suite.cfg.range_size), 32)
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		start := row_key((idx * 3571) % suite.cfg.rows)
		mut sw := time.new_stopwatch()
		result := reader.scan_rows_from(start, limit)!
		lookup_us << sw.elapsed().microseconds()
		if result.left.rows.len == 0 || result.right.rows.len == 0 {
			return error('snapshot table scan benchmark expected non-empty rows')
		}
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'snapshot_table_scan_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} commits=2 limit=${limit}'
	}
}

fn (suite BenchSuite) run_snapshot_index_lookup_latency_bench() !BenchResult {
	mut state := suite.build_persistent_snapshot_state_with_covering(true)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	mut reader := state.db.snapshot_index_pair_reader_for_commits(state.v1_commit, state.v2_commit,
		'users', 'email')!
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		email := row_email((idx * 3571) % suite.cfg.rows)
		mut sw := time.new_stopwatch()
		result := reader.find_rows_covering(email, 1)!
		lookup_us << sw.elapsed().microseconds()
		if result.left.rows.len != 1 || result.right.rows.len != 1 {
			return error('snapshot index lookup benchmark expected exactly one row per commit')
		}
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'snapshot_index_lookup_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} commits=2 index=email limit=1 covering=true'
	}
}

fn (suite BenchSuite) run_snapshot_index_prefix_lookup_latency_bench() !BenchResult {
	mut state := suite.build_persistent_snapshot_state_with_covering(true)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	mut reader := state.db.snapshot_index_pair_reader_for_commits(state.v1_commit, state.v2_commit,
		'users', 'email')!
	limit := min_int(max_int(1, suite.cfg.range_size), 16)
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		email := row_email((idx * 3571) % suite.cfg.rows)
		prefix := email[..if email.len < 11 { email.len } else { 11 }]
		start_pk := row_key((idx * 3571) % suite.cfg.rows)
		mut sw := time.new_stopwatch()
		result := reader.find_rows_covering_prefix_from(prefix, start_pk, limit)!
		lookup_us << sw.elapsed().microseconds()
		if result.left.rows.len == 0 && result.right.rows.len == 0 {
			return error('snapshot index prefix benchmark expected at least one match')
		}
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'snapshot_index_prefix_lookup_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} commits=2 index=email limit=${limit}'
	}
}

fn (suite BenchSuite) run_snapshot_index_prefix_primary_keys_latency_bench() !BenchResult {
	mut state := suite.build_persistent_snapshot_state_with_covering(true)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	mut reader := state.db.snapshot_index_pair_reader_for_commits(state.v1_commit, state.v2_commit,
		'users', 'email')!
	limit := min_int(max_int(1, suite.cfg.range_size), 16)
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		email := row_email((idx * 3571) % suite.cfg.rows)
		prefix := email[..if email.len < 11 { email.len } else { 11 }]
		start_pk := row_key((idx * 3571) % suite.cfg.rows)
		mut sw := time.new_stopwatch()
		left_keys, right_keys := reader.prefix_primary_keys_from(prefix, start_pk, limit)!
		lookup_us << sw.elapsed().microseconds()
		if left_keys.len == 0 && right_keys.len == 0 {
			return error('snapshot index prefix primary-key benchmark expected at least one match')
		}
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'snapshot_index_prefix_primary_keys_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} commits=2 index=email limit=${limit}'
	}
}

fn (suite BenchSuite) run_snapshot_index_prefix_count_latency_bench() !BenchResult {
	mut state := suite.build_persistent_snapshot_state_with_covering(true)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	mut reader := state.db.snapshot_index_pair_reader_for_commits(state.v1_commit, state.v2_commit,
		'users', 'email')!
	limit := min_int(max_int(1, suite.cfg.range_size), 16)
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		email := row_email((idx * 3571) % suite.cfg.rows)
		prefix := email[..if email.len < 11 { email.len } else { 11 }]
		start_pk := row_key((idx * 3571) % suite.cfg.rows)
		mut sw := time.new_stopwatch()
		left_count, right_count := reader.prefix_counts_from(prefix, start_pk, limit)!
		lookup_us << sw.elapsed().microseconds()
		if left_count == 0 && right_count == 0 {
			return error('snapshot index prefix count benchmark expected at least one match')
		}
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'snapshot_index_prefix_count_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} commits=2 index=email limit=${limit}'
	}
}

fn (suite BenchSuite) run_snapshot_index_prefix_projected_latency_bench() !BenchResult {
	mut state := suite.build_persistent_snapshot_state_with_covering(true)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	mut reader := state.db.snapshot_index_pair_reader_for_commits(state.v1_commit, state.v2_commit,
		'users', 'email')!
	limit := min_int(max_int(1, suite.cfg.range_size), 16)
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		email := row_email((idx * 3571) % suite.cfg.rows)
		prefix := email[..if email.len < 11 { email.len } else { 11 }]
		start_pk := row_key((idx * 3571) % suite.cfg.rows)
		mut sw := time.new_stopwatch()
		result := reader.find_rows_covering_prefix_projected_from(prefix, start_pk, limit, [
			'email',
		])!
		lookup_us << sw.elapsed().microseconds()
		if result.left.rows.len == 0 && result.right.rows.len == 0 {
			return error('snapshot index prefix projected benchmark expected at least one match')
		}
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'snapshot_index_prefix_projected_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} commits=2 index=email limit=${limit} columns=email'
	}
}

fn (suite BenchSuite) run_snapshot_index_prefix_non_covering_latency_bench() !BenchResult {
	mut state := suite.build_persistent_snapshot_state_with_covering(false)!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	mut reader := state.db.snapshot_index_pair_reader_for_commits(state.v1_commit, state.v2_commit,
		'users', 'email')!
	limit := min_int(max_int(1, suite.cfg.range_size), 16)
	mut lookup_us := []i64{cap: suite.cfg.lookups}
	for idx in 0 .. suite.cfg.lookups {
		email := row_email((idx * 3571) % suite.cfg.rows)
		prefix := email[..if email.len < 11 { email.len } else { 11 }]
		start_pk := row_key((idx * 3571) % suite.cfg.rows)
		mut sw := time.new_stopwatch()
		result := reader.find_rows_prefix_from(prefix, start_pk, limit)!
		lookup_us << sw.elapsed().microseconds()
		if result.left.rows.len == 0 && result.right.rows.len == 0 {
			return error('snapshot non-covering index prefix benchmark expected at least one match')
		}
	}
	total_us := sum_i64_slice(lookup_us)
	avg_us := f64(total_us) / f64(lookup_us.len)
	return BenchResult{
		name:        'snapshot_index_prefix_non_covering_latency'
		duration_ms: total_us / 1000
		ops:         lookup_us.len
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(lookup_us, 50)} p95_us=${percentile_i64(lookup_us,
			95)} max_us=${max_i64(lookup_us)} commits=2 index=email limit=${limit} covering=false'
	}
}

fn (suite BenchSuite) run_prolly_write_path_latency_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	samples := max_int(1, suite.cfg.lookups)
	mut write_us := []i64{cap: samples}
	mut commit_us := []i64{cap: samples}
	mut checkpoint_us := []i64{cap: samples}
	mut checkpoint_catalog_us := []i64{cap: samples}
	mut checkpoint_repo_meta_us := []i64{cap: samples}
	mut checkpoint_node_store_data_us := []i64{cap: samples}
	mut checkpoint_node_store_index_us := []i64{cap: samples}
	mut checkpoint_node_store_us := []i64{cap: samples}
	mut checkpoint_commit_store_data_us := []i64{cap: samples}
	mut checkpoint_commit_store_index_us := []i64{cap: samples}
	mut checkpoint_commit_store_us := []i64{cap: samples}
	mut tx_apply_us := []i64{cap: samples}
	mut snapshot_persist_us := []i64{cap: samples}
	mut branch_head_us := []i64{cap: samples}
	mut repo_meta_persist_us := []i64{cap: samples}
	mut path_depths := []int{cap: samples}
	mut added_nodes := []int{cap: samples}
	mut added_bytes := []int{cap: samples}
	mut matching_rewrites := 0
	for sample_idx in 0 .. samples {
		base_tree := state.db.tree_at_branch('main')!
		row_id := (sample_idx * 1613) % suite.cfg.rows
		primary_key := row_key(row_id)
		tree_key := encode_table_row_key('users', primary_key)
		stats := base_tree.key_stats(tree_key)!
		mut row := suite.user_row(row_id)
		mut bio := row_bio(row_id)
		if bio.len > 0 {
			pos := (sample_idx * 17 + bio.len / 2) % bio.len
			bio[pos] = bio[pos] ^ u8(0x01)
		}
		row.set('bio', bio)
		mut write_set := storage.TypedWriteSet.new()
		write_set.put('users', primary_key, row)
		mut sw := time.new_stopwatch()
		mut stage_sw := time.new_stopwatch()
		result := state.db.apply_typed_write_set('main', write_set, suite.chunk_cfg, storage.CommitMeta{
			author:    'bench'
			message:   'durable write path ${sample_idx}'
			timestamp: sample_idx + 2
		})!
		commit_elapsed := stage_sw.elapsed().microseconds()
		stage_sw.restart()
		checkpoint_timings := state.db.checkpoint_timed()!
		checkpoint_elapsed := checkpoint_timings.total_us
		elapsed := sw.elapsed().microseconds()
		diff := result.transaction_update.diff
		write_us << elapsed
		commit_us << commit_elapsed
		checkpoint_us << checkpoint_elapsed
		checkpoint_catalog_us << checkpoint_timings.catalog_us
		checkpoint_repo_meta_us << checkpoint_timings.engine.repository.repo_meta_us
		checkpoint_node_store_data_us << checkpoint_timings.engine.repository.node_store_data_us
		checkpoint_node_store_index_us << checkpoint_timings.engine.repository.node_store_index_us
		checkpoint_node_store_us << checkpoint_timings.engine.repository.node_store_us
		checkpoint_commit_store_data_us << checkpoint_timings.engine.repository.commit_store_data_us
		checkpoint_commit_store_index_us << checkpoint_timings.engine.repository.commit_store_index_us
		checkpoint_commit_store_us << checkpoint_timings.engine.repository.commit_store_us
		tx_apply_us << result.timings.tx_apply_us
		snapshot_persist_us << result.timings.snapshot_persist_us
		branch_head_us << result.timings.branch_head_us
		repo_meta_persist_us << result.timings.repo_meta_persist_us
		path_depths << stats.path_depth
		added_nodes << diff.added_cids.len
		added_bytes << result.update.snapshot.tree.bytes_for_cids(diff.added_cids)
		if diff.added_cids.len == stats.path_depth {
			matching_rewrites++
		}
	}
	total_us := sum_i64_slice(write_us)
	avg_us := f64(total_us) / f64(samples)
	return BenchResult{
		name:        'prolly_write_path_latency'
		duration_ms: total_us / 1000
		ops:         samples
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(write_us, 50)} p95_us=${percentile_i64(write_us,
			95)} max_us=${max_i64(write_us)} commit_p50_us=${percentile_i64(commit_us, 50)} commit_p95_us=${percentile_i64(commit_us,
			95)} checkpoint_p50_us=${percentile_i64(checkpoint_us, 50)} checkpoint_p95_us=${percentile_i64(checkpoint_us,
			95)} checkpoint_catalog_p95_us=${percentile_i64(checkpoint_catalog_us, 95)} checkpoint_repo_meta_p95_us=${percentile_i64(checkpoint_repo_meta_us,
			95)} checkpoint_node_store_data_p95_us=${percentile_i64(checkpoint_node_store_data_us,
			95)} checkpoint_node_store_index_p95_us=${percentile_i64(checkpoint_node_store_index_us,
			95)} checkpoint_node_store_p95_us=${percentile_i64(checkpoint_node_store_us, 95)} checkpoint_commit_store_data_p95_us=${percentile_i64(checkpoint_commit_store_data_us,
			95)} checkpoint_commit_store_index_p95_us=${percentile_i64(checkpoint_commit_store_index_us,
			95)} checkpoint_commit_store_p95_us=${percentile_i64(checkpoint_commit_store_us, 95)} tx_apply_p50_us=${percentile_i64(tx_apply_us,
			50)} tx_apply_p95_us=${percentile_i64(tx_apply_us, 95)} snapshot_persist_p50_us=${percentile_i64(snapshot_persist_us,
			50)} snapshot_persist_p95_us=${percentile_i64(snapshot_persist_us, 95)} branch_head_p50_us=${percentile_i64(branch_head_us,
			50)} branch_head_p95_us=${percentile_i64(branch_head_us, 95)} repo_meta_persist_p50_us=${percentile_i64(repo_meta_persist_us,
			50)} repo_meta_persist_p95_us=${percentile_i64(repo_meta_persist_us, 95)} durable=checkpoint path_depth_p50=${percentile_int(path_depths,
			50)} path_depth_p95=${percentile_int(path_depths, 95)} added_nodes_p50=${percentile_int(added_nodes,
			50)} added_nodes_p95=${percentile_int(added_nodes, 95)} added_bytes_p50=${percentile_int(added_bytes,
			50)} added_bytes_p95=${percentile_int(added_bytes, 95)} path_depth_eq_added_nodes=${matching_rewrites}/${samples} field=bio'
	}
}

fn (suite BenchSuite) run_prolly_write_path_data_only_latency_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	samples := max_int(1, suite.cfg.lookups)
	mut write_us := []i64{cap: samples}
	mut checkpoint_us := []i64{cap: samples}
	mut path_depths := []int{cap: samples}
	mut added_nodes := []int{cap: samples}
	mut added_bytes := []int{cap: samples}
	mut matching_rewrites := 0
	for sample_idx in 0 .. samples {
		base_tree := state.db.tree_at_branch('main')!
		row_id := (sample_idx * 1613) % suite.cfg.rows
		primary_key := row_key(row_id)
		tree_key := encode_table_row_key('users', primary_key)
		stats := base_tree.key_stats(tree_key)!
		mut row := suite.user_row(row_id)
		mut bio := row_bio(row_id)
		if bio.len > 0 {
			pos := (sample_idx * 17 + bio.len / 2) % bio.len
			bio[pos] = bio[pos] ^ u8(0x01)
		}
		row.set('bio', bio)
		mut write_set := storage.TypedWriteSet.new()
		write_set.put('users', primary_key, row)
		mut sw := time.new_stopwatch()
		result := state.db.apply_typed_write_set('main', write_set, suite.chunk_cfg, storage.CommitMeta{
			author:    'bench'
			message:   'data-only write path ${sample_idx}'
			timestamp: sample_idx + 2
		})!
		checkpoint_timings := state.db.checkpoint_timed_mode(.data_only)!
		elapsed := sw.elapsed().microseconds()
		diff := result.transaction_update.diff
		write_us << elapsed
		checkpoint_us << checkpoint_timings.total_us
		path_depths << stats.path_depth
		added_nodes << diff.added_cids.len
		added_bytes << result.update.snapshot.tree.bytes_for_cids(diff.added_cids)
		if diff.added_cids.len == stats.path_depth {
			matching_rewrites++
		}
	}
	total_us := sum_i64_slice(write_us)
	avg_us := f64(total_us) / f64(samples)
	return BenchResult{
		name:        'prolly_write_path_data_only_latency'
		duration_ms: total_us / 1000
		ops:         samples
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(write_us, 50)} p95_us=${percentile_i64(write_us,
			95)} max_us=${max_i64(write_us)} checkpoint_p50_us=${percentile_i64(checkpoint_us, 50)} checkpoint_p95_us=${percentile_i64(checkpoint_us,
			95)} durable=data_only path_depth_p50=${percentile_int(path_depths, 50)} path_depth_p95=${percentile_int(path_depths,
			95)} added_nodes_p50=${percentile_int(added_nodes, 50)} added_nodes_p95=${percentile_int(added_nodes,
			95)} added_bytes_p50=${percentile_int(added_bytes, 50)} added_bytes_p95=${percentile_int(added_bytes,
			95)} path_depth_eq_added_nodes=${matching_rewrites}/${samples} field=bio'
	}
}

fn (suite BenchSuite) run_prolly_write_path_group_commit_latency_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	samples := max_int(1, suite.cfg.lookups)
	group_every := 8
	mut session := state.db.begin_default_group_commit_session(storage.GroupCommitOptions{
		checkpoint_every: group_every
	})!
	mut write_us := []i64{cap: samples}
	mut non_checkpoint_us := []i64{cap: samples}
	mut checkpoint_hit_us := []i64{cap: samples}
	mut path_depths := []int{cap: samples}
	mut added_nodes := []int{cap: samples}
	mut added_bytes := []int{cap: samples}
	mut matching_rewrites := 0
	mut checkpoint_hits := 0
	for sample_idx in 0 .. samples {
		base_tree := state.db.tree_at_branch('main')!
		row_id := (sample_idx * 1613) % suite.cfg.rows
		primary_key := row_key(row_id)
		tree_key := encode_table_row_key('users', primary_key)
		stats := base_tree.key_stats(tree_key)!
		mut row := suite.user_row(row_id)
		mut bio := row_bio(row_id)
		if bio.len > 0 {
			pos := (sample_idx * 17 + bio.len / 2) % bio.len
			bio[pos] = bio[pos] ^ u8(0x01)
		}
		row.set('bio', bio)
		mut sw := time.new_stopwatch()
		result := session.put_row(mut state.db, 'users', primary_key, row, suite.chunk_cfg, storage.CommitMeta{
			author:    'bench'
			message:   'group commit write path ${sample_idx}'
			timestamp: sample_idx + 2
		})!
		elapsed := sw.elapsed().microseconds()
		hit_checkpoint := (sample_idx + 1) % group_every == 0
		if hit_checkpoint {
			checkpoint_hits++
			checkpoint_hit_us << elapsed
		} else {
			non_checkpoint_us << elapsed
		}
		diff := result.diff
		current_tree := session.transaction().current_tree()
		write_us << elapsed
		path_depths << stats.path_depth
		added_nodes << diff.added_cids.len
		added_bytes << current_tree.bytes_for_cids(diff.added_cids)
		if diff.added_cids.len == stats.path_depth {
			matching_rewrites++
		}
	}
	session.finish(mut state.db)!
	total_us := sum_i64_slice(write_us)
	avg_us := f64(total_us) / f64(samples)
	return BenchResult{
		name:        'prolly_write_path_group_commit_latency'
		duration_ms: total_us / 1000
		ops:         samples
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(write_us, 50)} p95_us=${percentile_i64(write_us,
			95)} max_us=${max_i64(write_us)} non_checkpoint_p50_us=${percentile_i64(non_checkpoint_us,
			50)} non_checkpoint_p95_us=${percentile_i64(non_checkpoint_us, 95)} checkpoint_hit_p50_us=${percentile_i64(checkpoint_hit_us,
			50)} checkpoint_hit_p95_us=${percentile_i64(checkpoint_hit_us, 95)} checkpoint_every=${group_every} checkpoint_hits=${checkpoint_hits} path_depth_p50=${percentile_int(path_depths,
			50)} path_depth_p95=${percentile_int(path_depths, 95)} added_nodes_p50=${percentile_int(added_nodes,
			50)} added_nodes_p95=${percentile_int(added_nodes, 95)} added_bytes_p50=${percentile_int(added_bytes,
			50)} added_bytes_p95=${percentile_int(added_bytes, 95)} path_depth_eq_added_nodes=${matching_rewrites}/${samples} field=bio'
	}
}

fn (suite BenchSuite) run_prolly_write_path_group_commit_data_only_async_latency_bench() !BenchResult {
	mut state := suite.build_persistent_typed_state()!
	defer {
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	samples := max_int(1, suite.cfg.lookups)
	group_every := 8
	group := storage.GroupCommitOptions.high_throughput().with_checkpoint_every(group_every)
	mut session := state.db.begin_default_group_commit_session(group)!
	mut write_us := []i64{cap: samples}
	mut non_checkpoint_us := []i64{cap: samples}
	mut checkpoint_hit_us := []i64{cap: samples}
	mut path_depths := []int{cap: samples}
	mut added_nodes := []int{cap: samples}
	mut added_bytes := []int{cap: samples}
	mut matching_rewrites := 0
	mut checkpoint_hits := 0
	for sample_idx in 0 .. samples {
		base_tree := state.db.tree_at_branch('main')!
		row_id := (sample_idx * 1613) % suite.cfg.rows
		primary_key := row_key(row_id)
		tree_key := encode_table_row_key('users', primary_key)
		stats := base_tree.key_stats(tree_key)!
		mut row := suite.user_row(row_id)
		mut bio := row_bio(row_id)
		if bio.len > 0 {
			pos := (sample_idx * 17 + bio.len / 2) % bio.len
			bio[pos] = bio[pos] ^ u8(0x01)
		}
		row.set('bio', bio)
		mut sw := time.new_stopwatch()
		result := session.put_row(mut state.db, 'users', primary_key, row, suite.chunk_cfg, storage.CommitMeta{
			author:    'bench'
			message:   'group commit data-only async write path ${sample_idx}'
			timestamp: sample_idx + 2
		})!
		elapsed := sw.elapsed().microseconds()
		hit_checkpoint := (sample_idx + 1) % group_every == 0
		if hit_checkpoint {
			checkpoint_hits++
			checkpoint_hit_us << elapsed
		} else {
			non_checkpoint_us << elapsed
		}
		diff := result.diff
		current_tree := session.transaction().current_tree()
		write_us << elapsed
		path_depths << stats.path_depth
		added_nodes << diff.added_cids.len
		added_bytes << current_tree.bytes_for_cids(diff.added_cids)
		if diff.added_cids.len == stats.path_depth {
			matching_rewrites++
		}
	}
	mut finish_sw := time.new_stopwatch()
	session.finish(mut state.db)!
	finish_us := finish_sw.elapsed().microseconds()
	total_us := sum_i64_slice(write_us)
	avg_us := f64(total_us) / f64(samples)
	return BenchResult{
		name:        'prolly_write_path_group_commit_data_only_async_latency'
		duration_ms: total_us / 1000
		ops:         samples
		bytes:       0
		note:        'avg_us=${avg_us:.2f} p50_us=${percentile_i64(write_us, 50)} p95_us=${percentile_i64(write_us,
			95)} max_us=${max_i64(write_us)} non_checkpoint_p50_us=${percentile_i64(non_checkpoint_us,
			50)} non_checkpoint_p95_us=${percentile_i64(non_checkpoint_us, 95)} checkpoint_hit_p50_us=${percentile_i64(checkpoint_hit_us,
			50)} checkpoint_hit_p95_us=${percentile_i64(checkpoint_hit_us, 95)} checkpoint_every=${group_every} checkpoint_hits=${checkpoint_hits} finish_us=${finish_us} path_depth_p50=${percentile_int(path_depths,
			50)} path_depth_p95=${percentile_int(path_depths, 95)} added_nodes_p50=${percentile_int(added_nodes,
			50)} added_nodes_p95=${percentile_int(added_nodes, 95)} added_bytes_p50=${percentile_int(added_bytes,
			50)} added_bytes_p95=${percentile_int(added_bytes, 95)} path_depth_eq_added_nodes=${matching_rewrites}/${samples} field=bio durable=data_only async_refresh=true'
	}
}

fn format_projection_policy(policy storage.AggregateProjectionRefreshPolicy, limit int) string {
	return match policy {
		.none { 'none' }
		.stale_one { 'stale_one' }
		.stale_up_to { 'stale_up_to(${limit})' }
		.stale_all { 'stale_all' }
	}
}

fn (suite BenchSuite) run_aggregate_projector_refresh_policy_sweep_bench() !BenchResult {
	samples := max_int(4, suite.cfg.lookups)
	policies := [
		storage.GroupCommitOptions.high_throughput().with_aggregate_projection_refresh_policy(.none),
		storage.GroupCommitOptions.high_throughput().with_aggregate_projection_refresh_policy(.stale_one),
		storage.GroupCommitOptions.high_throughput().with_aggregate_projection_refresh_policy(.stale_up_to).with_max_aggregate_projection_refreshes(1),
		storage.GroupCommitOptions.high_throughput().with_aggregate_projection_refresh_policy(.stale_all),
	]
	mut summaries := []string{cap: policies.len}
	for group in policies {
		mut state := suite.build_persistent_projector_state()!
		base_group := group.with_aggregate_projection_refresh_policy(.none)
		mut session := state.db.begin_default_group_commit_session(base_group)!
		mut write_us := []i64{cap: samples}
		for sample_idx in 0 .. samples {
			row_id := sample_idx % max_int(1, suite.cfg.rows)
			primary_key := 'item-${row_id:08}'.bytes()
			mut row := suite.projector_item_row(row_id)
			row.set('meta',
				'{"amount":${row_id + sample_idx + 1},"kind":"k${(row_id + sample_idx) % 8}"}')
			mut sw := time.new_stopwatch()
			_ = session.put_row(mut state.db, 'items', primary_key, row, suite.chunk_cfg, storage.CommitMeta{
				author:    'bench'
				message:   'projector refresh policy ${sample_idx}'
				timestamp: sample_idx + 2
			})!
			write_us << sw.elapsed().microseconds()
		}
		mut finish_sw := time.new_stopwatch()
		session.finish(mut state.db)!
		finish_us := finish_sw.elapsed().microseconds()
		mut refresh_us := i64(0)
		effective_limit := match group.aggregate_projection_refresh_policy {
			.none {
				-1
			}
			.stale_one {
				1
			}
			.stale_up_to {
				if group.max_aggregate_projection_refreshes > 0 {
					group.max_aggregate_projection_refreshes
				} else {
					1
				}
			}
			.stale_all {
				0
			}
		}

		if effective_limit >= 0 && group.aggregate_projection_refresh_policy != .none {
			mut refresh_sw := time.new_stopwatch()
			_ = state.db.refresh_aggregate_projections_limited('main', suite.chunk_cfg, storage.CommitMeta{
				author:    'bench'
				message:   'projector policy refresh'
				timestamp: samples + 2
			}, effective_limit)!
			refresh_us = refresh_sw.elapsed().microseconds()
		}
		states := state.db.projection_states_at_branch('main')!
		mut fresh := 0
		mut stale := 0
		mut refreshed_names := []string{}
		for state_row in states {
			if state_row.fresh {
				fresh++
				refreshed_names << state_row.projection.name
			} else {
				stale++
			}
		}
		summaries << '${format_projection_policy(group.aggregate_projection_refresh_policy,
			group.max_aggregate_projection_refreshes)}:p50=${percentile_i64(write_us, 50)}us,p95=${percentile_i64(write_us, 95)}us,finish=${finish_us}us,refresh=${refresh_us}us,fresh=${fresh},stale=${stale},refreshed=[${refreshed_names.join(',')}]'
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
	}
	return BenchResult{
		name:        'aggregate_projector_refresh_policy_sweep'
		duration_ms: 0
		ops:         samples
		bytes:       0
		note:        summaries.join(' ')
	}
}

fn (suite BenchSuite) run_prolly_write_path_group_commit_sweep_bench() !BenchResult {
	checkpoints := [2, 4, 8, 16, 32]
	samples := max_int(1, suite.cfg.lookups)
	mut summaries := []string{cap: checkpoints.len}
	for checkpoint_every in checkpoints {
		mut state := suite.build_persistent_typed_state()!
		group :=
			storage.GroupCommitOptions.high_throughput().with_checkpoint_every(checkpoint_every)
		mut session := state.db.begin_default_group_commit_session(group)!
		mut write_us := []i64{cap: samples}
		mut non_checkpoint_us := []i64{cap: samples}
		mut checkpoint_hit_us := []i64{}
		for sample_idx in 0 .. samples {
			row_id := (sample_idx * 1613) % suite.cfg.rows
			primary_key := row_key(row_id)
			mut row := suite.user_row(row_id)
			mut bio := row_bio(row_id)
			if bio.len > 0 {
				pos := (sample_idx * 17 + bio.len / 2) % bio.len
				bio[pos] = bio[pos] ^ u8(0x01)
			}
			row.set('bio', bio)
			mut sw := time.new_stopwatch()
			_ = session.put_row(mut state.db, 'users', primary_key, row, suite.chunk_cfg, storage.CommitMeta{
				author:    'bench'
				message:   'group commit sweep ${sample_idx}'
				timestamp: sample_idx + 2
			})!
			elapsed := sw.elapsed().microseconds()
			write_us << elapsed
			if (sample_idx + 1) % checkpoint_every == 0 {
				checkpoint_hit_us << elapsed
			} else {
				non_checkpoint_us << elapsed
			}
		}
		mut finish_sw := time.new_stopwatch()
		session.finish(mut state.db)!
		finish_us := finish_sw.elapsed().microseconds()
		state.db.close() or {}
		os.rmdir_all(state.root_dir) or {}
		summaries << 'every=${checkpoint_every}:p50=${percentile_i64(write_us, 50)}us,p95=${percentile_i64(write_us, 95)}us,nonchk_p95=${percentile_i64(non_checkpoint_us, 95)}us,chk_p95=${percentile_i64(checkpoint_hit_us, 95)}us,finish=${finish_us}us'
	}
	return BenchResult{
		name:        'prolly_write_path_group_commit_sweep'
		duration_ms: 0
		ops:         samples * checkpoints.len
		bytes:       0
		note:        summaries.join(' | ')
	}
}

fn (suite BenchSuite) run_working_set_update_bench(mut state BenchState) !BenchResult {
	mut set := state.repo.typed_working_set_at_branch('main', [state.spec], mut state.node_store, mut
		state.commit_store)!
	mut writes := storage.TypedWriteSet.new()
	for idx in 0 .. suite.cfg.updates {
		row_id := (idx * 1613) % suite.cfg.rows
		mut row := suite.user_row(row_id)
		row.set('active', row_id % 2 != 0)
		writes.put('users', row_key(row_id), row)
	}
	mut sw := time.new_stopwatch()
	_ = set.apply_write_set(writes, suite.chunk_cfg)!
	return BenchResult{
		name:        'typed_working_set_updates'
		duration_ms: sw.elapsed().milliseconds()
		ops:         suite.cfg.updates
		bytes:       0
		note:        'staged_changes=${set.has_changes()}'
	}
}

fn (suite BenchSuite) run_merge_bench(mut _ BenchState) !BenchResult {
	mut merge_state := suite.build_typed_state_for_spec(suite.users_merge_spec()!)!
	head := merge_state.repo.head()!
	if !merge_state.repo.has_branch('feature') {
		_ = merge_state.repo.create_branch('feature', head.commit_cid)!
	}

	mut feature_writes := storage.TypedWriteSet.new()
	for idx in 0 .. suite.cfg.merge_writes {
		row_id := suite.cfg.rows + idx
		feature_writes.put('users', row_key(row_id), suite.user_row(row_id))
	}
	_ = merge_state.repo.apply_typed_write_set_to_branch('feature', [merge_state.spec],
		feature_writes, suite.chunk_cfg, storage.CommitMeta{
		author:    'bench'
		message:   'feature writes'
		timestamp: 3
	}, mut merge_state.node_store, mut merge_state.commit_store)!

	mut main_set := merge_state.repo.typed_working_set_at_branch('main', [merge_state.spec], mut
		merge_state.node_store, mut merge_state.commit_store)!
	mut main_writes := storage.TypedWriteSet.new()
	for idx in 0 .. suite.cfg.merge_writes {
		row_id := suite.cfg.rows + suite.cfg.merge_writes + idx
		main_writes.put('users', row_key(row_id), suite.user_row(row_id))
	}
	_ = main_set.apply_write_set(main_writes, suite.chunk_cfg)!

	mut sw := time.new_stopwatch()
	result := merge_state.repo.typed_merge_branch_into_working_set(mut main_set, 'feature',
		[]storage.ConflictResolution{}, suite.chunk_cfg, mut merge_state.node_store, mut
		merge_state.commit_store)!
	return BenchResult{
		name:        'typed_branch_merge'
		duration_ms: sw.elapsed().milliseconds()
		ops:         suite.cfg.merge_writes * 2
		bytes:       0
		note:        'conflicts=${result.merge_result.conflicts.len} merge_changed_keys=${result.merge_result.changed_keys.len} merge_changed_subtrees=${result.merge_result.changed_subtrees.len} merge_resolved_keys=${result.resolution.resolved_keys.len} staged_added=${result.staged_diff.added_cids.len} merge_ms=${result.timings.merge_ms} resolve_ms=${result.timings.resolve_ms} changed_rows_ms=${result.timings.changed_rows_ms} reindex_ms=${result.timings.reindex_ms} reindex_strategy=${result.timings.reindex.strategy} reindex_items_ms=${result.timings.reindex.items_ms} reindex_remove_ms=${result.timings.reindex.remove_ms} reindex_insert_ms=${result.timings.reindex.insert_ms} reindex_build_ms=${result.timings.reindex.rebuild_ms} reindex_item_count=${result.timings.reindex.item_count} reindex_changed_tables=${result.timings.reindex.changed_tables} reindex_changed_rows=${result.timings.reindex.changed_rows} reindex_removed_indexes=${result.timings.reindex.removed_indexes} reindex_inserted_indexes=${result.timings.reindex.inserted_indexes}'
	}
}

fn (suite BenchSuite) users_spec() !storage.TypedTableSpec {
	table_def := storage.TableDef.new('users', [
		storage.ColumnDef.sum_i64('id', false)!,
		storage.ColumnDef.new('email', .string_, false)!,
		storage.ColumnDef.new('active', .bool_, false)!,
		storage.ColumnDef.new('bio', .bytes_, true)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table_def, [
		storage.SchemaIndexDef.new('email', 'email')!,
	])!
}

fn (suite BenchSuite) users_merge_spec() !storage.TypedTableSpec {
	table_def := storage.TableDef.new('users', [
		storage.ColumnDef.new('id', .i64_, false)!,
		storage.ColumnDef.new('email', .string_, false)!,
		storage.ColumnDef.new('active', .bool_, false)!,
		storage.ColumnDef.new('bio', .bytes_, true)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table_def, [
		storage.SchemaIndexDef.new('email', 'email')!,
	])!
}

fn (suite BenchSuite) prolly_bench_items(target_bytes int) []storage.KVPair {
	value_len := 960
	record_overhead := 8 + 16
	item_bytes := value_len + record_overhead
	item_count := max_int(1024, target_bytes / item_bytes)
	mut items := []storage.KVPair{cap: item_count}
	for idx in 0 .. item_count {
		key := 'bench-${idx:08}'.bytes()
		value := suite.prolly_bench_value(idx)
		items << storage.KVPair{
			key:   key
			value: value
		}
	}
	return items
}

fn (suite BenchSuite) prolly_bench_value(seed int) []u8 {
	value_len := 960
	mut value := []u8{len: value_len}
	for j in 0 .. value_len {
		value[j] = u8((seed * 31 + j * 17 + j / 13) % 251)
	}
	return value
}

fn (suite BenchSuite) prolly_bench_result(name string, target_bytes int, item_count int, base_tree storage.Tree, next_tree storage.Tree, diff storage.TreeDiff, elapsed time.Duration) BenchResult {
	duration_ms := elapsed.milliseconds()
	duration_us := elapsed.microseconds()
	added_bytes := next_tree.bytes_for_cids(diff.added_cids)
	reused_bytes := next_tree.bytes_for_cids(diff.reused_cids)
	base_nodes := base_tree.reachable_node_count() or { 0 }
	next_nodes := next_tree.reachable_node_count() or { 0 }
	base_bytes := base_tree.reachable_node_bytes() or { 0 }
	next_bytes := next_tree.reachable_node_bytes() or { 0 }
	reuse_ratio := if base_nodes > 0 {
		f64(diff.reused_cids.len) / f64(base_nodes)
	} else {
		0.0
	}
	return BenchResult{
		name:        name
		duration_ms: duration_ms
		ops:         1
		bytes:       target_bytes
		note:        'items=${item_count} root_us=${duration_us} base_nodes=${base_nodes} next_nodes=${next_nodes} added_nodes=${diff.added_cids.len} removed_nodes=${diff.removed_cids.len} reused_nodes=${diff.reused_cids.len} base_bytes=${base_bytes} next_bytes=${next_bytes} added_bytes=${added_bytes} reused_bytes=${reused_bytes} reuse_ratio=${reuse_ratio:.4f} root_changed=${base_tree.root.cid != next_tree.root.cid}'
	}
}

fn (suite BenchSuite) measure_tree_put(base_tree storage.Tree, item storage.KVPair) !(time.Duration, storage.Tree) {
	mut sw := time.new_stopwatch()
	next_tree := base_tree.put(item, suite.chunk_cfg)!
	return sw.elapsed(), next_tree
}

fn (suite BenchSuite) prolly_distribution_warmup(base_tree storage.Tree, items []storage.KVPair) ! {
	if items.len == 0 {
		return
	}
	item := items[suite.prolly_sample_index(items.len, 0)]
	mut next_value := item.value.clone()
	if next_value.len > 0 {
		next_value[0] = next_value[0] ^ u8(0x01)
	}
	_, _ = suite.measure_tree_put(base_tree, storage.KVPair{
		key:   item.key.clone()
		value: next_value
	})!
}

fn (suite BenchSuite) prolly_sample_count() int {
	return min_int(64, max_int(16, suite.cfg.lookups))
}

fn (suite BenchSuite) prolly_sample_index(item_count int, sample_idx int) int {
	if item_count <= 0 {
		return 0
	}
	return (sample_idx * 7919 + item_count / 3) % item_count
}

fn (suite BenchSuite) prolly_distribution_result(name string, target_bytes int, item_count int, samples int, root_us []i64, added_bytes []int, added_nodes []int, path_depths []int, leaf_item_counts []int) BenchResult {
	return BenchResult{
		name:        name
		duration_ms: percentile_i64(root_us, 95) / 1000
		ops:         samples
		bytes:       target_bytes
		note:        'items=${item_count} samples=${samples} root_us_p50=${percentile_i64(root_us,
			50)} root_us_p95=${percentile_i64(root_us, 95)} root_us_max=${max_i64(root_us)} path_depth_p50=${percentile_int(path_depths,
			50)} path_depth_p95=${percentile_int(path_depths, 95)} leaf_items_p50=${percentile_int(leaf_item_counts,
			50)} leaf_items_p95=${percentile_int(leaf_item_counts, 95)} added_nodes_p50=${percentile_int(added_nodes,
			50)} added_nodes_p95=${percentile_int(added_nodes, 95)} added_nodes_max=${max_int_slice(added_nodes)} added_bytes_p50=${percentile_int(added_bytes,
			50)} added_bytes_p95=${percentile_int(added_bytes, 95)} added_bytes_max=${max_int_slice(added_bytes)}'
	}
}

fn (suite BenchSuite) user_row(id int) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('id', i64(id))
	row.set('email', row_email(id))
	row.set('active', id % 2 == 0)
	row.set('bio', row_bio(id))
	return row
}

fn (suite BenchSuite) large_payload(size int) []u8 {
	mut data := []u8{len: size}
	for idx in 0 .. size {
		data[idx] = u8((idx * 131 + idx / 97) % 251)
	}
	return data
}

fn (suite BenchSuite) chunk_hashes(data []u8, chunks []storage.Chunk) []string {
	mut hashes := []string{cap: chunks.len}
	for chunk in chunks {
		hashes << storage.chunk_cid_hex(data[chunk.start..chunk.end])
	}
	return hashes
}

fn row_key(id int) []u8 {
	return '${id:08}'.bytes()
}

fn row_email(id int) string {
	return 'user-${id:08}@example.com'
}

fn metric_row_key(id int, total_rows int) []u8 {
	bucket_count := 26
	safe_total := max_int(1, total_rows)
	bucket := min_int(bucket_count - 1, (id * bucket_count) / safe_total)
	bucket_start := (bucket * safe_total) / bucket_count
	local_idx := id - bucket_start
	return '${u8(`a`) + u8(bucket):c}${local_idx:08}'.bytes()
}

fn row_bio(id int) []u8 {
	return 'bio-${id:08}-payload-for-prollytree-benchmark'.bytes()
}

fn encode_table_row_key(table_name string, primary_key []u8) []u8 {
	mut out := 't|${table_name}|'.bytes()
	out << primary_key
	return out
}

fn encode_index_entry_key(table_name string, index_name string, index_key []u8, primary_key []u8) []u8 {
	mut out := 'i|${table_name}|${index_name}|'.bytes()
	out << index_key
	out << [u8(`|`)]
	out << primary_key
	return out
}

fn min_int(a int, b int) int {
	if a < b {
		return a
	}
	return b
}

fn max_int(a int, b int) int {
	if a > b {
		return a
	}
	return b
}

fn sum_i64_slice(values []i64) i64 {
	mut total := i64(0)
	for value in values {
		total += value
	}
	return total
}

fn percentile_i64(values []i64, percentile int) i64 {
	if values.len == 0 {
		return 0
	}
	mut sorted := values.clone()
	sorted.sort()
	idx := ((sorted.len - 1) * percentile) / 100
	return sorted[idx]
}

fn percentile_int(values []int, percentile int) int {
	if values.len == 0 {
		return 0
	}
	mut sorted := values.clone()
	sorted.sort()
	idx := ((sorted.len - 1) * percentile) / 100
	return sorted[idx]
}

fn max_i64(values []i64) i64 {
	if values.len == 0 {
		return 0
	}
	mut max_v := values[0]
	for value in values[1..] {
		if value > max_v {
			max_v = value
		}
	}
	return max_v
}

fn max_int_slice(values []int) int {
	if values.len == 0 {
		return 0
	}
	mut max_v := values[0]
	for value in values[1..] {
		if value > max_v {
			max_v = value
		}
	}
	return max_v
}

fn print_results(results []BenchResult) {
	println('| Scenario | Duration (ms) | Ops | Ops/sec | Bytes | Notes |')
	println('| --- | ---: | ---: | ---: | ---: | --- |')
	for result in results {
		ops_per_sec := if result.duration_ms > 0 {
			f64(result.ops) / (f64(result.duration_ms) / 1000.0)
		} else {
			f64(result.ops)
		}
		println('| ${result.name} | ${result.duration_ms} | ${result.ops} | ${ops_per_sec:.2f} | ${result.bytes} | ${result.note} |')
	}
}

fn main() {
	cfg := BenchConfig.from_args()
	suite := BenchSuite.new(cfg)
	results := suite.run() or {
		eprintln('benchmark failed: ${err}')
		exit(1)
	}
	println('# PollyTree Benchmark')
	println('')
	println('rows=${cfg.rows} batch_size=${cfg.batch_size} lookups=${cfg.lookups} range_size=${cfg.range_size} updates=${cfg.updates} merge_writes=${cfg.merge_writes}')
	println('')
	print_results(results)
}
