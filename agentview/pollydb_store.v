module agentview

import os
import query as queryapi
import storage
import time

const store_branch = 'main'
const session_list_min_updated_at = '0001-01-01T00:00:00.000000Z'
const session_list_max_updated_at = '9999-12-31T23:59:59.999999Z'
const search_index_version = 'search-v7-content-text-fts'
const agentview_general_fts_indexes = ['entries_content_text_fts_idx']
const session_summary_select_columns = ['id', 'title', 'updated_at', 'started_at', 'cwd', 'source',
	'originator', 'cli_version', 'path', 'archived', 'entry_count', 'user_turns', 'tool_calls']
const transcript_entry_select_columns = ['seq', 'timestamp', 'role', 'kind', 'tool_name', 'call_id',
	'title', 'content_text', 'content_md', 'raw_type', 'phase']

pub struct PollyDbStore {
pub:
	root_dir string
}

pub struct BrowserStoreSession {
mut:
	db      storage.PersistentDatabase
	session storage.DatabaseSession
}

pub fn PollyDbStore.open(root_dir string) !PollyDbStore {
	mut store := PollyDbStore{
		root_dir: normalize_root_dir(root_dir)
	}
	store.init_schema()!
	return store
}

pub fn (store PollyDbStore) begin_browser_session() !BrowserStoreSession {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	return BrowserStoreSession{
		db:      db
		session: session
	}
}

pub fn (mut session BrowserStoreSession) close() ! {
	session.db.close()!
}

fn normalize_root_dir(path string) string {
	if path.len == 0 {
		return path
	}
	return if os.exists(path) { os.real_path(path) } else { os.norm_path(path) }
}

fn (store PollyDbStore) init_schema() ! {
	if !os.exists(store.root_dir) {
		os.mkdir_all(store.root_dir)!
	}
	status := storage.PersistentDatabase.inspect(store.root_dir, store_branch) or {
		storage.PersistentDatabaseStatusReport{}
	}
	mut db := if status.repository_exists || status.catalog_exists {
		storage.PersistentDatabase.open(store.root_dir, store_branch)!
	} else {
		storage.PersistentDatabase.init(store.root_dir, store_branch)!
	}
	defer {
		db.close() or {}
	}
	mut changed_tables := []string{}
	if db.register_or_update_table(sessions_spec()!)! {
		changed_tables << 'sessions'
	}
	if db.register_or_update_table(ingest_state_spec()!)! {
		changed_tables << 'ingest_state'
	}
	if db.register_or_update_table(search_state_spec()!)! {
		changed_tables << 'search_state'
	}
	if db.register_or_update_table(search_meta_state_spec()!)! {
		changed_tables << 'search_meta_state'
	}
	if db.register_or_update_table(sync_resume_state_spec()!)! {
		changed_tables << 'sync_resume_state'
	}
	if db.register_or_update_table(entry_ingest_state_spec()!)! {
		changed_tables << 'entry_ingest_state'
	}
	if db.register_or_update_table(entry_search_state_spec()!)! {
		changed_tables << 'entry_search_state'
	}
	if db.register_or_update_table(entries_spec(false)!)! {
		changed_tables << 'entries'
	}
	if changed_tables.len > 0 && store_branch in db.branch_names() {
		_ = db.rebuild_indexes_at_branch(store_branch, changed_tables, storage.ChunkConfig.default())!
	}
	db.checkpoint()!
}

pub fn (store PollyDbStore) ensure_search_schema() !bool {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	changed := db.register_or_update_table(entries_spec(true)!)!
	if changed {
		db.checkpoint()!
	}
	return changed
}

pub fn desired_search_index_names() ![]string {
	spec := entries_spec(true)!
	return spec.indexes.map(it.name)
}

pub fn desired_entries_search_spec() !storage.TypedTableSpec {
	return entries_spec(true)!
}

pub fn (store PollyDbStore) ensure_search_indexes() !bool {
	stats := store.ensure_search_indexes_with_progress_and_config(no_search_index_progress,
		storage.ChunkConfig.default())!
	return stats.changed
}

pub fn (store PollyDbStore) ensure_search_indexes_with_progress(reporter SearchIndexProgressReporter) !SearchIndexStats {
	return store.ensure_search_indexes_with_progress_and_config(reporter, storage.ChunkConfig.default())
}

pub fn (store PollyDbStore) ensure_search_indexes_with_progress_and_config(reporter SearchIndexProgressReporter, cfg storage.ChunkConfig) !SearchIndexStats {
	mut total_sw := time.new_stopwatch()
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	search_spec := entries_spec(true)!
	needs_markdown_backfill := spec_has_markdown_fts_index(search_spec)
	use_split_backed := cfg.enable_split_backed_working_set
		&& !search_spec.indexes.any(it.is_field_selector())
	effective_cfg := if use_split_backed {
		cfg
	} else {
		cfg.with_split_backed_working_set(false)
	}
	reporter(SearchIndexProgress{
		phase: 'start'
	})
	ingest_states := load_existing_ingest_states_by_path(mut db) or {
		map[string]IngestState{}
	}
	entry_ingest_states := load_all_entry_ingest_states(mut db) or {
		map[string]EntryIngestState{}
	}
	entry_search_states := load_all_entry_search_states(mut db) or {
		map[string]EntrySearchState{}
	}
	mut target_entry_ids := []string{}
	mut stale_entry_search_ids := []string{}
	mut session_ids := []string{}
	mut seen_session_ids := map[string]bool{}
	for _, ingest in ingest_states {
		if !seen_session_ids[ingest.session_id] {
			seen_session_ids[ingest.session_id] = true
			session_ids << ingest.session_id
		}
	}
	current_index_version := load_search_meta_value(mut db, 'index_version') or { '' }
	mut rebuild_ms := i64(0)
	changed := db.register_or_update_table(search_spec)!
	if changed {
		db.checkpoint()!
	}
	force_rebuild := current_index_version != search_index_version
	for entry_id, ingest in entry_ingest_states {
		search := entry_search_states[entry_id] or { EntrySearchState{} }
		if search.id.len > 0 && search.entry_hash == ingest.entry_hash {
			continue
		}
		target_entry_ids << entry_id
	}
	if force_rebuild {
		target_entry_ids = load_meta_markup_entry_ids(mut db) or { []string{} }
	}
	if !needs_markdown_backfill {
		target_entry_ids = []string{}
	}
	for entry_id in entry_search_states.keys() {
		if entry_id !in entry_ingest_states {
			stale_entry_search_ids << entry_id
		}
	}
	mut backfill_sw := time.new_stopwatch()
	backfill := if needs_markdown_backfill {
		backfill_search_markdown_for_entries_with_config(mut db, target_entry_ids, effective_cfg,
			force_rebuild)!
	} else {
		SearchBackfillResult{}
	}
	backfill_ms := backfill_sw.elapsed().milliseconds()
	reporter(SearchIndexProgress{
		phase:           'backfill'
		rows_scanned:    backfill.rows_scanned
		rows_backfilled: backfill.rows_backfilled
		backfill_ms:     backfill_ms
	})
	if (changed || force_rebuild) && store_branch in db.branch_names() {
		mut rebuild_sw := time.new_stopwatch()
		db.rebuild_fts_indexes_at_branch(store_branch, ['entries'])!
		rebuild_ms = rebuild_sw.elapsed().milliseconds()
		reporter(SearchIndexProgress{
			phase:           'rebuild'
			rows_scanned:    backfill.rows_scanned
			rows_backfilled: backfill.rows_backfilled
			backfill_ms:     backfill_ms
			rebuild_ms:      rebuild_ms
		})
	}
	if target_entry_ids.len > 0 || stale_entry_search_ids.len > 0 {
		write_entry_search_states(mut db, entry_ingest_states, target_entry_ids, stale_entry_search_ids,
			effective_cfg)!
	}
	if changed || force_rebuild || backfill.rows_backfilled > 0 || target_entry_ids.len > 0
		|| stale_entry_search_ids.len > 0 {
		write_search_states(mut db, ingest_states, session_ids)!
		write_search_meta_value(mut db, 'index_version', search_index_version)!
		db.checkpoint()!
	}
	stats := SearchIndexStats{
		rows_scanned:    backfill.rows_scanned
		rows_backfilled: backfill.rows_backfilled
		backfill_ms:     backfill_ms
		rebuild_ms:      rebuild_ms
		total_ms:        total_sw.elapsed().milliseconds()
		changed:         changed || force_rebuild || backfill.rows_scanned > 0
			|| stale_entry_search_ids.len > 0
	}
	reporter(SearchIndexProgress{
		phase:           'done'
		rows_scanned:    stats.rows_scanned
		rows_backfilled: stats.rows_backfilled
		backfill_ms:     stats.backfill_ms
		rebuild_ms:      stats.rebuild_ms
		total_ms:        stats.total_ms
	})
	return stats
}

fn spec_has_markdown_fts_index(spec storage.TypedTableSpec) bool {
	for index in spec.indexes {
		if !index.is_fts() {
			continue
		}
		column := spec.table.column(index.column) or { continue }
		if column.typ == .markdown_ {
			return true
		}
	}
	return false
}

pub fn (store PollyDbStore) sync_codex(codex_root string) !SyncStats {
	return store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{},
		no_sync_progress, storage.ChunkConfig.default())
}

pub fn (store PollyDbStore) sync_codex_with_progress(codex_root string, reporter SyncProgressReporter) !SyncStats {
	return store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{},
		reporter, storage.ChunkConfig.default())
}

pub fn (store PollyDbStore) sync_codex_with_progress_and_config(codex_root string, reporter SyncProgressReporter, cfg storage.ChunkConfig) !SyncStats {
	return store.sync_codex_with_options_and_progress_and_config(codex_root, SyncOptions{},
		reporter, cfg)
}

pub fn (store PollyDbStore) sync_codex_with_options_and_progress_and_config(codex_root string, options SyncOptions, reporter SyncProgressReporter, cfg storage.ChunkConfig) !SyncStats {
	return store.sync_codex_single_pass_with_options_and_progress_and_config(codex_root,
		options, reporter, cfg)
}

