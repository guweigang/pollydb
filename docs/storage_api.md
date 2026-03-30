# PollyDB Storage API Draft

This document defines the intended stable storage-facing API for `pollydb`.
It is written for the future `vsql` integration, not for SQL parsing or DDL.

For a CLI-first walkthrough, see [tutorial.md](/Users/guweigang/Source/pollytree/docs/tutorial.md).

## Goals

- Keep the public contract small and typed.
- Treat `Typed*` APIs as the primary storage integration surface.
- Keep raw tree / key encoding helpers internal unless a caller truly needs them.
- Separate stable contracts from implementation details such as CDC chunking and index rebuild helpers.

## Stable Public Types

### Schema and Type System

- `ColumnType`
- `ColumnDef`
- `TableDef`
- `ColumnValue`
- `NullValue`
- `TypedRowData`
- `TypedRowCodec`

These types define the storage contract for rows and columns. `vsql` should map its parsed schema into `TableDef` and use `TypedRowData` for row values.
`ColumnDef` also carries column-level aggregate intent. Today the supported declaration is `AGGREGATE(SUM)` for `i64` columns only. In CLI/catalog form this is encoded as `name:i64:sum`, for example `total:i64:sum`.
Undeclared columns still support ad-hoc scanned `SUM(...)`, but only declared aggregate columns are eligible for subtree/root aggregate metadata optimizations.

Current primitive and semi-structured column support:

- `bool`
- `i64`
- `string`
- `bytes`
- `enum(...)`
- `json`
- `datetime`

`enum(...)` is stored as a constrained string payload and validated against the declared value list.
`json` is currently stored as validated JSON text. Index-aware JSON querying supports declared scalar object paths such as `meta.kind` or `meta.kind.code`.
`datetime` is currently stored as validated RFC3339 UTC text.

Current `datetime` column behaviors:

- `name:datetime`
- `name:datetime:current_timestamp`
- `name:datetime:current_timestamp:auto_update`

`current_timestamp` fills a missing datetime on insert.
`auto_update` refreshes the datetime automatically on update.
CLI write paths also accept `CURRENT_TIMESTAMP` as a datetime value literal.

### Table and Index Specification

- `SchemaIndexDef`
- `TypedTableSpec`

`TypedTableSpec` is the unit of registration for typed transactions and working sets. It combines one `TableDef` with zero or more secondary indexes.
`SchemaIndexDef.new(...)` creates a normal secondary index, while `SchemaIndexDef.covering(...)` creates a covering index that stores the encoded row payload inside the index value so index reads can avoid a table lookup.
For typed tables, `SchemaIndexDef.json_path(...)` and `SchemaIndexDef.json_path_covering(...)` declare JSON-object path indexes such as `meta.kind:string`, `meta.kind.code:string`, or `meta.enabled:bool:covering`.

Current JSON-path index contract:

- nested object paths are supported with dot notation
- only scalar field types are supported: `string`, `bool`, `i64`
- the base column must be declared as `json`
- string-valued JSON-path indexes participate in exact lookup and prefix lookup
- arrays and non-scalar JSON values are not indexable
- covering JSON-path indexes can decode rows directly from index values, just like normal covering indexes

### Typed Table Access

- `TypedSchemaRow`
- `TypedSchemaView`
- `TypedIndexedSchemaView`

Use these when direct typed table access is needed outside a transaction, for example targeted tests or low-level tooling.

### Typed Mutation and Transaction Flow

- `TypedWriteOp`
- `TypedWriteSet`
- `TypedTransaction`
- `TypedTransactionResult`
- `TypedWorkingSet`

This is the main mutation flow that `vsql` should depend on:

1. Define `TypedTableSpec`
2. Open a `TypedTransaction` or `TypedWorkingSet`
3. Build a `TypedWriteSet`
4. Apply writes
5. Inspect `TreeDiff` / `WorkingSetStatus`
6. Commit through `Repository`

### Repository and Versioning

