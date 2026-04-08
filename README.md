# PollyTree

![PollyDB brand](assets/pollydb_brand.png)

PollyTree is the home of `pollydb`, a versioned typed database and query engine for structured rows, large text fields, and markdown-backed content.

## What is here

- `storage/`: the `pollydb` storage engine, typed schema layer, query layer, and tree/chunk infrastructure
- `agentview/`: a terminal browser for Codex-style session archives, used as a real-world testbed for query and search performance
- `cmd/pollydb/`: CLI entry points for database operations
- `cmd/agentview_cli/`: CLI entry points for archive import, indexing, benchmarking, and browsing
- `docs/`: design notes, performance roadmaps, and query-layer planning

## Project focus

PollyTree is currently centered on three themes:

- versioned typed storage for application data
- efficient query execution over large local archives
- markdown-aware storage without forcing markdown AST to be the primary full-text search path

## AgentView

`agentview` imports local AI session archives into `pollydb`, builds search indexes, and provides a terminal UI for:

- session lists
- transcript browsing
- indexed search

Typical commands:

```bash
agentview sync-codex
agentview index-search
agentview browse
```

## Status

The repository is actively exploring:

- stronger query execution primitives such as covering scans, ordered scans, reverse scans, and top-N access
- split-backed working representations for typed tables
- better search architecture for large text fields and session archives