fn (store PollyDbStore) sync_codex_single_pass_with_options_and_progress_and_config(codex_root string, options SyncOptions, reporter SyncProgressReporter, cfg storage.ChunkConfig) !SyncStats {
	mut total_sw := time.new_stopwatch()
	mut paths := discover_codex_session_paths(codex_root)!
	paths.sort()
	paths.reverse_in_place()
	if paths.len == 0 {
		return SyncStats{}
	}
	mut title_by_id := load_codex_session_titles(codex_root)!
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	mut existing := map[string]SessionSummary{}
	mut existing_ingest := map[string]IngestState{}
	existing_resume := load_sync_resume_state(mut db, 'codex_sync') or { SyncResumeState{} }
	resume_anchor_present := existing_resume.last_completed_path.len > 0
		&& existing_resume.last_completed_path in paths
	if store_branch_exists(mut db) {
		existing = load_existing_sessions_by_id(mut db) or {
			map[string]SessionSummary{}
		}
		existing_ingest = load_existing_ingest_states_by_path(mut db) or {
			map[string]IngestState{}
		}
	}
	mut skipped := 0
	batch_sessions := if options.batch_sessions > 0 { options.batch_sessions } else { 0 }
	mut checkpoint_count := 0
	empty_markdown := ingest_markdown_for_store(mut db, '')!
	reporter(SyncProgress{
		total_sessions:    paths.len
		imported_sessions: 0
		imported_entries:  0
		skipped_sessions:  skipped
		checkpoint_count:  checkpoint_count
		batch_sessions:    batch_sessions
		phase:             'start'
	})
	mut entry_count := 0
	mut processed := 0
	mut imported := 0
	mut total_read_ms := i64(0)
	mut total_build_ms := i64(0)
	mut total_apply_ms := i64(0)
	mut total_tx_ms := i64(0)
	mut total_aggregate_ms := i64(0)
	mut total_fast_update_ms := i64(0)
	mut total_fast_update_can_ms := i64(0)
	mut total_fast_update_path_ms := i64(0)
	mut total_fast_update_encode_ms := i64(0)
	mut total_fast_update_replace_ms := i64(0)
	mut total_fallback_ms := i64(0)
	mut total_fallback_items_ms := i64(0)
	mut total_fallback_items_key_ms := i64(0)
	mut total_fallback_items_fill_ms := i64(0)
	mut total_fallback_ops_ms := i64(0)
	mut total_fallback_ops_key_ms := i64(0)
	mut total_fallback_ops_lookup_ms := i64(0)
	mut total_fallback_ops_encode_ms := i64(0)
	mut total_fallback_ops_state_ms := i64(0)
	mut total_fallback_ops_state_new_key_ms := i64(0)
	mut total_fallback_ops_state_item_ms := i64(0)
	mut total_fallback_ops_state_cache_ms := i64(0)
	mut total_fallback_ops_index_ms := i64(0)
	mut total_fallback_build_ms := i64(0)
	mut total_fallback_build_prepare_ms := i64(0)
	mut total_fallback_build_prepare_keys_ms := i64(0)
	mut total_fallback_build_prepare_keys_sort_ms := i64(0)
	mut total_fallback_build_prepare_keys_merge_ms := i64(0)
	mut total_fallback_build_prepare_rows_ms := i64(0)
	mut total_fallback_build_prepare_rows_key_ms := i64(0)
	mut total_fallback_build_prepare_rows_value_ms := i64(0)
	mut total_fallback_build_leaf_ms := i64(0)
	mut total_fallback_build_leaf_chunk_ms := i64(0)
	mut total_fallback_build_leaf_node_ms := i64(0)
	mut total_fallback_build_leaf_node_serialize_ms := i64(0)
	mut total_fallback_build_leaf_node_cid_ms := i64(0)
	mut total_fallback_build_leaf_node_add_ms := i64(0)
	mut total_fallback_build_internal_ms := i64(0)
	mut total_commit_ms := i64(0)
	mut total_checkpoint_ms := i64(0)
	mut total_flush_ms := i64(0)
	mut batch_imported := 0
	mut last_completed_path := existing_resume.last_completed_path
	mut last_completed_session_id := existing_resume.last_completed_session_id
	mut waiting_for_resume_anchor := resume_anchor_present
	mut stopped_after_batch := false
	use_split_group_commit := cfg.enable_split_backed_working_set && existing_ingest.len > 0
	mut seeded := store_branch_exists(mut db)
	mut active_group_commit := false
	mut session := storage.GroupCommitSession{}
	mut split_session := storage.SplitGroupCommitSession{}
	mut ingest_rows := map[string]storage.TypedRowData{}
	if seeded {
		if use_split_group_commit {
			split_session = db.begin_split_group_commit_session(storage.SessionOptions.for_branch(store_branch),
				storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512),
				cfg)!
		} else {
			session = db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
				storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
		}
		active_group_commit = true
	}
	for path in paths {
		if waiting_for_resume_anchor {
			skipped++
			processed++
			reached_anchor := path == existing_resume.last_completed_path
			reporter(SyncProgress{
				total_sessions:     paths.len
				processed_sessions: processed
				imported_sessions:  imported
				imported_entries:   entry_count
				skipped_sessions:   skipped
				checkpoint_count:   checkpoint_count
				batch_sessions:     batch_sessions
				session_id:         if reached_anchor {
					existing_resume.last_completed_session_id
				} else {
					''
				}
				phase:              'resume_skip'
			})
			if reached_anchor {
				waiting_for_resume_anchor = false
			}
			continue
		}
		fingerprint := current_source_fingerprint(path)
		mut summary := SessionSummary{}
		mut needs_import := true
		mut current := SessionSummary{}
		mut found_existing := false
		state := existing_ingest[path] or { IngestState{} }
		if state.path.len > 0 && state.source_mtime_unix == fingerprint.source_mtime_unix
			&& state.source_size_bytes == fingerprint.source_size_bytes {
			if candidate := existing[state.session_id] {
				skipped++
				processed++
				reporter(SyncProgress{
					total_sessions:     paths.len
					processed_sessions: processed
					imported_sessions:  imported
					imported_entries:   entry_count
					skipped_sessions:   skipped
					checkpoint_count:   checkpoint_count
					batch_sessions:     batch_sessions
					session_id:         candidate.id
					session_title:      candidate.title
					phase:              'skip'
				})
				continue
			}
		}
		candidate_id := if state.session_id.len > 0 {
			state.session_id
		} else {
			session_id_from_path(path)
		}
		if candidate := existing[candidate_id] {
			current = candidate
			found_existing = true
		} else if existing.len > 0 {
			summary = read_codex_session_summary(path, mut title_by_id)!
			if candidate := existing[summary.id] {
				current = candidate
				found_existing = true
			}
		}
		source_changed := !(state.path.len > 0
			&& state.source_mtime_unix == fingerprint.source_mtime_unix
			&& state.source_size_bytes == fingerprint.source_size_bytes)
		if found_existing && !source_changed {
			if summary.id.len == 0 {
				summary = read_codex_session_summary(path, mut title_by_id)!
			}
			if same_session_summary(current, summary) {
				needs_import = false
			}
		}
		if !needs_import {
			if summary.id.len > 0 {
				ingest_rows[path] = build_ingest_state_row(path, summary.id, fingerprint)
				existing_ingest[path] = IngestState{
					path:              path
					session_id:        summary.id
					source_mtime_unix: fingerprint.source_mtime_unix
					source_size_bytes: fingerprint.source_size_bytes
				}
			}
			skipped++
			processed++
			reporter(SyncProgress{
				total_sessions:     paths.len
				processed_sessions: processed
				imported_sessions:  imported
				imported_entries:   entry_count
				skipped_sessions:   skipped
				checkpoint_count:   checkpoint_count
				batch_sessions:     batch_sessions
				session_id:         summary.id
				session_title:      summary.title
				phase:              'skip'
			})
			continue
		}
		mut read_sw := time.new_stopwatch()
		transcript := read_codex_transcript(path, mut title_by_id)!
		read_ms := read_sw.elapsed().milliseconds()
		total_read_ms += read_ms
		summary = transcript.summary
		if !seeded {
			seed_store_branch(mut db, summary)!
			seeded = true
		}
		if !active_group_commit {
			if use_split_group_commit {
				split_session = db.begin_split_group_commit_session(storage.SessionOptions.for_branch(store_branch),
					storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512),
					cfg)!
			} else {
				session = db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
					storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
			}
			active_group_commit = true
		}
		reporter(SyncProgress{
			total_sessions:     paths.len
			processed_sessions: processed
			imported_sessions:  imported
			imported_entries:   entry_count
			skipped_sessions:   skipped
			session_id:         summary.id
			session_title:      summary.title
			phase:              'import'
			read_ms:            read_ms
		})
		mut build_sw := time.new_stopwatch()
		existing_entry_states := load_existing_entry_ingest_states_by_session(mut db,
			summary.id) or {
			map[string]EntryIngestState{}
		}
		mut session_rows := map[string]storage.TypedRowData{}
		session_rows[summary.id] = build_session_row(transcript.summary)
		mut entry_rows := map[string]storage.TypedRowData{}
		mut entry_state_rows := map[string]storage.TypedRowData{}
		mut seen_entry_ids := map[string]bool{}
		for entry in transcript.entries {
			entry_id, row := build_session_entry_row(transcript.summary, entry, empty_markdown)
			entry_hash := fingerprint_session_entry_row(row)
			seen_entry_ids[entry_id] = true
			existing_entry_state := existing_entry_states[entry_id] or { EntryIngestState{} }
			if existing_entry_state.id.len > 0 && existing_entry_state.entry_hash == entry_hash {
				continue
			}
			entry_rows[entry_id] = row
			entry_state_rows[entry_id] = build_entry_ingest_state_row(entry_id, summary.id,
				entry_hash)
			entry_count++
		}
		mut stale_entry_ids := [][]u8{}
		for entry_id in existing_entry_states.keys() {
			if entry_id in seen_entry_ids {
				continue
			}
			stale_entry_ids << entry_id.bytes()
		}
		build_ms := build_sw.elapsed().milliseconds()
		total_build_ms += build_ms
		mut apply_sw := time.new_stopwatch()
		mut tx_ms := i64(0)
		mut aggregate_ms := i64(0)
		mut fast_update_ms := i64(0)
		mut fast_update_can_ms := i64(0)
		mut fast_update_path_ms := i64(0)
		mut fast_update_encode_ms := i64(0)
		mut fast_update_replace_ms := i64(0)
		mut fallback_ms := i64(0)
		mut fallback_items_ms := i64(0)
		mut fallback_items_key_ms := i64(0)
		mut fallback_items_fill_ms := i64(0)
		mut fallback_ops_ms := i64(0)
		mut fallback_ops_key_ms := i64(0)
		mut fallback_ops_lookup_ms := i64(0)
		mut fallback_ops_encode_ms := i64(0)
		mut fallback_ops_state_ms := i64(0)
		mut fallback_ops_state_new_key_ms := i64(0)
		mut fallback_ops_state_item_ms := i64(0)
		mut fallback_ops_state_cache_ms := i64(0)
		mut fallback_ops_index_ms := i64(0)
		mut fallback_build_ms := i64(0)
		mut fallback_build_prepare_ms := i64(0)
		mut fallback_build_prepare_keys_ms := i64(0)
		mut fallback_build_prepare_keys_sort_ms := i64(0)
		mut fallback_build_prepare_keys_merge_ms := i64(0)
		mut fallback_build_prepare_rows_ms := i64(0)
		mut fallback_build_prepare_rows_key_ms := i64(0)
		mut fallback_build_prepare_rows_value_ms := i64(0)
		mut fallback_build_leaf_ms := i64(0)
		mut fallback_build_leaf_chunk_ms := i64(0)
		mut fallback_build_leaf_node_ms := i64(0)
		mut fallback_build_leaf_node_serialize_ms := i64(0)
		mut fallback_build_leaf_node_cid_ms := i64(0)
		mut fallback_build_leaf_node_add_ms := i64(0)
		mut fallback_build_internal_ms := i64(0)
		mut commit_ms := i64(0)
		mut checkpoint_ms := i64(0)
		mut flush_ms := i64(0)
		if use_split_group_commit {
			if stale_entry_ids.len > 0 {
				delete_result := split_session.delete_rows(mut db, 'entries', stale_entry_ids,
					cfg, sync_meta('delete stale entries ${summary.id}'))!
				tx_ms += delete_result.group_commit.transaction_ms
				commit_ms += delete_result.group_commit.commit_ms
				checkpoint_ms += delete_result.group_commit.checkpoint_ms
				flush_ms += delete_result.group_commit.flush_ms
				entry_state_delete_result := split_session.delete_rows(mut db, 'entry_ingest_state',
					stale_entry_ids, cfg, sync_meta('delete stale entry ingest state ${summary.id}'))!
				tx_ms += entry_state_delete_result.group_commit.transaction_ms
				commit_ms += entry_state_delete_result.group_commit.commit_ms
				checkpoint_ms += entry_state_delete_result.group_commit.checkpoint_ms
				flush_ms += entry_state_delete_result.group_commit.flush_ms
			}
			session_result := split_session.put_rows(mut db, 'sessions', session_rows,
				cfg, sync_meta('sync session ${summary.id}'))!
			tx_ms += session_result.group_commit.transaction_ms
			commit_ms += session_result.group_commit.commit_ms
			checkpoint_ms += session_result.group_commit.checkpoint_ms
			flush_ms += session_result.group_commit.flush_ms
			if entry_rows.len > 0 {
				entry_result := split_session.put_rows(mut db, 'entries', entry_rows,
					cfg, sync_meta('sync entries ${summary.id}'))!
				tx_ms += entry_result.group_commit.transaction_ms
				commit_ms += entry_result.group_commit.commit_ms
				checkpoint_ms += entry_result.group_commit.checkpoint_ms
				flush_ms += entry_result.group_commit.flush_ms
			}
			if entry_state_rows.len > 0 {
				entry_state_result := split_session.put_rows(mut db, 'entry_ingest_state',
					entry_state_rows, cfg, sync_meta('sync entry ingest state ${summary.id}'))!
				tx_ms += entry_state_result.group_commit.transaction_ms
				commit_ms += entry_state_result.group_commit.commit_ms
				checkpoint_ms += entry_state_result.group_commit.checkpoint_ms
				flush_ms += entry_state_result.group_commit.flush_ms
			}
		} else {
			if stale_entry_ids.len > 0 {
				delete_result := session.delete_rows(mut db, 'entries', stale_entry_ids,
					cfg, sync_meta('delete stale entries ${summary.id}'))!
				tx_ms += delete_result.group_commit.transaction_ms
				aggregate_ms += delete_result.timings.aggregate_ms
				fast_update_ms += delete_result.timings.fast_update_ms
				fast_update_can_ms += delete_result.timings.fast_update_can_ms
				fast_update_path_ms += delete_result.timings.fast_update_path_ms
				fast_update_encode_ms += delete_result.timings.fast_update_encode_ms
				fast_update_replace_ms += delete_result.timings.fast_update_replace_ms
				fallback_ms += delete_result.timings.fallback_ms
				fallback_items_ms += delete_result.timings.fallback_items_ms
				fallback_items_key_ms += delete_result.timings.fallback_items_key_ms
				fallback_items_fill_ms += delete_result.timings.fallback_items_fill_ms
				fallback_ops_ms += delete_result.timings.fallback_ops_ms
				fallback_ops_key_ms += delete_result.timings.fallback_ops_key_ms
				fallback_ops_lookup_ms += delete_result.timings.fallback_ops_lookup_ms
				fallback_ops_encode_ms += delete_result.timings.fallback_ops_encode_ms
				fallback_ops_state_ms += delete_result.timings.fallback_ops_state_ms
				fallback_ops_state_new_key_ms += delete_result.timings.fallback_ops_state_new_key_ms
				fallback_ops_state_item_ms += delete_result.timings.fallback_ops_state_item_ms
				fallback_ops_state_cache_ms += delete_result.timings.fallback_ops_state_cache_ms
				fallback_ops_index_ms += delete_result.timings.fallback_ops_index_ms
				fallback_build_ms += delete_result.timings.fallback_build_ms
				fallback_build_prepare_ms += delete_result.timings.fallback_build_prepare_ms
				fallback_build_prepare_keys_ms += delete_result.timings.fallback_build_prepare_keys_ms
				fallback_build_prepare_keys_sort_ms += delete_result.timings.fallback_build_prepare_keys_sort_ms
				fallback_build_prepare_keys_merge_ms += delete_result.timings.fallback_build_prepare_keys_merge_ms
				fallback_build_prepare_rows_ms += delete_result.timings.fallback_build_prepare_rows_ms
				fallback_build_prepare_rows_key_ms += delete_result.timings.fallback_build_prepare_rows_key_ms
				fallback_build_prepare_rows_value_ms += delete_result.timings.fallback_build_prepare_rows_value_ms
				fallback_build_leaf_ms += delete_result.timings.fallback_build_leaf_ms
				fallback_build_leaf_chunk_ms += delete_result.timings.fallback_build_leaf_chunk_ms
				fallback_build_leaf_node_ms += delete_result.timings.fallback_build_leaf_node_ms
				fallback_build_leaf_node_serialize_ms += delete_result.timings.fallback_build_leaf_node_serialize_ms
				fallback_build_leaf_node_cid_ms += delete_result.timings.fallback_build_leaf_node_cid_ms
				fallback_build_leaf_node_add_ms += delete_result.timings.fallback_build_leaf_node_add_ms
				fallback_build_internal_ms += delete_result.timings.fallback_build_internal_ms
				commit_ms += delete_result.group_commit.commit_ms
				checkpoint_ms += delete_result.group_commit.checkpoint_ms
				flush_ms += delete_result.group_commit.flush_ms
				entry_state_delete_result := session.delete_rows(mut db, 'entry_ingest_state',
					stale_entry_ids, cfg, sync_meta('delete stale entry ingest state ${summary.id}'))!
				tx_ms += entry_state_delete_result.group_commit.transaction_ms
				aggregate_ms += entry_state_delete_result.timings.aggregate_ms
				fast_update_ms += entry_state_delete_result.timings.fast_update_ms
				fast_update_can_ms += entry_state_delete_result.timings.fast_update_can_ms
				fast_update_path_ms += entry_state_delete_result.timings.fast_update_path_ms
				fast_update_encode_ms += entry_state_delete_result.timings.fast_update_encode_ms
				fast_update_replace_ms += entry_state_delete_result.timings.fast_update_replace_ms
				fallback_ms += entry_state_delete_result.timings.fallback_ms
				fallback_items_ms += entry_state_delete_result.timings.fallback_items_ms
				fallback_items_key_ms += entry_state_delete_result.timings.fallback_items_key_ms
				fallback_items_fill_ms += entry_state_delete_result.timings.fallback_items_fill_ms
				fallback_ops_ms += entry_state_delete_result.timings.fallback_ops_ms
				fallback_ops_key_ms += entry_state_delete_result.timings.fallback_ops_key_ms
				fallback_ops_lookup_ms += entry_state_delete_result.timings.fallback_ops_lookup_ms
				fallback_ops_encode_ms += entry_state_delete_result.timings.fallback_ops_encode_ms
				fallback_ops_state_ms += entry_state_delete_result.timings.fallback_ops_state_ms
				fallback_ops_state_new_key_ms += entry_state_delete_result.timings.fallback_ops_state_new_key_ms
				fallback_ops_state_item_ms += entry_state_delete_result.timings.fallback_ops_state_item_ms
				fallback_ops_state_cache_ms += entry_state_delete_result.timings.fallback_ops_state_cache_ms
				fallback_ops_index_ms += entry_state_delete_result.timings.fallback_ops_index_ms
				fallback_build_ms += entry_state_delete_result.timings.fallback_build_ms
				fallback_build_prepare_ms += entry_state_delete_result.timings.fallback_build_prepare_ms
				fallback_build_prepare_keys_ms += entry_state_delete_result.timings.fallback_build_prepare_keys_ms
				fallback_build_prepare_keys_sort_ms += entry_state_delete_result.timings.fallback_build_prepare_keys_sort_ms
				fallback_build_prepare_keys_merge_ms += entry_state_delete_result.timings.fallback_build_prepare_keys_merge_ms
				fallback_build_prepare_rows_ms += entry_state_delete_result.timings.fallback_build_prepare_rows_ms
				fallback_build_prepare_rows_key_ms += entry_state_delete_result.timings.fallback_build_prepare_rows_key_ms
				fallback_build_prepare_rows_value_ms += entry_state_delete_result.timings.fallback_build_prepare_rows_value_ms
				fallback_build_leaf_ms += entry_state_delete_result.timings.fallback_build_leaf_ms
				fallback_build_leaf_chunk_ms += entry_state_delete_result.timings.fallback_build_leaf_chunk_ms
				fallback_build_leaf_node_ms += entry_state_delete_result.timings.fallback_build_leaf_node_ms
				fallback_build_leaf_node_serialize_ms += entry_state_delete_result.timings.fallback_build_leaf_node_serialize_ms
				fallback_build_leaf_node_cid_ms += entry_state_delete_result.timings.fallback_build_leaf_node_cid_ms
				fallback_build_leaf_node_add_ms += entry_state_delete_result.timings.fallback_build_leaf_node_add_ms
				fallback_build_internal_ms += entry_state_delete_result.timings.fallback_build_internal_ms
				commit_ms += entry_state_delete_result.group_commit.commit_ms
				checkpoint_ms += entry_state_delete_result.group_commit.checkpoint_ms
				flush_ms += entry_state_delete_result.group_commit.flush_ms
			}
			session_result := session.put_rows(mut db, 'sessions', session_rows, cfg,
				sync_meta('sync session ${summary.id}'))!
			tx_ms += session_result.group_commit.transaction_ms
			aggregate_ms += session_result.timings.aggregate_ms
			fast_update_ms += session_result.timings.fast_update_ms
			fast_update_can_ms += session_result.timings.fast_update_can_ms
			fast_update_path_ms += session_result.timings.fast_update_path_ms
			fast_update_encode_ms += session_result.timings.fast_update_encode_ms
			fast_update_replace_ms += session_result.timings.fast_update_replace_ms
			fallback_ms += session_result.timings.fallback_ms
			fallback_items_ms += session_result.timings.fallback_items_ms
			fallback_items_key_ms += session_result.timings.fallback_items_key_ms
			fallback_items_fill_ms += session_result.timings.fallback_items_fill_ms
			fallback_ops_ms += session_result.timings.fallback_ops_ms
			fallback_ops_key_ms += session_result.timings.fallback_ops_key_ms
			fallback_ops_lookup_ms += session_result.timings.fallback_ops_lookup_ms
			fallback_ops_encode_ms += session_result.timings.fallback_ops_encode_ms
			fallback_ops_state_ms += session_result.timings.fallback_ops_state_ms
			fallback_ops_state_new_key_ms += session_result.timings.fallback_ops_state_new_key_ms
			fallback_ops_state_item_ms += session_result.timings.fallback_ops_state_item_ms
			fallback_ops_state_cache_ms += session_result.timings.fallback_ops_state_cache_ms
			fallback_ops_index_ms += session_result.timings.fallback_ops_index_ms
			fallback_build_ms += session_result.timings.fallback_build_ms
			fallback_build_prepare_ms += session_result.timings.fallback_build_prepare_ms
			fallback_build_prepare_keys_ms += session_result.timings.fallback_build_prepare_keys_ms
			fallback_build_prepare_keys_sort_ms += session_result.timings.fallback_build_prepare_keys_sort_ms
			fallback_build_prepare_keys_merge_ms += session_result.timings.fallback_build_prepare_keys_merge_ms
			fallback_build_prepare_rows_ms += session_result.timings.fallback_build_prepare_rows_ms
			fallback_build_prepare_rows_key_ms += session_result.timings.fallback_build_prepare_rows_key_ms
			fallback_build_prepare_rows_value_ms += session_result.timings.fallback_build_prepare_rows_value_ms
			fallback_build_leaf_ms += session_result.timings.fallback_build_leaf_ms
			fallback_build_leaf_chunk_ms += session_result.timings.fallback_build_leaf_chunk_ms
			fallback_build_leaf_node_ms += session_result.timings.fallback_build_leaf_node_ms
			fallback_build_leaf_node_serialize_ms += session_result.timings.fallback_build_leaf_node_serialize_ms
			fallback_build_leaf_node_cid_ms += session_result.timings.fallback_build_leaf_node_cid_ms
			fallback_build_leaf_node_add_ms += session_result.timings.fallback_build_leaf_node_add_ms
			fallback_build_internal_ms += session_result.timings.fallback_build_internal_ms
			commit_ms += session_result.group_commit.commit_ms
			checkpoint_ms += session_result.group_commit.checkpoint_ms
			flush_ms += session_result.group_commit.flush_ms
			if entry_rows.len > 0 {
				entry_result := session.put_rows(mut db, 'entries', entry_rows, cfg, sync_meta('sync entries ${summary.id}'))!
				tx_ms += entry_result.group_commit.transaction_ms
				aggregate_ms += entry_result.timings.aggregate_ms
				fast_update_ms += entry_result.timings.fast_update_ms
				fast_update_can_ms += entry_result.timings.fast_update_can_ms
				fast_update_path_ms += entry_result.timings.fast_update_path_ms
				fast_update_encode_ms += entry_result.timings.fast_update_encode_ms
				fast_update_replace_ms += entry_result.timings.fast_update_replace_ms
				fallback_ms += entry_result.timings.fallback_ms
				fallback_items_ms += entry_result.timings.fallback_items_ms
				fallback_items_key_ms += entry_result.timings.fallback_items_key_ms
				fallback_items_fill_ms += entry_result.timings.fallback_items_fill_ms
				fallback_ops_ms += entry_result.timings.fallback_ops_ms
				fallback_ops_key_ms += entry_result.timings.fallback_ops_key_ms
				fallback_ops_lookup_ms += entry_result.timings.fallback_ops_lookup_ms
				fallback_ops_encode_ms += entry_result.timings.fallback_ops_encode_ms
				fallback_ops_state_ms += entry_result.timings.fallback_ops_state_ms
				fallback_ops_state_new_key_ms += entry_result.timings.fallback_ops_state_new_key_ms
				fallback_ops_state_item_ms += entry_result.timings.fallback_ops_state_item_ms
				fallback_ops_state_cache_ms += entry_result.timings.fallback_ops_state_cache_ms
				fallback_ops_index_ms += entry_result.timings.fallback_ops_index_ms
				fallback_build_ms += entry_result.timings.fallback_build_ms
				fallback_build_prepare_ms += entry_result.timings.fallback_build_prepare_ms
				fallback_build_prepare_keys_ms += entry_result.timings.fallback_build_prepare_keys_ms
				fallback_build_prepare_keys_sort_ms += entry_result.timings.fallback_build_prepare_keys_sort_ms
				fallback_build_prepare_keys_merge_ms += entry_result.timings.fallback_build_prepare_keys_merge_ms
				fallback_build_prepare_rows_ms += entry_result.timings.fallback_build_prepare_rows_ms
				fallback_build_prepare_rows_key_ms += entry_result.timings.fallback_build_prepare_rows_key_ms
				fallback_build_prepare_rows_value_ms += entry_result.timings.fallback_build_prepare_rows_value_ms
				fallback_build_leaf_ms += entry_result.timings.fallback_build_leaf_ms
				fallback_build_leaf_chunk_ms += entry_result.timings.fallback_build_leaf_chunk_ms
				fallback_build_leaf_node_ms += entry_result.timings.fallback_build_leaf_node_ms
				fallback_build_leaf_node_serialize_ms += entry_result.timings.fallback_build_leaf_node_serialize_ms
				fallback_build_leaf_node_cid_ms += entry_result.timings.fallback_build_leaf_node_cid_ms
				fallback_build_leaf_node_add_ms += entry_result.timings.fallback_build_leaf_node_add_ms
				fallback_build_internal_ms += entry_result.timings.fallback_build_internal_ms
				commit_ms += entry_result.group_commit.commit_ms
				checkpoint_ms += entry_result.group_commit.checkpoint_ms
				flush_ms += entry_result.group_commit.flush_ms
			}
			if entry_state_rows.len > 0 {
				entry_state_result := session.put_rows(mut db, 'entry_ingest_state', entry_state_rows,
					cfg, sync_meta('sync entry ingest state ${summary.id}'))!
				tx_ms += entry_state_result.group_commit.transaction_ms
				aggregate_ms += entry_state_result.timings.aggregate_ms
				fast_update_ms += entry_state_result.timings.fast_update_ms
				fast_update_can_ms += entry_state_result.timings.fast_update_can_ms
				fast_update_path_ms += entry_state_result.timings.fast_update_path_ms
				fast_update_encode_ms += entry_state_result.timings.fast_update_encode_ms
				fast_update_replace_ms += entry_state_result.timings.fast_update_replace_ms
				fallback_ms += entry_state_result.timings.fallback_ms
				fallback_items_ms += entry_state_result.timings.fallback_items_ms
				fallback_items_key_ms += entry_state_result.timings.fallback_items_key_ms
				fallback_items_fill_ms += entry_state_result.timings.fallback_items_fill_ms
				fallback_ops_ms += entry_state_result.timings.fallback_ops_ms
				fallback_ops_key_ms += entry_state_result.timings.fallback_ops_key_ms
				fallback_ops_lookup_ms += entry_state_result.timings.fallback_ops_lookup_ms
				fallback_ops_encode_ms += entry_state_result.timings.fallback_ops_encode_ms
				fallback_ops_state_ms += entry_state_result.timings.fallback_ops_state_ms
				fallback_ops_state_new_key_ms += entry_state_result.timings.fallback_ops_state_new_key_ms
				fallback_ops_state_item_ms += entry_state_result.timings.fallback_ops_state_item_ms
				fallback_ops_state_cache_ms += entry_state_result.timings.fallback_ops_state_cache_ms
				fallback_ops_index_ms += entry_state_result.timings.fallback_ops_index_ms
				fallback_build_ms += entry_state_result.timings.fallback_build_ms
				fallback_build_prepare_ms += entry_state_result.timings.fallback_build_prepare_ms
				fallback_build_prepare_keys_ms += entry_state_result.timings.fallback_build_prepare_keys_ms
				fallback_build_prepare_keys_sort_ms += entry_state_result.timings.fallback_build_prepare_keys_sort_ms
				fallback_build_prepare_keys_merge_ms += entry_state_result.timings.fallback_build_prepare_keys_merge_ms
				fallback_build_prepare_rows_ms += entry_state_result.timings.fallback_build_prepare_rows_ms
				fallback_build_prepare_rows_key_ms += entry_state_result.timings.fallback_build_prepare_rows_key_ms
				fallback_build_prepare_rows_value_ms += entry_state_result.timings.fallback_build_prepare_rows_value_ms
				fallback_build_leaf_ms += entry_state_result.timings.fallback_build_leaf_ms
				fallback_build_leaf_chunk_ms += entry_state_result.timings.fallback_build_leaf_chunk_ms
				fallback_build_leaf_node_ms += entry_state_result.timings.fallback_build_leaf_node_ms
				fallback_build_leaf_node_serialize_ms += entry_state_result.timings.fallback_build_leaf_node_serialize_ms
				fallback_build_leaf_node_cid_ms += entry_state_result.timings.fallback_build_leaf_node_cid_ms
				fallback_build_leaf_node_add_ms += entry_state_result.timings.fallback_build_leaf_node_add_ms
				fallback_build_internal_ms += entry_state_result.timings.fallback_build_internal_ms
				commit_ms += entry_state_result.group_commit.commit_ms
				checkpoint_ms += entry_state_result.group_commit.checkpoint_ms
				flush_ms += entry_state_result.group_commit.flush_ms
			}
		}
		ingest_rows[path] = build_ingest_state_row(path, summary.id, fingerprint)
		existing_ingest[path] = IngestState{
			path:              path
			session_id:        summary.id
			source_mtime_unix: fingerprint.source_mtime_unix
			source_size_bytes: fingerprint.source_size_bytes
		}
		existing[summary.id] = summary
		apply_ms := apply_sw.elapsed().milliseconds()
		total_apply_ms += apply_ms
		total_tx_ms += tx_ms
		total_aggregate_ms += aggregate_ms
		total_fast_update_ms += fast_update_ms
		total_fast_update_can_ms += fast_update_can_ms
		total_fast_update_path_ms += fast_update_path_ms
		total_fast_update_encode_ms += fast_update_encode_ms
		total_fast_update_replace_ms += fast_update_replace_ms
		total_fallback_ms += fallback_ms
		total_fallback_items_ms += fallback_items_ms
		total_fallback_items_key_ms += fallback_items_key_ms
		total_fallback_items_fill_ms += fallback_items_fill_ms
		total_fallback_ops_ms += fallback_ops_ms
		total_fallback_ops_key_ms += fallback_ops_key_ms
		total_fallback_ops_lookup_ms += fallback_ops_lookup_ms
		total_fallback_ops_encode_ms += fallback_ops_encode_ms
		total_fallback_ops_state_ms += fallback_ops_state_ms
		total_fallback_ops_state_new_key_ms += fallback_ops_state_new_key_ms
		total_fallback_ops_state_item_ms += fallback_ops_state_item_ms
		total_fallback_ops_state_cache_ms += fallback_ops_state_cache_ms
		total_fallback_ops_index_ms += fallback_ops_index_ms
		total_fallback_build_ms += fallback_build_ms
		total_fallback_build_prepare_ms += fallback_build_prepare_ms
		total_fallback_build_prepare_keys_ms += fallback_build_prepare_keys_ms
		total_fallback_build_prepare_keys_sort_ms += fallback_build_prepare_keys_sort_ms
		total_fallback_build_prepare_keys_merge_ms += fallback_build_prepare_keys_merge_ms
		total_fallback_build_prepare_rows_ms += fallback_build_prepare_rows_ms
		total_fallback_build_prepare_rows_key_ms += fallback_build_prepare_rows_key_ms
		total_fallback_build_prepare_rows_value_ms += fallback_build_prepare_rows_value_ms
		total_fallback_build_leaf_ms += fallback_build_leaf_ms
		total_fallback_build_leaf_chunk_ms += fallback_build_leaf_chunk_ms
		total_fallback_build_leaf_node_ms += fallback_build_leaf_node_ms
		total_fallback_build_leaf_node_serialize_ms += fallback_build_leaf_node_serialize_ms
		total_fallback_build_leaf_node_cid_ms += fallback_build_leaf_node_cid_ms
		total_fallback_build_leaf_node_add_ms += fallback_build_leaf_node_add_ms
		total_fallback_build_internal_ms += fallback_build_internal_ms
		total_commit_ms += commit_ms
		total_checkpoint_ms += checkpoint_ms
		total_flush_ms += flush_ms
		reporter(SyncProgress{
			total_sessions:                        paths.len
			processed_sessions:                    processed
			imported_sessions:                     imported
			imported_entries:                      entry_count
			skipped_sessions:                      skipped
			checkpoint_count:                      checkpoint_count
			batch_sessions:                        batch_sessions
			session_id:                            summary.id
			session_title:                         summary.title
			phase:                                 'profile'
			read_ms:                               read_ms
			build_ms:                              build_ms
			apply_ms:                              apply_ms
			tx_ms:                                 tx_ms
			aggregate_ms:                          aggregate_ms
			fast_update_ms:                        fast_update_ms
			fast_update_can_ms:                    fast_update_can_ms
			fast_update_path_ms:                   fast_update_path_ms
			fast_update_encode_ms:                 fast_update_encode_ms
			fast_update_replace_ms:                fast_update_replace_ms
			fallback_ms:                           fallback_ms
			fallback_items_ms:                     fallback_items_ms
			fallback_items_key_ms:                 fallback_items_key_ms
			fallback_items_fill_ms:                fallback_items_fill_ms
			fallback_ops_ms:                       fallback_ops_ms
			fallback_ops_key_ms:                   fallback_ops_key_ms
			fallback_ops_lookup_ms:                fallback_ops_lookup_ms
			fallback_ops_encode_ms:                fallback_ops_encode_ms
			fallback_ops_state_ms:                 fallback_ops_state_ms
			fallback_ops_state_new_key_ms:         fallback_ops_state_new_key_ms
			fallback_ops_state_item_ms:            fallback_ops_state_item_ms
			fallback_ops_state_cache_ms:           fallback_ops_state_cache_ms
			fallback_ops_index_ms:                 fallback_ops_index_ms
			fallback_build_ms:                     fallback_build_ms
			fallback_build_prepare_ms:             fallback_build_prepare_ms
			fallback_build_prepare_keys_ms:        fallback_build_prepare_keys_ms
			fallback_build_prepare_keys_sort_ms:   fallback_build_prepare_keys_sort_ms
			fallback_build_prepare_keys_merge_ms:  fallback_build_prepare_keys_merge_ms
			fallback_build_prepare_rows_ms:        fallback_build_prepare_rows_ms
			fallback_build_prepare_rows_key_ms:    fallback_build_prepare_rows_key_ms
			fallback_build_prepare_rows_value_ms:  fallback_build_prepare_rows_value_ms
			fallback_build_leaf_ms:                fallback_build_leaf_ms
			fallback_build_leaf_chunk_ms:          fallback_build_leaf_chunk_ms
			fallback_build_leaf_node_ms:           fallback_build_leaf_node_ms
			fallback_build_leaf_node_serialize_ms: fallback_build_leaf_node_serialize_ms
			fallback_build_leaf_node_cid_ms:       fallback_build_leaf_node_cid_ms
			fallback_build_leaf_node_add_ms:       fallback_build_leaf_node_add_ms
			fallback_build_internal_ms:            fallback_build_internal_ms
			commit_ms:                             commit_ms
			checkpoint_ms:                         checkpoint_ms
			flush_ms:                              flush_ms
			total_ms:                              read_ms + build_ms + apply_ms
		})
		imported++
		processed++
		batch_imported++
		last_completed_path = path
		last_completed_session_id = summary.id
		if batch_sessions > 0 && batch_imported >= batch_sessions {
			flush_sync_batch(mut db, mut session, mut split_session, use_split_group_commit,
				ingest_rows, cfg)!
			ingest_rows = map[string]storage.TypedRowData{}
			batch_imported = 0
			active_group_commit = false
			checkpoint_count++
			write_sync_resume_state(mut db, SyncResumeState{
				name:                      'codex_sync'
				last_completed_path:       last_completed_path
				last_completed_session_id: last_completed_session_id
				completed_batches:         existing_resume.completed_batches + checkpoint_count
				completed_sessions:        existing_resume.completed_sessions + imported
			})!
			reporter(SyncProgress{
				total_sessions:     paths.len
				processed_sessions: processed
				imported_sessions:  imported
				imported_entries:   entry_count
				skipped_sessions:   skipped
				checkpoint_count:   checkpoint_count
				batch_sessions:     batch_sessions
				phase:              'checkpoint'
				checkpoint_ms:      total_checkpoint_ms
			})
			stopped_after_batch = true
			break
		}
	}
	mut finish_sw := time.new_stopwatch()
	if seeded && active_group_commit {
		if ingest_rows.len > 0 || batch_imported > 0 || imported == 0 {
			flush_sync_batch(mut db, mut session, mut split_session, use_split_group_commit,
				ingest_rows, cfg)!
			checkpoint_count++
			if imported > 0 {
				write_sync_resume_state(mut db, SyncResumeState{
					name:                      'codex_sync'
					last_completed_path:       last_completed_path
					last_completed_session_id: last_completed_session_id
					completed_batches:         existing_resume.completed_batches + checkpoint_count
					completed_sessions:        existing_resume.completed_sessions + imported
				})!
			}
		}
	}
	if !stopped_after_batch {
		clear_sync_resume_state(mut db, 'codex_sync')!
		last_completed_path = ''
		last_completed_session_id = ''
	}
	finish_ms := finish_sw.elapsed().milliseconds()
	reporter(SyncProgress{
		total_sessions:                        paths.len
		processed_sessions:                    processed
		imported_sessions:                     imported
		imported_entries:                      entry_count
		skipped_sessions:                      skipped
		checkpoint_count:                      checkpoint_count
		batch_sessions:                        batch_sessions
		phase:                                 'done'
		read_ms:                               total_read_ms
		build_ms:                              total_build_ms
		apply_ms:                              total_apply_ms
		tx_ms:                                 total_tx_ms
		aggregate_ms:                          total_aggregate_ms
		fast_update_ms:                        total_fast_update_ms
		fast_update_can_ms:                    total_fast_update_can_ms
		fast_update_path_ms:                   total_fast_update_path_ms
		fast_update_encode_ms:                 total_fast_update_encode_ms
		fast_update_replace_ms:                total_fast_update_replace_ms
		fallback_ms:                           total_fallback_ms
		fallback_items_ms:                     total_fallback_items_ms
		fallback_items_key_ms:                 total_fallback_items_key_ms
		fallback_items_fill_ms:                total_fallback_items_fill_ms
		fallback_ops_ms:                       total_fallback_ops_ms
		fallback_ops_key_ms:                   total_fallback_ops_key_ms
		fallback_ops_lookup_ms:                total_fallback_ops_lookup_ms
		fallback_ops_encode_ms:                total_fallback_ops_encode_ms
		fallback_ops_state_ms:                 total_fallback_ops_state_ms
		fallback_ops_state_new_key_ms:         total_fallback_ops_state_new_key_ms
		fallback_ops_state_item_ms:            total_fallback_ops_state_item_ms
		fallback_ops_state_cache_ms:           total_fallback_ops_state_cache_ms
		fallback_ops_index_ms:                 total_fallback_ops_index_ms
		fallback_build_ms:                     total_fallback_build_ms
		fallback_build_prepare_ms:             total_fallback_build_prepare_ms
		fallback_build_prepare_keys_ms:        total_fallback_build_prepare_keys_ms
		fallback_build_prepare_keys_sort_ms:   total_fallback_build_prepare_keys_sort_ms
		fallback_build_prepare_keys_merge_ms:  total_fallback_build_prepare_keys_merge_ms
		fallback_build_prepare_rows_ms:        total_fallback_build_prepare_rows_ms
		fallback_build_prepare_rows_key_ms:    total_fallback_build_prepare_rows_key_ms
		fallback_build_prepare_rows_value_ms:  total_fallback_build_prepare_rows_value_ms
		fallback_build_leaf_ms:                total_fallback_build_leaf_ms
		fallback_build_leaf_chunk_ms:          total_fallback_build_leaf_chunk_ms
		fallback_build_leaf_node_ms:           total_fallback_build_leaf_node_ms
		fallback_build_leaf_node_serialize_ms: total_fallback_build_leaf_node_serialize_ms
		fallback_build_leaf_node_cid_ms:       total_fallback_build_leaf_node_cid_ms
		fallback_build_leaf_node_add_ms:       total_fallback_build_leaf_node_add_ms
		fallback_build_internal_ms:            total_fallback_build_internal_ms
		commit_ms:                             total_commit_ms
		checkpoint_ms:                         total_checkpoint_ms
		flush_ms:                              total_flush_ms
		finish_ms:                             finish_ms
		total_ms:                              total_sw.elapsed().milliseconds()
	})
	return SyncStats{
		sessions:                              imported
		entries:                               entry_count
		skipped:                               skipped
		processed_sessions:                    processed
		total_sessions:                        paths.len
		paused_for_resume:                     stopped_after_batch
		resume_session_id:                     if stopped_after_batch {
			last_completed_session_id
		} else {
			''
		}
		resume_path:                           if stopped_after_batch {
			last_completed_path
		} else {
			''
		}
		read_ms:                               total_read_ms
		build_ms:                              total_build_ms
		apply_ms:                              total_apply_ms
		tx_ms:                                 total_tx_ms
		aggregate_ms:                          total_aggregate_ms
		fast_update_ms:                        total_fast_update_ms
		fast_update_can_ms:                    total_fast_update_can_ms
		fast_update_path_ms:                   total_fast_update_path_ms
		fast_update_encode_ms:                 total_fast_update_encode_ms
		fast_update_replace_ms:                total_fast_update_replace_ms
		fallback_ms:                           total_fallback_ms
		fallback_items_ms:                     total_fallback_items_ms
		fallback_items_key_ms:                 total_fallback_items_key_ms
		fallback_items_fill_ms:                total_fallback_items_fill_ms
		fallback_ops_ms:                       total_fallback_ops_ms
		fallback_ops_key_ms:                   total_fallback_ops_key_ms
		fallback_ops_lookup_ms:                total_fallback_ops_lookup_ms
		fallback_ops_encode_ms:                total_fallback_ops_encode_ms
		fallback_ops_state_ms:                 total_fallback_ops_state_ms
		fallback_ops_state_new_key_ms:         total_fallback_ops_state_new_key_ms
		fallback_ops_state_item_ms:            total_fallback_ops_state_item_ms
		fallback_ops_state_cache_ms:           total_fallback_ops_state_cache_ms
		fallback_ops_index_ms:                 total_fallback_ops_index_ms
		fallback_build_ms:                     total_fallback_build_ms
		fallback_build_prepare_ms:             total_fallback_build_prepare_ms
		fallback_build_prepare_keys_ms:        total_fallback_build_prepare_keys_ms
		fallback_build_prepare_keys_sort_ms:   total_fallback_build_prepare_keys_sort_ms
		fallback_build_prepare_keys_merge_ms:  total_fallback_build_prepare_keys_merge_ms
		fallback_build_prepare_rows_ms:        total_fallback_build_prepare_rows_ms
		fallback_build_prepare_rows_key_ms:    total_fallback_build_prepare_rows_key_ms
		fallback_build_prepare_rows_value_ms:  total_fallback_build_prepare_rows_value_ms
		fallback_build_leaf_ms:                total_fallback_build_leaf_ms
		fallback_build_leaf_chunk_ms:          total_fallback_build_leaf_chunk_ms
		fallback_build_leaf_node_ms:           total_fallback_build_leaf_node_ms
		fallback_build_leaf_node_serialize_ms: total_fallback_build_leaf_node_serialize_ms
		fallback_build_leaf_node_cid_ms:       total_fallback_build_leaf_node_cid_ms
		fallback_build_leaf_node_add_ms:       total_fallback_build_leaf_node_add_ms
		fallback_build_internal_ms:            total_fallback_build_internal_ms
		commit_ms:                             total_commit_ms
		checkpoint_ms:                         total_checkpoint_ms
		flush_ms:                              total_flush_ms
		finish_ms:                             finish_ms
		total_ms:                              total_sw.elapsed().milliseconds()
	}
}

