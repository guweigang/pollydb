# Codex Session Schema

This document captures the logical schema for importing Codex sessions into PollyDB.
It is intentionally DDL-like, even though the authoritative runtime definitions live in
`agentview/pollydb_store.v`.

A companion SQL-shaped snapshot lives at `docs/codex_session_schema.sql` so schema review
does not require reading V code.

## Goals

- Preserve raw Codex session/transcript structure with stable primary keys.
- Support high-throughput append/import for large session archives.
- Separate ingestion-state bookkeeping from query/search tables.
- Keep lexical search and markdown-derived search as explicitly declared indexes.
- Make the schema discoverable for future `vsql` and external tooling.

## Table Families

There are three distinct table families:

1. `sessions` and `entries`
   The user-facing archive model for Codex sessions and transcript entries.

2. `ingest_state`, `entry_ingest_state`, `sync_resume_state`
   Import/checkpoint bookkeeping used to resume and deduplicate ingestion.

3. `search_state`, `entry_search_state`, `search_meta_state`
   Search-index bookkeeping used to decide whether markdown/FTS search state is stale.

## Logical DDL

### `sessions`

Purpose:
- one row per Codex session
- list/archive/filter sessions
- support incremental re-import by `path` and freshness by `updated_at`

Logical shape:

```sql
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
```

Indexes:

```sql
create index updated_at_idx on sessions(updated_at);
create covering index updated_at_cover_idx on sessions(updated_at);
create index path_idx on sessions(path);
```

Why:
- `updated_at_cover_idx` is the hot path for session listing.
- `path_idx` supports import-state reconciliation and file-origin lookup.

### `entries`

Purpose:
- one row per transcript entry
- preserve importable/searchable conversation text
- serve transcript playback, memory extraction, and lexical retrieval

Logical shape:

```sql
create table entries (
  id             string primary key,
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
```

Base indexes:

```sql
create index entries_session_idx on entries(session_id);
create covering index entries_session_cover_idx on entries(session_id)
  storing (id, session_id, session_title, seq, timestamp, role, kind, tool_name, call_id, title, raw_type, phase);
create index entries_timestamp_idx on entries(timestamp);
```

`entries_session_cover_idx` intentionally does not store `content_text` or `content_md`.
Session-list, memory-link, and lightweight transcript metadata reads stay index-only, while full transcript/search-local reads fetch the base row for large content instead of duplicating markdown into the secondary index.

Search indexes:

```sql
create fts index entries_content_text_fts_idx on entries(content_text)
  tokenizer = "unicode61 remove_diacritics 2"
  prefix_lengths = [2, 3, 4];
```

Memory/vector indexes when memory schema is enabled:

```sql
create embedding index entries_content_block_vec_idx
  on entries(content_md) scope block model "bge-small-zh-v1.5";

create embedding index entries_content_path_vec_idx
  on entries(content_md) scope path model "bge-small-zh-v1.5";
```

Why:
- `session_id` is the main transcript retrieval path.
- `timestamp` supports time-oriented scans and global audit/search ordering.
- `content_text` FTS is the main lexical search surface today.
- `content_md` should be treated as a derived/search payload, not the core import key.

### `ingest_state`

Purpose:
- one row per source file path
- tells us whether a Codex session file changed since last import

```sql
create table ingest_state (
  path               string primary key,
  session_id         string not null,
  source_mtime_unix  i64 not null,
  source_size_bytes  i64 not null
);

create index ingest_session_idx on ingest_state(session_id);
```

### `entry_ingest_state`

Purpose:
- one row per imported entry
- stores a stable content hash/fingerprint for incremental entry-level re-import

```sql
create table entry_ingest_state (
  id         string primary key,
  session_id string not null,
  entry_hash string not null
);

create index entry_ingest_session_idx on entry_ingest_state(session_id);
```

### `search_state`

Purpose:
- one row per session for search freshness bookkeeping

```sql
create table search_state (
  session_id         string primary key,
  source_mtime_unix  i64 not null,
  source_size_bytes  i64 not null
);
```

