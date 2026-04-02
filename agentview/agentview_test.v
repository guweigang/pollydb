module agentview

import os

fn test_session_id_from_path() {
	assert session_id_from_path('/tmp/rollout-2026-04-01T16-26-59-019d4827-2b6a-7161-a45f-7574568616a6.jsonl') == '019d4827-2b6a-7161-a45f-7574568616a6'
}

fn test_compact_snippet_trims_long_text() {
	snippet := compact_snippet('alpha beta gamma delta epsilon zeta eta theta iota kappa lambda', 'theta', 24)
	assert snippet.contains('theta')
}

fn test_list_and_load_codex_sessions_from_fixture() {
	root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	sessions := list_codex_sessions(root, 10) or { panic(err) }
	assert sessions.len == 1
	assert sessions[0].id == 'session-001'
	assert sessions[0].title == 'Fixture thread'
	assert sessions[0].tool_calls == 1

	transcript := load_codex_session(root, 'session-001') or { panic(err) }
	assert transcript.entries.len == 5
	assert transcript.entries[0].role == 'user'
	assert transcript.entries[1].kind == .message
	assert transcript.entries[2].kind == .reasoning
	assert transcript.entries[3].kind == .tool_call
	assert transcript.entries[4].kind == .tool_result
}

fn test_pollydb_store_sync_and_query_fixture() {
	codex_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-fixture')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	stats := store.sync_codex(codex_root) or { panic(err) }
	assert stats.sessions == 1
	assert stats.entries == 5

	sessions := store.list_sessions(10) or { panic(err) }
	assert sessions.len == 1
	assert sessions[0].title == 'Fixture thread'

	transcript := store.load_session('session-001') or { panic(err) }
	assert transcript.entries.len == 5
	assert transcript.entries[0].text == 'Review this patch'

	hits := store.search('inspect', 10) or { panic(err) }
	assert hits.len > 0
	search_page := store.search_entries(SearchRequest{
		query: 'inspect'
		session_id: 'session-001'
		limit: 1
	}) or { panic(err) }
	assert search_page.total > 0
	assert search_page.hits.len == 1
	assert search_page.hits[0].session_id == 'session-001'

	list_page := store.list_sessions_page(SessionListRequest{
		query: 'fixture'
		limit: 10
	}) or { panic(err) }
	assert list_page.total == 1
	assert list_page.sessions.len == 1

	transcript_page := store.load_transcript_page(TranscriptRequest{
		session_id: 'session-001'
		offset: 1
		limit: 2
	}) or { panic(err) }
	assert transcript_page.total_entries == 5
	assert transcript_page.entries.len == 2
	assert transcript_page.entries[0].seq == 1
	assert transcript_page.entries[1].seq == 2

	second := store.sync_codex(codex_root) or { panic(err) }
	assert second.sessions == 0
	assert second.entries == 0
	assert second.skipped == 1
}