fn flush_sync_batch(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, mut split_session storage.SplitGroupCommitSession, use_split_group_commit bool, ingest_rows map[string]storage.TypedRowData, cfg storage.ChunkConfig) ! {
	if use_split_group_commit {
		if ingest_rows.len > 0 {
			_ = split_session.put_rows(mut db, 'ingest_state', ingest_rows, cfg, sync_meta('sync ingest state'))!
		}
		split_session.finish(mut db)!
	} else {
		if ingest_rows.len > 0 {
			_ = session.put_rows(mut db, 'ingest_state', ingest_rows, cfg, sync_meta('sync ingest state'))!
		}
		session.finish(mut db)!
	}
	db.checkpoint()!
}

fn no_sync_progress(_ SyncProgress) {}

fn no_search_index_progress(_ SearchIndexProgress) {}

pub fn (store PollyDbStore) list_sessions(limit int) ![]SessionSummary {
	result := store.list_sessions_page(SessionListRequest{
		limit: limit
	})!
	return result.sessions
}

pub fn (store PollyDbStore) list_sessions_page(request SessionListRequest) !SessionListResult {
	return (store.list_sessions_page_explained(request)!).result
}

pub fn (mut store_session BrowserStoreSession) list_sessions_page_explained(request SessionListRequest) !SessionListExecution {
	mut total_sw := time.new_stopwatch()
	return list_sessions_page_in_session(mut store_session.db, store_session.session,
		request, storage.PersistentDatabaseOpenTimings{}, 0, mut total_sw)
}

