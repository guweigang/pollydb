module main

import memory
import memorydb
import os
import storage

struct ReplayOverviewGenerator {
	output string
}

fn (mut generator ReplayOverviewGenerator) generate(prompt string) !string {
	_ = prompt
	return generator.output
}

fn main() {
	run() or { panic(err) }
}

fn run() ! {
	model_path := if os.args.len > 1 {
		os.args[1]
	} else {
		return error('usage: v -d llama_cpp run cmd/bench/llama_replay_overview_smoke.v /path/to/model.gguf [query]')
	}
	query_text := if os.args.len > 2 { os.args[2] } else { '数据库优化' }
	root_dir := os.join_path(os.vtmp_dir(), 'pollydb-llama-replay-overview-smoke')
	os.rmdir_all(root_dir) or {}

	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	defer {
		db.close() or {}
	}
	mut engine := memory.new_llama_embedding_engine(memory.LlamaEmbeddingConfig{
		model_path:   model_path
		n_ctx:        512
		n_batch:      512
		n_gpu_layers: 999
	})!
	defer {
		engine.close()
	}
	mut generator := ReplayOverviewGenerator{
		output: 'TOPIC: db-optimization\nSUMMARY_MD:\n# Summary\n\n我们集中讨论了数据库查询优化以及本地优先约束。\n\nINSIGHT_MD:\n## Insight\n\n保留可回放证据，再做语义蒸馏。\nEND_REFLECTION'
	}

	spec := storage.TypedTableSpec.new(storage.TableDef.new('docs', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('body', .markdown_, false)!,
	], ['id'])!, [
		storage.SchemaIndexDef.embedding_markdown('body_path_vec_idx', 'body', .path,
			'bge-small')!,
	])!
	db.register_table(spec)!
	memorydb.register_capability(mut db, memory.MemoryCapabilityDef.reflective_field('docs',
		'body', memory.ReflectionOptions{
		embedding_index: 'body_path_vec_idx'
		reflection_kind: 'summary'
	})!)!

	session := db.open_session('main')!
	doc_1 := db.ingest_markdown('# Query\n\n数据库优化和查询规划\n\n## Constraints\n\n保持本地优先与可回放证据。\n')!
	doc_2 := db.ingest_markdown('# Indexes\n\n数据库索引设计与查询优化\n\n## Notes\n\n优先保留向量检索与关键词检索双轨。\n')!
	doc_3 := db.ingest_markdown('# Weather\n\n今天天气不错，晚上吃面。\n')!

	mut seed_row_1 := storage.TypedRowData.new()
	seed_row_1.set('id', 'doc-1')
	seed_row_1.set('body', doc_1)
	mut seed_row_2 := storage.TypedRowData.new()
	seed_row_2.set('id', 'doc-2')
	seed_row_2.set('body', doc_2)
	mut seed_row_3 := storage.TypedRowData.new()
	seed_row_3.set('id', 'doc-3')
	seed_row_3.set('body', doc_3)

	mut writes := storage.TypedWriteSet.new()
	writes.put('docs', 'doc-1'.bytes(), seed_row_1)
	writes.put('docs', 'doc-2'.bytes(), seed_row_2)
	writes.put('docs', 'doc-3'.bytes(), seed_row_3)
	db.apply_typed_write_set('main', writes, storage.ChunkConfig.default(), storage.CommitMeta{
		author:    'gwg'
		message:   'seed replay docs'
		timestamp: 1
	})!

	_ = memorydb.reflect_memory_persistent(mut db, 'main', 2, mut engine, mut generator,
		memory.ReflectorScheduleOptions{
		write_threshold: 2
		neighbor_limit:  2
		max_jobs:        1
	}, storage.ChunkConfig.default(), storage.CommitMeta{
		author:    'gwg'
		message:   'persist replay reflection'
		timestamp: 2
	})!

	replay := memorydb.replay_query(mut db, mut engine, memory.ReplayQueryRequest{
		branch_name:      'main'
		text:             query_text
		seed_limit:       3
		neighbor_limit:   6
		reflection_limit: 3
	})!
	overview := memory.replay_overview('main', replay.evidence_hits, replay.reflections)

	println('root_dir=${root_dir}')
	println('query=${query_text}')
	println('topics=${overview.topics.len} evidence=${overview.evidence.len} roots=${overview.timeline.derived_from_root_hashes.len}')
	for idx, topic in overview.topics {
		println('topic[${idx}] score=${topic.score:.4f} kind=${topic.reflection_kind} title=${topic.title}')
	}
	for idx, evidence in overview.evidence {
		println('evidence[${idx}] score=${evidence.score:.4f} via=${evidence.via_link_kind} key=${evidence.table_name}/${evidence.primary_key.bytestr()} anchor=${evidence.anchor}')
	}
	for idx, root_hash in overview.timeline.derived_from_root_hashes {
		println('timeline_root[${idx}]=${root_hash}')
	}

	_ = session
}
