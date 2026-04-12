module agentview

import os
import storage

pub struct SyncStats {
pub:
	sessions int
	entries  int
	skipped  int
	processed_sessions int
	total_sessions int
	paused_for_resume bool
	resume_session_id string
	resume_path string
	read_ms  i64
	build_ms i64
	apply_ms i64
	tx_ms    i64
	aggregate_ms i64
	fast_update_ms i64
	fast_update_can_ms i64
	fast_update_path_ms i64
	fast_update_encode_ms i64
	fast_update_replace_ms i64
	fallback_ms i64
	fallback_items_ms i64
	fallback_items_key_ms i64
	fallback_items_fill_ms i64
	fallback_ops_ms i64
	fallback_ops_key_ms i64
	fallback_ops_lookup_ms i64
	fallback_ops_encode_ms i64
	fallback_ops_state_ms i64
	fallback_ops_state_new_key_ms i64
	fallback_ops_state_item_ms i64
	fallback_ops_state_cache_ms i64
	fallback_ops_index_ms i64
	fallback_build_ms i64
	fallback_build_prepare_ms i64
	fallback_build_prepare_keys_ms i64
	fallback_build_prepare_keys_sort_ms i64
	fallback_build_prepare_keys_merge_ms i64
	fallback_build_prepare_rows_ms i64
	fallback_build_prepare_rows_key_ms i64
	fallback_build_prepare_rows_value_ms i64
	fallback_build_leaf_ms i64
	fallback_build_leaf_chunk_ms i64
	fallback_build_leaf_node_ms i64
	fallback_build_leaf_node_serialize_ms i64
	fallback_build_leaf_node_cid_ms i64
	fallback_build_leaf_node_add_ms i64
	fallback_build_internal_ms i64
	commit_ms i64
	checkpoint_ms i64
	flush_ms i64
	finish_ms i64
	total_ms i64
}

pub struct SyncOptions {
pub:
	batch_sessions int
}

pub struct SyncProgress {
pub:
	total_sessions    int
	processed_sessions int
	imported_sessions int
	imported_entries  int
	skipped_sessions  int
	checkpoint_count  int
	batch_sessions    int
	session_id        string
	session_title     string
	phase             string
	read_ms           i64
	build_ms          i64
	apply_ms          i64
	tx_ms             i64
	aggregate_ms      i64
	fast_update_ms    i64
	fast_update_can_ms i64
	fast_update_path_ms i64
	fast_update_encode_ms i64
	fast_update_replace_ms i64
	fallback_ms       i64
	fallback_items_ms i64
	fallback_items_key_ms i64
	fallback_items_fill_ms i64
	fallback_ops_ms   i64
	fallback_ops_key_ms i64
	fallback_ops_lookup_ms i64
	fallback_ops_encode_ms i64
	fallback_ops_state_ms i64
	fallback_ops_state_new_key_ms i64
	fallback_ops_state_item_ms i64
	fallback_ops_state_cache_ms i64
	fallback_ops_index_ms i64
	fallback_build_ms i64
	fallback_build_prepare_ms i64
	fallback_build_prepare_keys_ms i64
	fallback_build_prepare_keys_sort_ms i64
	fallback_build_prepare_keys_merge_ms i64
	fallback_build_prepare_rows_ms i64
	fallback_build_prepare_rows_key_ms i64
	fallback_build_prepare_rows_value_ms i64
	fallback_build_leaf_ms i64
	fallback_build_leaf_chunk_ms i64
	fallback_build_leaf_node_ms i64
	fallback_build_leaf_node_serialize_ms i64
	fallback_build_leaf_node_cid_ms i64
	fallback_build_leaf_node_add_ms i64
	fallback_build_internal_ms i64
	commit_ms         i64
	checkpoint_ms     i64
	flush_ms          i64
	finish_ms         i64
	total_ms          i64
}

pub type SyncProgressReporter = fn (SyncProgress)

pub struct SearchIndexStats {
pub:
	rows_scanned  int
	rows_backfilled int
	backfill_ms   i64
	rebuild_ms    i64
	total_ms      i64
	changed       bool
}

pub struct SearchIndexProgress {
pub:
	phase           string
	rows_scanned    int
	rows_backfilled int
	backfill_ms     i64
	rebuild_ms      i64
	total_ms        i64
}

pub type SearchIndexProgressReporter = fn (SearchIndexProgress)

pub struct SessionListRequest {
pub:
	limit          int = 20
	offset         int
	query          string
	cwd_prefix     string
	source         string
	include_archived bool = true
}

pub struct SessionListResult {
pub:
	total    int
	sessions []SessionSummary
}

pub struct SessionListExecution {
pub:
	result  SessionListResult
	explain QueryPathExplain
	query   storage.QueryExecutionTimings
	open_ms i64
	open_backends_ms i64
	open_catalog_ms i64
	open_engine_ms i64
	open_replay_journal_ms i64
	open_repo_meta_ms i64
	open_node_store_ms i64
	open_commit_store_ms i64
	session_ms i64
	total_ms i64
}

pub struct TranscriptRequest {
pub:
	session_id string
	offset     int
	limit      int = 200
}

pub struct TranscriptPage {
pub:
	summary      SessionSummary
	total_entries int
	entries      []SessionEntry
}

pub struct TranscriptExecution {
pub:
	result             TranscriptPage
	explain            QueryPathExplain
	open_ms            i64
	open_backends_ms   i64
	open_catalog_ms    i64
	open_engine_ms     i64
	open_replay_journal_ms i64
	open_repo_meta_ms  i64
	open_node_store_ms i64
	open_commit_store_ms i64
	session_ms         i64
	summary_lookup_ms  i64
	index_lookup_ms    i64
	decode_ms          i64
	order_ms           i64
	markdown_ms        i64
	total_ms           i64
}

pub struct SearchRequest {
pub:
	query      string
	session_id string
	preferred_session_id string
	cwd_prefix string
	source     string
	kind       string
	limit      int = 20
	offset     int
}

pub struct SearchResult {
pub:
	total int
	hits  []SearchHit
}

pub struct QueryPathExplain {
pub:
	strategy   string
	index_name string
	notes      []string
}

pub struct BrowserQueryExplain {
pub:
	sessions   QueryPathExplain
	transcript QueryPathExplain
	search     QueryPathExplain
}

pub struct SearchExecution {
pub:
	result  SearchResult
	explain QueryPathExplain
	open_ms            i64
	open_backends_ms   i64
	open_catalog_ms    i64
	open_engine_ms     i64
	open_replay_journal_ms i64
	open_repo_meta_ms  i64
	open_node_store_ms i64
	open_commit_store_ms i64
	session_ms         i64
	session_summary_ms i64
	fts_lookup_ms   i64
	filter_rank_ms  i64
	paginate_ms     i64
	total_ms        i64
}

pub interface SessionStore {
	sync_codex(codex_root string) !SyncStats
	list_sessions(limit int) ![]SessionSummary
	list_sessions_page(request SessionListRequest) !SessionListResult
	load_session(session_id string) !SessionTranscript
	load_transcript_page(request TranscriptRequest) !TranscriptPage
	search(query string, limit int) ![]SearchHit
	search_entries(request SearchRequest) !SearchResult
}

pub fn default_store_root() string {
	return os.join_path(os.home_dir(), '.agentview', 'pollydb')
}
