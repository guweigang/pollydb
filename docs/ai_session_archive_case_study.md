# AI Session Archive Case Study

This document designs a realistic `pollydb` case for ingesting local conversation history from developer AI tools into one versioned database for audit, recovery, and cross-project search.

The target use case is:

- read local session data from tools such as Claude Code, Codex, and GitHub Copilot
- preserve the original on-disk record for audit and replay
- normalize the parts that users actually want to query
- use `pollydb`'s `json` and native `markdown` support instead of flattening everything into one giant blob

## Design Principles

- Keep the raw source record.
- Normalize only the stable, cross-tool concepts.
- Separate session-level metadata from message/event-level detail.
- Use `json` for volatile provider-specific payloads.
- Use `markdown` for human-readable transcript content, summaries, and rendered tool output when it is text-first.

## Source Schema Analysis

The source formats below are a mix of confirmed facts from the paths/formats already identified and inferred structure from how these tools usually persist conversations. The paths are relatively stable; the inner JSON shape is much more volatile and should be treated as adapter-owned.

## 1. Claude Code

Expected local shape:

- root under `~/.claude/`
- project-scoped history under `~/.claude/projects/...`
- transcript storage in `jsonl`

Observed storage characteristics:

- one line usually represents one event
- events are append-only and ordered
- events may include user prompts, assistant responses, tool invocations, tool results, and session metadata changes

Stable concepts worth normalizing:

- tool family: `claude_code`
- project/workspace key
- session id or conversation file identity
- event timestamp/order
- actor role: `user`, `assistant`, `tool`, `system`
- event kind: `message`, `tool_call`, `tool_result`, `meta`
- raw payload

Volatile details that should stay in `json`:

- exact event type names
- tool input/output envelope
- model/provider usage fields
- retry or streaming chunk metadata

## 2. Copilot CLI / Codex-like CLI Session State

Expected local shape:

- session-state directory or local SQLite session store
- state geared toward resume, `/chronicle`, or chat restoration

Observed storage characteristics:

- one logical session may span multiple records
- some versions store coarse session snapshots rather than append-only event logs
- newer variants may persist to SQLite, so extraction will often happen through an adapter rather than direct file parsing

Stable concepts worth normalizing:

- tool family: `copilot_cli` or `codex`
- session id / thread id
- created / updated timestamps
- workspace or cwd
- user and assistant turns
- command/tool execution records

Volatile details that should stay in `json`:

- exact SQLite table layout
- terminal state
- provider-specific message block encoding
- ephemeral cache/resume internals

## 3. VS Code Copilot Chat

Expected local shape:

- workspace-scoped `chatSessions/*.json`
- one file per chat session

Observed storage characteristics:

- file-level record usually already groups a full session
- messages may embed references to workspace, notebooks, file citations, or agent actions
- a single session file can mix user prompts, assistant answers, follow-ups, and context attachments

Stable concepts worth normalizing:

- tool family: `copilot_chat`
- workspace id
- session id
- turn ordering
- role
- textual content
- attached file/context references

Volatile details that should stay in `json`:

- VS Code workspace storage internals
- attachment payload structure
- intermediate agent-state fields

## Canonical Model

Across all three families, the durable common denominator is:

- a session belongs to one tool family and one workspace context
- a session has many ordered entries
- some entries are human/assistant messages
- some entries are tool or command events
- every normalized row should still point back to the exact source file/record

That leads to a two-track ingest model:

1. Raw preservation track
   - keep source file metadata and exact raw records
2. Canonical query track
   - sessions, entries, tool actions, and optional derived summaries

## Recommended PollyDB Tables

The schema below is intentionally normalized enough for querying, but not so normalized that each provider field becomes its own column.

## Table 1: `ai_sessions`

One row per logical conversation/thread.

Recommended columns:

