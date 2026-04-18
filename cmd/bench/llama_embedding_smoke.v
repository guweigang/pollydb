module main

import math
import memory
import os
import storage

fn main() {
	run() or { panic(err) }
}

fn run() ! {
	model_path := if os.args.len > 1 {
		os.args[1]
	} else {
		return error('usage: v -d llama_cpp run cmd/bench/llama_embedding_smoke.v /path/to/model.gguf')
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

	query := '数据库索引优化和查询规划'
	related := '如何优化数据库查询和索引设计'
	unrelated := '今天的天气和晚饭吃什么'
	targets := memory.markdown_embedding_targets('# Memory\n\n' + query + '\n\n## Related\n\n' +
		related + '\n\n## Unrelated\n\n' + unrelated + '\n')!
	vectors := engine.embed_batch(memory.markdown_embedding_texts(targets))!

	println('model=${engine.model_name()}')
	println('dims=${engine.dimensions()}')
	println('targets=${targets.len}')
	for idx, target in targets {
		println('${idx}: scope=${target.scope} kind=${target.kind} anchor=${target.anchor} text=${target.text}')
	}

	query_vec := vectors[0]
	related_vec := vectors[1]
	unrelated_vec := vectors[2]
	println('cosine(query, related)=${cosine_similarity(query_vec, related_vec):.4f}')
	println('cosine(query, unrelated)=${cosine_similarity(query_vec, unrelated_vec):.4f}')
}

fn cosine_similarity(a []f32, b []f32) f64 {
	limit := if a.len < b.len { a.len } else { b.len }
	if limit == 0 {
		return 0.0
	}
	mut dot := f64(0)
	mut a_norm := f64(0)
	mut b_norm := f64(0)
	for idx in 0 .. limit {
		av := f64(a[idx])
		bv := f64(b[idx])
		dot += av * bv
		a_norm += av * av
		b_norm += bv * bv
	}
	if a_norm == 0 || b_norm == 0 {
		return 0.0
	}
	return dot / (math.sqrt(a_norm) * math.sqrt(b_norm))
}
