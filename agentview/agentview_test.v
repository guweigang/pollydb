module agentview

import os
import storage

fn make_multi_session_codex_fixture(dest_root string) {
	fixture_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	os.rmdir_all(dest_root) or {}
	os.cp_all(fixture_root, dest_root, true) or { panic(err) }
	index_path := os.join_path(dest_root, 'session_index.jsonl')
	mut index_text := os.read_file(index_path) or { panic(err) }
	index_text += '\n{"id":"session-002","thread_name":"Fixture thread two","updated_at":"2026-04-02T11:05:00Z"}\n'
	os.write_file(index_path, index_text) or { panic(err) }
	source_path := os.join_path(dest_root, 'sessions', '2026', '04', '01',
		'rollout-2026-04-01T10-00-00-session-001.jsonl')
	mut second_text := os.read_file(source_path) or { panic(err) }
	second_text = second_text.replace('session-001', 'session-002')
	second_text = second_text.replace('Fixture thread', 'Fixture thread two')
	second_text = second_text.replace('Review this patch', 'Resume fixture second session')
	second_text = second_text.replace('I will inspect the patch.', 'I will continue from the next batch.')
	second_text = second_text.replace('Checking changed files', 'Continuing batched sync')
	second_text = second_text.replace('call_001', 'call_002')
	second_text = second_text.replace('2026-04-01T10:00:00Z', '2026-04-02T11:00:00Z')
	second_text = second_text.replace('2026-04-01T10:00:05Z', '2026-04-02T11:00:05Z')
	second_text = second_text.replace('2026-04-01T10:00:06Z', '2026-04-02T11:00:06Z')
	second_text = second_text.replace('2026-04-01T10:00:07Z', '2026-04-02T11:00:07Z')
	second_text = second_text.replace('2026-04-01T10:00:08Z', '2026-04-02T11:00:08Z')
	second_text = second_text.replace('2026-04-01T10:00:09Z', '2026-04-02T11:00:09Z')
	second_dir := os.join_path(dest_root, 'sessions', '2026', '04', '02')
	os.mkdir_all(second_dir) or { panic(err) }
	second_path := os.join_path(second_dir, 'rollout-2026-04-02T11-00-00-session-002.jsonl')
	os.write_file(second_path, second_text) or { panic(err) }
}

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
	search_stats := store.ensure_search_indexes_with_progress(no_search_index_progress) or {
		panic(err)
	}
	assert search_stats.changed
	assert search_stats.rows_backfilled == 0

	sessions := store.list_sessions(10) or { panic(err) }
	assert sessions.len == 1
	assert sessions[0].title == 'Fixture thread'

	transcript := store.load_session('session-001') or { panic(err) }
	assert transcript.entries.len == 5
	assert transcript.entries[0].text == 'Review this patch'

	search_execution := store.search_entries_explained(SearchRequest{
		query: 'inspect'
		session_id: 'session-001'
		limit: 1
	}) or { panic(err) }
	assert search_execution.explain.strategy in ['general_fts_prefix', 'fts_no_hits', 'session_index_substring']
	assert search_execution.explain.strategy != 'no_fts_indexes'

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
	search_second := store.ensure_search_indexes_with_progress(no_search_index_progress) or {
		panic(err)
	}
	assert search_second.rows_backfilled == 0

	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	spec := session.table_spec('sessions') or { panic(err) }
	assert spec.indexes.any(it.name == 'updated_at_cover_idx')
	entry_spec := session.table_spec('entries') or { panic(err) }
	assert entry_spec.indexes.any(it.name == 'entries_content_text_fts_idx')
	ingest_rows := session.scan_table(mut db, 'ingest_state', 0) or { panic(err) }
	entry_search_rows := session.scan_table(mut db, 'entry_search_state', 0) or { panic(err) }
	assert ingest_rows.len == 1
	assert entry_search_rows.len == 0
}

