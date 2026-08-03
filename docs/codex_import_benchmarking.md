# Codex Import Benchmarking

This document defines how Codex session import should be benchmarked without
confusing application-layer work with PollyDB storage-layer work.

## Boundary

The storage engine should answer questions like:

- how fast can we append typed rows?
- how much does each index family cost?
- how expensive is index maintenance during write?
- what is the delta between immediate and deferred index construction?

The Codex adapter should answer different questions:

- how expensive is transcript parsing?
- how expensive is row/materialized-field generation?
- how expensive is entry hashing and deduplication?
- how expensive is markdown derivation for `content_md`?

If these are measured together, we get an end-to-end number, but we do not get a
useful explanation.

## Current Schema Provider

Codex session table definitions now live behind a dedicated provider in:

- [agentview/codex_schema.v](/Users/guweigang/Source/pollytree/agentview/codex_schema.v:1)

That provider exposes:

- `CodexSessionSchema`
- `storage.DatabaseSchema`
- `schema()`

This is the boundary that generic DDL export, schema inspection, and benchmark
setup should consume instead of reading `agentview/pollydb_store.v` directly.

## Benchmark Levels

### 1. Storage microbenchmarks

Use `cmd/bench` for generic engine questions:

- typed row write throughput
- primary-key scan throughput
- secondary-index lookup throughput
- branch merge/update costs
- chunk-store ingest costs

This level should not parse Codex data at all.

### 2. Schema-cost benchmarks

Measure the same synthetic `entries`-shaped data with different index sets:

- rows only
- rows + secondary indexes
- rows + FTS
- rows + FTS + embeddings

This level isolates the cost of schema declarations from Codex parsing logic.

Recommended matrix for `entries`:

```text
A. entries: no search, no memory indexes
B. entries: + content_text FTS
C. entries: + content_text FTS + markdown embedding indexes
```

### 3. Adapter benchmarks

Measure Codex-specific preprocessing before the row hits storage:

- session discovery
- jsonl read time
- event decoding
- session summary construction
- entry row construction
- entry hash generation
- markdown derivation

This level should report pure adapter time and row counts, even if writes are disabled.

### 4. End-to-end import benchmarks

Finally measure the real product path:

- parse Codex session files
- build rows
- write state tables
- write `sessions` / `entries`
- maintain indexes
- run search/markdown backfill when enabled

This is the number users feel, but it must be explained by the three lower layers.

## Required Timers

For Codex import, every benchmark run should break time into:

- `discover_ms`
- `read_ms`
- `decode_ms`
- `build_ms`
- `hash_ms`
- `markdown_ms`
- `state_lookup_ms`
- `row_write_ms`
- `index_update_ms`
- `checkpoint_ms`
- `fts_rebuild_ms`
- `total_ms`

If a timing cannot be separated yet, that is a profiling gap.

## Questions This Should Answer

With the layers above, we should be able to answer:

- whether bulk import is bottlenecked by storage or by Codex preprocessing
- whether FTS cost comes from index declaration or from rebuild strategy
- whether markdown cost belongs in the hot write path
- whether state tables are saving work or just adding work

## Immediate Next Targets

The current code suggests the next high-value measurements are:

1. `entries` row write throughput with and without `entries_content_text_fts_idx`
2. `build_session_entry_markdown(...)` cost per imported entry
3. `rebuild_fts_indexes_at_branch(..., ['entries'])` cost versus changed-row count
4. `load_existing_entry_ingest_states_by_session(...)` cost across large session sets

Those measurements will tell us where the next real throughput win is.
