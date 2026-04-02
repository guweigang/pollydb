module agentview

import os
import x.json2

struct CodexSessionIndexRow {
	id          string
	thread_name string
	updated_at  string
}

struct CodexHistoryRow {
	session_id string
	ts         i64
	text       string
}

struct CodexEventEnvelope {
	timestamp string
	typ       string @[json: 'type']
	payload   json2.Any
}

pub fn default_codex_root() string {
	return os.join_path(os.home_dir(), '.codex')
}

pub fn list_codex_sessions(root string, limit int) ![]SessionSummary {
	mut title_by_id := load_codex_session_titles(root)!
	mut paths := discover_codex_session_paths(root)!
	paths.sort()
	paths.reverse_in_place()
	mut sessions := []SessionSummary{}
	for path in paths {
		summary := read_codex_session_summary(path, mut title_by_id)!
		sessions << summary
		if limit > 0 && sessions.len >= limit {
			break
		}
	}
	return sessions
}

pub fn load_codex_session(root string, session_id string) !SessionTranscript {
	mut title_by_id := load_codex_session_titles(root)!
	path := find_codex_session_path(root, session_id)!
	return read_codex_transcript(path, mut title_by_id)
}

pub fn search_codex_sessions(root string, query string, limit int) ![]SearchHit {
	needle := query.to_lower()
	if needle.len == 0 {
		return []SearchHit{}
	}
	mut hits := []SearchHit{}
	sessions := list_codex_sessions(root, 0)!
	mut title_by_id := load_codex_session_titles(root)!
	for summary in sessions {
		transcript := read_codex_transcript(summary.path, mut title_by_id) or { continue }
		for entry in transcript.entries {
			haystack := '${entry.title}\n${entry.text}'.to_lower()
			if !haystack.contains(needle) {
				continue
			}
			hits << SearchHit{
				session_id: summary.id
				session_title: summary.title
				path: summary.path
				entry_seq: entry.seq
				kind: entry.kind
				role: entry.role
				timestamp: entry.timestamp
				snippet: compact_snippet(entry.text, query, 140)
			}
			if limit > 0 && hits.len >= limit {
				return hits
			}
		}
	}
	return hits
}

fn discover_codex_session_paths(root string) ![]string {
	mut paths := []string{}
	for base in [os.join_path(root, 'sessions'), os.join_path(root, 'archived_sessions')] {
		if !os.exists(base) {
			continue
		}
		if base.ends_with('archived_sessions') {
			for path in os.ls(base)! {
				full := os.join_path(base, path)
				if os.is_file(full) && full.ends_with('.jsonl') {
					paths << full
				}
			}
			continue
		}
		collect_jsonl_paths(base, mut paths)!
	}
	return paths
}

fn collect_jsonl_paths(dir string, mut paths []string) ! {
	for name in os.ls(dir)! {
		full := os.join_path(dir, name)
		if os.is_dir(full) {
			collect_jsonl_paths(full, mut paths)!
		} else if os.is_file(full) && full.ends_with('.jsonl') {
			paths << full
		}
	}
}

fn find_codex_session_path(root string, session_id string) !string {
	paths := discover_codex_session_paths(root)!
	for path in paths {
		if path.contains(session_id) {
			return path
		}
	}
	return error('codex session not found: ${session_id}')
}

fn load_codex_session_titles(root string) !map[string]string {
	index_path := os.join_path(root, 'session_index.jsonl')
	mut titles := map[string]string{}
	if !os.exists(index_path) {
		return titles
	}
	for line in os.read_lines(index_path)! {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		row := json2.decode[CodexSessionIndexRow](trimmed) or { continue }
		if row.id.len == 0 || row.thread_name.len == 0 {
			continue
		}
		titles[row.id] = row.thread_name
	}
	return titles
}

