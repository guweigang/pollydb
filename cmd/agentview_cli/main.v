module main

import os
import agentview

fn main() {
	args := normalized_args(os.args[1..])
	if args.len == 0 || args[0] in ['help', '--help', '-h'] {
		println(usage())
		return
	}
	command := args[0]
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
			stats := store.sync_codex_with_progress(codex_root, sync_progress_to_stderr) or {
				eprintln(err.msg())
				exit(1)
			}
			println('synced sessions=${stats.sessions} entries=${stats.entries} skipped=${stats.skipped} store=${store_root}')
		}
		'sessions' {
			request := agentview.SessionListRequest{
				limit: parse_limit(args, 20)
				offset: parse_flag_int(args, '--offset', 0)
				query: parse_flag_value(args, '--query')
				cwd_prefix: parse_flag_value(args, '--cwd-prefix')
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
				println(hit.snippet)
				println('')
			}
		}
		'browse' {
			agentview.browse_store(store, agentview.BrowserOptions{
				query: parse_flag_value(args, '--query')
				cwd_prefix: parse_flag_value(args, '--cwd-prefix')
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
	return 'agentview sync-codex [--codex-root <path>] [--store-root <path>]\n'
		+ 'agentview sessions [limit] [--offset N] [--query TEXT] [--cwd-prefix PATH] [--no-archived] [--store-root <path>]\n'
		+ 'agentview show <session_id> [--offset N] [--limit N] [--store-root <path>]\n'
		+ 'agentview search <query> [limit] [--offset N] [--session-id ID] [--store-root <path>]\n'
		+ 'agentview browse [--query TEXT] [--cwd-prefix PATH] [--no-archived] [--list-limit N] [--transcript-limit N] [--store-root <path>]\n'
		+ 'default codex root: ~/.codex\n'
		+ 'default store root: ~/.agentview/pollydb\n'
		+ 'note: sessions/show/search/browse will auto-sync from ~/.codex when the store is empty'
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
			return args[idx + 1]
		}
	}
	return agentview.default_codex_root()
}

fn resolve_store_root(args []string) string {
	for idx, arg in args {
		if arg == '--store-root' && idx + 1 < args.len {
			return args[idx + 1]
		}
	}
	return agentview.default_store_root()
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
	if command !in ['sessions', 'show', 'search', 'browse'] {
		return
	}
	result := store.list_sessions_page(agentview.SessionListRequest{
		limit: 1
		offset: 0
		include_archived: true
	}) or {
		if err.msg().contains('branch not found:') {
			eprintln('store is empty, syncing from ${codex_root} ...')
			store.sync_codex_with_progress(codex_root, sync_progress_to_stderr)!
			return
		}
		return err
	}
	if result.total > 0 {
		return
	}
	eprintln('store is empty, syncing from ${codex_root} ...')
	store.sync_codex_with_progress(codex_root, sync_progress_to_stderr)!
}

fn sync_progress_to_stderr(progress agentview.SyncProgress) {
	match progress.phase {
		'start' {
			eprintln('sync start total=${progress.total_sessions} skipped=${progress.skipped_sessions}')
		}
		'skip' {
			eprintln('sync skip ${progress.processed_sessions}/${progress.total_sessions} ${progress.session_id} ${progress.session_title}')
		}
		'import' {
			eprintln('sync import ${progress.processed_sessions + 1}/${progress.total_sessions} ${progress.session_id} ${progress.session_title}')
		}
		'done' {
			eprintln('sync done processed=${progress.processed_sessions} imported=${progress.imported_sessions} entries=${progress.imported_entries} skipped=${progress.skipped_sessions}')
		}
		else {}
	}
}