- `Repository`
- `PersistentRepository`
- `PersistentEngine`
- `PersistentDatabase`
- `PersistentDatabaseCheckpointInfo`
- `PersistentDatabaseRecoveryStatus`
- `PersistentDatabaseStatusReport`
- `DatabaseSession`
- `SessionOptions`
- `TransactionSession`
- `TypedTableCursor`
- `TypedIndexCursor`
- `TypedIndexRow`
- `Branch`
- `BranchUpdate`
- `BranchTypedTransactionResult`
- `BranchTypedWorkingSetResult`
- `WorkingSetMergeResult`
- `ConflictResolution`
- `ConflictResolutionStrategy`
- `MergeConflict`
- `MergeResult`
- `MergeResolution`
- `CommitMeta`
- `VirtualRootRef`

These are the stable version-control-like storage APIs. `vsql` should prefer `PersistentDatabase` or `PersistentEngine` for disk-backed embedding, and use branch-level typed APIs rather than calling low-level merge helpers directly. `PersistentDatabase` adds a minimal typed table catalog on top of `PersistentEngine`, persisted under `.pollydb/catalog.meta`.

Commits may also bind zero or more `virtual_roots`. This is the intended versioning hook for projector-managed side structures such as independent aggregate trees. A virtual root records:

- projector name
- virtual-tree root cid
- source data-root cid
- freshness (`fresh` vs stale/projecting)

This lets `pollydb` version side structures without inflating the primary prolly-tree node format.

`PersistentDatabaseStatusReport` distinguishes three related states:

- `data_durable`: chunk data and metadata are durable enough to recover database contents
- `index_snapshots_fresh`: sidecar index snapshots are current, so reopen can avoid chunk-file scans
- `node_index_snapshot_pending` / `commit_index_snapshot_pending`: the live process has newer in-memory index state that has not yet been published as a fresh sidecar snapshot
- `durable`: shorthand for `data_durable && index_snapshots_fresh`

### High-Throughput Chunk Ingest

- `ChunkConfig`
- `BufferManager`
- `ChunkStore`
- `ChunkIngestConfig`
- `ChunkIngestResult`

These types define the stable file-ingest surface for large binary payloads. `BufferManager` owns file scanning and chunking, `ChunkStore` owns append-only chunk persistence, and `ChunkIngestConfig` controls worker count and whether chunk metadata is returned to the caller.

### Persistent Node Storage

- `NodeByteStore`
- `PersistentNodeStore`
- `PersistentCommitStore`

`PersistentNodeStore` is the minimal disk-backed implementation of the `NodeStore` contract. It persists serialized prolly-tree nodes through `ChunkStore`, which makes it suitable for loading a tree back from a persisted root CID without keeping all reachable nodes in memory.

`PersistentCommitStore` is the matching disk-backed implementation of `CommitStore`. Together with `PersistentRepository`, it forms the current minimal on-disk versioned storage stack.

`NodeByteStore` is the low-latency raw-node reader contract. `PersistentNodeStore` implements it, and the byte-store lookup path is the current fast route for root-hash point reads and index scans without materializing whole `Node` structs.

### Low-Latency Branch Readers

- `BranchTableReader`
- `BranchIndexReader`
- `SnapshotTableReader`
- `SnapshotIndexReader`
- `SnapshotReadScheduler`
- `SnapshotTablePairReader`
- `SnapshotIndexPairReader`
- `RootHashMergePreview`

These readers bind a branch head `root_cid`, one `TypedTableSpec`, and one `NodeByteStore` into a small read-only contract.

