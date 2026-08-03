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
	id          string
	title       string
	updated_at  string
	started_at  string
	cwd         string
	source      string
	originator  string
	cli_version string
	path        string
	archived    bool
	entry_count int
	user_turns  int
	tool_calls  int
}

pub struct SessionEntry {
pub:
	seq       int
	agent     string
	timestamp string
	kind      EntryKind
	role      string
	title     string
	text      string
	tool_name string
	call_id   string
	status    string
	raw_type  string
	phase     string
pub mut:
	markdown string
}

pub struct SessionTranscript {
pub:
	summary SessionSummary
	entries []SessionEntry
}

pub struct SearchHit {
pub:
	session_id     string
	session_title  string
	session_cwd    string
	session_source string
	path           string
	entry_seq      int
	kind           EntryKind
	role           string
	timestamp      string
	snippet        string
}

pub struct EpisodeSourceRef {
pub:
	table_name  string
	primary_key string
	column_name string
	start_seq   int
	end_seq     int
	text        string
}

pub struct Episode {
pub:
	episode_id             string
	session_id             string
	start_seq              int
	end_seq                int
	title                  string
	intent                 string
	outcome                string
	status                 string
	cwd                    string
	repo                   string
	confidence             int
	source_refs            []EpisodeSourceRef
	derived_from_root_hash string
	created_at             string
	updated_at             string
}

pub struct EpisodeReport {
pub:
	report_id              string
	episode_id             string
	summary_md             string
	decisions_json         string
	failures_json          string
	commands_json          string
	files_json             string
	open_questions_json    string
	source_refs            []EpisodeSourceRef
	derived_from_root_hash string
	created_at             string
}

pub struct EpisodeReasoningNode {
pub:
	node_id                string
	episode_id             string
	kind                   string
	title                  string
	content                string
	start_seq              int
	end_seq                int
	confidence             int
	source_refs            []EpisodeSourceRef
	derived_from_root_hash string
	created_at             string
}

pub struct EpisodeReasoningLink {
pub:
	link_id                string
	episode_id             string
	from_node_id           string
	to_node_id             string
	kind                   string
	confidence             int
	evidence_refs          []EpisodeSourceRef
	derived_from_root_hash string
	created_at             string
}

pub struct EpisodeGraph {
pub:
	episode Episode
	report  EpisodeReport
	nodes   []EpisodeReasoningNode
	links   []EpisodeReasoningLink
}