### `entry_search_state`

Purpose:
- one row per entry for search freshness bookkeeping

```sql
create table entry_search_state (
  id         string primary key,
  session_id string not null,
  entry_hash string not null
);

create index entry_search_session_idx on entry_search_state(session_id);
```

### `search_meta_state`

Purpose:
- tiny key/value table for search schema/index versioning

```sql
create table search_meta_state (
  name   string primary key,
  value  string not null
);
```

### `sync_resume_state`

Purpose:
- batch import checkpointing/resume

```sql
create table sync_resume_state (
  name                       string primary key,
  last_completed_path        string not null,
  last_completed_session_id  string not null,
  completed_batches          i64 not null,
  completed_sessions         i64 not null
);
```

## Design Principles

### 1. `entries` is the core product table

For Codex archive use cases, the core business table is `entries`, not the state tables.
Optimization work should primarily target:

- bulk `entries` row writes
- `entries_session_*` transcript retrieval
- `entries_content_text_fts_idx` lexical search build/update
- markdown/search payload generation for `content_md`

### 2. State tables should never dominate import cost

`ingest_state`, `entry_ingest_state`, `search_state`, and `entry_search_state` exist only to
avoid unnecessary work. If maintaining them costs as much as re-importing data, the design is
wrong.

### 3. FTS is a declared schema feature, not an accidental side effect

The Codex archive should always record lexical search as an explicit schema declaration.
That means the DDL-like source of truth must include:

- which column is searchable
- which tokenizer/prefix strategy is used
- whether the index is exact FTS, markdown-derived FTS, or vector-only

### 4. Markdown is a derived search/storage payload

For Codex sessions, `content_text` is the canonical imported text.
`content_md` exists to support:

- markdown field selectors
- markdown-derived FTS and later richer semantic indexing
- memory extraction / reflection pipelines

That means we should feel free to optimize `content_md` generation aggressively as long as
query semantics stay intact.

## Current Gaps

These are the main modeling/performance gaps still worth addressing:

1. We do not have a dedicated persisted schema snapshot for this model beyond code and docs.
   We should eventually export a machine-readable schema manifest, not just prose.

2. `entries_session_idx` is single-column.
   If transcript playback needs stronger ordering guarantees or cheaper session-local scans,
   we may want either:
   - composite `(session_id, seq)` support, or
   - a stronger convention that `id = "${session_id}:${seq}"` is sufficient for ordered scans.

3. Search indexing is still too rebuild-heavy for large imports.
   The schema is fine, but the maintenance strategy needs incremental FTS updates rather than
   whole-table rebuild behavior.

## Recommended Next DDL Moves

If we want Codex session storage to scale for large archive imports, the next schema-level
changes worth making are:

1. Add a session-local ordered scan index on `entries(session_id, seq)`.
   Today transcript reads lean on `entries_session_idx` plus row inspection. A dedicated
   ordered index would make transcript playback and per-session incremental work cheaper and
   more explicit.

2. Keep FTS declared on `entries.content_text`, but move maintenance to incremental updates.
   The current table/index shape is acceptable; the expensive part is rebuild strategy, not
   the declaration itself.

3. Treat markdown ingestion as a derived pipeline, not a primary write-path requirement.
   `content_md` should stay in schema, but we should feel free to batch or defer its materialization
   during bulk import.

4. Consider exporting a machine-readable schema manifest from the same source as the runtime
   specs so docs and implementation cannot drift.

## Source Of Truth

Current authoritative runtime definitions:

- `CodexSessionSchema.schema()` in [agentview/codex_schema.v](/Users/guweigang/Source/pollytree/agentview/codex_schema.v:49)
- `storage.DatabaseSchema` in [storage/schema_provider.v](/Users/guweigang/Source/pollytree/storage/schema_provider.v:3)
- runtime import/write logic in [agentview/pollydb_store.v](/Users/guweigang/Source/pollytree/agentview/pollydb_store.v:1)

This document is the durable, reviewable logical DDL companion to those definitions.