- `BranchTableReader` is the preferred point-read path for primary-key lookups.
- `BranchIndexReader` is the preferred low-latency path for exact secondary-index reads and prefix scans.
- Covering indexes (`SchemaIndexDef.covering(...)`) let `BranchIndexReader` decode rows directly from index values and avoid an extra table lookup.
- `TypedRowCodec.decode_projected(...)` is the lightweight projection decode helper for covering-index reads that only need a subset of columns.
- `SnapshotTableReader` and `SnapshotIndexReader` are the equivalent read-only contracts bound to a durable commit/root snapshot rather than a live branch head.
- `SnapshotReadScheduler` is the current minimal multi-version parallel lookup coordinator. It reopens the durable on-disk database state for each worker so reads against `v1`, `v2`, or different branch heads do not interfere with each other. It is intended for durable snapshots, not for uncheckpointed live overlays.
- `SnapshotTablePairReader` and `SnapshotIndexPairReader` are the higher-reuse contracts for comparing two durable commits inside one already-open database process. Prefer them over the scheduler when the same `v1/v2` pair will be scanned repeatedly.

Current default ingest policy:

- chunk boundaries use GearHash / FastCDC logic
- chunk CIDs use native `xxHash3` through a thin C FFI wrapper
- the recommended high-throughput ingest path is `ChunkStore.open_high_throughput(...)` plus single-worker `ChunkIngestConfig.high_throughput()`
- high-throughput ingest keeps append throughput high by deferring in-memory index construction until after the write path completes
- multi-worker ingest remains available, but should be treated as workload-dependent rather than assumed faster

## Recommended Integration Surface For `vsql`

The recommended storage-layer entrypoints are:

- `TableDef.new(...)`
- `ColumnDef.new(...)`
- `TypedTableSpec.new(...)`
- `TypedRowData.new()`
- `(mut row TypedRowData).set(...)`
- `(mut row TypedRowData).set_null(...)`
- `TypedWriteSet.new()`
- `(mut set TypedWriteSet).put(...)`
- `(mut set TypedWriteSet).delete(...)`
- `PersistentDatabase.open(...)`
- `PersistentDatabase.init(...)`
- `(mut db PersistentDatabase).register_table(...)`
- `(db PersistentDatabase).table_names()`
- `(db PersistentDatabase).table_spec(...)`
- `(db PersistentDatabase).open_session(...)`
- `(db PersistentDatabase).begin_session(...)`
- `(db PersistentDatabase).begin_default_session(...)`
- `SessionOptions.for_branch(...)`
- `(mut db PersistentDatabase).begin_transaction(...)`
- `(mut db PersistentDatabase).begin_working_set(...)`
- `(mut db PersistentDatabase).apply_typed_write_set(...)`
- `(mut db PersistentDatabase).commit_typed_working_set(...)`
- `(mut db PersistentDatabase).merge_into_working_set(...)`
- `(mut db PersistentDatabase).checkpoint()`
- `(mut db PersistentDatabase).checkpoint_mode(...)`
- `(mut db PersistentDatabase).checkpoint_timed_mode(...)`
- `(mut db PersistentDatabase).refresh_index_snapshots()`
- `PersistentDatabase.refresh_index_snapshots_async_for(...)`
- `GroupCommitOptions.high_throughput()`
  - defaults to `checkpoint_mode=data_only`
  - defaults to aggregate projector refresh policy `stale_one`
