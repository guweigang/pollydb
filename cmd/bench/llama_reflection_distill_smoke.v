module main

import memory
import os

fn main() {
	run() or { panic(err) }
}

fn run() ! {
	model_path := if os.args.len > 1 {
		os.args[1]
	} else {
		return error('usage: v -d llama_cpp run cmd/bench/llama_reflection_distill_smoke.v /path/to/model.gguf')
	}
	mut generator := memory.new_llama_generation_engine(memory.LlamaGenerationConfig{
		model_path:   model_path
		n_ctx:        2048
		n_batch:      512
		n_gpu_layers: 0
		max_tokens:   220
	})!
	defer {
		generator.close()
	}
	job := memory.ReflectionJob{
		branch_name:     'main'
		table_name:      'memory_entries'
		primary_key:     'entry-1'.bytes()
		column_name:     'content_md'
		reflection_kind: 'summary'
		seed_scope:      .path
		seed_anchor:     '/h1:local-memory'
		seed_text:       'PollyDB 持有记忆真相；SQLite 只做 FTS；USearch 是可重建 ANN 视图。'
		evidence:        [
			memory.ReflectionEvidence{
				table_name:  'memory_entries'
				primary_key: 'entry-2'.bytes()
				column_name: 'content_md'
				target_id:   'entry-2:path'
				score:       0.98
				scope:       .path
				kind:        'heading_path'
				anchor:      '/h1:vector'
				path_hint:   'blocks[0]'
				text:        '向量记录已经迁回 PollyDB typed table，SQLite 不再保存 vector payload。'
			},
			memory.ReflectionEvidence{
				table_name:  'memory_entries'
				primary_key: 'entry-3'.bytes()
				column_name: 'content_md'
				target_id:   'entry-3:path'
				score:       0.93
				scope:       .path
				kind:        'heading_path'
				anchor:      '/h1:reflector'
				path_hint:   'blocks[0]'
				text:        'Reflector 已经能构建 evidence job，并把 summary 与 semantic links 写回 PollyDB。'
			},
		]
	}
	input := memory.generate_reflection_persist_input(job, mut generator, memory.ReflectionDistillOptions{
		title:     '本地记忆引擎边界'
		topic_key: 'local-memory-engine'
	})!
	println('TITLE: ${input.title}')
	println('TOPIC: ${input.topic_key}')
	println('SUMMARY_MD:')
	println(input.summary_md)
	println('INSIGHT_MD:')
	println(input.insight_md)
}