pub fn (store PollyDbStore) list_sessions_page_explained(request SessionListRequest) !SessionListExecution {
	mut total_sw := time.new_stopwatch()
	open_result := storage.PersistentDatabase.open_profiled(store.root_dir, store_branch)!
	mut db := open_result.database
	defer {
		db.close() or {}
	}
	mut session_sw := time.new_stopwatch()
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	session_ms := session_sw.elapsed().milliseconds()
	return list_sessions_page_in_session(mut db, session, request, open_result.timings,
		session_ms, mut total_sw)!
}

fn list_sessions_page_in_session(mut db storage.PersistentDatabase, session storage.DatabaseSession, request SessionListRequest, open_timings storage.PersistentDatabaseOpenTimings, session_ms i64, mut total_sw time.StopWatch) !SessionListExecution {
	if request.query.len == 0 && request.cwd_prefix.len == 0 && request.source.len == 0
		&& request.include_archived {
		fetch_limit := max_int(request.offset + max_int(request.limit, 0), max_int(request.limit,
			0))
		mut query_db := queryapi.open_database(db.root_dir, session.branch_name)!
		defer {
			query_db.close() or {}
		}
		query_session := query_db.begin_session(session.branch_name)!
		profile := queryapi.query_page_profiled(query_session, mut query_db, queryapi.Request{
			table_name:     'sessions'
			order_by:       queryapi.Order{
				column_name: 'updated_at'
				direction:   .desc
			}
			select_columns: session_summary_select_columns
			limit:          fetch_limit
		})!
		page := profile.page
		mut out := []SessionSummary{cap: page.rows.len}
		for row in page.rows {
			out << decode_session_summary_query(row)!
		}
		start := clamp_offset(request.offset, out.len)
		end := clamp_limit(start, request.limit, out.len)
		lower_bound_total := if page.cursor.has_more {
			request.offset + out.len + 1
		} else {
			out.len
		}
		return SessionListExecution{
			result:                 SessionListResult{
				total:    lower_bound_total
				sessions: out[start..end].clone()
			}
			explain:                explain_session_list_path(session.table_spec('sessions') or {
				storage.TypedTableSpec{}
			}, request)
			query:                  profile.timings
			open_ms:                open_timings.total_ms
			open_backends_ms:       open_timings.backends_ms
			open_catalog_ms:        open_timings.catalog_ms
			open_engine_ms:         open_timings.engine.total_ms
			open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
			open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
			open_node_store_ms:     open_timings.engine.repository.node_store_ms
			open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
			session_ms:             session_ms
			total_ms:               total_sw.elapsed().milliseconds()
		}
	}
	rows := load_session_list_rows(mut db, session)!
	mut out := []SessionSummary{cap: rows.len}
	for row in rows {
		out << decode_session_summary(row)!
	}
	if request.query.len > 0 || request.cwd_prefix.len > 0 || request.source.len > 0
		|| !request.include_archived {
		needle := request.query.to_lower()
		mut filtered := []SessionSummary{}
		for item in out {
			if !request.include_archived && item.archived {
				continue
			}
			if request.cwd_prefix.len > 0 && !item.cwd.starts_with(request.cwd_prefix) {
				continue
			}
			if request.source.len > 0 && item.source.to_lower() != request.source.to_lower() {
				continue
			}
			if needle.len > 0 {
				haystack := '${item.title}\n${item.cwd}\n${item.path}'.to_lower()
				if !haystack.contains(needle) {
					continue
				}
			}
			filtered << item
		}
		out = filtered.clone()
	}
	total := out.len
	start := clamp_offset(request.offset, total)
	end := clamp_limit(start, request.limit, total)
	return SessionListExecution{
		result:                 SessionListResult{
			total:    total
			sessions: out[start..end].clone()
		}
		explain:                explain_session_list_path(session.table_spec('sessions') or {
			storage.TypedTableSpec{}
		}, request)
		query:                  queryapi.ExecutionTimings{
			total_ms:      total_sw.elapsed().milliseconds()
			fetched_rows:  rows.len
			filtered_rows: out.len
			returned_rows: max_int(end - start, 0)
		}
		open_ms:                open_timings.total_ms
		open_backends_ms:       open_timings.backends_ms
		open_catalog_ms:        open_timings.catalog_ms
		open_engine_ms:         open_timings.engine.total_ms
		open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
		open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
		open_node_store_ms:     open_timings.engine.repository.node_store_ms
		open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
		session_ms:             session_ms
		total_ms:               total_sw.elapsed().milliseconds()
	}
}

