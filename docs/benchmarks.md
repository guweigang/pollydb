# Benchmark Harness

`pollydb` now includes a repeatable benchmark executable at:

- `/Users/guweigang/Source/pollytree/cmd/bench/main.v`

## What It Measures

- `cdc_file_cid_10m` / `cdc_file_store_10m`
  Measure the default indexed chunk ingest path: FastCDC chunking plus native `xxHash3` chunk CIDs and immediate in-memory index maintenance.

- `cdc_file_cid_parallel_10m` / `cdc_file_store_parallel_10m`
  Measure the optional multi-worker ingest path. These scenarios are useful for experimentation, but they are not assumed to outperform the default path on every machine or payload shape.

- `cdc_file_store_deferred_index_10m`
  Measures the recommended high-throughput ingest path: FastCDC chunking plus native `xxHash3` chunk CIDs, `writev`-backed append writes on Darwin, and deferred in-memory index construction via `ChunkStore.open_high_throughput(...)`.

- `cdc_chunker_10m`
  Measures FastCDC-style chunking over a large payload and reports chunk reuse after a 1-byte head insert.

- `typed_point_lookup`
  Measures point reads through the typed table path.

- `typed_primary_key_scan`
  Measures forward scan cost over primary-key order.

- `typed_secondary_index_lookup`
  Measures exact-match secondary-index lookups on `email`.

- `typed_working_set_updates`
  Measures staged typed updates through `TypedWorkingSet`.

- `typed_branch_merge`
  Measures a non-conflicting typed branch merge into a working set.

- `codex_entries_write_rows_only`
  Measures synthetic Codex `entries` writes with no secondary indexes and no FTS.

- `codex_entries_write_secondary_indexes`
  Measures the same synthetic Codex `entries` writes with the default non-FTS index set.

- `codex_entries_write_fts`
  Measures the same synthetic Codex `entries` writes with the default non-FTS index set plus `content_text` FTS.

- `codex_entries_update_rows_only` / `codex_entries_update_secondary_indexes` / `codex_entries_update_fts`
  Measure update cost for synthetic Codex `entries` rows under the three schema profiles.

- `codex_entries_delete_rows_only` / `codex_entries_delete_secondary_indexes` / `codex_entries_delete_fts`
  Measure delete cost for synthetic Codex `entries` rows under the three schema profiles.

- `codex_entries_secondary_lookup_secondary_indexes` / `codex_entries_secondary_lookup_fts`
  Measure `session_id` secondary-index lookup latency on the indexed `entries` schema profiles.

- `codex_entries_fts_query_fts`
  Measures direct `content_text` FTS query latency on the FTS-enabled `entries` schema profile.

## Run

Default run:

```sh
v run ./cmd/bench
```

Larger run:

```sh
v run ./cmd/bench --rows 1000000 --batch-size 5000 --lookups 50000 --range-size 5000 --updates 50000 --merge-writes 20000
```

## Parameters

- `--rows`
  Typed dataset size.

- `--batch-size`
  Write batch size during dataset construction.

- `--lookups`
  Number of point reads and secondary-index reads.

- `--range-size`
  Number of rows collected during the primary-key scan benchmark.

- `--updates`
  Number of staged updates for the working-set benchmark.

- `--merge-writes`
  Number of writes applied on each side before the merge benchmark.

- `--chunk-bytes`
  Payload size for the CDC benchmark.

- `--chunk-buffer-kb`
  File buffer size for streaming CDC benchmarks.

- `--chunk-workers`
  Worker count for parallel CDC hashing and ingest scenarios.

- `--mode`
  `all`, `cdc`, `typed`, `aggregate`, `sync`, or `schema`.

## Output

The harness prints a markdown table with:

- scenario name
- elapsed milliseconds
- operations
- derived operations per second
- byte volume where relevant
- scenario-specific notes

## Current Throughput Guidance

- For raw chunking, `cdc_core_10m` and `cdc_file_10m` show the FastCDC upper bound.
- For stable chunk ID throughput, prefer the native `xxHash3` path.
- For production-like ingest, prefer `ChunkStore.open_high_throughput(...)` with `ChunkIngestConfig.high_throughput()`.
- Multi-worker CID hashing is still available, but the benchmark should decide whether it helps on a specific machine and payload.

## Recommended Validation Progression

Start with:

```sh
v run ./cmd/bench --rows 10000 --lookups 2000 --updates 2000 --merge-writes 1000
```

Then scale to:

```sh
v run ./cmd/bench --rows 100000
```

Then push toward:

```sh
v run ./cmd/bench --rows 1000000 --batch-size 5000
```

That progression will help distinguish:

- algorithmic issues
- memory pressure
- merge/index-maintenance cost
- chunk reuse behavior under large payloads

For Codex schema-cost benchmarking specifically:

```sh
v run ./cmd/bench/main.v --mode schema --rows 10000 --batch-size 1000
```

That mode keeps the workload fixed and only changes the `entries` schema profile:

- rows only
- rows + secondary indexes
- rows + secondary indexes + FTS

It now exercises five operation families against those profiles:

- write
- update
- delete
- secondary-index lookup
- FTS query

## Layering Rule

This harness is for generic storage-engine benchmarking. It should not be used to
answer workload-adapter questions such as "why is Codex import slow?" by itself.

For workload-specific benchmarking, keep the layers separate:

- storage engine microbenchmarks in `cmd/bench`
- schema-cost benchmarks for a declared table/index profile
- adapter benchmarks for source parsing/materialization
- end-to-end import benchmarks for the full product path

For the Codex import workload specifically, see
[docs/codex_import_benchmarking.md](/Users/guweigang/Source/pollytree/docs/codex_import_benchmarking.md:1).