- `session_id:string`
- `tool_family:string`
- `tool_variant:string?`
- `account_id:string?`
- `workspace_key:string?`
- `project_path:string?`
- `cwd:string?`
- `host_machine:string?`
- `source_path:string`
- `source_format:enum(json|jsonl|sqlite|mixed)`
- `source_locator:json`
- `session_title:string?`
- `started_at:datetime`
- `updated_at:datetime:current_timestamp:auto_update`
- `ended_at:datetime?`
- `message_count:i64`
- `event_count:i64`
- `tool_call_count:i64`
- `model_names:json`
- `session_meta:json`
- `summary_md:markdown?`

Primary key:

- `session_id`

Suggested indexes:

- `tool_family_idx:tool_family`
- `workspace_key_idx:workspace_key`
- `started_at_idx:started_at`
- `updated_at_idx:updated_at`
- `source_path_idx:source_path`
- `title_idx:session_title`
- `format_idx:source_format`
- `variant_idx:tool_variant`
- `model_name_idx:model_names.primary:string` only if the importer stores a primary model in JSON

Why this table exists:

- fast listing by tool, project, or time
- dedupe/upsert target for repeated imports
- good anchor for joins in future SQL layers

## Table 2: `ai_entries`

One row per ordered session entry after normalization. This is the main query table.

Recommended columns:

- `entry_id:string`
- `session_id:string`
- `seq:i64`
- `parent_entry_id:string?`
- `role:enum(user|assistant|system|tool)`
- `entry_kind:enum(message|tool_call|tool_result|thought|meta|attachment|command)`
- `timestamp:datetime?`
- `model_name:string?`
- `tool_name:string?`
- `tool_call_id:string?`
- `status:enum(ok|error|partial|skipped)?`
- `content_text:string?`
- `content_md:markdown?`
- `content_json:json?`
- `usage_json:json?`
- `entry_meta:json`
- `source_record_ref:json`

Primary key:

- `entry_id`

Suggested indexes:

- `session_seq_idx:session_id`
- `role_idx:role`
- `kind_idx:entry_kind`
- `timestamp_idx:timestamp`
- `tool_name_idx:tool_name`
- `tool_call_id_idx:tool_call_id`
- `status_idx:status`
- `model_name_idx:model_name`
- `session_role_idx:entry_meta.session_role:string` if the importer wants a provider-specific role subtype

Recommended Markdown selector indexes when using V APIs:

- `content_heading_idx` on `content_md` selector `heading_text:1`
- `content_link_host_idx` on `content_md` selector `link_host`
- `content_code_lang_idx` on `content_md` selector `code_block_lang`

Why both `content_text` and `content_md`:

- `content_text` is cheap for short plain text and exact display
- `content_md` is better for rich transcript bodies, tool logs turned into readable markdown, and future structure-aware indexing

## Table 3: `ai_tool_calls`

One row per normalized tool invocation. This table is optional but strongly recommended because tool-call analytics become much simpler than filtering mixed entry rows.

Recommended columns:

- `tool_call_pk:string`
- `session_id:string`
- `entry_id:string`
- `seq:i64`
- `tool_name:string`
- `tool_call_id:string?`
- `phase:enum(call|result)`
- `ok:bool`
- `started_at:datetime?`
- `finished_at:datetime?`
- `duration_ms:i64?`
- `args_json:json?`
- `result_json:json?`
- `result_md:markdown?`
- `error_text:string?`
- `tool_meta:json`

Primary key:

- `tool_call_pk`

Suggested indexes:

- `tool_name_idx:tool_name`
- `session_idx:session_id`
- `entry_idx:entry_id`
- `phase_idx:phase`
- `ok_idx:ok`
- `started_at_idx:started_at`
- `duration_idx:duration_ms`

Why this table exists:

- query all shell/file/search/edit actions without scanning every message
- audit sensitive operations separately from chat text

## Table 4: `ai_raw_records`

The audit table. One row per original source record or source slice.

Recommended columns:

