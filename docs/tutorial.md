# PollyDB Tutorial

Related architecture notes:
- [Storage/Compute Separation](/Users/guweigang/Source/pollytree/docs/storage_compute_separation.md)
- [Platform Roadmap](/Users/guweigang/Source/pollytree/docs/platform_roadmap.md)

This tutorial shows the current `pollydb` workflow from the command line.
It focuses on the storage/database surface that already exists today:

- initialize a database
- define tables and indexes
- use version-control-like branch and merge semantics
- insert, update, delete, and query rows
- work with `bool`, `enum`, `json`, and `datetime`
- use aggregates and aggregate projectors

One transport note up front:

- current remote sync uses a Polly-Link Sidecar over plain HTTP + JSON
- it is not a generic RPC framework
- it is not WebSocket-based yet
- every sync phase is an explicit request/response step, which keeps the protocol easy to debug

This is intentionally CLI-first. `pollydb` already has lower-level V APIs, but the CLI is the easiest way to learn the model end to end.

For end-to-end example workflows, see [tutorial_scenarios.md](/Users/guweigang/Source/pollytree/docs/tutorial_scenarios.md).

One important CLI rule:

- if you run inside a repository directory, you can usually omit both `root_dir` and `branch`
- `pollydb` will use the current directory as `root_dir`
- `pollydb` will use the repository `default_branch` from `.pollydb/repo.meta`
- if you pass `root_dir` and/or `branch` explicitly, those values still win

## 1. Create a Database

Initialize a database in a directory:

```sh
v run ./cmd/pollydb -- init /tmp/pollydb-demo main
cd /tmp/pollydb-demo
```

This creates a `.pollydb/` directory under the target root with files such as:

- `.pollydb/repo.meta`
- `.pollydb/catalog.meta`
- `.pollydb/nodes.chunk`
- `.pollydb/commits.chunk`

Useful inspection commands:

```sh
v run ./cmd/pollydb -- status /tmp/pollydb-demo
v run ./cmd/pollydb -- inspect /tmp/pollydb-demo
```

## 2. Create Tables

Register a typed table:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-table users id \
  "id:string,name:string,email:string?,active:bool" \
  "email_idx:email,email_cover:email:covering"
```

Inspect the catalog:

```sh
cd /tmp/pollydb-demo
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- tables
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- describe-table users
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- export-catalog
```

### Supported Column Types

Current column declarations support:

- `bool`
- `i64`
- `string`
- `bytes`
- `enum(...)`
- `json`
- `datetime`

Examples:

```text
id:string
active:bool
payload:bytes
status:enum(active|draft|done)
meta:json
created_at:datetime:current_timestamp
updated_at:datetime:current_timestamp:auto_update
total:i64:sum
```

Notes:

- Append `?` to mark a column nullable, for example `email:string?`.
- Append `:sum` only for declared `i64` aggregate columns.
- `enum(...)` is stored as a validated string.
- `json` is stored as validated JSON text.
- `datetime` is stored as validated RFC3339 UTC text.
- Append `:current_timestamp` to fill a missing `datetime` on insert.
- Append `:auto_update` to refresh a `datetime` automatically on update.
- In CLI writes, `CURRENT_TIMESTAMP` can be used as a `datetime` value.

## 3. DDL-Like Capabilities

`pollydb` does not expose SQL DDL yet, but it already has a practical DDL-like surface.

### Today

- create/open database: `init`, `status`, `inspect`
- register table: `register-table`
- inspect schema: `describe-table`, `export-catalog`
- register aggregate projector: `register-aggregate-projection`
- create branches: `create-branch`

### Not Yet

- SQL parser for `CREATE TABLE`
- SQL parser for `ALTER TABLE`
- general-purpose in-place schema migration planner

For evolving aggregates after table creation, the preferred direction is an aggregate projector, not continued growth of the main data tree.

## 4. Indexes

### Normal Secondary Index

```text
email_idx:email
```

### Covering Index

```text
email_cover:email:covering
```

Covering indexes can satisfy some reads without going back to the base row.

### JSON Path Index

JSON scalar object paths are supported:

```text
kind_idx:meta.kind:string
kind_cover:meta.kind:string:covering
enabled_idx:meta.enabled:bool:covering
code_idx:meta.kind.code:string
```

Current JSON-path indexing rules:

- object-path navigation only
- scalar leaf type must be declared as `string`, `bool`, or `i64`
- arrays and non-scalar JSON leaves are not indexed yet

## 5. Git-Like Semantics

`pollydb` treats data changes like versioned commits on branches.

### Inspect Branches

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- branches
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- show-branch
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- log 10
```

### Create a Branch

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- create-branch feature
```

### Read a Branch Head

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- checkout feature
```

### Merge

Preview and report:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- merge-base main feature
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- merge-preview main feature
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- merge-report main feature 10
```

Merge:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- merge-branch main feature
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- merge-branch main feature ours
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- merge-branch main feature theirs
```

Conceptually:

- a branch head points to a commit
- each commit has a main data root
- commits may also carry virtual roots for aggregate projectors

## 5.1 Polly-Link and Sidecar Sync

Current remote sync goes through a Polly-Link Sidecar.
Today the transport is simple HTTP + JSON.

Current sync endpoints are:

