module main

import os
import storage

fn main() {
	run() or { panic(err) }
}

fn run() ! {
	model_path := if os.args.len > 1 {
		os.args[1]
	} else {
		return error('usage: v -d llama_cpp run cmd/bench/llama_vector_search_smoke.v /path/to/model.gguf')
	}
	root_dir := os.join_path(os.vtmp_dir(), 'pollydb-llama-vector-search-smoke')
	os.rmdir_all(root_dir) or {}

	mut db := storage.PersistentDatabase.init(root_dir, 'main')!
	defer {
		db.close() or {}
	}
	mut engine := storage.new_llama_embedding_engine(storage.LlamaEmbeddingConfig{
		model_path:   model_path
		n_ctx:        512
		n_batch:      512
		n_gpu_layers: 999
	})!
	defer {
		engine.close()
	}

	ref := db.ingest_markdown('# Notes\n\n数据库索引优化和查询规划\n\n## Related\n\n如何优化数据库查询和索引设计\n\n## Unrelated\n\n今天的天气和晚饭吃什么\n')!
	targets := db.index_markdown_ref_embeddings('main', ref, mut engine)!
	hits := db.query_markdown_text_embeddings(mut engine, '数据库优化', storage.VectorSearchQuery{
		branch_name: 'main'
		limit:       3
		scope:       .block
		scope_set:   true
	})!

	println('root_dir=${root_dir}')
	println('indexed_targets=${targets.len}')
	for idx, hit in hits {
		println('${idx}: score=${hit.score:.4f} scope=${hit.scope} anchor=${hit.anchor} text=${hit.text}')
	}
}