fn test_pollydb_store_sync_updates_only_changed_entries() {
	fixture_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	codex_root := os.join_path(os.vtmp_dir(), 'agentview-codex-entry-state')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-entry-state')
	os.rmdir_all(codex_root) or {}
	os.rmdir_all(store_root) or {}
	os.cp_all(fixture_root, codex_root, true) or { panic(err) }
	store := PollyDbStore.open(store_root) or { panic(err) }
	first := store.sync_codex(codex_root) or { panic(err) }
	assert first.sessions == 1
	assert first.entries == 5

	session_path := os.join_path(codex_root, 'sessions', '2026', '04', '01',
		'rollout-2026-04-01T10-00-00-session-001.jsonl')
	mut content := os.read_file(session_path) or { panic(err) }
	content = content.replace('I will inspect the patch.', 'I inspected the patch carefully.')
	os.write_file(session_path, content) or { panic(err) }

	second := store.sync_codex(codex_root) or { panic(err) }
	assert second.sessions == 1
	assert second.entries == 1
	assert second.skipped == 0

	transcript := store.load_session('session-001') or { panic(err) }
	assert transcript.entries.len == 5
	assert transcript.entries[1].text == 'I inspected the patch carefully.'

	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch('main')) or { panic(err) }
	entry_rows := session.scan_table(mut db, 'entries', 0) or { panic(err) }
	entry_state_rows := session.scan_table(mut db, 'entry_ingest_state', 0) or { panic(err) }
	entry_search_rows := session.scan_table(mut db, 'entry_search_state', 0) or { panic(err) }
	assert entry_rows.len == 5
	assert entry_state_rows.len == 5
	assert entry_search_rows.len == 0
}

fn test_pollydb_store_sync_codex_checkpoints_small_batches() {
	codex_root := os.join_path(os.dir(@FILE), 'testdata', 'codex_fixture')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-batched-sync')
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }
	stats := store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{
		batch_sessions: 1
	}, no_sync_progress, storage.ChunkConfig.default()) or { panic(err) }
	assert stats.sessions == 1
	assert stats.entries == 5

	sessions := store.list_sessions(10) or { panic(err) }
	assert sessions.len == 1
	assert sessions[0].id == 'session-001'

	transcript := store.load_session('session-001') or { panic(err) }
	assert transcript.entries.len == 5
	assert transcript.entries[0].seq == 0
}

fn test_pollydb_store_sync_codex_resume_state_across_batches() {
	codex_root := os.join_path(os.vtmp_dir(), 'agentview-codex-resume-fixture')
	store_root := os.join_path(os.vtmp_dir(), 'agentview-store-resume-state')
	make_multi_session_codex_fixture(codex_root)
	os.rmdir_all(store_root) or {}
	store := PollyDbStore.open(store_root) or { panic(err) }

	first := store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{
		batch_sessions: 1
	}, no_sync_progress, storage.ChunkConfig.default()) or { panic(err) }
	assert first.sessions == 1
	assert first.entries == 5
	assert first.skipped == 0
	assert first.paused_for_resume
	assert first.processed_sessions == 1
	assert first.total_sessions == 2
	assert first.resume_session_id == 'session-002'

	mut db := storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	mut resume := load_sync_resume_state(mut db, 'codex_sync') or { panic(err) }
	db.close() or { panic(err) }
	assert resume.last_completed_session_id == 'session-002'
	assert resume.last_completed_path.contains('session-002')

	sessions_after_first := store.list_sessions(10) or { panic(err) }
	assert sessions_after_first.len == 1
	assert sessions_after_first[0].id == 'session-002'

	second := store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{
		batch_sessions: 1
	}, no_sync_progress, storage.ChunkConfig.default()) or { panic(err) }
	assert second.sessions == 1
	assert second.entries == 5
	assert second.paused_for_resume
	assert second.processed_sessions == 2
	assert second.total_sessions == 2
	assert second.resume_session_id == 'session-001'
	db = storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	resume = load_sync_resume_state(mut db, 'codex_sync') or { panic(err) }
	db.close() or { panic(err) }
	assert resume.last_completed_session_id == 'session-001'
	assert resume.last_completed_path.contains('session-001')

	sessions_after_second := store.list_sessions(10) or { panic(err) }
	assert sessions_after_second.len == 2
	assert sessions_after_second[0].id == 'session-002'
	assert sessions_after_second[1].id == 'session-001'

	third := store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{
		batch_sessions: 1
	}, no_sync_progress, storage.ChunkConfig.default()) or { panic(err) }
	assert third.sessions == 0
	assert third.entries == 0
	assert third.skipped == 2
	assert !third.paused_for_resume
	assert third.processed_sessions == 2
	assert third.total_sessions == 2
	db = storage.PersistentDatabase.open(store_root, 'main') or { panic(err) }
	resume = load_sync_resume_state(mut db, 'codex_sync') or { panic(err) }
	db.close() or { panic(err) }
	assert resume.name == ''
}