pub fn (store PollyDbStore) explain_browser_queries(session_request SessionListRequest, transcript_request TranscriptRequest, search_request SearchRequest) !BrowserQueryExplain {
	mut db := storage.PersistentDatabase.open(store.root_dir, store_branch)!
	defer {
		db.close() or {}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	sessions_spec := session.table_spec('sessions') or { storage.TypedTableSpec{} }
	entries_spec := session.table_spec('entries') or { storage.TypedTableSpec{} }
	return BrowserQueryExplain{
		sessions:   explain_session_list_path(sessions_spec, session_request)
		transcript: explain_transcript_path(entries_spec, transcript_request)
		search:     explain_search_path(entries_spec, search_request)
	}
}

fn load_session_list_rows(mut db storage.PersistentDatabase, session storage.DatabaseSession) ![]storage.TypedSchemaRow {
	spec := session.table_spec('sessions') or { storage.TypedTableSpec{} }
	if table_has_index(spec, 'updated_at_cover_idx') {
		mut rows := session.lookup_index_between(mut db, 'sessions', 'updated_at_cover_idx',
			session_list_min_updated_at, session_list_max_updated_at, 0)!
		rows.reverse_in_place()
		return rows
	}
	mut rows := session.scan_table(mut db, 'sessions', 0)!
	rows.sort_with_compare(fn (a &storage.TypedSchemaRow, b &storage.TypedSchemaRow) int {
		left := a.data.get('updated_at') or { storage.ColumnValue('') }
		right := b.data.get('updated_at') or { storage.ColumnValue('') }
		left_value := match left {
			string { left }
			else { '' }
		}
		right_value := match right {
			string { right }
			else { '' }
		}
		if left_value > right_value {
			return -1
		}
		if left_value < right_value {
			return 1
		}
		return 0
	})
	return rows
}

fn explain_session_list_path(spec storage.TypedTableSpec, request SessionListRequest) QueryPathExplain {
	if request.query.len == 0 && request.cwd_prefix.len == 0 && request.source.len == 0
		&& request.include_archived {
		return QueryPathExplain{
			strategy:   'query_order_desc_projected'
			index_name: 'updated_at_cover_idx'
			notes:      [
				'session list uses query_page(order_by updated_at desc) with covering projection',
			]
		}
	}
	if table_has_index(spec, 'updated_at_cover_idx') {
		mut notes := [
			'results are read from updated_at covering index and reversed to newest-first',
		]
		if request.query.len > 0 || request.cwd_prefix.len > 0 || request.source.len > 0
			|| !request.include_archived {
			notes << 'text/source/cwd/archived filters are applied in memory after indexed read'
		}
		return QueryPathExplain{
			strategy:   'index_between_reverse'
			index_name: 'updated_at_cover_idx'
			notes:      notes
		}
	}
	return QueryPathExplain{
		strategy:   'table_scan'
		index_name: ''
		notes:      ['sessions table is fully scanned and sorted in memory']
	}
}

fn explain_transcript_path(spec storage.TypedTableSpec, request TranscriptRequest) QueryPathExplain {
	if request.session_id.len == 0 {
		return QueryPathExplain{
			strategy:   'not_requested'
			index_name: ''
			notes:      ['no session_id provided']
		}
	}
	if table_has_index(spec, 'entries_session_cover_idx') {
		return QueryPathExplain{
			strategy:   'index_exact_projected'
			index_name: 'entries_session_cover_idx'
			notes:      [
				'entries are fetched by covering session_id index, then ordered by seq in memory',
			]
		}
	}
	if table_has_index(spec, 'entries_session_idx') {
		return QueryPathExplain{
			strategy:   'index_exact'
			index_name: 'entries_session_idx'
			notes:      [
				'entries are fetched by session_id index, then ordered by seq in memory',
			]
		}
	}
	return QueryPathExplain{
		strategy:   'table_scan'
		index_name: ''
		notes:      [
			'entries_session_idx is missing, transcript would require full scan',
		]
	}
}

fn explain_search_path(spec storage.TypedTableSpec, request SearchRequest) QueryPathExplain {
	terms := normalized_search_terms(request.query)
	if terms.len == 0 {
		return QueryPathExplain{
			strategy:   'not_requested'
			index_name: ''
			notes:      ['no search query provided']
		}
	}
	mut indexes := []string{}
	for index_name in agentview_general_fts_indexes {
		if table_has_index(spec, index_name) {
			indexes << index_name
		}
	}
	if indexes.len > 0 {
		return QueryPathExplain{
			strategy:   'general_fts_prefix'
			index_name: indexes.join(',')
			notes:      [
				'search uses general PollyDB FTS indexes backed by SQLite FTS5; if no indexed hits are found it returns no results',
			]
		}
	}
	return QueryPathExplain{
		strategy:   'no_fts_indexes'
		index_name: ''
		notes:      [
			'FTS indexes are missing, so browser search returns no results instead of scanning entries',
		]
	}
}

pub fn (store PollyDbStore) load_session(session_id string) !SessionTranscript {
	page := store.load_transcript_page(TranscriptRequest{
		session_id: session_id
		limit:      100000
	})!
	return SessionTranscript{
		summary: page.summary
		entries: page.entries
	}
}

pub fn (store PollyDbStore) load_transcript_page(request TranscriptRequest) !TranscriptPage {
	return (store.load_transcript_page_explained(request)!).result
}

pub fn (mut store_session BrowserStoreSession) load_transcript_page_explained(request TranscriptRequest) !TranscriptExecution {
	mut total_sw := time.new_stopwatch()
	return load_transcript_page_in_session(mut store_session.db, store_session.session,
		request, storage.PersistentDatabaseOpenTimings{}, 0, mut total_sw)
}

pub fn (store PollyDbStore) load_transcript_page_explained(request TranscriptRequest) !TranscriptExecution {
	mut total_sw := time.new_stopwatch()
	open_result := storage.PersistentDatabase.open_profiled(store.root_dir, store_branch)!
	mut db := open_result.database
	defer {
		db.close() or {}
	}
	mut session_sw := time.new_stopwatch()
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	session_ms := session_sw.elapsed().milliseconds()
	return load_transcript_page_in_session(mut db, session, request, open_result.timings,
		session_ms, mut total_sw)!
}

fn load_transcript_page_in_session(mut db storage.PersistentDatabase, session storage.DatabaseSession, request TranscriptRequest, open_timings storage.PersistentDatabaseOpenTimings, session_ms i64, mut total_sw time.StopWatch) !TranscriptExecution {
	mut summary_sw := time.new_stopwatch()
	session_row := session.get_row(mut db, 'sessions', request.session_id.bytes())!
	summary := decode_session_summary(session_row)!
	summary_lookup_ms := summary_sw.elapsed().milliseconds()
	mut index_sw := time.new_stopwatch()
	rows := if table_has_index(session.table_spec('entries') or { storage.TypedTableSpec{} },
		'entries_session_cover_idx')
	{
		session.lookup_index_projected(mut db, 'entries', 'entries_session_cover_idx',
			request.session_id, 0, transcript_entry_select_columns)!
	} else {
		session.lookup_index(mut db, 'entries', 'entries_session_idx', request.session_id,
			0)!
	}
	index_lookup_ms := index_sw.elapsed().milliseconds()
	mut decode_sw := time.new_stopwatch()
	mut order_sw := time.new_stopwatch()
	mut entries := []SessionEntry{cap: rows.len}
	mut page_rows := []storage.TypedSchemaRow{}
	for row in rows {
		entries << decode_session_entry(row)!
		page_rows << row
	}
	decode_ms := decode_sw.elapsed().milliseconds()
	mut ordered := []SessionEntry{cap: entries.len}
	mut ordered_rows := []storage.TypedSchemaRow{cap: page_rows.len}
	mut order := []int{cap: entries.len}
	for idx in 0 .. entries.len {
		order << idx
	}
	order.sort_with_compare(fn [entries] (a &int, b &int) int {
		if entries[*a].seq < entries[*b].seq {
			return -1
		}
		if entries[*a].seq > entries[*b].seq {
			return 1
		}
		return 0
	})
	for idx in order {
		ordered << entries[idx]
		ordered_rows << page_rows[idx]
	}
	order_ms := order_sw.elapsed().milliseconds()
	total := ordered.len
	start := clamp_offset(request.offset, total)
	end := clamp_limit(start, request.limit, total)
	mut markdown_sw := time.new_stopwatch()
	mut page_entries := []SessionEntry{cap: max_int(end - start, 0)}
	for idx in start .. end {
		page_entries << decode_session_entry_with_markdown(mut db, ordered_rows[idx])!
	}
	markdown_ms := markdown_sw.elapsed().milliseconds()
	return TranscriptExecution{
		result:                 TranscriptPage{
			summary:       summary
			total_entries: total
			entries:       page_entries
		}
		explain:                explain_transcript_path(session.table_spec('entries') or {
			storage.TypedTableSpec{}
		}, request)
		open_ms:                open_timings.total_ms
		open_backends_ms:       open_timings.backends_ms
		open_catalog_ms:        open_timings.catalog_ms
		open_engine_ms:         open_timings.engine.total_ms
		open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
		open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
		open_node_store_ms:     open_timings.engine.repository.node_store_ms
		open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
		session_ms:             session_ms
		summary_lookup_ms:      summary_lookup_ms
		index_lookup_ms:        index_lookup_ms
		decode_ms:              decode_ms
		order_ms:               order_ms
		markdown_ms:            markdown_ms
		total_ms:               total_sw.elapsed().milliseconds()
	}
}

pub fn (store PollyDbStore) search(query string, limit int) ![]SearchHit {
	result := store.search_entries(SearchRequest{
		query: query
		limit: limit
	})!
	return result.hits
}

pub fn (store PollyDbStore) search_entries(request SearchRequest) !SearchResult {
	return (store.search_entries_explained(request)!).result
}

pub fn (mut store_session BrowserStoreSession) search_entries_explained(request SearchRequest) !SearchExecution {
	mut total_sw := time.new_stopwatch()
	query := request.query
	terms := normalized_search_terms(query)
	if terms.len == 0 {
		return SearchExecution{
			result:   SearchResult{}
			explain:  QueryPathExplain{
				strategy:   'not_requested'
				index_name: ''
				notes:      ['no search query provided']
			}
			total_ms: total_sw.elapsed().milliseconds()
		}
	}
	return search_entries_in_session(mut store_session.db, store_session.session, request,
		query, terms, storage.PersistentDatabaseOpenTimings{}, 0, mut total_sw)
}

pub fn (store PollyDbStore) search_entries_explained(request SearchRequest) !SearchExecution {
	mut total_sw := time.new_stopwatch()
	query := request.query
	terms := normalized_search_terms(query)
	if terms.len == 0 {
		return SearchExecution{
			result:   SearchResult{}
			explain:  QueryPathExplain{
				strategy:   'not_requested'
				index_name: ''
				notes:      ['no search query provided']
			}
			total_ms: total_sw.elapsed().milliseconds()
		}
	}
	open_result := storage.PersistentDatabase.open_profiled(store.root_dir, store_branch)!
	mut db := open_result.database
	defer {
		db.close() or {}
	}
	mut session_sw := time.new_stopwatch()
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	session_ms := session_sw.elapsed().milliseconds()
	return search_entries_in_session(mut db, session, request, query, terms, open_result.timings,
		session_ms, mut total_sw)!
}

fn search_entries_in_session(mut db storage.PersistentDatabase, session storage.DatabaseSession, request SearchRequest, query string, terms []string, open_timings storage.PersistentDatabaseOpenTimings, session_ms i64, mut total_sw time.StopWatch) !SearchExecution {
	mut session_summary_ms := i64(0)
	entries_spec := session.table_spec('entries') or { storage.TypedTableSpec{} }
	mut ranked := []RankedSearchHit{}
	mut seen := map[string]bool{}
	mut candidate_rows := []queryapi.QueryRow{}
	mut candidate_session_ids := []string{}
	mut seen_session_ids := map[string]bool{}
	mut used_fts := false
	mut fts_lookup_ms := i64(0)
	mut filter_rank_ms := i64(0)
	mut fts_pages := []queryapi.CursorPage{}
	for index_name in agentview_general_fts_indexes {
		if !table_has_index(entries_spec, index_name) {
			continue
		}
		used_fts = true
		mut lookup_sw := time.new_stopwatch()
		mut query_db := queryapi.open_database(db.root_dir, session.branch_name)!
		defer {
			query_db.close() or {}
		}
		query_session := query_db.begin_session(session.branch_name)!
		page := queryapi.query_page(query_session, mut query_db, queryapi.Request{
			table_name:     'entries'
			general_fts:    queryapi.GeneralFtsClause{
				index_name: index_name
				kind:       if terms.len > 1 {
					queryapi.FtsKind.all
				} else {
					queryapi.FtsKind.prefix
				}
				terms:      if terms.len > 1 { terms.clone() } else { [terms[0]] }
			}
			select_columns: [
				'id',
				'session_id',
				'session_title',
				'seq',
				'role',
				'kind',
				'tool_name',
				'title',
				'timestamp',
				'content_text',
			]
			limit:          search_candidate_fetch_limit(request)
		})!
		fts_lookup_ms += lookup_sw.elapsed().milliseconds()
		fts_pages << page
		if terms.len > 1 {
			break
		}
	}
	for page in fts_pages {
		for idx, row in page.rows {
			entry_id := must_string_query(row, 'id')!
			if seen[entry_id] {
				continue
			}
			seen[entry_id] = true
			candidate_rows << row
			session_id := entry_session_id_query(row)!
			if !seen_session_ids[session_id] {
				seen_session_ids[session_id] = true
				candidate_session_ids << session_id
			}
			_ = idx
		}
	}
	mut session_summaries := map[string]SessionSummary{}
	if candidate_session_ids.len > 0 {
		mut session_summary_sw := time.new_stopwatch()
		session_rows := session.get_rows_projected(mut db, 'sessions', candidate_session_ids.map(it.bytes()),
			session_summary_select_columns) or { []storage.TypedSchemaRow{} }
		session_summary_ms = session_summary_sw.elapsed().milliseconds()
		for row in session_rows {
			summary := decode_session_summary(row) or { continue }
			session_summaries[summary.id] = summary
		}
	}
	if candidate_rows.len > 0 {
		mut general_fts_by_entry_id := map[string]queryapi.GeneralFtsHit{}
		for page in fts_pages {
			for idx, row in page.rows {
				if idx >= page.general_fts_hits.len {
					continue
				}
				entry_id := must_string_query(row, 'id') or { continue }
				if entry_id !in general_fts_by_entry_id {
					general_fts_by_entry_id[entry_id] = page.general_fts_hits[idx]
				}
			}
		}
		mut rank_sw := time.new_stopwatch()
		for row in candidate_rows {
			summary := session_summaries[entry_session_id_query(row)!] or { SessionSummary{} }
			if !search_request_matches_query_row_metadata(request, row, summary) {
				continue
			}
			entry_id := must_string_query(row, 'id')!
			fts_hit := general_fts_by_entry_id[entry_id] or { queryapi.GeneralFtsHit{} }
			ranked << RankedSearchHit{
				hit:   build_search_hit_query_row_with_snippet(row, summary, query, fts_hit.snippet)
				score: score_search_query_row_fts(query, terms, row, summary, fts_hit.score)
			}
		}
		filter_rank_ms += rank_sw.elapsed().milliseconds()
	}
	if ranked.len > 0 {
		mut paginate_sw := time.new_stopwatch()
		result := paginate_ranked_search_hits(ranked, request)
		paginate_ms := paginate_sw.elapsed().milliseconds()
		return SearchExecution{
			result:                 result
			explain:                QueryPathExplain{
				strategy:   'general_fts_prefix'
				index_name: if used_fts { agentview_general_fts_indexes.join(',') } else { '' }
				notes:      [
					'search returned indexed hits from the general PollyDB FTS path without table-scan fallback',
				]
			}
			open_ms:                open_timings.total_ms
			open_backends_ms:       open_timings.backends_ms
			open_catalog_ms:        open_timings.catalog_ms
			open_engine_ms:         open_timings.engine.total_ms
			open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
			open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
			open_node_store_ms:     open_timings.engine.repository.node_store_ms
			open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
			session_ms:             session_ms
			session_summary_ms:     session_summary_ms
			fts_lookup_ms:          fts_lookup_ms
			filter_rank_ms:         filter_rank_ms
			paginate_ms:            paginate_ms
			total_ms:               total_sw.elapsed().milliseconds()
		}
	}
	if request.session_id.len > 0 {
		mut fallback_sw := time.new_stopwatch()
		ranked = collect_session_local_search_hits(mut db, session, request, query, terms)!
		filter_rank_ms += fallback_sw.elapsed().milliseconds()
		if ranked.len > 0 {
			mut paginate_sw := time.new_stopwatch()
			result := paginate_ranked_search_hits(ranked, request)
			paginate_ms := paginate_sw.elapsed().milliseconds()
			return SearchExecution{
				result:                 result
				explain:                QueryPathExplain{
					strategy:   'session_index_substring'
					index_name: if table_has_index(entries_spec, 'entries_session_cover_idx') {
						'entries_session_cover_idx'
					} else {
						'entries_session_idx'
					}
					notes:      [
						'no FTS hits; search fell back to substring matching inside the current session only',
					]
				}
				open_ms:                open_timings.total_ms
				open_backends_ms:       open_timings.backends_ms
				open_catalog_ms:        open_timings.catalog_ms
				open_engine_ms:         open_timings.engine.total_ms
				open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
				open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
				open_node_store_ms:     open_timings.engine.repository.node_store_ms
				open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
				session_ms:             session_ms
				session_summary_ms:     session_summary_ms
				fts_lookup_ms:          fts_lookup_ms
				filter_rank_ms:         filter_rank_ms
				paginate_ms:            paginate_ms
				total_ms:               total_sw.elapsed().milliseconds()
			}
		}
	}
	if request.session_id.len == 0 && request.preferred_session_id.len > 0 {
		preferred_request := SearchRequest{
			query:                request.query
			session_id:           request.preferred_session_id
			preferred_session_id: ''
			cwd_prefix:           request.cwd_prefix
			source:               request.source
			kind:                 request.kind
			limit:                request.limit
			offset:               request.offset
		}
		mut preferred_sw := time.new_stopwatch()
		ranked = collect_session_local_search_hits(mut db, session, preferred_request,
			query, terms)!
		filter_rank_ms += preferred_sw.elapsed().milliseconds()
		if ranked.len > 0 {
			mut paginate_sw := time.new_stopwatch()
			result := paginate_ranked_search_hits(ranked, request)
			paginate_ms := paginate_sw.elapsed().milliseconds()
			return SearchExecution{
				result:                 result
				explain:                QueryPathExplain{
					strategy:   'preferred_session_substring'
					index_name: if table_has_index(entries_spec, 'entries_session_cover_idx') {
						'entries_session_cover_idx'
					} else {
						'entries_session_idx'
					}
					notes:      [
						'no FTS hits; search fell back to substring matching inside the currently open session',
					]
				}
				open_ms:                open_timings.total_ms
				open_backends_ms:       open_timings.backends_ms
				open_catalog_ms:        open_timings.catalog_ms
				open_engine_ms:         open_timings.engine.total_ms
				open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
				open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
				open_node_store_ms:     open_timings.engine.repository.node_store_ms
				open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
				session_ms:             session_ms
				session_summary_ms:     session_summary_ms
				fts_lookup_ms:          fts_lookup_ms
				filter_rank_ms:         filter_rank_ms
				paginate_ms:            paginate_ms
				total_ms:               total_sw.elapsed().milliseconds()
			}
		}
	}
	if request.session_id.len == 0 {
		mut recent_sw := time.new_stopwatch()
		ranked = collect_recent_session_body_search_hits(mut db, session, request, query,
			terms)!
		filter_rank_ms += recent_sw.elapsed().milliseconds()
		if ranked.len > 0 {
			mut paginate_sw := time.new_stopwatch()
			result := paginate_ranked_search_hits(ranked, request)
			paginate_ms := paginate_sw.elapsed().milliseconds()
			return SearchExecution{
				result:                 result
				explain:                QueryPathExplain{
					strategy:   'recent_sessions_substring'
					index_name: if table_has_index(entries_spec, 'entries_session_cover_idx') {
						'updated_at_cover_idx+entries_session_cover_idx'
					} else {
						'updated_at_cover_idx+entries_session_idx'
					}
					notes:      [
						'no FTS hits; search fell back to substring matching across recent session bodies',
					]
				}
				open_ms:                open_timings.total_ms
				open_backends_ms:       open_timings.backends_ms
				open_catalog_ms:        open_timings.catalog_ms
				open_engine_ms:         open_timings.engine.total_ms
				open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
				open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
				open_node_store_ms:     open_timings.engine.repository.node_store_ms
				open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
				session_ms:             session_ms
				session_summary_ms:     session_summary_ms
				fts_lookup_ms:          fts_lookup_ms
				filter_rank_ms:         filter_rank_ms
				paginate_ms:            paginate_ms
				total_ms:               total_sw.elapsed().milliseconds()
			}
		}
	}
	if request.session_id.len == 0 {
		mut metadata_sw := time.new_stopwatch()
		ranked = collect_session_metadata_search_hits(mut db, session, request, query,
			terms)!
		filter_rank_ms += metadata_sw.elapsed().milliseconds()
		if ranked.len > 0 {
			mut paginate_sw := time.new_stopwatch()
			result := paginate_ranked_search_hits(ranked, request)
			paginate_ms := paginate_sw.elapsed().milliseconds()
			return SearchExecution{
				result:                 result
				explain:                QueryPathExplain{
					strategy:   'session_metadata_substring'
					index_name: if table_has_index(session.table_spec('sessions') or {
						storage.TypedTableSpec{}
					}, 'updated_at_cover_idx')
					{
						'updated_at_cover_idx'
					} else {
						''
					}
					notes:      [
						'no FTS hits; search fell back to session title/cwd/source/path substring matching',
					]
				}
				open_ms:                open_timings.total_ms
				open_backends_ms:       open_timings.backends_ms
				open_catalog_ms:        open_timings.catalog_ms
				open_engine_ms:         open_timings.engine.total_ms
				open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
				open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
				open_node_store_ms:     open_timings.engine.repository.node_store_ms
				open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
				session_ms:             session_ms
				session_summary_ms:     session_summary_ms
				fts_lookup_ms:          fts_lookup_ms
				filter_rank_ms:         filter_rank_ms
				paginate_ms:            paginate_ms
				total_ms:               total_sw.elapsed().milliseconds()
			}
		}
	}
	return SearchExecution{
		result:                 SearchResult{}
		explain:                if used_fts {
			QueryPathExplain{
				strategy:   'fts_no_hits'
				index_name: agentview_general_fts_indexes.join(',')
				notes:      [
					'general FTS indexes were queried but returned no usable hits',
				]
			}
		} else {
			QueryPathExplain{
				strategy:   'no_fts_indexes'
				index_name: ''
				notes:      [
					'FTS indexes are missing, so browser search returned no results',
				]
			}
		}
		open_ms:                open_timings.total_ms
		open_backends_ms:       open_timings.backends_ms
		open_catalog_ms:        open_timings.catalog_ms
		open_engine_ms:         open_timings.engine.total_ms
		open_replay_journal_ms: open_timings.engine.repository.replay_journal_ms
		open_repo_meta_ms:      open_timings.engine.repository.repository_meta_ms
		open_node_store_ms:     open_timings.engine.repository.node_store_ms
		open_commit_store_ms:   open_timings.engine.repository.commit_store_ms
		session_ms:             session_ms
		session_summary_ms:     session_summary_ms
		fts_lookup_ms:          fts_lookup_ms
		filter_rank_ms:         filter_rank_ms
		total_ms:               total_sw.elapsed().milliseconds()
	}
}

fn search_candidate_fetch_limit(request SearchRequest) int {
	base := if request.limit > 0 {
		max_int((request.offset + request.limit) * 3, 24)
	} else {
		24
	}
	return min_int(base, 48)
}

fn collect_session_local_search_hits(mut db storage.PersistentDatabase, session storage.DatabaseSession, request SearchRequest, query string, terms []string) ![]RankedSearchHit {
	if request.session_id.len == 0 {
		return []RankedSearchHit{}
	}
	session_row := session.get_row(mut db, 'sessions', request.session_id.bytes()) or {
		return []RankedSearchHit{}
	}
	summary := decode_session_summary(session_row) or { return []RankedSearchHit{} }
	rows := if table_has_index(session.table_spec('entries') or { storage.TypedTableSpec{} },
		'entries_session_cover_idx')
	{
		session.lookup_index_projected(mut db, 'entries', 'entries_session_cover_idx',
			request.session_id, 0, [
			'id',
			'session_id',
			'session_title',
			'seq',
			'role',
			'kind',
			'tool_name',
			'title',
			'timestamp',
			'content_text',
		])!
	} else {
		session.lookup_index(mut db, 'entries', 'entries_session_idx', request.session_id,
			0)!
	}
	mut ranked := []RankedSearchHit{}
	for row in rows {
		entry := decode_session_entry(row) or { continue }
		if !search_request_matches_entry(request, entry, summary, terms) {
			continue
		}
		ranked << RankedSearchHit{
			hit:   build_search_hit(row, entry, summary, query)
			score: score_search_entry(query, terms, entry, summary)
		}
	}
	return ranked
}

fn collect_session_metadata_search_hits(mut db storage.PersistentDatabase, session storage.DatabaseSession, request SearchRequest, query string, terms []string) ![]RankedSearchHit {
	rows := load_session_list_rows(mut db, session)!
	mut ranked := []RankedSearchHit{}
	for row in rows {
		summary := decode_session_summary(row) or { continue }
		if request.cwd_prefix.len > 0 && !summary.cwd.starts_with(request.cwd_prefix) {
			continue
		}
		if request.source.len > 0 && summary.source.to_lower() != request.source.to_lower() {
			continue
		}
		if request.kind.len > 0 && request.kind != 'all' {
			continue
		}
		haystack := '${summary.title}\n${summary.cwd}\n${summary.source}\n${summary.path}'.to_lower()
		mut matched := true
		for term in terms {
			if !haystack.contains(term) {
				matched = false
				break
			}
		}
		if !matched {
			continue
		}
		ranked << RankedSearchHit{
			hit:   build_session_metadata_search_hit(summary, query)
			score: score_session_metadata_search_hit(query, terms, summary)
		}
	}
	return ranked
}

fn collect_recent_session_body_search_hits(mut db storage.PersistentDatabase, session storage.DatabaseSession, request SearchRequest, query string, terms []string) ![]RankedSearchHit {
	rows := load_session_list_rows(mut db, session)!
	mut ranked := []RankedSearchHit{}
	mut sessions_scanned := 0
	mut entries_scanned := 0
	max_sessions := 48
	max_entries := 4000
	for row in rows {
		if sessions_scanned >= max_sessions || entries_scanned >= max_entries {
			break
		}
		summary := decode_session_summary(row) or { continue }
		if request.cwd_prefix.len > 0 && !summary.cwd.starts_with(request.cwd_prefix) {
			continue
		}
		if request.source.len > 0 && summary.source.to_lower() != request.source.to_lower() {
			continue
		}
		session_request := SearchRequest{
			query:      query
			session_id: summary.id
			cwd_prefix: request.cwd_prefix
			source:     request.source
			kind:       request.kind
			limit:      request.limit
			offset:     0
		}
		hits := collect_session_local_search_hits(mut db, session, session_request, query,
			terms)!
		sessions_scanned++
		entries_scanned += max_int(hits.len, 1)
		ranked << hits
		if ranked.len >= max_int((request.offset + request.limit) * 3, 20) {
			break
		}
	}
	return ranked
}

fn table_has_index(spec storage.TypedTableSpec, index_name string) bool {
	for index in spec.indexes {
		if index.name == index_name {
			return true
		}
	}
	return false
}

struct RankedSearchHit {
	hit   SearchHit
	score int
}

struct IngestState {
	path              string
	session_id        string
	source_mtime_unix i64
	source_size_bytes i64
}

struct SearchState {
	session_id        string
	source_mtime_unix i64
	source_size_bytes i64
}

struct SyncResumeState {
	name                      string
	last_completed_path       string
	last_completed_session_id string
	completed_batches         int
	completed_sessions        int
}

struct EntryIngestState {
	id         string
	session_id string
	entry_hash string
}

struct EntrySearchState {
	id         string
	session_id string
	entry_hash string
}

struct SourceFingerprint {
	source_mtime_unix i64
	source_size_bytes i64
}

fn sessions_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('sessions', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('title', .string_, false)!,
		storage.ColumnDef.new('updated_at', .datetime_, false)!,
		storage.ColumnDef.new('started_at', .datetime_, true)!,
		storage.ColumnDef.new('cwd', .string_, true)!,
		storage.ColumnDef.new('source', .string_, true)!,
		storage.ColumnDef.new('originator', .string_, true)!,
		storage.ColumnDef.new('cli_version', .string_, true)!,
		storage.ColumnDef.new('path', .string_, false)!,
		storage.ColumnDef.new('archived', .bool_, false)!,
		storage.ColumnDef.new('entry_count', .i64_, false)!,
		storage.ColumnDef.new('user_turns', .i64_, false)!,
		storage.ColumnDef.new('tool_calls', .i64_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('updated_at_idx', 'updated_at')!,
		storage.SchemaIndexDef.covering('updated_at_cover_idx', 'updated_at')!,
		storage.SchemaIndexDef.new('path_idx', 'path')!,
	])!
}

