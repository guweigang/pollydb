module main

import agentview
import memory
import os

fn main() {
	run() or { panic(err) }
}

fn run() ! {
	if os.args.len < 4 {
		return error('usage: v -d llama_cpp run cmd/bench/agentview_memory_quality_probe.v <codex_root|session.jsonl|flat_jsonl_dir> <store_root> <embedding.gguf> [generation.gguf|heuristic] [recent_sessions] [max_jobs] [neighbor_limit] [candidate_limit]')
	}
	codex_input := os.args[1]
	store_root := os.args[2]
	embedding_model := os.args[3]
	generation_model := if os.args.len > 4 { os.args[4] } else { 'heuristic' }
	recent_sessions := if os.args.len > 5 { os.args[5].int() } else { 1 }
	max_jobs := if os.args.len > 6 { os.args[6].int() } else { 3 }
	neighbor_limit := if os.args.len > 7 { os.args[7].int() } else { 3 }
	candidate_limit := if os.args.len > 8 { os.args[8].int() } else { max_jobs * 4 }

	os.rmdir_all(store_root) or {}
	codex_root := resolve_codex_root(codex_input, store_root)!
	store := agentview.PollyDbStore.open(store_root)!
	stats := store.sync_codex(codex_root)!
	_ = store.ensure_memory_schema()!
	salience := store.inspect_recent_memory_salience(recent_sessions)!
	println('codex_root=${codex_root}')
	println('synced_sessions=${stats.sessions}')
	println('synced_entries=${stats.entries}')
	print_salience(salience)
	if generation_model == 'salience-only' {
		return
	}
	mut embedding_engine := memory.new_llama_embedding_engine(memory.LlamaEmbeddingConfig{
		model_path:   embedding_model
		n_ctx:        512
		n_batch:      512
		n_gpu_layers: 0
	})!
	defer {
		embedding_engine.close()
	}
	options := agentview.MemoryDistillOptions{
		recent_sessions: recent_sessions
		max_jobs:        max_jobs
		neighbor_limit:  neighbor_limit
		min_evidence:    1
		candidate_limit: candidate_limit
	}
	persisted := if generation_model == 'heuristic' {
		store.distill_recent_memory_heuristic(mut embedding_engine, options)!
	} else {
		mut generator := memory.new_llama_generation_engine(memory.LlamaGenerationConfig{
			model_path:       generation_model
			n_ctx:            2048
			n_batch:          64
			n_gpu_layers:     0
			max_tokens:       260
			max_output_bytes: 12000
		})!
		defer {
			generator.close()
		}
		store.distill_recent_memory(mut embedding_engine, mut generator, options)!
	}
	println('reflections=${persisted.len}')
	for idx, reflection in persisted {
		println('reflection_${idx}_id=${reflection.reflection_id}')
		println('reflection_${idx}_title=${reflection.title}')
		println('reflection_${idx}_sources=${reflection.source_refs.len}')
		action := if reflection.supersedes_reflection_id.len > 0 { 'update' } else { 'add' }
		println('reflection_${idx}_memory_action=${action}')
		if reflection.supersedes_reflection_id.len > 0 {
			println('reflection_${idx}_supersedes=${reflection.supersedes_reflection_id}')
		}
		println('summary_${idx}<<EOF')
		println(reflection.summary_md)
		println('EOF')
	}
}

fn print_salience(salience agentview.MemorySalienceReport) {
	println('salience_raw_entries=${salience.raw_entries}')
	println('salience_candidate_entries=${salience.candidate_entries}')
	println('salience_embedding_candidate_entries=${salience.embedding_candidate_entries}')
	println('salience_candidate_types=${format_counts(salience.candidates_by_type)}')
	println('salience_skip_reasons=${format_counts(salience.skipped_by_reason)}')
	println('salience_discarded_before_embedding=${format_counts(salience.discarded_before_embedding)}')
}

fn resolve_codex_root(input string, store_root string) !string {
	if os.is_dir(input) && codex_root_has_session_files(input)! {
		return input
	}
	paths := flat_jsonl_paths(input)!
	if paths.len == 0 {
		return error('no codex sessions found in ${input}; expected a Codex root, a .jsonl file, or a flat directory of .jsonl files')
	}
	staged_root := '${store_root}-codex-root'
	os.rmdir_all(staged_root) or {}
	for path in paths {
		year, month, day := rollout_date_parts(os.file_name(path))
		dst_dir := os.join_path(staged_root, 'sessions', year, month, day)
		os.mkdir_all(dst_dir)!
		os.cp(path, os.join_path(dst_dir, os.file_name(path)))!
	}
	return staged_root
}

fn codex_root_has_session_files(root string) !bool {
	for base_name in ['sessions', 'archived_sessions'] {
		base := os.join_path(root, base_name)
		if !os.exists(base) {
			continue
		}
		if has_jsonl_file(base)! {
			return true
		}
	}
	return false
}

fn has_jsonl_file(dir string) !bool {
	for name in os.ls(dir)! {
		path := os.join_path(dir, name)
		if os.is_file(path) && path.ends_with('.jsonl') {
			return true
		}
		if os.is_dir(path) && has_jsonl_file(path)! {
			return true
		}
	}
	return false
}

fn flat_jsonl_paths(input string) ![]string {
	if os.is_file(input) {
		if input.ends_with('.jsonl') {
			return [input]
		}
		return []string{}
	}
	if !os.is_dir(input) {
		return []string{}
	}
	mut paths := []string{}
	for name in os.ls(input)! {
		path := os.join_path(input, name)
		if os.is_file(path) && path.ends_with('.jsonl') {
			paths << path
		}
	}
	paths.sort()
	return paths
}

fn rollout_date_parts(name string) (string, string, string) {
	prefix := 'rollout-'
	if name.starts_with(prefix) && name.len >= prefix.len + 10 {
		stamp := name[prefix.len..prefix.len + 10]
		parts := stamp.split('-')
		if parts.len == 3 && parts[0].len == 4 && parts[1].len == 2 && parts[2].len == 2 {
			return parts[0], parts[1], parts[2]
		}
	}
	return '1970', '01', '01'
}

fn format_counts(counts map[string]int) string {
	if counts.len == 0 {
		return '{}'
	}
	mut keys := counts.keys()
	keys.sort()
	mut parts := []string{}
	for key in keys {
		parts << '${key}:${counts[key]}'
	}
	return '{${parts.join(', ')}}'
}
