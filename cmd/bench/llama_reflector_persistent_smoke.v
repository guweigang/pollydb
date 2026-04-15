module main

import os
import storage

fn main() {
	run() or { panic(err) }
}

fn run() ! {
	if os.args.len < 3 {
		return error('usage: v -d llama_cpp run cmd/bench/llama_reflector_persistent_smoke.v /path/to/embedding.gguf /path/to/generation.gguf [root_dir]')
	}
	embedding_model_path := os.args[1]
	generation_model_path := os.args[2]
	root_dir := if os.args.len > 3 {
		os.args[3]
	} else {
		os.join_path(os.vtmp_dir(), 'pollydb-llama-reflector-persistent-smoke')
	}
	os.rmdir_all(root_dir) or {}

	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	defer {
		db.close() or {}
	}
	spec := memory_entries_spec()!
	db.register_table(spec)!
	db.register_memory_capability(storage.MemoryCapabilityDef.reflective_field('memory_entries',
		'content_md', storage.ReflectionOptions{
		embedding_index: 'content_path_vec_idx'
		reflection_kind: 'summary'
	})!)!

	ref_a := db.ingest_markdown('# PollyDB 真相层\n\nPollyDB 保存 BlockNode、向量记录、语义链接和反思状态。SQLite FTS 与 USearch 都只是可重建的外挂索引视图。\n')!
	ref_b := db.ingest_markdown('# 反思调度\n\nReflector 在写入量达到阈值后，利用向量邻居收集 evidence，再调用本地小模型生成复盘 Markdown，并把结果写回 PollyDB。\n')!
	mut row_a := storage.TypedRowData.new()
	row_a.set('id', 'entry-1')
	row_a.set('content_md', ref_a)
	mut row_b := storage.TypedRowData.new()
	row_b.set('id', 'entry-2')
	row_b.set('content_md', ref_b)
	codec := storage.TypedRowCodec.new(spec.table)
	seed_tree := storage.Tree.build([
		storage.KVPair{
			key:   storage.TableView.new(storage.Tree{}, spec.table.name).row_key('entry-1'.bytes())
			value: codec.encode(row_a)!
		},
		storage.KVPair{
			key:   storage.TableView.new(storage.Tree{}, spec.table.name).row_key('entry-2'.bytes())
			value: codec.encode(row_b)!
		},
	], storage.ChunkConfig.default())!
	_ = db.commit_to_branch('main', seed_tree, storage.CommitMeta{
		author:  'bench'
		message: 'seed memory entries'
	})!
	_ = db.note_reflector_writes('main', 2, storage.ChunkConfig.default(), storage.CommitMeta{
		author:  'bench'
		message: 'note reflector writes'
	})!

	mut embedding_engine := storage.new_llama_embedding_engine(storage.LlamaEmbeddingConfig{
		model_path:   embedding_model_path
		n_ctx:        512
		n_batch:      512
		n_gpu_layers: 0
	})!
	defer {
		embedding_engine.close()
	}
	mut generator := storage.new_llama_generation_engine(storage.LlamaGenerationConfig{
		model_path:       generation_model_path
		n_ctx:            2048
		n_batch:          512
		n_gpu_layers:     0
		max_tokens:       260
		max_output_bytes: 12000
	})!
	defer {
		generator.close()
	}

	mut scheduler := storage.ReflectorScheduler.new(storage.ReflectorScheduleOptions{
		write_threshold: 2
		neighbor_limit:  4
		max_jobs:        1
		min_evidence:    1
	})
	persisted := scheduler.maybe_reflect_persistent(mut db, 'main', mut embedding_engine, mut
		generator, storage.ChunkConfig.default(), storage.CommitMeta{
		author:  'bench'
		message: 'persistent reflector smoke'
	})!
	state := db.load_reflector_state('main')!
	println('root_dir=${root_dir}')
	println('reflections=${persisted.len}')
	println('pending_writes=${state.pending_writes}')
	println('last_reflected_root_hash=${state.last_reflected_root_hash}')
	for reflection in persisted {
		summary := db.load_markdown(reflection.summary_ref)!
		insight := if reflection.insight_ref.doc_root_id.len > 0 {
			db.load_markdown(reflection.insight_ref)!
		} else {
			''
		}
		println('reflection_id=${reflection.reflection_id}')
		println('title=${reflection.title}')
		println('topic=${reflection.topic_key}')
		println('sources=${reflection.source_refs.len}')
		println('SUMMARY_MD:')
		println(summary)
		println('INSIGHT_MD:')
		println(insight)
	}
}

fn memory_entries_spec() !storage.TypedTableSpec {
	return storage.TypedTableSpec.new(storage.TableDef.new('memory_entries', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('content_md', .markdown_, false)!,
	], ['id'])!, [
		storage.SchemaIndexDef.embedding_markdown('content_path_vec_idx', 'content_md',
			.path, 'bge-small')!,
	])!
}