- `GroupCommitOptions.durable_default()`
- `(options GroupCommitOptions).with_checkpoint_every(...)`
- `(mut db PersistentDatabase).begin_high_throughput_group_commit_session(...)`
- `(mut db PersistentDatabase).begin_default_high_throughput_group_commit_session(...)`
- `(db PersistentDatabase).checkpoint_info()`
- `PersistentDatabase.recovery_status(...)`
- `(mut db PersistentDatabase).status_report()`
- `PersistentDatabase.inspect(...)`
- `(session DatabaseSession).begin_transaction(...)`
- `(session DatabaseSession).begin_working_set(...)`
- `(session DatabaseSession).apply_write_set(...)`
- `(session DatabaseSession).get_row(...)`
- `(session DatabaseSession).put_row(...)`
- `(session DatabaseSession).delete_row(...)`
- `(session DatabaseSession).scan_table(...)`
- `(session DatabaseSession).count_rows(...)`
- `(session DatabaseSession).count_rows_range(...)`
- `(session DatabaseSession).sum_i64_column(...)`
- `(session DatabaseSession).sum_i64_column_range(...)`
- `(session DatabaseSession).lookup_index(...)`
- `(session DatabaseSession).lookup_index_prefix(...)`
- `(session DatabaseSession).lookup_index_prefix_projected(...)`
- `(session DatabaseSession).table_cursor(...)`
- `(session DatabaseSession).index_cursor(...)`
- `(session DatabaseSession).table_reader(...)`
- `(session DatabaseSession).index_reader(...)`
- `(mut session TransactionSession).apply_write_set(...)`
- `(session TransactionSession).get_row(...)`
- `(mut session TransactionSession).put_row(...)`
- `(mut session TransactionSession).delete_row(...)`
- `(session TransactionSession).scan_table(...)`
- `(session TransactionSession).lookup_index(...)`
- `(session TransactionSession).table_cursor(...)`
- `(session TransactionSession).index_cursor(...)`
- `(mut session TransactionSession).commit(...)`
- `(mut session TransactionSession).merge_from(...)`

For point reads and secondary-index reads:

- `(tx TypedTransaction).indexed_view(...)`
- `(view TypedIndexedSchemaView).get(...)`
- `(view TypedIndexedSchemaView).find_by_index(...)`

For low-latency branch reads:

- `(session DatabaseSession).table_reader(...)`
- `(session DatabaseSession).index_reader(...)`
- `(mut db PersistentDatabase).snapshot_table_reader_for_commit(...)`
- `(mut db PersistentDatabase).snapshot_index_reader_for_commit(...)`
- `(mut db PersistentDatabase).snapshot_table_pair_reader_for_commits(...)`
- `(mut db PersistentDatabase).snapshot_index_pair_reader_for_commits(...)`
- `(db PersistentDatabase).snapshot_read_scheduler()`
- `(scheduler SnapshotReadScheduler).get_row_async(...)`
- `(scheduler SnapshotReadScheduler).lookup_index_async(...)`
- `(scheduler SnapshotReadScheduler).scan_table_async(...)`
- `(scheduler SnapshotReadScheduler).scan_table_from_async(...)`
- `(scheduler SnapshotReadScheduler).lookup_index_prefix_async(...)`
- `(scheduler SnapshotReadScheduler).lookup_index_prefix_from_async(...)`
- `(mut db PersistentDatabase).preview_merge(...)`
- `(mut reader BranchTableReader).get_row(...)`
- `(mut reader BranchTableReader).get_row_with_stats(...)`
- `(mut reader BranchIndexReader).find_rows(...)`
- `(mut reader BranchIndexReader).find_rows_prefix(...)`
- `(mut reader BranchIndexReader).find_rows_covering(...)`
- `(mut reader BranchIndexReader).find_rows_covering_prefix(...)`
- `(mut reader BranchIndexReader).find_rows_covering_prefix_projected(...)`
- `(mut reader SnapshotTableReader).get_row(...)`
- `(mut reader SnapshotIndexReader).find_rows(...)`
- `(mut reader SnapshotIndexReader).find_rows_covering(...)`
- `(mut reader SnapshotIndexReader).find_rows_covering_prefix_projected_from(...)`
- `(mut reader SnapshotIndexPairReader).find_rows_covering(...)`
- `(mut reader SnapshotIndexPairReader).find_rows_covering_prefix_from(...)`
- `(mut reader SnapshotIndexPairReader).find_rows_covering_prefix_projected_from(...)`
- `Tree.lookup_in_byte_store(...)`
- `Tree.lookup_in_byte_store_with_stats(...)`
- `Tree.prefix_scan_in_byte_store(...)`
- `Tree.suffix_scan_in_byte_store(...)`

Current smoke-level latency targets already reached by this path are roughly:

- primary-key row lookup: ~20-25us
- exact covering-index lookup: ~25-30us
- exact non-covering secondary-index lookup: ~65-75us

## Declared Aggregate Metadata

