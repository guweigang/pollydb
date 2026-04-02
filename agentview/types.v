module agentview

pub enum EntryKind {
	message
	reasoning
	tool_call
	tool_result
	meta
}

pub struct SessionSummary {
pub:
	id           string
	title        string
	updated_at   string
	started_at   string
	cwd          string
	source       string
	originator   string
	cli_version  string
	path         string
	archived     bool
	entry_count  int
	user_turns   int
	tool_calls   int
}

pub struct SessionEntry {
pub:
	seq        int
	timestamp  string
	kind       EntryKind
	role       string
	title      string
	text       string
	tool_name  string
	call_id    string
	status     string
	raw_type   string
	phase      string
pub mut:
	markdown   string
}

pub struct SessionTranscript {
pub:
	summary SessionSummary
	entries []SessionEntry
}

pub struct SearchHit {
pub:
	session_id    string
	session_title string
	path          string
	entry_seq     int
	kind          EntryKind
	role          string
	timestamp     string
	snippet       string
}