- `raw_id:string`
- `session_id:string`
- `entry_id:string?`
- `tool_family:string`
- `source_path:string`
- `source_format:enum(json|jsonl|sqlite_row|sqlite_blob|other)`
- `record_locator:json`
- `record_order:i64`
- `captured_at:datetime:current_timestamp`
- `raw_json:json?`
- `raw_md:markdown?`
- `raw_bytes:bytes?`
- `raw_meta:json`

Primary key:

- `raw_id`

Suggested indexes:

- `session_idx:session_id`
- `tool_family_idx:tool_family`
- `source_path_idx:source_path`
- `record_order_idx:record_order`
- `record_kind_idx:raw_meta.kind:string`

Why this table exists:

- replay/debug an adapter bug
- preserve provider-specific fields you did not normalize yet
- maintain an audit trail without polluting query tables

## Table 5: `ai_ingest_runs`

Tracks importer executions and lets you support incremental sync from local disk.

Recommended columns:

- `run_id:string`
- `started_at:datetime`
- `finished_at:datetime?`
- `scanner_name:string`
- `tool_family:string`
- `root_path:string`
- `status:enum(running|ok|error|partial)`
- `files_seen:i64`
- `sessions_seen:i64`
- `entries_seen:i64`
- `records_seen:i64`
- `error_count:i64`
- `checkpoint_json:json`
- `stats_json:json`
- `log_md:markdown?`

Primary key:

- `run_id`

Suggested indexes:

- `tool_family_idx:tool_family`
- `started_at_idx:started_at`
- `status_idx:status`

## Why This Shape Fits PollyDB

This design matches the current strengths of `pollydb`:

- scalar metadata columns are cheap to index
- provider-specific variance lives in `json`
- transcript and tool output can live in native `markdown`
- session history is naturally append-only and branch-friendly
- audit imports can use branches, merge, and replay instead of destructive updates

## What Should Stay In JSON

Keep these in `json` unless a query proves they deserve promotion:

- full provider event envelopes
- token/cost accounting objects
- model configuration
- citation arrays
- attachment manifests
- provider-specific retry/streaming state
- SQLite row dumps or adapter-produced intermediate shapes

Promote a field to a top-level column only when:

- it appears across multiple tools
- users filter on it often
- you want an index on it

## What Should Use Markdown

Use `markdown` for:

- long assistant replies
- normalized transcript bodies
- rendered command output that benefits from fenced code blocks
- run summaries
- ingest error reports meant for humans

Do not use `markdown` for:

- tiny scalar text such as role/tool names
- provider envelopes
- exact raw JSON preservation

## Importer Mapping Strategy

Each adapter should emit three levels of output:

1. `raw`
   - exact source row/file/blob
2. `canonical session`
   - one `ai_sessions` row
3. `canonical entries`
   - zero or more `ai_entries` rows and optional `ai_tool_calls` rows

Recommended adapter boundary:

- Claude adapter parses `jsonl` line by line
- Copilot/Codex adapter reads file snapshots or queries SQLite, then emits canonical rows
- VS Code adapter parses each session JSON file into one session plus ordered entries

## Suggested Query Patterns

With the schema above, the interesting user queries become straightforward:

- "Show all Claude Code sessions for this repo last week"
- "Find every assistant answer that mentioned a given file path"
- "List all tool calls that ran shell commands and failed"
- "Compare session imports between two runs"
- "Replay the raw source records for one suspicious session"

## Versioning Strategy

Use branches to separate concerns:

- `import/main`
  - latest normalized state
- `import/raw-snapshots`
  - archival or debugging imports
- `analysis/...`
  - derived datasets, summaries, embeddings, or redaction experiments

This is a good fit for `pollydb` because source session data is inherently time-versioned and append-heavy.

## Practical Recommendation

If only one canonical query table is implemented first, start with:

- `ai_sessions`
- `ai_entries`
- `ai_raw_records`

That is the smallest useful shape.

If audit and tool analytics matter from day one, add:

- `ai_tool_calls`
- `ai_ingest_runs`

This gives a realistic end-to-end case for `pollydb`: local-first, append-heavy, schema-flexible, queryable, and versioned.
