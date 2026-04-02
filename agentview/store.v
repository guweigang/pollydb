module agentview

import os

pub struct SyncStats {
pub:
	sessions int
	entries  int
	skipped  int
}

pub struct SyncProgress {
pub:
	total_sessions    int
	processed_sessions int
	imported_sessions int
	imported_entries  int
	skipped_sessions  int
	session_id        string
	session_title     string
	phase             string
}

pub type SyncProgressReporter = fn (SyncProgress)

pub struct SessionListRequest {
pub:
	limit          int = 20
	offset         int
	query          string
	cwd_prefix     string
	include_archived bool = true
}

pub struct SessionListResult {
pub:
	total    int
	sessions []SessionSummary
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

pub struct SearchRequest {
pub:
	query      string
	session_id string
	limit      int = 20
	offset     int
}

pub struct SearchResult {
pub:
	total int
	hits  []SearchHit
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