fn ingest_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('ingest_state', [
		storage.ColumnDef.new('path', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('source_mtime_unix', .i64_, false)!,
		storage.ColumnDef.new('source_size_bytes', .i64_, false)!,
	], ['path'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('ingest_session_idx', 'session_id')!,
	])!
}

fn search_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('search_state', [
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('source_mtime_unix', .i64_, false)!,
		storage.ColumnDef.new('source_size_bytes', .i64_, false)!,
	], ['session_id'])!
	return storage.TypedTableSpec.new(table, []storage.SchemaIndexDef{})!
}

fn search_meta_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('search_meta_state', [
		storage.ColumnDef.new('name', .string_, false)!,
		storage.ColumnDef.new('value', .string_, false)!,
	], ['name'])!
	return storage.TypedTableSpec.new(table, []storage.SchemaIndexDef{})!
}

fn sync_resume_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('sync_resume_state', [
		storage.ColumnDef.new('name', .string_, false)!,
		storage.ColumnDef.new('last_completed_path', .string_, false)!,
		storage.ColumnDef.new('last_completed_session_id', .string_, false)!,
		storage.ColumnDef.new('completed_batches', .i64_, false)!,
		storage.ColumnDef.new('completed_sessions', .i64_, false)!,
	], ['name'])!
	return storage.TypedTableSpec.new(table, []storage.SchemaIndexDef{})!
}

fn entry_ingest_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('entry_ingest_state', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('entry_hash', .string_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('entry_ingest_session_idx', 'session_id')!,
	])!
}

fn entry_search_state_spec() !storage.TypedTableSpec {
	table := storage.TableDef.new('entry_search_state', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('entry_hash', .string_, false)!,
	], ['id'])!
	return storage.TypedTableSpec.new(table, [
		storage.SchemaIndexDef.new('entry_search_session_idx', 'session_id')!,
	])!
}

fn entries_spec(include_search_indexes bool) !storage.TypedTableSpec {
	table := storage.TableDef.new('entries', [
		storage.ColumnDef.new('id', .string_, false)!,
		storage.ColumnDef.new('session_id', .string_, false)!,
		storage.ColumnDef.new('session_title', .string_, false)!,
		storage.ColumnDef.new('seq', .i64_, false)!,
		storage.ColumnDef.new('timestamp', .datetime_, false)!,
		storage.ColumnDef.new('role', .string_, false)!,
		storage.ColumnDef.new('kind', .string_, false)!,
		storage.ColumnDef.new('tool_name', .string_, true)!,
		storage.ColumnDef.new('call_id', .string_, true)!,
		storage.ColumnDef.new('title', .string_, true)!,
		storage.ColumnDef.new('content_text', .string_, false)!,
		storage.ColumnDef.new('content_md', .markdown_, false)!,
		storage.ColumnDef.new('raw_type', .string_, true)!,
		storage.ColumnDef.new('phase', .string_, true)!,
	], ['id'])!
	mut indexes := [
		storage.SchemaIndexDef.new('entries_session_idx', 'session_id')!,
		storage.SchemaIndexDef.covering('entries_session_cover_idx', 'session_id')!,
		storage.SchemaIndexDef.new('entries_timestamp_idx', 'timestamp')!,
	]
	if include_search_indexes {
		indexes << storage.SchemaIndexDef.fts_with_options('entries_content_text_fts_idx',
			'content_text', storage.FtsIndexOptions{
			tokenizer:      'unicode61 remove_diacritics 2'
			prefix_lengths: [2, 3, 4]
		})!
	}
	return storage.TypedTableSpec.new(table, indexes)!
}

fn put_session_summary(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, summary SessionSummary) ! {
	row := build_session_row(summary)
	_ = session.put_row(mut db, 'sessions', summary.id.bytes(), row, storage.ChunkConfig.default(),
		sync_meta('sync session ${summary.id}'))!
}

fn put_session_entry(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, summary SessionSummary, entry SessionEntry, empty_markdown storage.MarkdownRef) ! {
	entry_id, row := build_session_entry_row(summary, entry, empty_markdown)
	_ = session.put_row(mut db, 'entries', entry_id.bytes(), row, storage.ChunkConfig.default(),
		sync_meta('sync entry ${entry_id}'))!
}

fn build_session_entry_row(summary SessionSummary, entry SessionEntry, empty_markdown storage.MarkdownRef) (string, storage.TypedRowData) {
	entry_id := '${summary.id}:${entry.seq}'
	mut row := storage.TypedRowData.new()
	row.set('id', entry_id)
	row.set('session_id', summary.id)
	row.set('session_title', summary.title)
	row.set('seq', i64(entry.seq))
	row.set('timestamp', if entry.timestamp.len > 0 { entry.timestamp } else { summary.updated_at })
	row.set('role', entry.role)
	row.set('kind', entry.kind.str())
	if entry.tool_name.len > 0 {
		row.set('tool_name', entry.tool_name)
	} else {
		row.set_null('tool_name')
	}
	if entry.call_id.len > 0 {
		row.set('call_id', entry.call_id)
	} else {
		row.set_null('call_id')
	}
	if entry.title.len > 0 {
		row.set('title', entry.title)
	} else {
		row.set_null('title')
	}
	content_text := if entry.text.len > 0 { entry.text } else { entry.tool_name }
	row.set('content_text', content_text)
	row.set('content_md', empty_markdown)
	if entry.raw_type.len > 0 {
		row.set('raw_type', entry.raw_type)
	} else {
		row.set_null('raw_type')
	}
	if entry.phase.len > 0 {
		row.set('phase', entry.phase)
	} else {
		row.set_null('phase')
	}
	return entry_id, row
}

fn should_skip_markdown_index(entry SessionEntry, content_text string) bool {
	if entry.kind in [.tool_call, .tool_result, .meta] {
		return true
	}
	return content_text.len > 32768
}

struct SearchBackfillResult {
	rows_scanned    int
	rows_backfilled int
}

fn backfill_search_markdown_for_entries(mut db storage.PersistentDatabase, entry_ids []string) !SearchBackfillResult {
	return backfill_search_markdown_for_entries_with_config(mut db, entry_ids, storage.ChunkConfig.default(),
		false)
}

fn backfill_search_markdown_for_entries_with_config(mut db storage.PersistentDatabase, entry_ids []string, cfg storage.ChunkConfig, force_reingest bool) !SearchBackfillResult {
	if !store_branch_exists(mut db) {
		return SearchBackfillResult{}
	}
	if entry_ids.len == 0 {
		return SearchBackfillResult{}
	}
	reader := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	use_split_group_commit := cfg.enable_split_backed_working_set
	mut session := storage.GroupCommitSession{}
	mut split_session := storage.SplitGroupCommitSession{}
	if use_split_group_commit {
		split_session = db.begin_split_group_commit_session(storage.SessionOptions.for_branch(store_branch),
			storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512), cfg)!
	} else {
		session = db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
			storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	}
	mut updated := 0
	mut scanned := 0
	for entry_id in entry_ids {
		row := reader.get_row(mut db, 'entries', entry_id.bytes()) or { continue }
		scanned++
		entry := decode_session_entry(row) or { continue }
		if should_skip_markdown_index(entry, entry.text) {
			continue
		}
		current_ref := opt_markdown_ref(row, 'content_md') or { storage.MarkdownRef{} }
		if current_ref.source_len > 0 && !force_reingest {
			continue
		}
		next_ref := ingest_markdown_for_store(mut db, entry.text) or { continue }
		mut next_row := row.data.clone()
		next_row.set('content_md', next_ref)
		if use_split_group_commit {
			_ = split_session.put_row(mut db, 'entries', row.primary_key, next_row, cfg,
				sync_meta('backfill markdown ${row.primary_key.bytestr()}'))!
		} else {
			_ = session.put_row(mut db, 'entries', row.primary_key, next_row, storage.ChunkConfig.default(),
				sync_meta('backfill markdown ${row.primary_key.bytestr()}'))!
		}
		updated++
	}
	if updated > 0 {
		if use_split_group_commit {
			split_session.finish(mut db)!
		} else {
			session.finish(mut db)!
		}
	}
	return SearchBackfillResult{
		rows_scanned:    scanned
		rows_backfilled: updated
	}
}

