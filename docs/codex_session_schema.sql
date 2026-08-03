-- Logical DDL snapshot for Codex session storage in PollyDB.
-- This is a reviewable schema artifact, not an executable migration file.
-- Runtime source of truth lives in agentview/pollydb_store.v.

create table sessions (
  id                string primary key,
  title             string not null,
  updated_at        datetime not null,
  started_at        datetime null,
  cwd               string null,
  source            string null,
  originator        string null,
  cli_version       string null,
  path              string not null,
  archived          bool not null,
  entry_count       i64 not null,
  user_turns        i64 not null,
  tool_calls        i64 not null
);

create index updated_at_idx on sessions(updated_at);
create covering index updated_at_cover_idx on sessions(updated_at);
create index path_idx on sessions(path);

create table entries (
  id             string primary key,
  agent          string not null,
  session_id     string not null,
  session_title  string not null,
  seq            i64 not null,
  timestamp      datetime not null,
  role           string not null,
  kind           string not null,
  tool_name      string null,
  call_id        string null,
  title          string null,
  content_text   string not null,
  content_md     markdown not null,
  raw_type       string null,
  phase          string null
);

create index entries_agent_idx on entries(agent);
create index entries_session_idx on entries(session_id);
create covering index entries_session_cover_idx on entries(session_id)
  storing (id, agent, session_id, session_title, seq, timestamp, role, kind, tool_name, call_id, title, raw_type, phase);
create index entries_timestamp_idx on entries(timestamp);
create fts index entries_content_text_fts_idx on entries(content_text)
  tokenizer = "unicode61 remove_diacritics 2"
  prefix_lengths = [2, 3, 4];

create embedding index entries_content_block_vec_idx
  on entries(content_md) scope block model "bge-small-zh-v1.5";

create embedding index entries_content_path_vec_idx
  on entries(content_md) scope path model "bge-small-zh-v1.5";

create table ingest_state (
  path               string primary key,
  session_id         string not null,
  source_mtime_unix  i64 not null,
  source_size_bytes  i64 not null
);

create index ingest_session_idx on ingest_state(session_id);

create table entry_ingest_state (
  id         string primary key,
  session_id string not null,
  entry_hash string not null
);

create index entry_ingest_session_idx on entry_ingest_state(session_id);

create table search_state (
  session_id         string primary key,
  source_mtime_unix  i64 not null,
  source_size_bytes  i64 not null
);

create table entry_search_state (
  id         string primary key,
  session_id string not null,
  entry_hash string not null
);

create index entry_search_session_idx on entry_search_state(session_id);

create table search_meta_state (
  name   string primary key,
  value  string not null
);

create table sync_resume_state (
  name                       string primary key,
  last_completed_path        string not null,
  last_completed_session_id  string not null,
  completed_batches          i64 not null,
  completed_sessions         i64 not null
);

-- Recommended next addition for import/playback scale:
-- create index entries_session_seq_idx on entries(session_id, seq);