`pollydb` now supports declaration-scoped aggregate metadata for `i64` columns:

- declare a column as `name:i64:sum` in CLI/catalog form
- or build it with `ColumnDef.sum_i64(...)`

Current contract:

- full-table `COUNT(*)` uses tree/subtree count metadata
- primary-key range `COUNT(*)` uses subtree count plus edge scans
- full-table `SUM(i64)` on declared aggregate columns uses aggregate metadata
- primary-key range `SUM(i64)` on declared aggregate columns uses a bucketed aggregate side-structure plus edge scans
- undeclared columns still work, but they fall back to scanned aggregation

Current aggregate benchmark signals on `1,000,000` rows:

- full-table `COUNT(*)`: effectively metadata-fast (`0 ms` at benchmark millisecond resolution)
- full-table declared `SUM(i64)`: effectively metadata-fast (`0 ms` at benchmark millisecond resolution)
- declared `SUM(i64)` over a `500,000`-row primary-key range on a bucket-friendly dataset: `~18 ms`
- covering prefix-index scan with small limit: ~45-60us

Current smoke-level durable snapshot pair-read latencies are roughly:

- table scan over two durable commits, limit 10: ~65-75us
- exact covering secondary-index lookup over two durable commits: ~45-65us
- covering prefix-index scan over two durable commits, limit 10: ~275-470us
- projected covering prefix-index scan over two durable commits, limit 10: ~180-200us
- non-covering prefix-index scan over two durable commits, limit 10: ~400-660us

## Future Aggregate Projectors

`pollydb` now includes projector-managed virtual trees and commit-bound virtual-root metadata:

- `AggregateProjectionDef`
- `AggregateProjectorState`
- `VirtualRootRef`

Current behavior:

- keep the primary data tree lightweight
- bind optional aggregate trees through commit metadata
- register aggregate projectors in the catalog
- mark new data-root commits with stale virtual roots
- refresh projectors explicitly or asynchronously into fresh virtual roots
- allow `ALTER TABLE ... ADD AGGREGATE(SUM)`-style features to backfill asynchronously

Projector freshness is now visible through:

- `projection_states_at_branch(...)`
- `status_report()`
- `inspect(...)`
- `pollydb projectors`

Projector definitions now also carry scheduling hints:

- `priority`
  - larger means refresh earlier
- `cost_hint`
  - `low | medium | high`
  - lower cost wins when priority ties

The current limited-refresh ordering is:

1. higher `priority`
2. lower `cost_hint`
3. stable lexical projector name

Aggregate projector refresh can now be budgeted with policy:

- `none`
- `stale_one`
- `stale_up_to`
- `stale_all`
  - current recommendation for the default high-throughput write path is `stale_one`

These policies are exposed through `GroupCommitOptions.aggregate_projection_refresh_policy` and can be combined with `max_aggregate_projection_refreshes` for bounded automatic catch-up.

CLI projector registration now supports:

- `pollydb register-aggregate-projection <root_dir> <branch> <name> <table_name> <column_name> [json_path] [priority] [cost_hint]`

Example:

- `pollydb register-aggregate-projection /tmp/mydb main sum_metrics metrics id "" 500 low`
- `pollydb register-aggregate-projection /tmp/mydb main sum_payload events payload amount.total 200 high`

## Durability Modes

`pollydb` now exposes two checkpoint modes:

- `full`
- `data_only`

`full` persists both chunk data durability and sidecar index snapshots. It is the most conservative mode and provides the fastest reopen path.

`data_only` fsyncs the underlying chunk data and repository/catalog metadata but skips sidecar index snapshots during the checkpoint itself. Recovery stays correct because reopen can fall back to chunk-file scanning and rebuild indexes when needed.

`refresh_index_snapshots()` is the companion control-plane operation for this mode. It publishes fresh sidecar index snapshots later, outside the main write path.