fn ingest_markdown_for_store(mut db storage.PersistentDatabase, text string) !storage.MarkdownRef {
	stored := storage.ingest_external_field_value(mut db, storage.ColumnDef.new('content_md',
		.markdown_, false)!, text)!
	return match stored {
		storage.MarkdownRef { stored }
		else { return error('expected markdown ref from external storage ingest') }
	}
}

fn sync_meta(message string) storage.CommitMeta {
	return storage.CommitMeta{
		author:    'agentview'
		message:   message
		timestamp: 0
	}
}

fn store_branch_exists(mut db storage.PersistentDatabase) bool {
	return store_branch in db.branch_names()
}

fn seed_store_branch(mut db storage.PersistentDatabase, summary SessionSummary) ! {
	spec := sessions_spec()!
	cfg := storage.ChunkConfig.default()
	codec := storage.TypedRowCodec.new(spec.table)
	row := build_session_row(summary)
	table_view := storage.TableView.new(storage.Tree{}, 'sessions')
	mut tree := storage.Tree.build([
		storage.KVPair{
			key:   table_view.row_key(summary.id.bytes())
			value: codec.encode(row)!
		},
	], cfg)!
	tree = storage.rebuild_typed_indexes_for_specs(tree, [spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entries_spec(false)!], cfg)!
	tree = storage.rebuild_typed_aggregates_for_specs(tree, [spec, ingest_state_spec()!,
		search_state_spec()!, entry_ingest_state_spec()!, entries_spec(false)!], cfg)!
	_ = db.commit_to_branch(store_branch, tree, storage.CommitMeta{
		author:    'agentview'
		message:   'seed agentview store'
		timestamp: 0
	})!
}

fn current_source_fingerprint(path string) SourceFingerprint {
	return SourceFingerprint{
		source_mtime_unix: os.file_last_mod_unix(path)
		source_size_bytes: i64(os.file_size(path))
	}
}

fn build_ingest_state_row(path string, session_id string, fingerprint SourceFingerprint) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('path', path)
	row.set('session_id', session_id)
	row.set('source_mtime_unix', fingerprint.source_mtime_unix)
	row.set('source_size_bytes', fingerprint.source_size_bytes)
	return row
}

fn build_search_state_row(session_id string, fingerprint SourceFingerprint) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('session_id', session_id)
	row.set('source_mtime_unix', fingerprint.source_mtime_unix)
	row.set('source_size_bytes', fingerprint.source_size_bytes)
	return row
}

fn build_entry_ingest_state_row(entry_id string, session_id string, entry_hash string) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('id', entry_id)
	row.set('session_id', session_id)
	row.set('entry_hash', entry_hash)
	return row
}

fn build_entry_search_state_row(entry_id string, session_id string, entry_hash string) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('id', entry_id)
	row.set('session_id', session_id)
	row.set('entry_hash', entry_hash)
	return row
}

fn build_search_meta_state_row(name string, value string) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('name', name)
	row.set('value', value)
	return row
}

fn fingerprint_session_entry_row(row storage.TypedRowData) string {
	mut parts := []string{}
	for column in ['id', 'session_id', 'session_title', 'seq', 'timestamp', 'role', 'kind',
		'tool_name', 'call_id', 'title', 'content_text', 'raw_type', 'phase'] {
		value := row.get(column) or { storage.NullValue{} }
		parts << '${value}'
	}
	return storage.chunk_cid_hex(parts.join('\n').bytes())
}

fn decode_session_summary(row storage.TypedSchemaRow) !SessionSummary {
	return SessionSummary{
		id:          must_string(row, 'id')!
		title:       must_string(row, 'title')!
		updated_at:  must_string(row, 'updated_at')!
		started_at:  opt_string(row, 'started_at')
		cwd:         opt_string(row, 'cwd')
		source:      opt_string(row, 'source')
		originator:  opt_string(row, 'originator')
		cli_version: opt_string(row, 'cli_version')
		path:        must_string(row, 'path')!
		archived:    must_bool(row, 'archived')!
		entry_count: int(must_i64(row, 'entry_count')!)
		user_turns:  int(must_i64(row, 'user_turns')!)
		tool_calls:  int(must_i64(row, 'tool_calls')!)
	}
}

fn decode_session_summary_query(row queryapi.QueryRow) !SessionSummary {
	return SessionSummary{
		id:          must_string_query(row, 'id')!
		title:       must_string_query(row, 'title')!
		updated_at:  must_string_query(row, 'updated_at')!
		started_at:  opt_string_query(row, 'started_at')
		cwd:         opt_string_query(row, 'cwd')
		source:      opt_string_query(row, 'source')
		originator:  opt_string_query(row, 'originator')
		cli_version: opt_string_query(row, 'cli_version')
		path:        must_string_query(row, 'path')!
		archived:    must_bool_query(row, 'archived')!
		entry_count: int(must_i64_query(row, 'entry_count')!)
		user_turns:  int(must_i64_query(row, 'user_turns')!)
		tool_calls:  int(must_i64_query(row, 'tool_calls')!)
	}
}

fn load_existing_sessions_by_id(mut db storage.PersistentDatabase) !map[string]SessionSummary {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'sessions', 0)!
	mut out := map[string]SessionSummary{}
	for row in rows {
		summary := decode_session_summary(row)!
		out[summary.id] = summary
	}
	return out
}

fn decode_ingest_state(row storage.TypedSchemaRow) !IngestState {
	return IngestState{
		path:              must_string(row, 'path')!
		session_id:        must_string(row, 'session_id')!
		source_mtime_unix: must_i64(row, 'source_mtime_unix')!
		source_size_bytes: must_i64(row, 'source_size_bytes')!
	}
}

fn load_existing_ingest_states_by_path(mut db storage.PersistentDatabase) !map[string]IngestState {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'ingest_state', 0) or { return map[string]IngestState{} }
	mut out := map[string]IngestState{}
	for row in rows {
		state := decode_ingest_state(row) or { continue }
		out[state.path] = state
	}
	return out
}

fn decode_search_state(row storage.TypedSchemaRow) !SearchState {
	return SearchState{
		session_id:        must_string(row, 'session_id')!
		source_mtime_unix: must_i64(row, 'source_mtime_unix')!
		source_size_bytes: must_i64(row, 'source_size_bytes')!
	}
}

fn decode_entry_ingest_state(row storage.TypedSchemaRow) !EntryIngestState {
	return EntryIngestState{
		id:         must_string(row, 'id')!
		session_id: must_string(row, 'session_id')!
		entry_hash: must_string(row, 'entry_hash')!
	}
}

fn decode_entry_search_state(row storage.TypedSchemaRow) !EntrySearchState {
	return EntrySearchState{
		id:         must_string(row, 'id')!
		session_id: must_string(row, 'session_id')!
		entry_hash: must_string(row, 'entry_hash')!
	}
}

fn load_existing_search_states_by_session(mut db storage.PersistentDatabase) !map[string]SearchState {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'search_state', 0) or { return map[string]SearchState{} }
	mut out := map[string]SearchState{}
	for row in rows {
		state := decode_search_state(row) or { continue }
		out[state.session_id] = state
	}
	return out
}

fn load_search_meta_value(mut db storage.PersistentDatabase, name string) !string {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	row := session.get_row(mut db, 'search_meta_state', name.bytes()) or { return '' }
	return must_string(row, 'value')!
}

fn write_search_meta_value(mut db storage.PersistentDatabase, name string, value string) ! {
	mut session := db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
		storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	_ = session.put_row(mut db, 'search_meta_state', name.bytes(), build_search_meta_state_row(name,
		value), storage.ChunkConfig.default(), sync_meta('sync search meta ${name}'))!
	session.finish(mut db)!
}

fn build_sync_resume_state_row(state SyncResumeState) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('name', state.name)
	row.set('last_completed_path', state.last_completed_path)
	row.set('last_completed_session_id', state.last_completed_session_id)
	row.set('completed_batches', i64(state.completed_batches))
	row.set('completed_sessions', i64(state.completed_sessions))
	return row
}

fn decode_sync_resume_state(row storage.TypedSchemaRow) !SyncResumeState {
	return SyncResumeState{
		name:                      must_string(row, 'name')!
		last_completed_path:       must_string(row, 'last_completed_path')!
		last_completed_session_id: must_string(row, 'last_completed_session_id')!
		completed_batches:         int(must_i64(row, 'completed_batches')!)
		completed_sessions:        int(must_i64(row, 'completed_sessions')!)
	}
}

fn load_sync_resume_state(mut db storage.PersistentDatabase, name string) !SyncResumeState {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	row := session.get_row(mut db, 'sync_resume_state', name.bytes()) or {
		return SyncResumeState{}
	}
	return decode_sync_resume_state(row)!
}

fn write_sync_resume_state(mut db storage.PersistentDatabase, state SyncResumeState) ! {
	if state.name.len == 0 {
		return
	}
	mut session := db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
		storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	_ = session.put_row(mut db, 'sync_resume_state', state.name.bytes(), build_sync_resume_state_row(state),
		storage.ChunkConfig.default(), sync_meta('sync resume state ${state.name}'))!
	session.finish(mut db)!
}

fn clear_sync_resume_state(mut db storage.PersistentDatabase, name string) ! {
	if name.len == 0 {
		return
	}
	mut session := db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
		storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	_ = session.delete_row(mut db, 'sync_resume_state', name.bytes(), storage.ChunkConfig.default(),
		sync_meta('clear resume state ${name}'))!
	session.finish(mut db)!
}

fn load_existing_entry_ingest_states_by_session(mut db storage.PersistentDatabase, session_id string) !map[string]EntryIngestState {
	if session_id.len == 0 {
		return map[string]EntryIngestState{}
	}
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.lookup_index(mut db, 'entry_ingest_state', 'entry_ingest_session_idx',
		session_id, 0) or { return map[string]EntryIngestState{} }
	mut out := map[string]EntryIngestState{}
	for row in rows {
		state := decode_entry_ingest_state(row) or { continue }
		out[state.id] = state
	}
	return out
}

fn load_all_entry_ingest_states(mut db storage.PersistentDatabase) !map[string]EntryIngestState {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'entry_ingest_state', 0) or {
		return map[string]EntryIngestState{}
	}
	mut out := map[string]EntryIngestState{}
	for row in rows {
		state := decode_entry_ingest_state(row) or { continue }
		out[state.id] = state
	}
	return out
}

fn load_all_entry_ids(mut db storage.PersistentDatabase) ![]string {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'entries', 0) or { return []string{} }
	mut out := []string{cap: rows.len}
	for row in rows {
		entry_id := must_string(row, 'id') or { continue }
		out << entry_id
	}
	return out
}

fn load_meta_markup_entry_ids(mut db storage.PersistentDatabase) ![]string {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'entries', 0) or { return []string{} }
	mut out := []string{}
	for row in rows {
		entry_id := must_string(row, 'id') or { continue }
		content_text := must_string(row, 'content_text') or { continue }
		if likely_needs_meta_fts_reingest(content_text) {
			out << entry_id
		}
	}
	return out
}

fn likely_needs_meta_fts_reingest(content_text string) bool {
	if content_text.len == 0 {
		return false
	}
	if !content_text.contains('<') || !content_text.contains('>') {
		return false
	}
	return content_text.contains('</') || content_text.contains('/>')
		|| content_text.contains('<cwd>') || content_text.contains('<shell>')
		|| content_text.contains('<environment_context>')
}

fn load_all_entry_search_states(mut db storage.PersistentDatabase) !map[string]EntrySearchState {
	session := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := session.scan_table(mut db, 'entry_search_state', 0) or {
		return map[string]EntrySearchState{}
	}
	mut out := map[string]EntrySearchState{}
	for row in rows {
		state := decode_entry_search_state(row) or { continue }
		out[state.id] = state
	}
	return out
}

fn write_search_states(mut db storage.PersistentDatabase, ingest_states map[string]IngestState, session_ids []string) ! {
	if session_ids.len == 0 {
		return
	}
	mut seen := map[string]bool{}
	mut rows := map[string]storage.TypedRowData{}
	for _, ingest in ingest_states {
		if ingest.session_id.len == 0 || ingest.session_id !in session_ids
			|| seen[ingest.session_id] {
			continue
		}
		rows[ingest.session_id] = build_search_state_row(ingest.session_id, SourceFingerprint{
			source_mtime_unix: ingest.source_mtime_unix
			source_size_bytes: ingest.source_size_bytes
		})
		seen[ingest.session_id] = true
	}
	if rows.len == 0 {
		return
	}
	mut session := db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
		storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	_ = session.put_rows(mut db, 'search_state', rows, storage.ChunkConfig.default(),
		sync_meta('sync search state'))!
	session.finish(mut db)!
}

fn write_entry_search_states(mut db storage.PersistentDatabase, ingest_states map[string]EntryIngestState, entry_ids []string, stale_entry_ids []string, cfg storage.ChunkConfig) ! {
	if entry_ids.len == 0 && stale_entry_ids.len == 0 {
		return
	}
	use_split_group_commit := cfg.enable_split_backed_working_set
	mut session := storage.GroupCommitSession{}
	mut split_session := storage.SplitGroupCommitSession{}
	if use_split_group_commit {
		split_session = db.begin_split_group_commit_session(storage.SessionOptions.for_branch(store_branch),
			storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512), cfg)!
	} else {
		session = db.begin_group_commit_session(storage.SessionOptions.for_branch(store_branch),
			storage.GroupCommitOptions.high_throughput().with_checkpoint_every(512))!
	}
	if stale_entry_ids.len > 0 {
		mut delete_keys := [][]u8{cap: stale_entry_ids.len}
		for entry_id in stale_entry_ids {
			delete_keys << entry_id.bytes()
		}
		if use_split_group_commit {
			_ = split_session.delete_rows(mut db, 'entry_search_state', delete_keys, cfg,
				sync_meta('delete stale entry search state'))!
		} else {
			_ = session.delete_rows(mut db, 'entry_search_state', delete_keys, storage.ChunkConfig.default(),
				sync_meta('delete stale entry search state'))!
		}
	}
	if entry_ids.len > 0 {
		mut rows := map[string]storage.TypedRowData{}
		for entry_id in entry_ids {
			state := ingest_states[entry_id] or { EntryIngestState{} }
			if state.id.len == 0 {
				continue
			}
			rows[entry_id] = build_entry_search_state_row(entry_id, state.session_id,
				state.entry_hash)
		}
		if rows.len > 0 {
			if use_split_group_commit {
				_ = split_session.put_rows(mut db, 'entry_search_state', rows, cfg, sync_meta('sync entry search state'))!
			} else {
				_ = session.put_rows(mut db, 'entry_search_state', rows, storage.ChunkConfig.default(),
					sync_meta('sync entry search state'))!
			}
		}
	}
	if use_split_group_commit {
		split_session.finish(mut db)!
	} else {
		session.finish(mut db)!
	}
}

fn same_session_summary(left SessionSummary, right SessionSummary) bool {
	return left.id == right.id && left.title == right.title && left.updated_at == right.updated_at
		&& left.started_at == right.started_at && left.cwd == right.cwd
		&& left.source == right.source && left.originator == right.originator
		&& left.cli_version == right.cli_version && left.path == right.path
		&& left.archived == right.archived && left.entry_count == right.entry_count
		&& left.user_turns == right.user_turns && left.tool_calls == right.tool_calls
}

fn delete_entries_for_sessions(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, session_ids []string) ! {
	if session_ids.len == 0 {
		return
	}
	reader := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	for session_id in session_ids {
		rows := reader.lookup_index(mut db, 'entries', 'entries_session_idx', session_id,
			0)!
		for row in rows {
			_ = session.delete_row(mut db, 'entries', row.primary_key, storage.ChunkConfig.default(),
				sync_meta('delete stale entry ${row.primary_key.bytestr()}'))!
		}
	}
}

fn delete_entries_for_session(mut db storage.PersistentDatabase, mut session storage.GroupCommitSession, session_id string) ! {
	if session_id.len == 0 {
		return
	}
	delete_entries_for_sessions(mut db, mut session, [session_id])!
}

fn existing_entry_primary_keys(mut db storage.PersistentDatabase, session_id string) ![][]u8 {
	if session_id.len == 0 {
		return [][]u8{}
	}
	reader := db.begin_session(storage.SessionOptions.for_branch(store_branch))!
	rows := reader.lookup_index(mut db, 'entries', 'entries_session_idx', session_id,
		0)!
	mut out := [][]u8{cap: rows.len}
	for row in rows {
		out << row.primary_key.clone()
	}
	return out
}

