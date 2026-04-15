# PollyDB Memory Module

`memory` owns the agent-memory acceleration layer:

- embedding/vector backend contracts
- USearch integration points
- reflection/replay orchestration seams

`storage` remains the source-of-truth layer for Prolly-tree data, typed rows,
catalogs, and branch snapshots. Sidecars are adapters over `storage`, not owners
of memory truth.

USearch is optional and guarded by `-d usearch`. PollyDB owns vector records in
typed tables; USearch persists only a rebuildable ANN file derived from those
records. SQLite is reserved for FTS5 lexical indexes and must not become vector
or memory storage.