`PersistentDatabase.refresh_index_snapshots_async_for(...)` is the current minimal async publication hook. It reopens the on-disk database state, refreshes sidecar snapshots, and can be waited on through `IndexSnapshotRefreshHandle`.

Operational guidance:

- Use `full` when reopen latency matters most and every checkpoint should refresh sidecar state.
- Use `data_only` when commit latency matters more than immediate sidecar freshness.
- Use group commit on top of either mode when batching many small writes.

Current recommended group-commit profiles:

- `GroupCommitOptions.durable_default()`
  - `checkpoint_every = 8`
  - `checkpoint_mode = full`
  - `auto_refresh_index_snapshots = false`
- `GroupCommitOptions.high_throughput()`
  - `checkpoint_every = 8`
  - `checkpoint_mode = data_only`
  - `auto_refresh_index_snapshots = true`
  - `aggregate_projection_refresh_policy = stale_one`

Current smoke-level sweep data shows `checkpoint_every = 8` is still the best balanced default for the high-throughput grouped path: it keeps checkpoint-hit `p95` lower than smaller batches without pushing too much latency into `finish()`. Larger values such as `16` or `32` can make median latency look better, but they shift more cost into final flush / finish and are less stable as a general default.

Current projector sweep data also supports `stale_one` as the default aggregate refresh policy for the high-throughput path, especially once projector scheduling hints are considered: limited budgets consistently pick the highest-priority, lowest-cost stale projector first.

For high-throughput file ingest:

- `BufferManager.new(...)`
- `ChunkStore.open_high_throughput(...)`
- `PersistentNodeStore.open_high_throughput(...)`
- `PersistentCommitStore.open_high_throughput(...)`
- `PersistentRepository.open(...)`
- `PersistentRepository.open_default(...)`
- `PersistentRepository.init(...)`
- `PersistentEngine.open(...)`
- `PersistentEngine.init(...)`
- `PersistentDatabase.open(...)`
- `PersistentDatabase.init(...)`
- `(mut db PersistentDatabase).persist_catalog(...)`
- `ChunkIngestConfig.default()`
- `ChunkIngestConfig.high_throughput()`
- `ChunkIngestConfig.analysis(...)`
- `ChunkIngestConfig.parallel(...)`
- `(mgr BufferManager).ingest_to_store(...)`
- `(mgr BufferManager).chunk_file_cids_with_workers(...)`

## Internal Or Unstable APIs

These exist to implement the storage engine but should not be considered stable integration points:

- Raw `Tree`, `Node`, and chunking internals
- Raw `TableView` / `IndexView` key-prefix helpers
- Internal typed index rebuild logic
- Untyped `RowCodec` / `SchemaView` / `WriteSet` flow

The untyped path remains useful for internal tests and migration work, but the typed path is the intended long-term contract.

## Contract Boundaries

### What `vsql` should own

- SQL parsing
- DDL parsing and validation
- Mapping SQL schema to `TableDef`
- Mapping SQL values to `ColumnValue`
- Query planning and execution

### What `pollydb` should own

- Typed row encoding
- Order-preserving index encoding
- Structural sharing and prolly-tree updates
- Secondary index maintenance
- Working set and merge behavior
- Snapshot / branch / commit persistence model

## Current Gaps Before Direct `vsql` Adoption

- No explicit column defaults yet
- No unique-index or constraint enforcement layer yet
- No typed range scan API over secondary indexes beyond cursor primitives
- No persisted on-disk chunk index reload path yet beyond the current in-memory rebuild used by high-throughput ingest
- No repository-level compaction, vacuum, or snapshot retention policy yet
- The default disk-backed repository layout now lives under `.pollydb/` with `repo.meta`, `catalog.meta`, `nodes.chunk`, and `commits.chunk`

## Next Recommended Phase

Once this contract is accepted, the next phase should be performance validation:

- Large bulk insert benchmarks
- Point lookup benchmarks
- Prefix / range scan benchmarks
- Secondary-index lookup benchmarks
- Merge and working-set mutation benchmarks
- Memory usage and chunk reuse measurements
