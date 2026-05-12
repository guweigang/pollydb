module main

import os
import agentview
import memory
import storage
import time

fn main() {
	args := normalized_args(os.args[1..])
	if args.len == 0 || args[0] in ['help', '--help', '-h'] {
		println(usage())
		return
	}
	command := args[0]
	if command == 'bench-codex' {
		run_bench_codex(args) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if command == 'bench-codex-delta' {
		run_bench_codex_delta(args) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if command == 'bench-codex-index-delta' {
		run_bench_codex_index_delta(args) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if command == 'bench-write-path' {
		run_bench_write_path(args) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if command == 'bench-write-layout' {
		run_bench_write_layout(args) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if command == 'bench-tree-build' {
		run_bench_tree_build(args) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if command == 'bench-split-materialize' {
		run_bench_split_materialize(args) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if command == 'bench-write-matrix' {
		run_bench_write_matrix(args) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if command == 'explain-browser' {
		run_explain_browser(args) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if command == 'bench-browser' {
		run_bench_browser(args) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	codex_root := resolve_codex_root(args)
	store_root := resolve_store_root(args)
	store := agentview.PollyDbStore.open(store_root) or {
		eprintln(err.msg())
		exit(1)
	}
	ensure_store_ready(command, store, codex_root) or {
		eprintln(err.msg())
		exit(1)
	}
	match command {
		'sync-codex' {
			cfg := storage.ChunkConfig.default().with_split_backed_working_set(has_flag(args, '--split-backed'))
			options := agentview.SyncOptions{
				batch_sessions: parse_flag_int(args, '--batch-sessions', 8)
			}
			stats := store.sync_codex_with_options_and_progress_and_config(codex_root, options,
				sync_progress_compact_to_stderr, cfg) or {
				eprintln(err.msg())
				exit(1)
			}
			if stats.paused_for_resume {
				println('sync paused processed=${stats.processed_sessions}/${stats.total_sessions} imported=${stats.sessions} entries=${stats.entries} skipped=${stats.skipped} resume_after=${stats.resume_session_id} store=${store_root}')
			} else {
				println('synced sessions=${stats.sessions} entries=${stats.entries} skipped=${stats.skipped} processed=${stats.processed_sessions}/${stats.total_sessions} store=${store_root}')
			}
		}
		'index-search' {
			cfg := storage.ChunkConfig.default().with_split_backed_working_set(has_flag(args, '--split-backed'))
			stats := store.ensure_search_indexes_with_progress_and_config(search_index_progress_to_stderr, cfg) or {
				eprintln(err.msg())
				exit(1)
			}
			if stats.changed {
				if stats.rebuild_ms > 0 {
					println('search indexes rebuilt store=${store_root} scanned=${stats.rows_scanned} backfilled=${stats.rows_backfilled} backfill=${stats.backfill_ms}ms rebuild=${stats.rebuild_ms}ms total=${stats.total_ms}ms')
				} else {
					println('search index updated store=${store_root} scanned=${stats.rows_scanned} backfilled=${stats.rows_backfilled} backfill=${stats.backfill_ms}ms total=${stats.total_ms}ms')
				}
			} else {
				println('search indexes already up to date store=${store_root} scanned=${stats.rows_scanned} backfilled=${stats.rows_backfilled} total=${stats.total_ms}ms')
			}
		}
		'sessions' {
			request := agentview.SessionListRequest{
				limit: parse_limit(args, 20)
				offset: parse_flag_int(args, '--offset', 0)
				query: parse_flag_value(args, '--query')
				cwd_prefix: parse_flag_value(args, '--cwd-prefix')
				source: parse_flag_value(args, '--source')
				include_archived: !has_flag(args, '--no-archived')
			}
			result := store.list_sessions_page(request) or {
				eprintln(err.msg())
				exit(1)
			}
			eprintln('sessions total=${result.total} offset=${request.offset} limit=${request.limit}')
			for session in result.sessions {
				println('${session.id} | ${session.updated_at} | ${session.title} | cwd=${session.cwd} | entries=${session.entry_count} | tools=${session.tool_calls}')
			}
		}
		'show' {
			if args.len < 2 {
				eprintln('show requires <session_id>')
				exit(1)
			}
			request := agentview.TranscriptRequest{
				session_id: args[1]
				offset: parse_flag_int(args, '--offset', 0)
				limit: parse_flag_int(args, '--limit', 200)
			}
			transcript := store.load_transcript_page(request) or {
				eprintln(err.msg())
				exit(1)
			}
			println('session=${transcript.summary.id}')
			println('title=${transcript.summary.title}')
			println('updated_at=${transcript.summary.updated_at}')
			println('cwd=${transcript.summary.cwd}')
			println('path=${transcript.summary.path}')
			println('entries=${transcript.total_entries} offset=${request.offset} limit=${request.limit}')
			println('')
			for entry in transcript.entries {
				label := left_pad('${entry.seq}', 4)
				mut head := '${label} [${entry.timestamp}] ${entry.kind.str()}'
				if entry.role.len > 0 {
					head += ' role=${entry.role}'
				}
				if entry.tool_name.len > 0 {
					head += ' tool=${entry.tool_name}'
				}
				println(head)
				if entry.text.len > 0 {
					println(entry.text)
				}
				println('')
			}
		}
		'search' {
			if args.len < 2 {
				eprintln('search requires <query>')
				exit(1)
			}
			request := agentview.SearchRequest{
				query: args[1]
				session_id: parse_flag_value(args, '--session-id')
				cwd_prefix: parse_flag_value(args, '--cwd-prefix')
				source: parse_flag_value(args, '--source')
				kind: parse_flag_value(args, '--kind')
				limit: parse_limit(args, 20)
				offset: parse_flag_int(args, '--offset', 0)
			}
			result := store.search_entries(request) or {
				eprintln(err.msg())
				exit(1)
			}
			eprintln('hits total=${result.total} offset=${request.offset} limit=${request.limit}')
			for hit in result.hits {
				println('${hit.session_id}#${hit.entry_seq} | ${hit.timestamp} | ${hit.session_title}')
				mut meta := []string{}
				if hit.session_source.len > 0 {
					meta << hit.session_source
				}
				if hit.session_cwd.len > 0 {
					meta << 'cwd=${hit.session_cwd}'
				}
				if meta.len > 0 {
					println(meta.join(' | '))
				}
				println(hit.snippet)
				println('')
			}
		}
		'memory' {
			run_memory_command(args, store) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'context' {
			run_context_command(args, store) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'browse' {
			agentview.browse_store(store, agentview.BrowserOptions{
				query: parse_flag_value(args, '--query')
				cwd_prefix: parse_flag_value(args, '--cwd-prefix')
				source: parse_flag_value(args, '--source')
				include_archived: !has_flag(args, '--no-archived')
				list_limit: parse_flag_int(args, '--list-limit', 100)
				transcript_limit: parse_flag_int(args, '--transcript-limit', 40)
			}) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		else {
			eprintln('unknown command: ${command}')
			eprintln(usage())
			exit(1)
		}
	}
}

fn usage() string {
	return 'agentview sync-codex [--codex-root <path>] [--store-root <path>] [--split-backed] [--batch-sessions N]\n'
		+ 'agentview index-search [--store-root <path>] [--split-backed]\n'
		+ 'agentview bench-codex [--codex-root <path>] [--store-root <path>] [--split-backed]\n'
		+ 'agentview bench-codex-delta [--codex-root <path>] [--store-root <path>] [--split-backed] [--sessions N] [--mutate N]\n'
		+ 'agentview bench-codex-index-delta [--codex-root <path>] [--store-root <path>] [--split-backed] [--sessions N] [--mutate N]\n'
		+ 'agentview bench-write-path [--existing N] [--ops N] [--rounds N] [--mode insert|update|delete|mixed] [--indexes N] [--partition auto|off|force]\n'
		+ 'agentview bench-write-layout [--existing N] [--ops N] [--rounds N] [--mode insert|update|delete|mixed] [--indexes N] [--partition auto|off|force]\n'
		+ 'agentview bench-tree-build [--items N] [--rounds N]\n'
		+ 'agentview bench-split-materialize [--existing N] [--indexes N] [--rounds N]\n'
		+ 'agentview bench-write-matrix [--existing N] [--ops N] [--rounds N] [--partition auto|off|force]\n'
		+ 'agentview explain-browser [--query TEXT] [--cwd-prefix PATH] [--source NAME] [--no-archived] [--session-id ID] [--search TEXT] [--kind KIND] [--store-root <path>]\n'
		+ 'agentview bench-browser [--query TEXT] [--cwd-prefix PATH] [--source NAME] [--no-archived] [--session-id ID] [--search TEXT] [--kind KIND] [--rounds N] [--store-root <path>]\n'
		+ 'agentview sessions [limit] [--offset N] [--query TEXT] [--cwd-prefix PATH] [--source NAME] [--no-archived] [--store-root <path>]\n'
		+ 'agentview show <session_id> [--offset N] [--limit N] [--store-root <path>]\n'
		+ 'agentview search <query> [limit] [--offset N] [--session-id ID] [--cwd-prefix PATH] [--source NAME] [--kind KIND] [--store-root <path>]\n'
		+ 'agentview browse [--query TEXT] [--cwd-prefix PATH] [--source NAME] [--no-archived] [--list-limit N] [--transcript-limit N] [--store-root <path>]\n'
		+ 'agentview memory list [--query TEXT] [--limit N] [--offset N] [--include-superseded] [--store-root <path>]\n'
		+ 'agentview memory search <query> [--limit N] [--offset N] [--include-superseded] [--store-root <path>]\n'
		+ 'agentview memory context <query> [--limit N] [--sources] [--store-root <path>]\n'
		+ 'agentview memory preview [--recent-sessions N] [--max-jobs N] [--neighbor-limit N] [--candidate-limit N] [--candidate-offset N] [--store-root <path>]\n'
		+ 'agentview memory distill [--recent-sessions N] [--max-jobs N] [--neighbor-limit N] [--candidate-limit N] [--candidate-offset N] [--store-root <path>]\n'
		+ 'agentview context <query> [--limit N] [--sources] [--store-root <path>]\n'
		+ 'default codex root: ~/.codex\n'
		+ 'default store root: ~/.agentview/pollydb\n'
		+ 'note: sessions/show/search/browse will auto-sync from ~/.codex when the store is empty\n'
		+ 'note: sync-codex now checkpoints in small batches by default; use --batch-sessions to tune resume-safe imports\n'
		+ 'note: sync-codex builds base indexes first; run index-search to add general FTS search indexes\n'
		+ 'note: bench-write-path measures synthetic typed fallback writes without reading ~/.codex\n'
		+ 'note: bench-write-layout compares mixed apply against apply+split-materialize for the same synthetic workload\n'
		+ 'note: bench-tree-build measures tree construction without typed schema/index maintenance\n'
		+ 'note: bench-split-materialize measures converting one mixed typed tree into split row/index trees\n'
		+ 'note: bench-write-matrix runs insert/update/delete/mixed across index-count presets\n'
		+ 'note: explain-browser shows whether browser list/transcript/search use indexes or scans\n'
		+ 'note: bench-browser measures the real browser-facing list/transcript/search calls against your store\n'
		+ 'note: memory preview/distill require -d llama_cpp and POLLYDB_MEMORY_EMBEDDING_MODEL; set POLLYDB_MEMORY_FAST_DISTILL=1 for heuristic text generation'
}

fn run_memory_command(args []string, store agentview.PollyDbStore) ! {
	subcommand := if args.len > 1 { args[1] } else { 'list' }
	match subcommand {
		'list' {
			result := store.list_memory(agentview.MemoryListRequest{
				query: parse_flag_value(args, '--query')
				limit: parse_limit(args, 20)
				offset: parse_flag_int(args, '--offset', 0)
				include_superseded: has_flag(args, '--include-superseded')
			})!
			print_memory_list(result)
		}
		'search' {
			query := memory_query_arg(args)!
			result := store.list_memory(agentview.MemoryListRequest{
				query: query
				limit: parse_limit(args, 20)
				offset: parse_flag_int(args, '--offset', 0)
				include_superseded: has_flag(args, '--include-superseded')
			})!
			print_memory_list(result)
		}
		'context' {
			query := memory_query_arg(args)!
			context := store.memory_context(agentview.MemoryContextRequest{
				query: query
				limit: parse_limit(args, 6)
				include_sources: has_flag(args, '--sources')
			})!
			print(context.markdown)
		}
		'preview' {
			run_memory_preview(args, store)!
		}
		'distill' {
			run_memory_distill(args, store)!
		}
		else {
			return error('unknown memory command: ${subcommand}; expected list|search|context|preview|distill')
		}
	}
}

fn run_memory_preview(args []string, store agentview.PollyDbStore) ! {
	$if llama_cpp ? {
		embedding_model_path := memory_embedding_model_path()!
		mut embedding_engine := memory.new_llama_embedding_engine(memory.LlamaEmbeddingConfig{
			model_path:   embedding_model_path
			n_ctx:        512
			n_batch:      512
			n_gpu_layers: 0
		})!
		defer {
			embedding_engine.close()
		}
		options := memory_distill_options_from_args(args)
		mut previews := []agentview.MemoryDistillPreviewCard{}
		if memory_use_heuristic_distill() {
			previews = store.preview_recent_memory_heuristic(mut embedding_engine, options)!
		} else {
			generation_model_path := memory_generation_model_path()!
			mut generator := memory.new_llama_generation_engine(memory.LlamaGenerationConfig{
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
			previews = store.preview_recent_memory(mut embedding_engine, mut generator, options)!
		}
		print_memory_preview(previews)
	} $else {
		return error('agentview memory preview requires a binary built with `-d llama_cpp`')
	}
}

fn run_memory_distill(args []string, store agentview.PollyDbStore) ! {
	$if llama_cpp ? {
		embedding_model_path := memory_embedding_model_path()!
		mut embedding_engine := memory.new_llama_embedding_engine(memory.LlamaEmbeddingConfig{
			model_path:   embedding_model_path
			n_ctx:        512
			n_batch:      512
			n_gpu_layers: 0
		})!
		defer {
			embedding_engine.close()
		}
		options := memory_distill_options_from_args(args)
		mut persisted := []memory.PersistedReflection{}
		if memory_use_heuristic_distill() {
			persisted = store.distill_recent_memory_heuristic(mut embedding_engine, options)!
		} else {
			generation_model_path := memory_generation_model_path()!
			mut generator := memory.new_llama_generation_engine(memory.LlamaGenerationConfig{
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
			persisted = store.distill_recent_memory(mut embedding_engine, mut generator, options)!
		}
		print_memory_distill_result(persisted)
	} $else {
		return error('agentview memory distill requires a binary built with `-d llama_cpp`')
	}
}

fn run_context_command(args []string, store agentview.PollyDbStore) ! {
	if args.len < 2 && parse_flag_value(args, '--query').len == 0 {
		return error('context requires <query>')
	}
	query := if parse_flag_value(args, '--query').len > 0 {
		parse_flag_value(args, '--query')
	} else {
		args[1]
	}
	context := store.memory_context(agentview.MemoryContextRequest{
		query: query
		limit: parse_limit(args, 6)
		include_sources: has_flag(args, '--sources')
	})!
	print(context.markdown)
}

fn memory_query_arg(args []string) !string {
	flag_query := parse_flag_value(args, '--query')
	if flag_query.len > 0 {
		return flag_query
	}
	if args.len > 2 {
		return args[2]
	}
	return error('memory ${if args.len > 1 { args[1] } else { '' }} requires <query> or --query')
}

fn print_memory_list(result agentview.MemoryListResult) {
	eprintln('memories total=${result.total} strategy=${result.strategy}')
	for card in result.memories {
		active := if card.active { 'active' } else { 'superseded' }
		score := if card.score > 0 { ' score=${card.score}' } else { '' }
		println('${card.reflection_id} | ${active}${score} | ${card.created_at} | sources=${card.source_count}')
		println(card.title)
		summary := first_memory_summary_line(card.summary_md)
		if summary.len > 0 {
			println(summary)
		}
		if card.topic_key.len > 0 {
			println('topic=${card.topic_key}')
		}
		if card.supersedes_reflection_id.len > 0 {
			println('supersedes=${card.supersedes_reflection_id}')
		}
		println('')
	}
}

fn print_memory_preview(previews []agentview.MemoryDistillPreviewCard) {
	mut keep_count := 0
	mut discard_count := 0
	mut discard_reasons := map[string]int{}
	for preview in previews {
		if preview.decision.keep {
			keep_count++
		} else {
			discard_count++
			reason := if preview.decision.reason.len > 0 { preview.decision.reason } else { 'discard' }
			discard_reasons[reason] = discard_reasons[reason] + 1
		}
	}
	println('memory_preview cards=${previews.len} keep=${keep_count} discard=${discard_count} discard_reasons=${format_memory_counts(discard_reasons)}')
	for preview in previews {
		println('')
		println('action=${preview.write_plan.action} reason=${preview.write_plan.reason} score=${preview.write_plan.score} confidence=${preview.write_plan.trace.confidence}')
		println('title=${preview.title}')
		println('topic=${preview.topic_key} evidence=${preview.evidence_count} supersedes=${preview.supersedes_id}')
		println('signals=${preview.write_plan.trace.signals.join(',')} blockers=${preview.write_plan.trace.blockers.join(',')}')
		println('inference=${preview.write_plan.trace.inference}')
		if preview.write_plan.action == 'discard' {
			println('discarded candidate; no memory card will be written')
			continue
		}
		println('')
		println(preview.summary_md.trim_space())
		if preview.insight_md.trim_space().len > 0 {
			println('')
			println(preview.insight_md.trim_space())
		}
	}
}

fn print_memory_distill_result(persisted []memory.PersistedReflection) {
	println('memory_distill reflections=${persisted.len}')
	if persisted.len == 0 {
		println('no new reflections')
		return
	}
	for reflection in persisted {
		println('')
		println('id=${reflection.reflection_id} kind=${reflection.reflection_kind} topic=${reflection.topic_key} sources=${reflection.source_refs.len}')
		if reflection.supersedes_reflection_id.len > 0 {
			println('supersedes=${reflection.supersedes_reflection_id}')
		}
		println('title=${reflection.title}')
		println('')
		println(reflection.summary_md.trim_space())
		if reflection.insight_md.trim_space().len > 0 {
			println('')
			println(reflection.insight_md.trim_space())
		}
	}
}

fn format_memory_counts(counts map[string]int) string {
	if counts.len == 0 {
		return '{}'
	}
	mut keys := []string{cap: counts.len}
	for key, _ in counts {
		keys << key
	}
	keys.sort()
	mut parts := []string{cap: keys.len}
	for key in keys {
		parts << '${key}:${counts[key]}'
	}
	return parts.join(',')
}

fn first_memory_summary_line(summary_md string) string {
	for line in summary_md.split_into_lines() {
		cleaned := line.trim_space()
		if cleaned.len == 0 || cleaned.starts_with('#') {
			continue
		}
		return cleaned
	}
	return ''
}

fn memory_distill_options_from_args(args []string) agentview.MemoryDistillOptions {
	max_jobs := parse_flag_int(args, '--max-jobs', 4)
	return agentview.MemoryDistillOptions{
		recent_sessions:  parse_flag_int(args, '--recent-sessions', 64)
		max_jobs:         max_jobs
		neighbor_limit:   parse_flag_int(args, '--neighbor-limit', 8)
		min_evidence:     parse_flag_int(args, '--min-evidence', 1)
		candidate_limit:  parse_flag_int(args, '--candidate-limit', max_jobs * 16)
		candidate_offset: parse_flag_int(args, '--candidate-offset', 0)
	}
}

fn memory_use_heuristic_distill() bool {
	return os.getenv('POLLYDB_MEMORY_FAST_DISTILL').trim_space() in ['1', 'true', 'yes']
}

fn memory_embedding_model_path() !string {
	model_path := os.getenv('POLLYDB_MEMORY_EMBEDDING_MODEL').trim_space()
	if model_path.len == 0 {
		return error('missing embedding model path; set POLLYDB_MEMORY_EMBEDDING_MODEL')
	}
	return model_path
}

fn memory_generation_model_path() !string {
	model_path := os.getenv('POLLYDB_MEMORY_GENERATION_MODEL').trim_space()
	if model_path.len == 0 {
		return error('missing generation model path; set POLLYDB_MEMORY_GENERATION_MODEL or POLLYDB_MEMORY_FAST_DISTILL=1')
	}
	return model_path
}

fn run_explain_browser(args []string) ! {
	store_root := resolve_store_root(args)
	store := agentview.PollyDbStore.open(store_root)!
	session_request := agentview.SessionListRequest{
		limit: 20
		query: parse_flag_value(args, '--query')
		cwd_prefix: parse_flag_value(args, '--cwd-prefix')
		source: parse_flag_value(args, '--source')
		include_archived: !has_flag(args, '--no-archived')
	}
	transcript_request := agentview.TranscriptRequest{
		session_id: parse_flag_value(args, '--session-id')
		limit: 40
	}
	search_request := agentview.SearchRequest{
		query: parse_flag_value(args, '--search')
		session_id: parse_flag_value(args, '--session-id')
		cwd_prefix: parse_flag_value(args, '--cwd-prefix')
		source: parse_flag_value(args, '--source')
		kind: parse_flag_value(args, '--kind')
		limit: 20
	}
	explain := store.explain_browser_queries(session_request, transcript_request, search_request)!
	println('sessions: strategy=${explain.sessions.strategy} index=${explain.sessions.index_name}')
	for note in explain.sessions.notes {
		println('  - ${note}')
	}
	println('transcript: strategy=${explain.transcript.strategy} index=${explain.transcript.index_name}')
	for note in explain.transcript.notes {
		println('  - ${note}')
	}
	println('search: strategy=${explain.search.strategy} index=${explain.search.index_name}')
	for note in explain.search.notes {
		println('  - ${note}')
	}
}

fn run_bench_browser(args []string) ! {
	store_root := resolve_store_root(args)
	store := agentview.PollyDbStore.open(store_root)!
	mut browser_session := store.begin_browser_session()!
	defer {
		browser_session.close() or {}
	}
	rounds := parse_flag_int(args, '--rounds', 5)
	session_request := agentview.SessionListRequest{
		limit: 50
		query: parse_flag_value(args, '--query')
		cwd_prefix: parse_flag_value(args, '--cwd-prefix')
		source: parse_flag_value(args, '--source')
		include_archived: !has_flag(args, '--no-archived')
	}
	transcript_request := agentview.TranscriptRequest{
		session_id: parse_flag_value(args, '--session-id')
		limit: 40
	}
	search_request := agentview.SearchRequest{
		query: parse_flag_value(args, '--search')
		session_id: parse_flag_value(args, '--session-id')
		cwd_prefix: parse_flag_value(args, '--cwd-prefix')
		source: parse_flag_value(args, '--source')
		kind: parse_flag_value(args, '--kind')
		limit: 20
	}
	mut sessions_ms := i64(0)
	mut sessions_open_ms := i64(0)
	mut sessions_open_backends_ms := i64(0)
	mut sessions_open_catalog_ms := i64(0)
	mut sessions_open_engine_ms := i64(0)
	mut sessions_open_replay_ms := i64(0)
	mut sessions_open_repo_meta_ms := i64(0)
	mut sessions_open_node_ms := i64(0)
	mut sessions_open_commit_ms := i64(0)
	mut sessions_begin_ms := i64(0)
	mut sessions_query_plan_ms := i64(0)
	mut sessions_query_normalize_ms := i64(0)
	mut sessions_query_fetch_ms := i64(0)
	mut sessions_query_fetch_begin_tx_ms := i64(0)
	mut sessions_query_fetch_begin_checkout_ms := i64(0)
	mut sessions_query_fetch_begin_tree_load_ms := i64(0)
	mut sessions_query_fetch_begin_wrap_ms := i64(0)
	mut sessions_query_fetch_view_ms := i64(0)
	mut sessions_query_fetch_scan_ms := i64(0)
	mut sessions_query_fetch_scan_nodes := 0
	mut sessions_query_fetch_scan_leaves := 0
	mut sessions_query_fetch_scan_items := 0
	mut sessions_query_filter_ms := i64(0)
	mut sessions_query_project_ms := i64(0)
	mut sessions_query_continuation_ms := i64(0)
	mut transcript_ms := i64(0)
	mut transcript_open_ms := i64(0)
	mut transcript_open_backends_ms := i64(0)
	mut transcript_open_catalog_ms := i64(0)
	mut transcript_open_engine_ms := i64(0)
	mut transcript_open_replay_ms := i64(0)
	mut transcript_open_repo_meta_ms := i64(0)
	mut transcript_open_node_ms := i64(0)
	mut transcript_open_commit_ms := i64(0)
	mut transcript_begin_ms := i64(0)
	mut transcript_summary_ms := i64(0)
	mut transcript_index_ms := i64(0)
	mut transcript_decode_ms := i64(0)
	mut transcript_order_ms := i64(0)
	mut transcript_markdown_ms := i64(0)
	mut search_ms := i64(0)
	mut search_open_ms := i64(0)
	mut search_open_backends_ms := i64(0)
	mut search_open_catalog_ms := i64(0)
	mut search_open_engine_ms := i64(0)
	mut search_open_replay_ms := i64(0)
	mut search_open_repo_meta_ms := i64(0)
	mut search_open_node_ms := i64(0)
	mut search_open_commit_ms := i64(0)
	mut search_begin_ms := i64(0)
	mut search_session_summary_ms := i64(0)
	mut search_fts_ms := i64(0)
	mut search_filter_rank_ms := i64(0)
	mut search_paginate_ms := i64(0)
	for _ in 0 .. rounds {
		session_execution := browser_session.list_sessions_page_explained(session_request)!
		sessions_ms += session_execution.total_ms
		sessions_open_ms += session_execution.open_ms
		sessions_open_backends_ms += session_execution.open_backends_ms
		sessions_open_catalog_ms += session_execution.open_catalog_ms
		sessions_open_engine_ms += session_execution.open_engine_ms
		sessions_open_replay_ms += session_execution.open_replay_journal_ms
		sessions_open_repo_meta_ms += session_execution.open_repo_meta_ms
		sessions_open_node_ms += session_execution.open_node_store_ms
		sessions_open_commit_ms += session_execution.open_commit_store_ms
		sessions_begin_ms += session_execution.session_ms
		sessions_query_plan_ms += session_execution.query.plan_ms
		sessions_query_normalize_ms += session_execution.query.normalize_ms
		sessions_query_fetch_ms += session_execution.query.fetch_ms
		sessions_query_fetch_begin_tx_ms += session_execution.query.fetch_begin_tx_ms
		sessions_query_fetch_begin_checkout_ms += session_execution.query.fetch_begin_checkout_ms
		sessions_query_fetch_begin_tree_load_ms += session_execution.query.fetch_begin_tree_load_ms
		sessions_query_fetch_begin_wrap_ms += session_execution.query.fetch_begin_wrap_ms
		sessions_query_fetch_view_ms += session_execution.query.fetch_view_ms
		sessions_query_fetch_scan_ms += session_execution.query.fetch_scan_ms
		sessions_query_fetch_scan_nodes += session_execution.query.fetch_scan_nodes
		sessions_query_fetch_scan_leaves += session_execution.query.fetch_scan_leaves
		sessions_query_fetch_scan_items += session_execution.query.fetch_scan_items
		sessions_query_filter_ms += session_execution.query.filter_ms
		sessions_query_project_ms += session_execution.query.project_ms
		sessions_query_continuation_ms += session_execution.query.continuation_ms
		if transcript_request.session_id.len > 0 {
			transcript_execution := browser_session.load_transcript_page_explained(transcript_request)!
			transcript_ms += transcript_execution.total_ms
			transcript_open_ms += transcript_execution.open_ms
			transcript_open_backends_ms += transcript_execution.open_backends_ms
			transcript_open_catalog_ms += transcript_execution.open_catalog_ms
			transcript_open_engine_ms += transcript_execution.open_engine_ms
			transcript_open_replay_ms += transcript_execution.open_replay_journal_ms
			transcript_open_repo_meta_ms += transcript_execution.open_repo_meta_ms
			transcript_open_node_ms += transcript_execution.open_node_store_ms
			transcript_open_commit_ms += transcript_execution.open_commit_store_ms
			transcript_begin_ms += transcript_execution.session_ms
			transcript_summary_ms += transcript_execution.summary_lookup_ms
			transcript_index_ms += transcript_execution.index_lookup_ms
			transcript_decode_ms += transcript_execution.decode_ms
			transcript_order_ms += transcript_execution.order_ms
			transcript_markdown_ms += transcript_execution.markdown_ms
		}
		if search_request.query.len > 0 {
			search_execution := browser_session.search_entries_explained(search_request)!
			search_ms += search_execution.total_ms
			search_open_ms += search_execution.open_ms
			search_open_backends_ms += search_execution.open_backends_ms
			search_open_catalog_ms += search_execution.open_catalog_ms
			search_open_engine_ms += search_execution.open_engine_ms
			search_open_replay_ms += search_execution.open_replay_journal_ms
			search_open_repo_meta_ms += search_execution.open_repo_meta_ms
			search_open_node_ms += search_execution.open_node_store_ms
			search_open_commit_ms += search_execution.open_commit_store_ms
			search_begin_ms += search_execution.session_ms
			search_session_summary_ms += search_execution.session_summary_ms
			search_fts_ms += search_execution.fts_lookup_ms
			search_filter_rank_ms += search_execution.filter_rank_ms
			search_paginate_ms += search_execution.paginate_ms
		}
	}
	divisor := if rounds > 0 { i64(rounds) } else { i64(1) }
	println('browser bench store=${store_root} rounds=${rounds}')
	println('sessions avg=${sessions_ms / divisor}ms')
	println('sessions breakdown open=${sessions_open_ms / divisor}ms backends=${sessions_open_backends_ms / divisor}ms catalog=${sessions_open_catalog_ms / divisor}ms engine=${sessions_open_engine_ms / divisor}ms replay=${sessions_open_replay_ms / divisor}ms repo_meta=${sessions_open_repo_meta_ms / divisor}ms node=${sessions_open_node_ms / divisor}ms commit=${sessions_open_commit_ms / divisor}ms begin=${sessions_begin_ms / divisor}ms plan=${sessions_query_plan_ms / divisor}ms normalize=${sessions_query_normalize_ms / divisor}ms fetch=${sessions_query_fetch_ms / divisor}ms fetch_begin_tx=${sessions_query_fetch_begin_tx_ms / divisor}ms fetch_checkout=${sessions_query_fetch_begin_checkout_ms / divisor}ms fetch_tree_load=${sessions_query_fetch_begin_tree_load_ms / divisor}ms fetch_wrap=${sessions_query_fetch_begin_wrap_ms / divisor}ms fetch_view=${sessions_query_fetch_view_ms / divisor}ms fetch_scan=${sessions_query_fetch_scan_ms / divisor}ms fetch_scan_nodes=${sessions_query_fetch_scan_nodes / rounds} fetch_scan_leaves=${sessions_query_fetch_scan_leaves / rounds} fetch_scan_items=${sessions_query_fetch_scan_items / rounds} filter=${sessions_query_filter_ms / divisor}ms project=${sessions_query_project_ms / divisor}ms continuation=${sessions_query_continuation_ms / divisor}ms')
	if transcript_request.session_id.len > 0 {
		println('transcript avg=${transcript_ms / divisor}ms session=${transcript_request.session_id}')
		println('transcript breakdown open=${transcript_open_ms / divisor}ms backends=${transcript_open_backends_ms / divisor}ms catalog=${transcript_open_catalog_ms / divisor}ms engine=${transcript_open_engine_ms / divisor}ms replay=${transcript_open_replay_ms / divisor}ms repo_meta=${transcript_open_repo_meta_ms / divisor}ms node=${transcript_open_node_ms / divisor}ms commit=${transcript_open_commit_ms / divisor}ms begin=${transcript_begin_ms / divisor}ms summary=${transcript_summary_ms / divisor}ms index=${transcript_index_ms / divisor}ms decode=${transcript_decode_ms / divisor}ms order=${transcript_order_ms / divisor}ms markdown=${transcript_markdown_ms / divisor}ms')
	}
	if search_request.query.len > 0 {
		println('search avg=${search_ms / divisor}ms query=${search_request.query}')
		println('search breakdown open=${search_open_ms / divisor}ms backends=${search_open_backends_ms / divisor}ms catalog=${search_open_catalog_ms / divisor}ms engine=${search_open_engine_ms / divisor}ms replay=${search_open_replay_ms / divisor}ms repo_meta=${search_open_repo_meta_ms / divisor}ms node=${search_open_node_ms / divisor}ms commit=${search_open_commit_ms / divisor}ms begin=${search_begin_ms / divisor}ms session_summary=${search_session_summary_ms / divisor}ms fts=${search_fts_ms / divisor}ms filter_rank=${search_filter_rank_ms / divisor}ms paginate=${search_paginate_ms / divisor}ms')
	}
}

fn run_bench_codex(args []string) ! {
	codex_root := resolve_codex_root(args)
	cfg := storage.ChunkConfig.default().with_detailed_timings(true).with_split_backed_working_set(has_flag(args, '--split-backed'))
	store_root := if has_flag(args, '--store-root') {
		resolve_store_root(args)
	} else {
		normalize_cli_path(os.join_path(os.vtmp_dir(), 'agentview-bench-${time.now().unix_micro()}'))
	}
	os.rmdir_all(store_root) or {}
	os.mkdir_all(store_root)!
	eprintln('bench start codex_root=${codex_root} store=${store_root}')
	mut store := agentview.PollyDbStore.open(store_root)!
	eprintln('bench phase=sync-first')
	sync_first := store.sync_codex_with_progress_and_config(codex_root, sync_progress_detailed_to_stderr, cfg)!
	state_after_sync_first := bench_store_state_counts(store_root) or { BenchStoreStateCounts{} }
	eprintln('bench phase=index-first')
	index_first := store.ensure_search_indexes_with_progress_and_config(search_index_progress_to_stderr, cfg)!
	state_after_index_first := bench_store_state_counts(store_root) or { BenchStoreStateCounts{} }
	eprintln('bench phase=reopen')
	store = agentview.PollyDbStore.open(store_root)!
	eprintln('bench phase=sync-second')
	sync_second := store.sync_codex_with_progress_and_config(codex_root, sync_progress_detailed_to_stderr, cfg)!
	state_after_sync_second := bench_store_state_counts(store_root) or { BenchStoreStateCounts{} }
	eprintln('bench phase=index-second')
	index_second := store.ensure_search_indexes_with_progress_and_config(search_index_progress_to_stderr, cfg)!
	state_after_index_second := bench_store_state_counts(store_root) or { BenchStoreStateCounts{} }
	eprintln('bench done store=${store_root}')
	println('bench store=${store_root}')
	println('sync first sessions=${sync_first.sessions} entries=${sync_first.entries} skipped=${sync_first.skipped} read=${sync_first.read_ms}ms build=${sync_first.build_ms}ms apply=${sync_first.apply_ms}ms tx=${sync_first.tx_ms}ms aggregate=${sync_first.aggregate_ms}ms fast=${sync_first.fast_update_ms}ms fast_can=${sync_first.fast_update_can_ms}ms fast_path=${sync_first.fast_update_path_ms}ms fast_encode=${sync_first.fast_update_encode_ms}ms fast_replace=${sync_first.fast_update_replace_ms}ms fallback=${sync_first.fallback_ms}ms fallback_items=${sync_first.fallback_items_ms}ms fallback_items_key=${sync_first.fallback_items_key_ms}ms fallback_items_fill=${sync_first.fallback_items_fill_ms}ms fallback_ops=${sync_first.fallback_ops_ms}ms fallback_ops_key=${sync_first.fallback_ops_key_ms}ms fallback_ops_lookup=${sync_first.fallback_ops_lookup_ms}ms fallback_ops_encode=${sync_first.fallback_ops_encode_ms}ms fallback_ops_state=${sync_first.fallback_ops_state_ms}ms fallback_ops_state_new_key=${sync_first.fallback_ops_state_new_key_ms}ms fallback_ops_state_item=${sync_first.fallback_ops_state_item_ms}ms fallback_ops_state_cache=${sync_first.fallback_ops_state_cache_ms}ms fallback_ops_index=${sync_first.fallback_ops_index_ms}ms fallback_build=${sync_first.fallback_build_ms}ms fallback_build_prepare=${sync_first.fallback_build_prepare_ms}ms fallback_build_prepare_keys=${sync_first.fallback_build_prepare_keys_ms}ms fallback_build_prepare_keys_sort=${sync_first.fallback_build_prepare_keys_sort_ms}ms fallback_build_prepare_keys_merge=${sync_first.fallback_build_prepare_keys_merge_ms}ms fallback_build_prepare_rows=${sync_first.fallback_build_prepare_rows_ms}ms fallback_build_prepare_rows_key=${sync_first.fallback_build_prepare_rows_key_ms}ms fallback_build_prepare_rows_value=${sync_first.fallback_build_prepare_rows_value_ms}ms fallback_build_leaf=${sync_first.fallback_build_leaf_ms}ms fallback_build_leaf_chunk=${sync_first.fallback_build_leaf_chunk_ms}ms fallback_build_leaf_node=${sync_first.fallback_build_leaf_node_ms}ms fallback_build_leaf_node_serialize=${sync_first.fallback_build_leaf_node_serialize_ms}ms fallback_build_leaf_node_cid=${sync_first.fallback_build_leaf_node_cid_ms}ms fallback_build_leaf_node_add=${sync_first.fallback_build_leaf_node_add_ms}ms fallback_build_internal=${sync_first.fallback_build_internal_ms}ms commit=${sync_first.commit_ms}ms checkpoint=${sync_first.checkpoint_ms}ms flush=${sync_first.flush_ms}ms finish=${sync_first.finish_ms}ms total=${sync_first.total_ms}ms')
	println('sync second sessions=${sync_second.sessions} entries=${sync_second.entries} skipped=${sync_second.skipped} read=${sync_second.read_ms}ms build=${sync_second.build_ms}ms apply=${sync_second.apply_ms}ms tx=${sync_second.tx_ms}ms aggregate=${sync_second.aggregate_ms}ms fast=${sync_second.fast_update_ms}ms fast_can=${sync_second.fast_update_can_ms}ms fast_path=${sync_second.fast_update_path_ms}ms fast_encode=${sync_second.fast_update_encode_ms}ms fast_replace=${sync_second.fast_update_replace_ms}ms fallback=${sync_second.fallback_ms}ms fallback_items=${sync_second.fallback_items_ms}ms fallback_items_key=${sync_second.fallback_items_key_ms}ms fallback_items_fill=${sync_second.fallback_items_fill_ms}ms fallback_ops=${sync_second.fallback_ops_ms}ms fallback_ops_key=${sync_second.fallback_ops_key_ms}ms fallback_ops_lookup=${sync_second.fallback_ops_lookup_ms}ms fallback_ops_encode=${sync_second.fallback_ops_encode_ms}ms fallback_ops_state=${sync_second.fallback_ops_state_ms}ms fallback_ops_state_new_key=${sync_second.fallback_ops_state_new_key_ms}ms fallback_ops_state_item=${sync_second.fallback_ops_state_item_ms}ms fallback_ops_state_cache=${sync_second.fallback_ops_state_cache_ms}ms fallback_ops_index=${sync_second.fallback_ops_index_ms}ms fallback_build=${sync_second.fallback_build_ms}ms fallback_build_prepare=${sync_second.fallback_build_prepare_ms}ms fallback_build_prepare_keys=${sync_second.fallback_build_prepare_keys_ms}ms fallback_build_prepare_keys_sort=${sync_second.fallback_build_prepare_keys_sort_ms}ms fallback_build_prepare_keys_merge=${sync_second.fallback_build_prepare_keys_merge_ms}ms fallback_build_prepare_rows=${sync_second.fallback_build_prepare_rows_ms}ms fallback_build_prepare_rows_key=${sync_second.fallback_build_prepare_rows_key_ms}ms fallback_build_prepare_rows_value=${sync_second.fallback_build_prepare_rows_value_ms}ms fallback_build_leaf=${sync_second.fallback_build_leaf_ms}ms fallback_build_leaf_chunk=${sync_second.fallback_build_leaf_chunk_ms}ms fallback_build_leaf_node=${sync_second.fallback_build_leaf_node_ms}ms fallback_build_leaf_node_serialize=${sync_second.fallback_build_leaf_node_serialize_ms}ms fallback_build_leaf_node_cid=${sync_second.fallback_build_leaf_node_cid_ms}ms fallback_build_leaf_node_add=${sync_second.fallback_build_leaf_node_add_ms}ms fallback_build_internal=${sync_second.fallback_build_internal_ms}ms commit=${sync_second.commit_ms}ms checkpoint=${sync_second.checkpoint_ms}ms flush=${sync_second.flush_ms}ms finish=${sync_second.finish_ms}ms total=${sync_second.total_ms}ms')
	println('index first changed=${index_first.changed} scanned=${index_first.rows_scanned} backfilled=${index_first.rows_backfilled} backfill=${index_first.backfill_ms}ms rebuild=${index_first.rebuild_ms}ms total=${index_first.total_ms}ms')
	println('index second changed=${index_second.changed} scanned=${index_second.rows_scanned} backfilled=${index_second.rows_backfilled} backfill=${index_second.backfill_ms}ms rebuild=${index_second.rebuild_ms}ms total=${index_second.total_ms}ms')
	println('state after_sync_first entries=${state_after_sync_first.entries} ingest=${state_after_sync_first.ingest_state} entry_ingest=${state_after_sync_first.entry_ingest_state} search=${state_after_sync_first.search_state} entry_search=${state_after_sync_first.entry_search_state}')
	println('state after_index_first entries=${state_after_index_first.entries} ingest=${state_after_index_first.ingest_state} entry_ingest=${state_after_index_first.entry_ingest_state} search=${state_after_index_first.search_state} entry_search=${state_after_index_first.entry_search_state}')
	println('state after_sync_second entries=${state_after_sync_second.entries} ingest=${state_after_sync_second.ingest_state} entry_ingest=${state_after_sync_second.entry_ingest_state} search=${state_after_sync_second.search_state} entry_search=${state_after_sync_second.entry_search_state}')
	println('state after_index_second entries=${state_after_index_second.entries} ingest=${state_after_index_second.ingest_state} entry_ingest=${state_after_index_second.entry_ingest_state} search=${state_after_index_second.search_state} entry_search=${state_after_index_second.entry_search_state}')
}

fn run_bench_codex_delta(args []string) ! {
	codex_root := resolve_codex_root(args)
	session_limit := parse_flag_int(args, '--sessions', 20)
	mutate_count := parse_flag_int(args, '--mutate', 5)
	subset_root := normalize_cli_path(os.join_path(os.vtmp_dir(), 'agentview-bench-codex-delta-src-${time.now().unix_micro()}'))
	store_root := if has_flag(args, '--store-root') {
		resolve_store_root(args)
	} else {
		normalize_cli_path(os.join_path(os.vtmp_dir(), 'agentview-bench-codex-delta-store-${time.now().unix_micro()}'))
	}
	cfg := storage.ChunkConfig.default().with_detailed_timings(true).with_split_backed_working_set(has_flag(args, '--split-backed'))
	os.rmdir_all(subset_root) or {}
	os.rmdir_all(store_root) or {}
	os.mkdir_all(subset_root)!
	os.mkdir_all(store_root)!
	mut selected_paths := build_codex_subset(codex_root, subset_root, session_limit)!
	if selected_paths.len == 0 {
		return error('no codex sessions found under ${codex_root}')
	}
	mut store := agentview.PollyDbStore.open(store_root)!
	eprintln('bench delta start codex_root=${codex_root} subset=${subset_root} store=${store_root} sessions=${selected_paths.len} mutate=${mutate_count}')
	eprintln('bench delta phase=sync-first')
	sync_first := store.sync_codex_with_progress_and_config(subset_root, sync_progress_detailed_to_stderr, storage.ChunkConfig.default())!
	eprintln('bench delta phase=mutate')
	mutated := mutate_codex_subset(mut selected_paths, mutate_count)!
	eprintln('bench delta phase=reopen')
	store = agentview.PollyDbStore.open(store_root)!
	eprintln('bench delta phase=sync-second')
	sync_second := store.sync_codex_with_progress_and_config(subset_root, sync_progress_detailed_to_stderr, cfg)!
	println('bench delta store=${store_root} subset=${subset_root}')
	println('delta first sessions=${sync_first.sessions} entries=${sync_first.entries} skipped=${sync_first.skipped} total=${sync_first.total_ms}ms apply=${sync_first.apply_ms}ms')
	println('delta second sessions=${sync_second.sessions} entries=${sync_second.entries} skipped=${sync_second.skipped} total=${sync_second.total_ms}ms apply=${sync_second.apply_ms}ms split_backed=${cfg.enable_split_backed_working_set}')
	println('delta mutated=${mutated}')
}

fn run_bench_codex_index_delta(args []string) ! {
	codex_root := resolve_codex_root(args)
	session_limit := parse_flag_int(args, '--sessions', 20)
	mutate_count := parse_flag_int(args, '--mutate', 5)
	subset_root := normalize_cli_path(os.join_path(os.vtmp_dir(), 'agentview-bench-codex-index-delta-src-${time.now().unix_micro()}'))
	store_root := if has_flag(args, '--store-root') {
		resolve_store_root(args)
	} else {
		normalize_cli_path(os.join_path(os.vtmp_dir(), 'agentview-bench-codex-index-delta-store-${time.now().unix_micro()}'))
	}
	cfg := storage.ChunkConfig.default().with_split_backed_working_set(has_flag(args, '--split-backed'))
	os.rmdir_all(subset_root) or {}
	os.rmdir_all(store_root) or {}
	os.mkdir_all(subset_root)!
	os.mkdir_all(store_root)!
	mut selected_paths := build_codex_subset(codex_root, subset_root, session_limit)!
	if selected_paths.len == 0 {
		return error('no codex sessions found under ${codex_root}')
	}
	mut store := agentview.PollyDbStore.open(store_root)!
	eprintln('bench index delta start codex_root=${codex_root} subset=${subset_root} store=${store_root} sessions=${selected_paths.len} mutate=${mutate_count}')
	eprintln('bench index delta phase=sync-first')
	_ = store.sync_codex_with_progress_and_config(subset_root, sync_progress_noop, storage.ChunkConfig.default())!
	eprintln('bench index delta phase=index-first')
	index_first := store.ensure_search_indexes_with_progress_and_config(search_index_progress_to_stderr, storage.ChunkConfig.default())!
	eprintln('bench index delta phase=mutate')
	mutated := mutate_codex_subset(mut selected_paths, mutate_count)!
	eprintln('bench index delta phase=reopen')
	store = agentview.PollyDbStore.open(store_root)!
	eprintln('bench index delta phase=sync-second')
	_ = store.sync_codex_with_progress_and_config(subset_root, sync_progress_noop, cfg)!
	eprintln('bench index delta phase=index-second')
	index_second := store.ensure_search_indexes_with_progress_and_config(search_index_progress_to_stderr, cfg)!
	println('bench index delta store=${store_root} subset=${subset_root}')
	println('index delta first changed=${index_first.changed} scanned=${index_first.rows_scanned} backfilled=${index_first.rows_backfilled} backfill=${index_first.backfill_ms}ms rebuild=${index_first.rebuild_ms}ms total=${index_first.total_ms}ms')
	println('index delta second changed=${index_second.changed} scanned=${index_second.rows_scanned} backfilled=${index_second.rows_backfilled} backfill=${index_second.backfill_ms}ms rebuild=${index_second.rebuild_ms}ms total=${index_second.total_ms}ms split_backed=${cfg.enable_split_backed_working_set}')
	println('index delta mutated=${mutated}')
}

fn build_codex_subset(src_root string, dst_root string, limit int) ![]string {
	mut src_paths := []string{}
	for base_name in ['sessions', 'archived_sessions'] {
		base := os.join_path(src_root, base_name)
		if !os.exists(base) {
			continue
		}
		collect_jsonl_files(base, mut src_paths)!
	}
	src_paths.sort()
	src_paths.reverse_in_place()
	mut picked := src_paths.clone()
	if limit > 0 && src_paths.len > limit {
		picked = src_paths[..limit].clone()
	}
	for path in picked {
		rel := path.after(src_root)
		dst_path := os.join_path(dst_root, rel.trim_left('/'))
		os.mkdir_all(os.dir(dst_path))!
		os.cp(path, dst_path)!
	}
	index_path := os.join_path(src_root, 'session_index.jsonl')
	if os.exists(index_path) {
		os.cp(index_path, os.join_path(dst_root, 'session_index.jsonl'))!
	}
	return discover_subset_session_paths(dst_root)!
}

fn collect_jsonl_files(dir string, mut paths []string) ! {
	for name in os.ls(dir)! {
		full := os.join_path(dir, name)
		if os.is_dir(full) {
			collect_jsonl_files(full, mut paths)!
		} else if os.is_file(full) && full.ends_with('.jsonl') {
			paths << full
		}
	}
}

fn discover_subset_session_paths(root string) ![]string {
	mut paths := []string{}
	for base_name in ['sessions', 'archived_sessions'] {
		base := os.join_path(root, base_name)
		if !os.exists(base) {
			continue
		}
		collect_jsonl_files(base, mut paths)!
	}
	paths.sort()
	paths.reverse_in_place()
	return paths
}

fn mutate_codex_subset(mut paths []string, limit int) !int {
	mut changed := 0
	timestamp := '2026-04-06T00:00:00Z'
	for path in paths {
		if limit > 0 && changed >= limit {
			break
		}
		mut content := os.read_file(path)!
		if !content.ends_with('\n') {
			content += '\n'
		}
		content += '{"timestamp":"' + timestamp + '","type":"user_message","payload":{"text":"bench delta mutation ${changed}"}}\n'
		os.write_file(path, content)!
		changed++
	}
	return changed
}

struct BenchStoreStateCounts {
	entries            int
	ingest_state       int
	entry_ingest_state int
	search_state       int
	entry_search_state int
}

fn bench_store_state_counts(store_root string) !BenchStoreStateCounts {
	mut db := storage.PersistentDatabase.open(store_root, 'main')!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch('main'))!
	return BenchStoreStateCounts{
		entries: count_table_rows(mut db, session, 'entries')
		ingest_state: count_table_rows(mut db, session, 'ingest_state')
		entry_ingest_state: count_table_rows(mut db, session, 'entry_ingest_state')
		search_state: count_table_rows(mut db, session, 'search_state')
		entry_search_state: count_table_rows(mut db, session, 'entry_search_state')
	}
}

fn count_table_rows(mut db storage.PersistentDatabase, session storage.DatabaseSession, table_name string) int {
	rows := session.scan_table(mut db, table_name, 0) or { return 0 }
	return rows.len
}

fn run_bench_write_path(args []string) ! {
	partition_mode := parse_partition_mode(args)!
	mut cfg := storage.ChunkConfig.default().with_detailed_timings(true).with_partitioned_rebuild(partition_mode != 'off')
	if partition_mode == 'force' {
		cfg = cfg.with_force_partitioned_rebuild(true)
	}
	existing_rows := parse_flag_int(args, '--existing', 4096)
	batch_rows := parse_flag_int(args, '--ops', 1024)
	rounds := parse_flag_int(args, '--rounds', 5)
	index_count := parse_flag_int(args, '--indexes', 3)
	mode := parse_flag_value(args, '--mode')
	bench_mode := if mode.len == 0 { 'insert' } else { mode }
	if existing_rows <= 0 || batch_rows <= 0 || rounds <= 0 {
		return error('bench-write-path requires positive --existing, --ops, and --rounds values')
	}
	if index_count <= 0 || index_count > bench_index_columns.len {
		return error('bench-write-path requires --indexes between 1 and ${bench_index_columns.len}')
	}
	if bench_mode !in ['insert', 'update', 'delete', 'mixed'] {
		return error('bench-write-path requires --mode insert|update|delete|mixed')
	}
	spec := bench_entries_spec(index_count)!
	view := bench_entries_view(spec, existing_rows, cfg)!
	ops := bench_entry_ops(spec.table.name, existing_rows, batch_rows, bench_mode)
	mut total_elapsed_ms := i64(0)
	mut total_fallback_ops_encode_ms := i64(0)
	mut total_fallback_ops_index_ms := i64(0)
	mut total_fallback_build_prepare_rows_ms := i64(0)
	mut total_fallback_build_prepare_rows_key_ms := i64(0)
	mut total_fallback_build_prepare_rows_value_ms := i64(0)
	mut total_fallback_build_prepare_keys_merge_ms := i64(0)
	mut total_fallback_build_ms := i64(0)
	mut total_fallback_build_leaf_node_ms := i64(0)
	mut total_fallback_build_leaf_node_serialize_ms := i64(0)
	mut total_fallback_build_internal_ms := i64(0)
	println('bench write path existing=${existing_rows} ops=${batch_rows} rounds=${rounds} mode=${bench_mode} indexes=${index_count} partition=${partition_mode}')
	for round := 0; round < rounds; round++ {
		mut sw := time.new_stopwatch()
		update := view.apply_write_ops(ops, cfg)!
		elapsed_ms := sw.elapsed().milliseconds()
		total_elapsed_ms += elapsed_ms
		total_fallback_ops_encode_ms += update.timings.ops_encode_ms
		total_fallback_ops_index_ms += update.timings.ops_index_ms
		total_fallback_build_prepare_rows_ms += update.timings.build_prepare_rows_ms
		total_fallback_build_prepare_rows_key_ms += update.timings.build_prepare_rows_key_ms
		total_fallback_build_prepare_rows_value_ms += update.timings.build_prepare_rows_value_ms
		total_fallback_build_prepare_keys_merge_ms += update.timings.build_prepare_keys_merge_ms
		total_fallback_build_ms += update.timings.build_ms
		total_fallback_build_leaf_node_ms += update.timings.build_leaf_node_ms
		total_fallback_build_leaf_node_serialize_ms += update.timings.build_leaf_node_serialize_ms
		total_fallback_build_internal_ms += update.timings.build_internal_ms
		println('round ${round + 1}/${rounds} elapsed=${elapsed_ms}ms fallback_ops_encode=${update.timings.ops_encode_ms}ms fallback_ops_index=${update.timings.ops_index_ms}ms fallback_build_prepare_rows=${update.timings.build_prepare_rows_ms}ms fallback_build_prepare_keys_merge=${update.timings.build_prepare_keys_merge_ms}ms fallback_build=${update.timings.build_ms}ms fallback_build_leaf_node=${update.timings.build_leaf_node_ms}ms fallback_build_leaf_node_serialize=${update.timings.build_leaf_node_serialize_ms}ms fallback_build_internal=${update.timings.build_internal_ms}ms')
	}
	plan := view.plan_write_spans(ops) or { storage.MutationSpanPlanStats{} }
	println('avg elapsed=${total_elapsed_ms / rounds}ms fallback_ops_encode=${total_fallback_ops_encode_ms / rounds}ms fallback_ops_index=${total_fallback_ops_index_ms / rounds}ms fallback_build_prepare_rows=${total_fallback_build_prepare_rows_ms / rounds}ms fallback_build_prepare_rows_key=${total_fallback_build_prepare_rows_key_ms / rounds}ms fallback_build_prepare_rows_value=${total_fallback_build_prepare_rows_value_ms / rounds}ms fallback_build_prepare_keys_merge=${total_fallback_build_prepare_keys_merge_ms / rounds}ms fallback_build=${total_fallback_build_ms / rounds}ms fallback_build_leaf_node=${total_fallback_build_leaf_node_ms / rounds}ms fallback_build_leaf_node_serialize=${total_fallback_build_leaf_node_serialize_ms / rounds}ms fallback_build_internal=${total_fallback_build_internal_ms / rounds}ms changed=${plan.changed_keys} new=${plan.new_keys} deleted=${plan.deleted_existing_keys} touched=${plan.touched_existing_keys} spans=${plan.spans} max_span=${plan.max_span_keys} avg_span=${plan.avg_span_keys} covered_existing=${plan.covered_existing_keys}/${plan.existing_keys} covered_pct=${plan.covered_existing_pct} partition_candidate=${plan.partition_candidate}')
}

fn run_bench_write_layout(args []string) ! {
	partition_mode := parse_partition_mode(args)!
	mut cfg := storage.ChunkConfig.default().with_detailed_timings(true).with_partitioned_rebuild(partition_mode != 'off')
	if partition_mode == 'force' {
		cfg = cfg.with_force_partitioned_rebuild(true)
	}
	existing_rows := parse_flag_int(args, '--existing', 4096)
	batch_rows := parse_flag_int(args, '--ops', 1024)
	rounds := parse_flag_int(args, '--rounds', 5)
	index_count := parse_flag_int(args, '--indexes', 3)
	mode := parse_flag_value(args, '--mode')
	bench_mode := if mode.len == 0 { 'update' } else { mode }
	if existing_rows <= 0 || batch_rows <= 0 || rounds <= 0 {
		return error('bench-write-layout requires positive --existing, --ops, and --rounds values')
	}
	if index_count <= 0 || index_count > bench_index_columns.len {
		return error('bench-write-layout requires --indexes between 1 and ${bench_index_columns.len}')
	}
	if bench_mode !in ['insert', 'update', 'delete', 'mixed'] {
		return error('bench-write-layout requires --mode insert|update|delete|mixed')
	}
	spec := bench_entries_spec(index_count)!
	view := bench_entries_view(spec, existing_rows, cfg)!
	ops := bench_entry_ops(spec.table.name, existing_rows, batch_rows, bench_mode)
	stats := bench_write_layout_once(view, ops, cfg, rounds)
	println('bench write layout existing=${existing_rows} ops=${batch_rows} rounds=${rounds} mode=${bench_mode} indexes=${index_count} partition=${partition_mode}')
	println('avg apply=${stats.apply_ms}ms split_materialize=${stats.split_materialize_ms}ms apply_plus_split=${stats.apply_plus_split_ms}ms split_apply_prototype=${stats.split_apply_prototype_ms}ms split_apply_delta=${stats.split_apply_delta_ms}ms split_apply_batched=${stats.split_apply_batched_ms}ms split_apply_batched_steady=${stats.split_apply_batched_steady_ms}ms split_apply_batched_bridge=${stats.split_apply_batched_bridge_ms}ms split_working_set_apply=${stats.split_working_set_apply_ms}ms')
}

fn run_bench_tree_build(args []string) ! {
	cfg := storage.ChunkConfig.default().with_detailed_timings(true)
	item_count := parse_flag_int(args, '--items', 32768)
	rounds := parse_flag_int(args, '--rounds', 5)
	if item_count <= 0 || rounds <= 0 {
		return error('bench-tree-build requires positive --items and --rounds values')
	}
	items := bench_tree_items(item_count)
	mut total_regular_elapsed_ms := i64(0)
	mut total_regular_leaf_ms := i64(0)
	mut total_regular_leaf_chunk_ms := i64(0)
	mut total_regular_leaf_node_ms := i64(0)
	mut total_regular_leaf_node_serialize_ms := i64(0)
	mut total_regular_leaf_node_cid_ms := i64(0)
	mut total_regular_internal_ms := i64(0)
	mut total_bulk_elapsed_ms := i64(0)
	mut total_bulk_leaf_ms := i64(0)
	mut total_bulk_leaf_chunk_ms := i64(0)
	mut total_bulk_leaf_node_ms := i64(0)
	mut total_bulk_leaf_node_serialize_ms := i64(0)
	mut total_bulk_leaf_node_cid_ms := i64(0)
	mut total_bulk_internal_ms := i64(0)
	println('bench tree build items=${item_count} rounds=${rounds} note=use larger --items for stable leaf/internal timings')
	for round := 0; round < rounds; round++ {
		mut regular_sw := time.new_stopwatch()
		regular_result := storage.Tree.build_sorted_with_timings(items, cfg)!
		regular_elapsed_ms := regular_sw.elapsed().milliseconds()
		total_regular_elapsed_ms += regular_elapsed_ms
		total_regular_leaf_ms += regular_result.timings.leaf_ms
		total_regular_leaf_chunk_ms += regular_result.timings.leaf_chunk_ms
		total_regular_leaf_node_ms += regular_result.timings.leaf_node_ms
		total_regular_leaf_node_serialize_ms += regular_result.timings.leaf_node_serialize_ms
		total_regular_leaf_node_cid_ms += regular_result.timings.leaf_node_cid_ms
		total_regular_internal_ms += regular_result.timings.internal_ms
		mut bulk_sw := time.new_stopwatch()
		bulk_result := storage.Tree.build_sorted_bulk_with_timings(items, cfg)!
		bulk_elapsed_ms := bulk_sw.elapsed().milliseconds()
		total_bulk_elapsed_ms += bulk_elapsed_ms
		total_bulk_leaf_ms += bulk_result.timings.leaf_ms
		total_bulk_leaf_chunk_ms += bulk_result.timings.leaf_chunk_ms
		total_bulk_leaf_node_ms += bulk_result.timings.leaf_node_ms
		total_bulk_leaf_node_serialize_ms += bulk_result.timings.leaf_node_serialize_ms
		total_bulk_leaf_node_cid_ms += bulk_result.timings.leaf_node_cid_ms
		total_bulk_internal_ms += bulk_result.timings.internal_ms
		println('round ${round + 1}/${rounds} regular=${regular_elapsed_ms}ms regular_leaf=${regular_result.timings.leaf_ms}ms regular_internal=${regular_result.timings.internal_ms}ms bulk=${bulk_elapsed_ms}ms bulk_leaf=${bulk_result.timings.leaf_ms}ms bulk_internal=${bulk_result.timings.internal_ms}ms')
	}
	println('avg regular_elapsed=${total_regular_elapsed_ms / rounds}ms regular_leaf=${total_regular_leaf_ms / rounds}ms regular_leaf_chunk=${total_regular_leaf_chunk_ms / rounds}ms regular_leaf_node=${total_regular_leaf_node_ms / rounds}ms regular_leaf_node_serialize=${total_regular_leaf_node_serialize_ms / rounds}ms regular_leaf_node_cid=${total_regular_leaf_node_cid_ms / rounds}ms regular_internal=${total_regular_internal_ms / rounds}ms')
	println('avg bulk_elapsed=${total_bulk_elapsed_ms / rounds}ms bulk_leaf=${total_bulk_leaf_ms / rounds}ms bulk_leaf_chunk=${total_bulk_leaf_chunk_ms / rounds}ms bulk_leaf_node=${total_bulk_leaf_node_ms / rounds}ms bulk_leaf_node_serialize=${total_bulk_leaf_node_serialize_ms / rounds}ms bulk_leaf_node_cid=${total_bulk_leaf_node_cid_ms / rounds}ms bulk_internal=${total_bulk_internal_ms / rounds}ms')
}

fn run_bench_split_materialize(args []string) ! {
	cfg := storage.ChunkConfig.default()
	existing_rows := parse_flag_int(args, '--existing', 4096)
	index_count := parse_flag_int(args, '--indexes', 3)
	rounds := parse_flag_int(args, '--rounds', 5)
	if existing_rows <= 0 || rounds <= 0 {
		return error('bench-split-materialize requires positive --existing and --rounds values')
	}
	if index_count <= 0 || index_count > bench_index_columns.len {
		return error('bench-split-materialize requires --indexes between 1 and ${bench_index_columns.len}')
	}
	spec := bench_entries_spec(index_count)!
	view := bench_entries_view(spec, existing_rows, cfg)!
	mut total_elapsed_ms := i64(0)
	println('bench split materialize existing=${existing_rows} indexes=${index_count} rounds=${rounds}')
	for round := 0; round < rounds; round++ {
		mut sw := time.new_stopwatch()
		split := view.materialize_split_storage(cfg)!
		elapsed_ms := sw.elapsed().milliseconds()
		total_elapsed_ms += elapsed_ms
		println('round ${round + 1}/${rounds} elapsed=${elapsed_ms}ms row_root=${split.rows_tree.root.cid} index_trees=${split.index_trees.len}')
	}
	println('avg elapsed=${total_elapsed_ms / rounds}ms')
}

fn run_bench_write_matrix(args []string) ! {
	partition_mode := parse_partition_mode(args)!
	mut cfg := storage.ChunkConfig.default().with_detailed_timings(true).with_partitioned_rebuild(partition_mode != 'off')
	if partition_mode == 'force' {
		cfg = cfg.with_force_partitioned_rebuild(true)
	}
	existing_rows := parse_flag_int(args, '--existing', 4096)
	batch_rows := parse_flag_int(args, '--ops', 1024)
	rounds := parse_flag_int(args, '--rounds', 3)
	if existing_rows <= 0 || batch_rows <= 0 || rounds <= 0 {
		return error('bench-write-matrix requires positive --existing, --ops, and --rounds values')
	}
	index_counts := [1, 3, bench_index_columns.len]
	modes := ['insert', 'update', 'delete', 'mixed']
	println('bench write matrix existing=${existing_rows} ops=${batch_rows} rounds=${rounds} partition=${partition_mode}')
	for index_count in index_counts {
		spec := bench_entries_spec(index_count)!
		view := bench_entries_view(spec, existing_rows, cfg)!
		for mode in modes {
			ops := bench_entry_ops(spec.table.name, existing_rows, batch_rows, mode)
			stats := bench_write_path_once(view, ops, cfg, rounds)
			println('indexes=${index_count} mode=${mode} elapsed=${stats.elapsed_ms}ms ops_encode=${stats.fallback_ops_encode_ms}ms ops_index=${stats.fallback_ops_index_ms}ms prepare_rows=${stats.fallback_build_prepare_rows_ms}ms prepare_merge=${stats.fallback_build_prepare_keys_merge_ms}ms build=${stats.fallback_build_ms}ms changed=${stats.changed_keys} new=${stats.new_keys} deleted=${stats.deleted_existing_keys} touched=${stats.touched_existing_keys} spans=${stats.span_count} max_span=${stats.span_max_keys} avg_span=${stats.span_avg_keys} covered_existing=${stats.span_covered_existing_keys} covered_pct=${stats.span_covered_existing_pct} partition_candidate=${stats.partition_candidate}')
		}
	}
}

const bench_index_columns = ['session_id', 'timestamp', 'kind', 'tag', 'project', 'role']

fn bench_entries_spec(index_count int) !storage.TypedTableSpec {
	table := storage.TableDef.new('entries', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('timestamp', .datetime_, false)!,
		storage.ColumnDef.new('kind', .string_, false)!,
		storage.ColumnDef.new('tag', .string_, false)!,
		storage.ColumnDef.new('project', .string_, false)!,
		storage.ColumnDef.new('role', .string_, false)!,
		storage.ColumnDef.new('content_text', .string_, false)!,
	], ['id'])!
	mut indexes := []storage.SchemaIndexDef{}
	for idx, column_name in bench_index_columns[..index_count] {
		indexes << storage.SchemaIndexDef.new('entries_bench_${idx + 1}_${column_name}_idx', column_name)!
	}
	return storage.TypedTableSpec.new(table, indexes)!
}

fn bench_entries_view(spec storage.TypedTableSpec, existing_rows int, cfg storage.ChunkConfig) !storage.TypedIndexedSchemaView {
	codec := storage.TypedRowCodec.new(spec.table)
	table_view := storage.TableView.new(storage.Tree{}, spec.table.name)
	mut items := []storage.KVPair{cap: existing_rows}
	for i := 0; i < existing_rows; i++ {
		row := bench_entry_row(i)
		primary_key := bench_entry_id(i)
		items << storage.KVPair{
			key: table_view.row_key(primary_key.bytes())
			value: codec.encode(row)!
		}
	}
	mut seed_tree := storage.Tree.build(items, cfg)!
	seed_tree = storage.rebuild_typed_indexes_for_specs(seed_tree, [spec], cfg)!
	schema := storage.TypedSchemaView.new(storage.TableView.new(seed_tree, spec.table.name), codec)
	return storage.TypedIndexedSchemaView.new(schema, spec.indexes)!
}

struct BenchWritePathStats {
	elapsed_ms                          i64
	fallback_ops_encode_ms             i64
	fallback_ops_index_ms              i64
	fallback_build_prepare_rows_ms     i64
	fallback_build_prepare_keys_merge_ms i64
	fallback_build_ms                  i64
	changed_keys                       int
	new_keys                           int
	deleted_existing_keys              int
	touched_existing_keys              int
	span_count                         int
	span_max_keys                      int
	span_avg_keys                      int
	span_covered_existing_keys         int
	span_covered_existing_pct          int
	partition_candidate                bool
}

struct BenchWriteLayoutStats {
	apply_ms            i64
	split_materialize_ms i64
	apply_plus_split_ms i64
	split_apply_prototype_ms i64
	split_apply_delta_ms i64
	split_apply_batched_ms i64
	split_apply_batched_steady_ms i64
	split_apply_batched_bridge_ms i64
	split_working_set_apply_ms i64
}

fn bench_write_path_once(view storage.TypedIndexedSchemaView, ops []storage.TypedWriteOp, cfg storage.ChunkConfig, rounds int) BenchWritePathStats {
	plan := view.plan_write_spans(ops) or { storage.MutationSpanPlanStats{} }
	mut total_elapsed_ms := i64(0)
	mut total_fallback_ops_encode_ms := i64(0)
	mut total_fallback_ops_index_ms := i64(0)
	mut total_fallback_build_prepare_rows_ms := i64(0)
	mut total_fallback_build_prepare_keys_merge_ms := i64(0)
	mut total_fallback_build_ms := i64(0)
	for _ in 0 .. rounds {
		mut sw := time.new_stopwatch()
		update := view.apply_write_ops(ops, cfg) or { continue }
		total_elapsed_ms += sw.elapsed().milliseconds()
		total_fallback_ops_encode_ms += update.timings.ops_encode_ms
		total_fallback_ops_index_ms += update.timings.ops_index_ms
		total_fallback_build_prepare_rows_ms += update.timings.build_prepare_rows_ms
		total_fallback_build_prepare_keys_merge_ms += update.timings.build_prepare_keys_merge_ms
		total_fallback_build_ms += update.timings.build_ms
	}
	return BenchWritePathStats{
		elapsed_ms: total_elapsed_ms / rounds
		fallback_ops_encode_ms: total_fallback_ops_encode_ms / rounds
		fallback_ops_index_ms: total_fallback_ops_index_ms / rounds
		fallback_build_prepare_rows_ms: total_fallback_build_prepare_rows_ms / rounds
		fallback_build_prepare_keys_merge_ms: total_fallback_build_prepare_keys_merge_ms / rounds
		fallback_build_ms: total_fallback_build_ms / rounds
		changed_keys: plan.changed_keys
		new_keys: plan.new_keys
		deleted_existing_keys: plan.deleted_existing_keys
		touched_existing_keys: plan.touched_existing_keys
		span_count: plan.spans
		span_max_keys: plan.max_span_keys
		span_avg_keys: plan.avg_span_keys
		span_covered_existing_keys: plan.covered_existing_keys
		span_covered_existing_pct: plan.covered_existing_pct
		partition_candidate: plan.partition_candidate
	}
}

fn bench_write_layout_once(view storage.TypedIndexedSchemaView, ops []storage.TypedWriteOp, cfg storage.ChunkConfig, rounds int) BenchWriteLayoutStats {
	mut total_apply_ms := i64(0)
	mut total_split_ms := i64(0)
	mut total_split_apply_ms := i64(0)
	mut total_split_delta_ms := i64(0)
	mut total_split_batched_ms := i64(0)
	split_view := view.split_backed(cfg) or { view }
	mut total_split_batched_steady_ms := i64(0)
	mut total_split_batched_bridge_ms := i64(0)
	spec := storage.TypedTableSpec.new(view.schema.codec.table, view.indexes) or { panic(err) }
	base_working_set := storage.TypedWorkingSet.new('bench', 'base', view.schema.table.tree, [spec]) or { panic(err) }
	split_working_set := base_working_set.split_backed(cfg) or { panic(err) }
	write_set := typed_write_set_from_ops(ops)
	mut total_split_working_set_apply_ms := i64(0)
	for _ in 0 .. rounds {
		mut apply_sw := time.new_stopwatch()
		update := view.apply_write_ops(ops, cfg) or { continue }
		total_apply_ms += apply_sw.elapsed().milliseconds()
		mut split_sw := time.new_stopwatch()
		_ := update.view.materialize_split_storage(cfg) or { continue }
		total_split_ms += split_sw.elapsed().milliseconds()
		mut split_apply_sw := time.new_stopwatch()
		_ := view.apply_write_ops_split_rebuild(ops, cfg) or { continue }
		total_split_apply_ms += split_apply_sw.elapsed().milliseconds()
		mut split_delta_sw := time.new_stopwatch()
		_ := view.apply_write_ops_split_delta(ops, cfg) or { continue }
		total_split_delta_ms += split_delta_sw.elapsed().milliseconds()
		mut split_batched_sw := time.new_stopwatch()
		_ := view.apply_write_ops_split_batched(ops, cfg) or { continue }
		total_split_batched_ms += split_batched_sw.elapsed().milliseconds()
		mut split_batched_steady_sw := time.new_stopwatch()
		_ := split_view.apply_write_ops_split_batched(ops, cfg) or { continue }
		total_split_batched_steady_ms += split_batched_steady_sw.elapsed().milliseconds()
		mut split_batched_bridge_sw := time.new_stopwatch()
		bridge_split := split_view.apply_write_ops_split_batched(ops, cfg) or { continue }
		_ = (storage.TypedSchemaView.new_with_split_storage(bridge_split, view.schema.codec))
		_ = (storage.TypedIndexedSchemaView.new_with_split_storage(storage.TypedSchemaView.new_with_split_storage(bridge_split,
			view.schema.codec), view.indexes, bridge_split) or { continue }).mixed_backed(cfg) or { continue }
		total_split_batched_bridge_ms += split_batched_bridge_sw.elapsed().milliseconds()
		mut split_working_set_sw := time.new_stopwatch()
		mut working_set := split_working_set.clone()
		_ = working_set.apply_write_set(write_set, cfg) or { continue }
		total_split_working_set_apply_ms += split_working_set_sw.elapsed().milliseconds()
	}
	return BenchWriteLayoutStats{
		apply_ms: total_apply_ms / rounds
		split_materialize_ms: total_split_ms / rounds
		apply_plus_split_ms: (total_apply_ms + total_split_ms) / rounds
		split_apply_prototype_ms: total_split_apply_ms / rounds
		split_apply_delta_ms: total_split_delta_ms / rounds
		split_apply_batched_ms: total_split_batched_ms / rounds
		split_apply_batched_steady_ms: total_split_batched_steady_ms / rounds
		split_apply_batched_bridge_ms: total_split_batched_bridge_ms / rounds
		split_working_set_apply_ms: total_split_working_set_apply_ms / rounds
	}
}

fn typed_write_set_from_ops(ops []storage.TypedWriteOp) storage.TypedWriteSet {
	mut set := storage.TypedWriteSet.new()
	for op in ops {
		if op.delete {
			set.delete(op.table_name, op.primary_key)
		} else {
			set.put(op.table_name, op.primary_key, op.row)
		}
	}
	return set
}

fn bench_entry_ops(table_name string, existing_rows int, count int, mode string) []storage.TypedWriteOp {
	mut ops := []storage.TypedWriteOp{cap: count}
	match mode {
		'insert' {
			for i := existing_rows; i < existing_rows + count; i++ {
				ops << storage.TypedWriteOp{
					table_name: table_name
					primary_key: bench_entry_id(i).bytes()
					row: bench_entry_row(i)
					delete: false
				}
			}
		}
		'update' {
			for i := 0; i < count; i++ {
				target := i % existing_rows
				ops << storage.TypedWriteOp{
					table_name: table_name
					primary_key: bench_entry_id(target).bytes()
					row: bench_entry_row_variant(target, 'update')
					delete: false
				}
			}
		}
		'delete' {
			for i := 0; i < count; i++ {
				target := i % existing_rows
				ops << storage.TypedWriteOp{
					table_name: table_name
					primary_key: bench_entry_id(target).bytes()
					row: storage.TypedRowData.new()
					delete: true
				}
			}
		}
		'mixed' {
			for i := 0; i < count; i++ {
				match i % 3 {
					0 {
						target := i % existing_rows
						ops << storage.TypedWriteOp{
							table_name: table_name
							primary_key: bench_entry_id(target).bytes()
							row: bench_entry_row_variant(target, 'update')
							delete: false
						}
					}
					1 {
						target := i % existing_rows
						ops << storage.TypedWriteOp{
							table_name: table_name
							primary_key: bench_entry_id(target).bytes()
							row: storage.TypedRowData.new()
							delete: true
						}
					}
					else {
						target := existing_rows + i
						ops << storage.TypedWriteOp{
							table_name: table_name
							primary_key: bench_entry_id(target).bytes()
							row: bench_entry_row_variant(target, 'insert')
							delete: false
						}
					}
				}
			}
		}
		else {}
	}
	return ops
}

fn bench_entry_row(i int) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('id', bench_entry_id(i))
	row.set('session_id', 'session-${(i / 128):04d}')
	row.set('timestamp', '2026-04-06T12:${(i % 60):02d}:${(i % 60):02d}.000000Z')
	row.set('kind', bench_entry_kind(i))
	row.set('tag', 'tag-${(i / 32) % 16:02d}')
	row.set('project', 'project-${(i / 256) % 8:02d}')
	row.set('role', bench_entry_role(i))
	row.set('content_text', 'entry ${i:08d} synthetic payload for typed write path benchmark')
	return row
}

fn bench_entry_row_variant(i int, variant string) storage.TypedRowData {
	mut row := bench_entry_row(i)
	match variant {
		'update' {
			row.set('timestamp', '2026-04-07T08:${(i % 60):02d}:${((i * 7) % 60):02d}.000000Z')
			row.set('kind', bench_entry_kind(i + 1))
			row.set('tag', 'tag-${(i / 17) % 16:02d}')
			row.set('project', 'project-${(i / 91) % 8:02d}')
			row.set('role', bench_entry_role(i + 1))
			row.set('content_text', 'entry ${i:08d} updated synthetic payload for typed write path benchmark')
		}
		'insert' {
			row.set('content_text', 'entry ${i:08d} inserted synthetic payload for typed write path benchmark')
		}
		else {}
	}
	return row
}

fn bench_tree_items(count int) []storage.KVPair {
	mut items := []storage.KVPair{cap: count}
	for i := 0; i < count; i++ {
		items << storage.KVPair{
			key: bench_tree_key(i)
			value: bench_tree_value(i)
		}
	}
	return items
}

fn bench_tree_key(i int) []u8 {
	return 'tree-key-${i:08d}'.bytes()
}

fn bench_tree_value(i int) []u8 {
	return 'tree-value-${i:08d}-payload-${bench_entry_kind(i)}'.bytes()
}

fn bench_entry_id(i int) string {
	return 'entry-${i:08d}'
}

fn bench_entry_kind(i int) string {
	return match i % 4 {
		0 { 'message' }
		1 { 'reasoning' }
		2 { 'tool_call' }
		else { 'tool_result' }
	}
}

fn bench_entry_role(i int) string {
	return match i % 3 {
		0 { 'user' }
		1 { 'assistant' }
		else { 'tool' }
	}
}

fn normalized_args(args []string) []string {
	if args.len > 0 && args[0] == '--' {
		return args[1..]
	}
	return args
}

fn resolve_codex_root(args []string) string {
	for idx, arg in args {
		if arg == '--codex-root' && idx + 1 < args.len {
			return normalize_cli_path(args[idx + 1])
		}
	}
	return normalize_cli_path(agentview.default_codex_root())
}

fn resolve_store_root(args []string) string {
	for idx, arg in args {
		if arg == '--store-root' && idx + 1 < args.len {
			return normalize_cli_path(args[idx + 1])
		}
	}
	return normalize_cli_path(agentview.default_store_root())
}

fn normalize_cli_path(path string) string {
	if path.len == 0 {
		return path
	}
	return if os.exists(path) { os.real_path(path) } else { os.norm_path(path) }
}

fn parse_limit(args []string, fallback int) int {
	flag_limit := parse_flag_int(args, '--limit', 0)
	if flag_limit > 0 {
		return flag_limit
	}
	for arg in args[1..] {
		if arg.starts_with('--') {
			continue
		}
		if arg.int() > 0 {
			return arg.int()
		}
	}
	return fallback
}

fn parse_flag_value(args []string, name string) string {
	for idx, arg in args {
		if arg == name && idx + 1 < args.len {
			return args[idx + 1]
		}
	}
	return ''
}

fn parse_flag_int(args []string, name string, fallback int) int {
	value := parse_flag_value(args, name)
	if value.int() > 0 || value == '0' {
		return value.int()
	}
	return fallback
}

fn parse_partition_mode(args []string) !string {
	value := parse_flag_value(args, '--partition')
	if value.len == 0 {
		return 'auto'
	}
	if value !in ['auto', 'off', 'force'] {
		return error('partition mode must be auto|off|force')
	}
	return value
}

fn has_flag(args []string, name string) bool {
	for arg in args {
		if arg == name {
			return true
		}
	}
	return false
}

fn left_pad(value string, width int) string {
	if value.len >= width {
		return value
	}
	return ' '.repeat(width - value.len) + value
}

fn ensure_store_ready(command string, store agentview.PollyDbStore, codex_root string) ! {
	if command !in ['sessions', 'show', 'search', 'browse', 'memory', 'context'] {
		return
	}
	result := store.list_sessions_page(agentview.SessionListRequest{
		limit: 1
		offset: 0
		include_archived: true
	}) or {
		if err.msg().contains('branch not found:') {
			eprintln('store is empty, syncing from ${codex_root} ...')
			store.sync_codex_with_options_and_progress_and_config(codex_root, agentview.SyncOptions{
				batch_sessions: 8
			}, sync_progress_compact_to_stderr, storage.ChunkConfig.default())!
			return
		}
		return err
	}
	if result.total > 0 {
		return
	}
	eprintln('store is empty, syncing from ${codex_root} ...')
	store.sync_codex_with_options_and_progress_and_config(codex_root, agentview.SyncOptions{
		batch_sessions: 8
	}, sync_progress_compact_to_stderr, storage.ChunkConfig.default())!
}

fn sync_progress_compact_to_stderr(progress agentview.SyncProgress) {
	match progress.phase {
		'start' {
			eprintln('sync start total=${progress.total_sessions} skipped=${progress.skipped_sessions}')
		}
		'skip' {
			eprintln('sync skip ${progress.processed_sessions}/${progress.total_sessions} ${progress.session_id} ${progress.session_title}')
		}
		'resume_skip' {
			if progress.session_id.len > 0 {
				eprintln('sync resume anchor ${progress.processed_sessions}/${progress.total_sessions} ${progress.session_id}')
			} else {
				eprintln('sync resume skip ${progress.processed_sessions}/${progress.total_sessions}')
			}
		}
		'import' {
			eprintln('sync import ${progress.processed_sessions + 1}/${progress.total_sessions} ${progress.session_id} ${progress.session_title}')
		}
		'checkpoint' {
			if progress.batch_sessions > 0 {
				eprintln('sync batch ${progress.checkpoint_count} done processed=${progress.processed_sessions}/${progress.total_sessions} imported=${progress.imported_sessions} entries=${progress.imported_entries} skipped=${progress.skipped_sessions}; run the same command again to continue')
			} else {
				eprintln('sync checkpoint processed=${progress.processed_sessions} imported=${progress.imported_sessions} entries=${progress.imported_entries} skipped=${progress.skipped_sessions}')
			}
		}
		'done' {
			eprintln('sync done processed=${progress.processed_sessions} imported=${progress.imported_sessions} entries=${progress.imported_entries} skipped=${progress.skipped_sessions} checkpoints=${progress.checkpoint_count} read=${progress.read_ms}ms build=${progress.build_ms}ms apply=${progress.apply_ms}ms finish=${progress.finish_ms}ms total=${progress.total_ms}ms')
		}
		else {}
	}
}

fn sync_progress_noop(progress agentview.SyncProgress) {
	_ = progress
}

fn sync_progress_detailed_to_stderr(progress agentview.SyncProgress) {
	match progress.phase {
		'start', 'skip', 'import', 'checkpoint' {
			sync_progress_compact_to_stderr(progress)
		}
		'profile' {
			eprintln('sync profile ${progress.processed_sessions + 1}/${progress.total_sessions} ${progress.session_id} read=${progress.read_ms}ms build=${progress.build_ms}ms apply=${progress.apply_ms}ms tx=${progress.tx_ms}ms aggregate=${progress.aggregate_ms}ms fast=${progress.fast_update_ms}ms fast_can=${progress.fast_update_can_ms}ms fast_path=${progress.fast_update_path_ms}ms fast_encode=${progress.fast_update_encode_ms}ms fast_replace=${progress.fast_update_replace_ms}ms fallback=${progress.fallback_ms}ms fallback_items=${progress.fallback_items_ms}ms fallback_items_key=${progress.fallback_items_key_ms}ms fallback_items_fill=${progress.fallback_items_fill_ms}ms fallback_ops=${progress.fallback_ops_ms}ms fallback_ops_key=${progress.fallback_ops_key_ms}ms fallback_ops_lookup=${progress.fallback_ops_lookup_ms}ms fallback_ops_encode=${progress.fallback_ops_encode_ms}ms fallback_ops_state=${progress.fallback_ops_state_ms}ms fallback_ops_state_new_key=${progress.fallback_ops_state_new_key_ms}ms fallback_ops_state_item=${progress.fallback_ops_state_item_ms}ms fallback_ops_state_cache=${progress.fallback_ops_state_cache_ms}ms fallback_ops_index=${progress.fallback_ops_index_ms}ms fallback_build=${progress.fallback_build_ms}ms fallback_build_prepare=${progress.fallback_build_prepare_ms}ms fallback_build_prepare_keys=${progress.fallback_build_prepare_keys_ms}ms fallback_build_prepare_keys_sort=${progress.fallback_build_prepare_keys_sort_ms}ms fallback_build_prepare_keys_merge=${progress.fallback_build_prepare_keys_merge_ms}ms fallback_build_prepare_rows=${progress.fallback_build_prepare_rows_ms}ms fallback_build_prepare_rows_key=${progress.fallback_build_prepare_rows_key_ms}ms fallback_build_prepare_rows_value=${progress.fallback_build_prepare_rows_value_ms}ms fallback_build_leaf=${progress.fallback_build_leaf_ms}ms fallback_build_leaf_chunk=${progress.fallback_build_leaf_chunk_ms}ms fallback_build_leaf_node=${progress.fallback_build_leaf_node_ms}ms fallback_build_leaf_node_serialize=${progress.fallback_build_leaf_node_serialize_ms}ms fallback_build_leaf_node_cid=${progress.fallback_build_leaf_node_cid_ms}ms fallback_build_leaf_node_add=${progress.fallback_build_leaf_node_add_ms}ms fallback_build_internal=${progress.fallback_build_internal_ms}ms commit=${progress.commit_ms}ms checkpoint=${progress.checkpoint_ms}ms flush=${progress.flush_ms}ms total=${progress.total_ms}ms')
		}
		'done' {
			eprintln('sync done processed=${progress.processed_sessions} imported=${progress.imported_sessions} entries=${progress.imported_entries} skipped=${progress.skipped_sessions} checkpoints=${progress.checkpoint_count} read=${progress.read_ms}ms build=${progress.build_ms}ms apply=${progress.apply_ms}ms tx=${progress.tx_ms}ms aggregate=${progress.aggregate_ms}ms fast=${progress.fast_update_ms}ms fast_can=${progress.fast_update_can_ms}ms fast_path=${progress.fast_update_path_ms}ms fast_encode=${progress.fast_update_encode_ms}ms fast_replace=${progress.fast_update_replace_ms}ms fallback=${progress.fallback_ms}ms fallback_items=${progress.fallback_items_ms}ms fallback_items_key=${progress.fallback_items_key_ms}ms fallback_items_fill=${progress.fallback_items_fill_ms}ms fallback_ops=${progress.fallback_ops_ms}ms fallback_ops_key=${progress.fallback_ops_key_ms}ms fallback_ops_lookup=${progress.fallback_ops_lookup_ms}ms fallback_ops_encode=${progress.fallback_ops_encode_ms}ms fallback_ops_state=${progress.fallback_ops_state_ms}ms fallback_ops_state_new_key=${progress.fallback_ops_state_new_key_ms}ms fallback_ops_state_item=${progress.fallback_ops_state_item_ms}ms fallback_ops_state_cache=${progress.fallback_ops_state_cache_ms}ms fallback_ops_index=${progress.fallback_ops_index_ms}ms fallback_build=${progress.fallback_build_ms}ms fallback_build_prepare=${progress.fallback_build_prepare_ms}ms fallback_build_prepare_keys=${progress.fallback_build_prepare_keys_ms}ms fallback_build_prepare_keys_sort=${progress.fallback_build_prepare_keys_sort_ms}ms fallback_build_prepare_keys_merge=${progress.fallback_build_prepare_keys_merge_ms}ms fallback_build_prepare_rows=${progress.fallback_build_prepare_rows_ms}ms fallback_build_prepare_rows_key=${progress.fallback_build_prepare_rows_key_ms}ms fallback_build_prepare_rows_value=${progress.fallback_build_prepare_rows_value_ms}ms fallback_build_leaf=${progress.fallback_build_leaf_ms}ms fallback_build_leaf_chunk=${progress.fallback_build_leaf_chunk_ms}ms fallback_build_leaf_node=${progress.fallback_build_leaf_node_ms}ms fallback_build_leaf_node_serialize=${progress.fallback_build_leaf_node_serialize_ms}ms fallback_build_leaf_node_cid=${progress.fallback_build_leaf_node_cid_ms}ms fallback_build_leaf_node_add=${progress.fallback_build_leaf_node_add_ms}ms fallback_build_internal=${progress.fallback_build_internal_ms}ms commit=${progress.commit_ms}ms checkpoint=${progress.checkpoint_ms}ms flush=${progress.flush_ms}ms finish=${progress.finish_ms}ms total=${progress.total_ms}ms')
		}
		else {}
	}
}

fn search_index_progress_to_stderr(progress agentview.SearchIndexProgress) {
	match progress.phase {
		'start' {
			eprintln('index start')
		}
		'backfill' {
			eprintln('index backfill scanned=${progress.rows_scanned} backfilled=${progress.rows_backfilled} took=${progress.backfill_ms}ms')
		}
		'rebuild' {
			eprintln('index rebuild scanned=${progress.rows_scanned} backfilled=${progress.rows_backfilled} backfill=${progress.backfill_ms}ms rebuild=${progress.rebuild_ms}ms')
		}
		'done' {
			eprintln('index done scanned=${progress.rows_scanned} backfilled=${progress.rows_backfilled} backfill=${progress.backfill_ms}ms rebuild=${progress.rebuild_ms}ms total=${progress.total_ms}ms')
		}
		else {}
	}
}