fn read_codex_session_summary(path string, mut titles map[string]string) !SessionSummary {
	lines := os.read_lines(path)!
	mut id := ''
	mut started_at := ''
	mut updated_at := ''
	mut cwd := ''
	mut source := ''
	mut originator := ''
	mut cli_version := ''
	mut entry_count := 0
	mut user_turns := 0
	mut tool_calls := 0
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		env := json2.decode[CodexEventEnvelope](trimmed) or { continue }
		if env.timestamp.len > 0 {
			updated_at = env.timestamp
		}
		match env.typ {
			'session_meta' {
				meta := any_map(env.payload)
				id = any_string(meta['id'] or { json2.Any('') })
				started_at = any_string(meta['timestamp'] or { json2.Any('') })
				cwd = any_string(meta['cwd'] or { json2.Any('') })
				source = any_string(meta['source'] or { json2.Any('') })
				originator = any_string(meta['originator'] or { json2.Any('') })
				cli_version = any_string(meta['cli_version'] or { json2.Any('') })
			}
			'user_message' {
				user_turns++
				entry_count++
			}
			'response_item' {
				item := any_map(env.payload)
				item_type := any_string(item['type'] or { json2.Any('') })
				match item_type {
					'message', 'reasoning', 'function_call', 'function_call_output', 'custom_tool_call', 'custom_tool_call_output' {
						entry_count++
					}
					else {}
				}
				if item_type == 'function_call' || item_type == 'custom_tool_call' {
					tool_calls++
				}
			}
			'event_msg' {
				msg := any_map(env.payload)
				if any_string(msg['type'] or { json2.Any('') }) == 'agent_message' {
					entry_count++
				}
			}
			else {}
		}
	}
	if id.len == 0 {
		id = session_id_from_path(path)
	}
	title := titles[id] or { infer_title_from_path(path) }
	return SessionSummary{
		id: id
		title: title
		updated_at: updated_at
		started_at: started_at
		cwd: cwd
		source: source
		originator: originator
		cli_version: cli_version
		path: path
		archived: path.contains('/archived_sessions/')
		entry_count: entry_count
		user_turns: user_turns
		tool_calls: tool_calls
	}
}

fn read_codex_transcript(path string, mut titles map[string]string) !SessionTranscript {
	summary := read_codex_session_summary(path, mut titles)!
	lines := os.read_lines(path)!
	mut entries := []SessionEntry{}
	mut seq := 0
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		env := json2.decode[CodexEventEnvelope](trimmed) or { continue }
		match env.typ {
			'user_message' {
				payload := any_map(env.payload)
				text := first_non_empty([
					any_string(payload['text'] or { json2.Any('') }),
					any_string(payload['message'] or { json2.Any('') }),
				])
				if text.len == 0 {
					continue
				}
				entries << SessionEntry{
					seq: seq
					timestamp: env.timestamp
					kind: .message
					role: 'user'
					title: ''
					text: text
					raw_type: env.typ
				}
				seq++
			}
			'event_msg' {
				payload := any_map(env.payload)
				msg_type := any_string(payload['type'] or { json2.Any('') })
				if msg_type != 'agent_message' {
					continue
				}
				text := any_string(payload['message'] or { json2.Any('') })
				if text.len == 0 {
					continue
				}
				entries << SessionEntry{
					seq: seq
					timestamp: env.timestamp
					kind: .message
					role: 'assistant'
					title: 'commentary'
					text: text
					phase: any_string(payload['phase'] or { json2.Any('') })
					raw_type: msg_type
				}
				seq++
			}
			'response_item' {
				item := any_map(env.payload)
				item_type := any_string(item['type'] or { json2.Any('') })
				match item_type {
					'message' {
						role := any_string(item['role'] or { json2.Any('assistant') })
						if role in ['developer', 'system'] {
							continue
						}
						text := extract_response_message_text(item)
						if text.len == 0 {
							continue
						}
						entries << SessionEntry{
							seq: seq
							timestamp: env.timestamp
							kind: .message
							role: role
							text: text
							phase: any_string(item['phase'] or { json2.Any('') })
							raw_type: item_type
						}
						seq++
					}
					'reasoning' {
						text := extract_reasoning_text(item)
						if text.len == 0 {
							continue
						}
						entries << SessionEntry{
							seq: seq
							timestamp: env.timestamp
							kind: .reasoning
							role: 'assistant'
							text: text
							raw_type: item_type
						}
						seq++
					}
					'function_call', 'custom_tool_call' {
						entries << SessionEntry{
							seq: seq
							timestamp: env.timestamp
							kind: .tool_call
							role: 'tool'
							tool_name: any_string(item['name'] or { json2.Any('') })
							call_id: any_string(item['call_id'] or { json2.Any('') })
							text: any_string(item['arguments'] or { json2.Any('') })
							raw_type: item_type
						}
						seq++
					}
					'function_call_output', 'custom_tool_call_output' {
						entries << SessionEntry{
							seq: seq
							timestamp: env.timestamp
							kind: .tool_result
							role: 'tool'
							call_id: any_string(item['call_id'] or { json2.Any('') })
							text: any_string(item['output'] or { json2.Any('') })
							raw_type: item_type
						}
						seq++
					}
					else {}
				}
			}
			else {}
		}
	}
	return SessionTranscript{
		summary: summary
		entries: entries
	}
}