- `POST /v1/sync/offer`
- `POST /v1/sync/missing`
- `POST /v1/sync/exchange`
- `POST /v1/sync/exchange-full`
- `POST /v1/sync/apply`

Current control-plane endpoints are:

- `GET /v1/repos`
- `POST /v1/repos/open`
- `GET /v1/branches`
- `GET /v1/repo-activity`
- `GET /v1/branch-activity`
- `GET /v1/branch-log`

Examples:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- sidecar-repos http://127.0.0.1:8765
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- sidecar-open-repo http://127.0.0.1:8765 team-a main
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- sidecar-repo-activity http://127.0.0.1:8765 team-a 10
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- sync-push-sidecar http://127.0.0.1:8765 team-a main auto
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- sync-pull-sidecar http://127.0.0.1:8765 team-a main auto
```

This transport will likely evolve later, but the current HTTP form is the reference implementation for Polly-Link and Polly-Hub M1.

## 6. CRUD

### Insert or Update a Row

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row users 001 \
  "id=001,name=Ada,email=ada@example.com,active=true"
```

### Read One Row

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- get-row users 001
```

### Delete One Row

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- delete-row users 001
```

### Scan a Table

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- scan-table users 10
```

## 7. Query by Index

### Exact Lookup

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- lookup-index users email_idx ada@example.com 10
```

### Continue Scanning the Same Index Value

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- scan-index users email_idx ada@example.com 001 10
```

### Prefix Lookup

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- prefix-index users email_cover ada 10
```

### Prefix Lookup with Projection

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- prefix-index-projected users email_cover ada "email" 10
```

This is especially useful for covering indexes and low-latency projected reads.

## 8. Working with `bool`, `enum`, `json`, and `datetime`

A richer schema:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-table items id \
  "id:string,status:enum(active|draft),meta:json,enabled:bool" \
  "status_idx:status,kind_idx:meta.kind:string,kind_cover:meta.kind:string:covering,enabled_idx:meta.enabled:bool:covering"
```

For timestamped rows:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- create-table events id \
  "id:string,title:string,created_at:datetime:current_timestamp,updated_at:datetime:current_timestamp:auto_update" \
  "-"

v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row events 001 \
  "id=001,title=Draft"
```

On insert, `created_at` and `updated_at` are filled automatically. On later updates, `updated_at` is refreshed automatically:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row events 001 \
  "title=Published"
```

You can also provide a timestamp explicitly:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row events 002 \
  "id=002,title=Imported,created_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP"
```

Insert a row:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row items 001 \
  "id=001,status=active,enabled=true,meta={\"kind\":{\"code\":\"alpha\"},\"enabled\":true}"
```

### Update One JSON Path

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- set-json-path items 001 meta kind.code string beta
```

### Set a JSON Path to `null`

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- null-json-path items 001 meta enabled
```

### Delete a JSON Path

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- delete-json-path items 001 meta legacy
```

### Patch Multiple JSON Paths

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- patch-json-paths items 001 meta \
  "kind.code=string:beta,enabled=null,legacy=delete"
```

JSON-path indexes are maintained automatically when these updates touch indexed paths.

## 9. Aggregates

### Declared Aggregate Columns

If a column is declared as `i64:sum`, `pollydb` can maintain aggregate metadata:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-table metrics id \
  "id:i64:sum,name:string" \
  "-"
```

Fast aggregate reads:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- count-rows metrics
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- count-rows-range metrics 100 500
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- sum-column metrics id
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- sum-column-range metrics id 100 500
```

Current behavior:

- full-table `COUNT(*)` is metadata-fast
- range `COUNT(*)` is metadata-assisted
- declared `SUM(i64)` is metadata-fast for full-table reads
- declared `SUM(i64)` range queries use bucketed aggregate side structures

## 10. Aggregate Projectors

For aggregates you do not want to push deeper into the main data tree, use aggregate projectors.

Register one:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-aggregate-projection sum_metrics metrics id "" 500 low
```

For JSON numeric paths:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-aggregate-projection sum_payload metrics payload amount.total 500 medium
```

Inspect projector state:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- projectors
```

Refresh projector roots:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- refresh-aggregate-projections stale_one
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- refresh-aggregate-projections stale_up_to 2
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- refresh-aggregate-projections stale_all
```

Current refresh policies:

- `none`
- `stale_one`
- `stale_up_to`
- `stale_all`

Current scheduling hints:

- `priority`
- `cost_hint = low | medium | high`

When budget is limited, `pollydb` refreshes:

1. higher priority first
2. lower cost hint first
3. name order as a stable tie-breaker

## 11. Durability and Checkpointing

### Full Checkpoint

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- checkpoint
```

### Data-Only Checkpoint

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- checkpoint data_only
```

`data_only` makes the main data durable while allowing some derived state such as sidecar index snapshots to catch up later.

You can publish index sidecars explicitly:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- refresh-index-snapshots
```

## 12. What PollyDB Already Feels Like

Today, `pollydb` already behaves like a small versioned database engine:

- typed tables
- secondary indexes
- covering indexes
- JSON-path indexes
- Git-like branches and merges
- durable commits and checkpoints
- aggregate metadata
- aggregate projectors with independent refresh policy

What it does not have yet is a SQL frontend. The underlying storage/database model is already there; SQL parsing and `vsql` integration are the next layer on top.