fn build_session_row(summary SessionSummary) storage.TypedRowData {
	mut row := storage.TypedRowData.new()
	row.set('id', summary.id)
	row.set('title', summary.title)
	row.set('updated_at', summary.updated_at)
	if summary.started_at.len > 0 {
		row.set('started_at', summary.started_at)
	} else {
		row.set_null('started_at')
	}
	if summary.cwd.len > 0 {
		row.set('cwd', summary.cwd)
	} else {
		row.set_null('cwd')
	}
	if summary.source.len > 0 {
		row.set('source', summary.source)
	} else {
		row.set_null('source')
	}
	if summary.originator.len > 0 {
		row.set('originator', summary.originator)
	} else {
		row.set_null('originator')
	}
	if summary.cli_version.len > 0 {
		row.set('cli_version', summary.cli_version)
	} else {
		row.set_null('cli_version')
	}
	row.set('path', summary.path)
	row.set('archived', summary.archived)
	row.set('entry_count', i64(summary.entry_count))
	row.set('user_turns', i64(summary.user_turns))
	row.set('tool_calls', i64(summary.tool_calls))
	return row
}

fn decode_session_entry(row storage.TypedSchemaRow) !SessionEntry {
	return SessionEntry{
		seq:       int(must_i64(row, 'seq')!)
		timestamp: must_string(row, 'timestamp')!
		kind:      parse_entry_kind(must_string(row, 'kind')!)
		role:      must_string(row, 'role')!
		title:     opt_string(row, 'title')
		text:      must_string(row, 'content_text')!
		markdown:  ''
		tool_name: opt_string(row, 'tool_name')
		call_id:   opt_string(row, 'call_id')
		raw_type:  opt_string(row, 'raw_type')
		phase:     opt_string(row, 'phase')
	}
}

fn decode_session_entry_with_markdown(mut db storage.PersistentDatabase, row storage.TypedSchemaRow) !SessionEntry {
	mut entry := decode_session_entry(row)!
	ref := opt_markdown_ref(row, 'content_md') or { return entry }
	entry.markdown = db.load_markdown(ref) or { entry.text }
	return entry
}

fn entry_session_id(row storage.TypedSchemaRow) !string {
	return must_string(row, 'session_id')
}

fn entry_session_id_query(row queryapi.QueryRow) !string {
	return must_string_query(row, 'session_id')
}

fn entry_session_title(row storage.TypedSchemaRow) !string {
	return must_string(row, 'session_title')
}

fn entry_session_title_query(row queryapi.QueryRow) !string {
	return must_string_query(row, 'session_title')
}

fn must_string(row storage.TypedSchemaRow, name string) !string {
	value := row.data.get(name)!
	return match value {
		string { value }
		else { return error('expected string column: ${name}') }
	}
}

fn must_string_query(row queryapi.QueryRow, name string) !string {
	return row.data.get(name)!.as_string()
}

fn opt_markdown_ref(row storage.TypedSchemaRow, name string) ?storage.MarkdownRef {
	value := row.data.get(name) or { return none }
	return match value {
		storage.MarkdownRef { value }
		else { none }
	}
}

fn opt_string_query(row queryapi.QueryRow, name string) string {
	value := row.data.get(name) or { return '' }
	if value.is_null() {
		return ''
	}
	return value.as_string() or { '' }
}

fn must_i64_query(row queryapi.QueryRow, name string) !i64 {
	return row.data.get(name)!.as_i64()
}

fn must_bool_query(row queryapi.QueryRow, name string) !bool {
	return row.data.get(name)!.as_bool()
}

fn opt_string(row storage.TypedSchemaRow, name string) string {
	if !row.data.has(name) {
		return ''
	}
	value := row.data.get(name) or { return '' }
	return match value {
		string { value }
		else { '' }
	}
}

fn must_i64(row storage.TypedSchemaRow, name string) !i64 {
	value := row.data.get(name)!
	return match value {
		i64 { value }
		else { return error('expected i64 column: ${name}') }
	}
}

fn must_bool(row storage.TypedSchemaRow, name string) !bool {
	value := row.data.get(name)!
	return match value {
		bool { value }
		else { return error('expected bool column: ${name}') }
	}
}

fn parse_entry_kind(value string) EntryKind {
	return match value {
		'message' { .message }
		'reasoning' { .reasoning }
		'tool_call' { .tool_call }
		'tool_result' { .tool_result }
		else { .meta }
	}
}

fn normalized_search_terms(query string) []string {
	mut terms := []string{}
	mut seen := map[string]bool{}
	for term in storage.fts_tokenize_text(query.replace('\n', ' ')) {
		if term.len > 0 && !seen[term] {
			seen[term] = true
			terms << term
		}
	}
	if terms.len > 0 {
		return terms
	}
	for raw in query.replace('\n', ' ').split(' ') {
		term := raw.trim_space().to_lower()
		if term.len > 0 && !seen[term] {
			seen[term] = true
			terms << term
		}
	}
	return terms
}

fn search_request_matches_entry(request SearchRequest, entry SessionEntry, summary SessionSummary, terms []string) bool {
	if !search_request_matches_entry_metadata(request, entry, summary) {
		return false
	}
	haystack := search_haystack(entry, summary)
	for term in terms {
		if !haystack.contains(term) {
			return false
		}
	}
	return true
}

fn search_request_matches_row_metadata(request SearchRequest, row storage.TypedSchemaRow, summary SessionSummary) bool {
	if request.session_id.len > 0 && summary.id != request.session_id {
		return false
	}
	if request.cwd_prefix.len > 0 && !summary.cwd.starts_with(request.cwd_prefix) {
		return false
	}
	if request.source.len > 0 && summary.source.to_lower() != request.source.to_lower() {
		return false
	}
	return entry_kind_matches_filter(search_hit_entry_kind(row), request.kind)
}

fn search_request_matches_query_row_metadata(request SearchRequest, row queryapi.QueryRow, summary SessionSummary) bool {
	if request.session_id.len > 0 && summary.id != request.session_id {
		return false
	}
	if request.cwd_prefix.len > 0 && !summary.cwd.starts_with(request.cwd_prefix) {
		return false
	}
	if request.source.len > 0 && summary.source.to_lower() != request.source.to_lower() {
		return false
	}
	return entry_kind_matches_filter(search_hit_entry_kind_query(row), request.kind)
}

fn search_request_matches_entry_metadata(request SearchRequest, entry SessionEntry, summary SessionSummary) bool {
	if request.session_id.len > 0 && summary.id != request.session_id {
		return false
	}
	if request.cwd_prefix.len > 0 && !summary.cwd.starts_with(request.cwd_prefix) {
		return false
	}
	if request.source.len > 0 && summary.source.to_lower() != request.source.to_lower() {
		return false
	}
	if !entry_kind_matches_filter(entry.kind, request.kind) {
		return false
	}
	return true
}

fn search_haystack(entry SessionEntry, summary SessionSummary) string {
	return '${entry.title}\n${entry.tool_name}\n${entry.text}\n${summary.title}\n${summary.cwd}\n${summary.source}'.to_lower()
}

fn entry_kind_matches_filter(kind EntryKind, filter string) bool {
	if filter.len == 0 || filter == 'all' {
		return true
	}
	return match filter {
		'message' { kind == .message }
		'reasoning' { kind == .reasoning }
		'meta' { kind == .meta }
		'tool' { kind in [.tool_call, .tool_result] }
		'tool_call' { kind == .tool_call }
		'tool_result' { kind == .tool_result }
		else { kind.str() == filter }
	}
}

fn build_search_hit(row storage.TypedSchemaRow, entry SessionEntry, summary SessionSummary, query string) SearchHit {
	return build_search_hit_with_snippet(row, entry, summary, query, '')
}

fn build_search_hit_row_with_snippet(row storage.TypedSchemaRow, summary SessionSummary, query string, snippet string) SearchHit {
	return SearchHit{
		session_id:     entry_session_id(row) or { summary.id }
		session_title:  entry_session_title(row) or { summary.title }
		session_cwd:    summary.cwd
		session_source: summary.source
		path:           summary.path
		entry_seq:      search_hit_entry_seq(row)
		kind:           search_hit_entry_kind(row)
		role:           opt_string(row, 'role')
		timestamp:      opt_string(row, 'timestamp')
		snippet:        if snippet.len > 0 {
			snippet
		} else {
			compact_snippet(search_hit_text(row, summary), query, 160)
		}
	}
}

fn build_search_hit_query_row_with_snippet(row queryapi.QueryRow, summary SessionSummary, query string, snippet string) SearchHit {
	return SearchHit{
		session_id:     entry_session_id_query(row) or { summary.id }
		session_title:  entry_session_title_query(row) or { summary.title }
		session_cwd:    summary.cwd
		session_source: summary.source
		path:           summary.path
		entry_seq:      search_hit_entry_seq_query(row)
		kind:           search_hit_entry_kind_query(row)
		role:           opt_string_query(row, 'role')
		timestamp:      opt_string_query(row, 'timestamp')
		snippet:        if snippet.len > 0 {
			snippet
		} else {
			compact_snippet(search_hit_text_query(row, summary), query, 160)
		}
	}
}

fn build_search_hit_with_snippet(row storage.TypedSchemaRow, entry SessionEntry, summary SessionSummary, query string, snippet string) SearchHit {
	haystack := if entry.text.len > 0 {
		entry.text
	} else {
		'${entry.title}\n${entry.tool_name}\n${summary.title}'
	}
	return SearchHit{
		session_id:     entry_session_id(row) or { summary.id }
		session_title:  entry_session_title(row) or { summary.title }
		session_cwd:    summary.cwd
		session_source: summary.source
		path:           summary.path
		entry_seq:      entry.seq
		kind:           entry.kind
		role:           entry.role
		timestamp:      entry.timestamp
		snippet:        if snippet.len > 0 { snippet } else { compact_snippet(haystack, query, 160) }
	}
}

fn build_session_metadata_search_hit(summary SessionSummary, query string) SearchHit {
	haystack := '${summary.title}\n${summary.cwd}\n${summary.source}\n${summary.path}'
	return SearchHit{
		session_id:     summary.id
		session_title:  summary.title
		session_cwd:    summary.cwd
		session_source: summary.source
		path:           summary.path
		entry_seq:      -1
		kind:           .meta
		role:           'session'
		timestamp:      summary.updated_at
		snippet:        compact_snippet(haystack, query, 160)
	}
}

fn search_hit_entry_seq(row storage.TypedSchemaRow) int {
	return int(must_i64(row, 'seq') or { 0 })
}

fn search_hit_entry_seq_query(row queryapi.QueryRow) int {
	return int(must_i64_query(row, 'seq') or { 0 })
}

fn search_hit_entry_kind(row storage.TypedSchemaRow) EntryKind {
	return parse_entry_kind(opt_string(row, 'kind'))
}

fn search_hit_entry_kind_query(row queryapi.QueryRow) EntryKind {
	return parse_entry_kind(opt_string_query(row, 'kind'))
}

fn search_hit_text(row storage.TypedSchemaRow, summary SessionSummary) string {
	content_text := opt_string(row, 'content_text')
	if content_text.len > 0 {
		return content_text
	}
	return '${opt_string(row, 'title')}\n${opt_string(row, 'tool_name')}\n${summary.title}'
}

fn search_hit_text_query(row queryapi.QueryRow, summary SessionSummary) string {
	content_text := opt_string_query(row, 'content_text')
	if content_text.len > 0 {
		return content_text
	}
	return '${opt_string_query(row, 'title')}\n${opt_string_query(row, 'tool_name')}\n${summary.title}'
}

fn score_search_entry(query string, terms []string, entry SessionEntry, summary SessionSummary) int {
	mut score := 0
	title := entry.title.to_lower()
	tool_name := entry.tool_name.to_lower()
	text := entry.text.to_lower()
	session_title := summary.title.to_lower()
	query_lower := query.to_lower()
	if title.contains(query_lower) {
		score += 90
	}
	if tool_name.contains(query_lower) {
		score += 80
	}
	if session_title.contains(query_lower) {
		score += 70
	}
	if text.contains(query_lower) {
		score += 50
	}
	for term in terms {
		if title.contains(term) {
			score += 24
		}
		if tool_name.contains(term) {
			score += 22
		}
		if session_title.contains(term) {
			score += 18
		}
		if text.contains(term) {
			score += 10
		}
	}
	score += match entry.kind {
		.message { 8 }
		.reasoning { 6 }
		.tool_call { 4 }
		.tool_result { 4 }
		.meta { 2 }
	}
	return score
}

fn score_search_row_fts(query string, terms []string, row storage.TypedSchemaRow, summary SessionSummary, fts_score f64) int {
	mut score := 0
	title := opt_string(row, 'title').to_lower()
	tool_name := opt_string(row, 'tool_name').to_lower()
	text := opt_string(row, 'content_text').to_lower()
	session_title := summary.title.to_lower()
	query_lower := query.to_lower()
	if title.contains(query_lower) {
		score += 90
	}
	if tool_name.contains(query_lower) {
		score += 80
	}
	if session_title.contains(query_lower) {
		score += 70
	}
	if text.contains(query_lower) {
		score += 50
	}
	for term in terms {
		if title.contains(term) {
			score += 24
		}
		if tool_name.contains(term) {
			score += 22
		}
		if session_title.contains(term) {
			score += 18
		}
		if text.contains(term) {
			score += 10
		}
	}
	score += match search_hit_entry_kind(row) {
		.message { 8 }
		.reasoning { 6 }
		.tool_call { 4 }
		.tool_result { 4 }
		.meta { 2 }
	}
	if fts_score < 0 {
		score += int((-fts_score) * 1000.0)
	}
	return score
}

fn score_search_query_row_fts(query string, terms []string, row queryapi.QueryRow, summary SessionSummary, fts_score f64) int {
	mut score := 0
	title := opt_string_query(row, 'title').to_lower()
	tool_name := opt_string_query(row, 'tool_name').to_lower()
	text := opt_string_query(row, 'content_text').to_lower()
	session_title := summary.title.to_lower()
	query_lower := query.to_lower()
	if title.contains(query_lower) {
		score += 90
	}
	if tool_name.contains(query_lower) {
		score += 80
	}
	if session_title.contains(query_lower) {
		score += 70
	}
	if text.contains(query_lower) {
		score += 50
	}
	for term in terms {
		if title.contains(term) {
			score += 24
		}
		if tool_name.contains(term) {
			score += 22
		}
		if session_title.contains(term) {
			score += 18
		}
		if text.contains(term) {
			score += 10
		}
	}
	score += match search_hit_entry_kind_query(row) {
		.message { 8 }
		.reasoning { 6 }
		.tool_call { 4 }
		.tool_result { 4 }
		.meta { 2 }
	}
	if fts_score < 0 {
		score += int((-fts_score) * 1000.0)
	}
	return score
}

fn score_search_entry_fts(query string, terms []string, entry SessionEntry, summary SessionSummary, fts_score f64) int {
	mut score := score_search_entry(query, terms, entry, summary)
	if fts_score < 0 {
		score += int((-fts_score) * 1000.0)
	}
	return score
}

fn score_session_metadata_search_hit(query string, terms []string, summary SessionSummary) int {
	mut score := 0
	query_lower := query.to_lower()
	title := summary.title.to_lower()
	cwd := summary.cwd.to_lower()
	source := summary.source.to_lower()
	path := summary.path.to_lower()
	if title.contains(query_lower) {
		score += 120
	}
	if cwd.contains(query_lower) {
		score += 100
	}
	if source.contains(query_lower) {
		score += 70
	}
	if path.contains(query_lower) {
		score += 60
	}
	for term in terms {
		if title.contains(term) {
			score += 20
		}
		if cwd.contains(term) {
			score += 15
		}
		if source.contains(term) {
			score += 10
		}
		if path.contains(term) {
			score += 10
		}
	}
	return score
}

fn clamp_offset(offset int, total int) int {
	if offset <= 0 {
		return 0
	}
	if offset >= total {
		return total
	}
	return offset
}

fn clamp_limit(start int, limit int, total int) int {
	if limit <= 0 {
		return total
	}
	end := start + limit
	if end > total {
		return total
	}
	return end
}

fn paginate_ranked_search_hits(hits []RankedSearchHit, request SearchRequest) SearchResult {
	mut ranked := hits.clone()
	ranked.sort_with_compare(fn (a &RankedSearchHit, b &RankedSearchHit) int {
		if a.score > b.score {
			return -1
		}
		if a.score < b.score {
			return 1
		}
		if a.hit.timestamp > b.hit.timestamp {
			return -1
		}
		if a.hit.timestamp < b.hit.timestamp {
			return 1
		}
		if a.hit.entry_seq > b.hit.entry_seq {
			return -1
		}
		if a.hit.entry_seq < b.hit.entry_seq {
			return 1
		}
		return 0
	})
	total := ranked.len
	start := clamp_offset(request.offset, total)
	end := clamp_limit(start, request.limit, total)
	mut out := []SearchHit{cap: max_int(end - start, 0)}
	for item in ranked[start..end] {
		out << item.hit
	}
	return SearchResult{
		total: total
		hits:  out
	}
}