fn any_map(value json2.Any) map[string]json2.Any {
	return match value {
		map[string]json2.Any { value.clone() }
		else { map[string]json2.Any{} }
	}
}

fn any_array(value json2.Any) []json2.Any {
	return match value {
		[]json2.Any { value.clone() }
		else { []json2.Any{} }
	}
}

fn any_string(value json2.Any) string {
	return match value {
		string { value }
		int { value.str() }
		i64 { value.str() }
		f64 { value.str() }
		bool { value.str() }
		else { '' }
	}
}

fn extract_response_message_text(item map[string]json2.Any) string {
	content := any_array(item['content'] or { []json2.Any{} })
	mut parts := []string{}
	for node in content {
		entry := any_map(node)
		node_type := any_string(entry['type'] or { json2.Any('') })
		match node_type {
			'output_text', 'input_text' {
				text := any_string(entry['text'] or { json2.Any('') })
				if text.len > 0 {
					parts << text
				}
			}
			else {}
		}
	}
	return parts.join('\n\n')
}

fn extract_reasoning_text(item map[string]json2.Any) string {
	summary := any_array(item['summary'] or { []json2.Any{} })
	mut parts := []string{}
	for node in summary {
		entry := any_map(node)
		text := any_string(entry['text'] or { json2.Any('') })
		if text.len > 0 {
			parts << text
		}
	}
	if parts.len > 0 {
		return parts.join('\n')
	}
	return any_string(item['content'] or { json2.Any('') })
}

fn session_id_from_path(path string) string {
	base := os.file_name(path)
	name := if base.ends_with('.jsonl') { base[..base.len - '.jsonl'.len] } else { base }
	if name.len >= 36 {
		tail := name[name.len - 36..]
		if tail.count('-') == 4 {
			return tail
		}
	}
	return name
}

fn infer_title_from_path(path string) string {
	base := os.file_name(path)
	if base.ends_with('.jsonl') {
		return base[..base.len - '.jsonl'.len]
	}
	return base
}

fn compact_snippet(text string, query string, width int) string {
	runes := text.runes()
	if runes.len <= width {
		return text.replace('\n', ' ').trim_space()
	}
	lower := text.to_lower()
	needle := query.to_lower()
	idx := lower.index(needle) or { 0 }
	lower_runes := lower.runes()
	mut rune_idx := 0
	for i := 0; i < lower_runes.len; i++ {
		if lower_runes[..i].string().len >= idx {
			rune_idx = i
			break
		}
	}
	start := if rune_idx > width / 3 { rune_idx - width / 3 } else { 0 }
	end := if start + width < runes.len { start + width } else { runes.len }
	mut snippet := runes[start..end].string().replace('\n', ' ').trim_space()
	if start > 0 {
		snippet = '...' + snippet
	}
	if end < runes.len {
		snippet += '...'
	}
	return snippet
}

fn first_non_empty(values []string) string {
	for value in values {
		if value.len > 0 {
			return value
		}
	}
	return ''
}
