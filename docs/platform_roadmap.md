# PollyDB -> Polly-Link -> Polly-Hub

This roadmap describes how the current `pollydb` codebase can evolve from a strong local versioned database into a full data collaboration platform.

The short version is:

- `PollyDB` is the versioned storage and query kernel.
- `Polly-Link` is the hash-based sync and merge protocol.
- `Polly-Hub` is the multi-user service layer that turns the kernel and protocol into a product.

## Current Position

Today the project already has the hardest kernel pieces in place:

- content-addressed Prolly-tree storage
- branch / commit / merge-base / merge-report semantics
- low-latency root-hash readers
- aggregate projectors and meta-commit virtual roots
- sync planning, push/pull helpers, and manifest negotiation
- provider/backend abstraction for future storage/compute separation

That means the project is no longer "just a toy database". The next milestones are about service shape, collaboration loops, and operational completeness.

## Layer 1: PollyDB

PollyDB is the local database kernel.

### What PollyDB Owns

- versioned data model
- content-addressed nodes and commits
- branch coordination
- typed tables, indexes, aggregates, projectors
- local durability and recovery
- root-hash read APIs

### Current State

Mostly present today:

- local repository layout in `.pollydb`
- typed CRUD and indexes
- JSON/enum/bool/datetime support
- aggregate keys and aggregate projectors
- projector stale/fresh policy
- merge preview/report/commit flows
- provider-driven backend entry points

### Exit Criteria

PollyDB can be considered "kernel-complete" when:

- repository repair / fsck exists
- GC / compaction policy is defined
- backup / restore story is documented
- merge and sync APIs are stable enough for service embedding

## Layer 2: Polly-Link

Polly-Link is the replication and collaboration protocol.

### What Polly-Link Owns

- hash-based negotiation
- missing-CID discovery
- packet exchange
- attach-by-CAS branch advancement
- divergence detection
- auto-merge attempt before surfacing conflicts

### Current State

Already present in local, transport-neutral form:

- `SyncSession`
- `SyncOffer`
- `SyncManifest`
- `SyncMissingSet`
- `SyncExchange`
- `push_branch_to_repo(...)`
- `pull_branch_to_repo(...)`
- manifest depth policies
- sync negotiation policy recommendation
- `auto_merge_by_roots(...)`

### Next Milestones

#### Polly-Link M1: Transport-ready protocol

- define request/response envelopes for Sidecar transport
- preserve current local sync logic as the reference implementation
- standardize packet batching and size limits
- add explicit sync error classes:
  - stale branch head
  - malformed packet
  - missing parent commit
  - merge required

Current transport choice:

- today Polly-Link uses a minimal HTTP + JSON Sidecar surface
- each sync phase is an explicit endpoint, not a generic RPC framework
- it is not WebSocket-based yet
- this keeps the protocol easy to inspect and debug while the sync model stabilizes

Current sync endpoints:

- `POST /v1/sync/offer`
- `POST /v1/sync/missing`
- `POST /v1/sync/exchange`
- `POST /v1/sync/exchange-full`
- `POST /v1/sync/apply`

#### Polly-Link M2: Collaboration loop

- detect branch divergence during push
- attempt `3-way` auto-merge
- if merge succeeds:
  - synthesize merged commit
  - attach merged branch head
- if merge fails:
  - return structured conflict report

#### Polly-Link M3: Real network optimization

- Sidecar transport
- RTT-aware policy defaulting
- manifest depth policy selection on live links
- stream packets instead of waiting for full exchange materialization
- evaluate moving from plain HTTP request/response to:
  - a thinner RPC-style surface on the same messages
  - or a streaming transport such as WebSocket when packet streaming becomes more important than simple debuggability

### Exit Criteria

Polly-Link is "platform-ready" when:

- tiny changes sync as tiny object sets across a real network
- interrupted sync resumes naturally
- divergence either auto-merges or returns precise conflict reports
- sync policy can be chosen automatically from link characteristics

## Layer 3: Polly-Hub

Polly-Hub is the service layer.

### What Polly-Hub Owns

- remote repository hosting
- authn/authz
- tenant and namespace model
- audit logs
- background refresh and catch-up
- operational tooling

### Recommended Service Split

Use the current architecture boundary:

- object/chunk storage:
  - nodes
  - commits
  - virtual roots
- strongly consistent metadata store:
  - branch heads
  - repo metadata
  - catalog metadata
- compute layer:
  - query sessions
  - merge workers
  - projector refresh workers
  - sync planners

### Polly-Hub Milestones

#### Polly-Hub M1: Sidecar service

- expose `push/pull/recommend-policy`
- use provider-backed repository open/init
- authenticate repo and branch operations
- support per-repo namespaces
- expose minimal control-plane read APIs:
  - repo list
  - repo open/create
  - branch list
  - repo activity
  - branch activity
  - branch log

#### Polly-Hub M2: Hosted collaboration

- merge endpoint
- conflict report endpoint
- branch activity timeline
- notebook/project sharing workflows

#### Polly-Hub M3: Operability

- health and repair endpoints
- metrics for:
  - packets
  - bytes
  - merge rate
  - stale projector lag
- GC/retention tooling
- backup/restore and disaster recovery

### Exit Criteria

Polly-Hub is "sellable platform infrastructure" when:

- remote repos are multi-tenant
- sync/merge flows are service-backed
- observability and repair stories exist
- cost story is visible through global dedup and object reuse

## Why This Stack Matters

This stack is commercially interesting because each layer compounds the previous one:

- `PollyDB` makes versioned structured data cheap and fast.
- `Polly-Link` makes changes small and collaboration natural.
- `Polly-Hub` turns those properties into a hosted product.

The differentiators are:

- global dedup through content addressing
- merge semantics at the data-tree layer, not only at text files
- projector and virtual-root model for derived state without bloating the primary tree
- clean path toward storage/compute separation

## Recommended Execution Order

If the goal is to reach "usable collaboration platform" fastest, this is the order to follow.

1. Finish Polly-Link service readiness.
   - transport-neutral protocol is already in place
   - next step is Sidecar transport and divergence workflow

2. Complete sync + merge collaboration loop.
   - push
   - divergence detect
   - auto-merge attempt
   - conflict report fallback

3. Harden PollyDB operational core.
   - repair
   - GC
   - backup/restore

4. Build Polly-Hub around provider-backed repositories.
   - auth
   - namespaces
   - observability
   - hosted workflows

## Near-Term Backlog

The highest-value next engineering items are:

- Sidecar RPC/HTTP surface for `Polly-Link`
- `auto_merge_commits(...)` / `auto_merge_branches(...)`
- divergence-aware `push`
- sync benchmark with real transport
- repository repair / fsck
- branch-head metrics and audit log

## Practical Reading Guide

- Start with [tutorial.md](/Users/guweigang/Source/pollytree/docs/tutorial.md) for CLI usage.
- Read [storage_api.md](/Users/guweigang/Source/pollytree/docs/storage_api.md) for the stable storage contract.
- Read [storage_compute_separation.md](/Users/guweigang/Source/pollytree/docs/storage_compute_separation.md) for backend/provider architecture.
- Use this document when deciding what to build next at the platform level.
