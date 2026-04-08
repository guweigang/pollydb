# PollyDB Query Layer Roadmap

This note turns the recent `agentview browser` findings into an engineering plan
for the PollyDB query layer.

The goal is not to optimize one application in isolation.
The goal is to make PollyDB behave more like a database and less like "versioned
storage with a thin typed accessor layer".

That matters because:

- `agentview browser` is now the most honest query-layer litmus test
- future `vsql` depends on a strong query executor rather than stronger storage alone

## Core Judgment

The current bottleneck is **not** primarily:

- lack of field types
- lack of index declarations
- lack of versioned storage capability

The current bottleneck **is**:

- query execution paths that still have high read amplification
- index-backed reads that are not yet cheap enough in practice
- a physical layout that is still too mixed for some interactive workloads

So the next round should target:

1. execution layer
2. physical read/write layout
3. reusable query products above storage

## Scope Split

The work naturally falls into three layers.

### 1. `storage/`

This is where the engine-level improvements belong.

Main responsibilities:

- typed row / index execution
- tree traversal and cursor behavior
- split-backed row/index layouts
- read amplification reduction
- stable low-level explainable operators

What belongs here next:

- covering scan paths that truly avoid row fetch/decode
- reverse / top-N / range index execution as first-class operators
- projection pushdown into covering/index reads
- lower-overhead typed readers on top of versioned trees
- continued split-backed steady-state work for the proven winning path
  - incremental `sync-codex`

### 2. `query/`

This is where the planner/explain surface should get stronger.

Main responsibilities:

- legal query shape validation
- planner strategy selection
- capability exposure
- request-time explain
- execution-path visibility

What belongs here next:

- stable `EXPLAIN` / planner preview output
- explicit strategy names for:
  - covering scan
  - projected scan
  - reverse/top-N index scan
  - scan fallback
- richer plan metadata:
  - expected post-filters
  - projected columns
  - continuation friendliness
  - likely read amplification notes

### 3. PollyDB Product Capability

This is where the database becomes more usable for real applications.

Main responsibilities:

- repeatable operational patterns
- read models / materialized projections
- index lifecycle
- benchmark and diagnostics surfaces

What belongs here next:

- explicit search/index lifecycle commands and diagnostics
- read-model / materialized-projection support for interactive apps
- browser/CLI-observable query strategy surfaces
- benchmark surfaces that separate:
  - tree-only cost
  - typed apply cost
  - app end-to-end cost

## Priority Order

If only one line can be funded at a time, use this order.

### Priority 1: Execution-Layer Maturity

Before more app work or more SQL work, PollyDB should gain:

- real covering scan execution
- projection pushdown
- reverse/top-N/range scans
- lower read amplification from versioned trees to typed rows

This is the most leveraged work because both `agentview` and future `vsql`
depend on it.

### Priority 2: Split-Backed Steady-State Where It Already Wins

Keep using the proven rule:

- mixed for first import
- split-backed for incremental `sync-codex`
- mixed fallback for selector-heavy search maintenance

Do not expand split-backed blindly.
Only keep pushing the workloads where benchmark evidence is already positive.

### Priority 3: Read Models / Materialized Projections

Once execution is strong enough, add a generic read-model story for workloads
like:

- latest session lists
- transcript-by-session views
- search-ready entry projections

This should be framed as a general PollyDB capability, not an `agentview`
special case.

## What Agentview Proves

`agentview browser` is useful because it compresses the real query problem into
three visible reads:

- latest-N session list
- per-session transcript page
- structured/FTS search

If PollyDB cannot satisfy those interactively, then future consumers will hit
the same wall.

So the correct interpretation is:

- `agentview` is the proving ground
- not the exception case

## What VSQL Needs From This Layer

`vsql` should stay thin.
That only works if PollyDB already provides:

- efficient index-backed execution
- strong planner preview / explain
- stable capability metadata
- predictable continuation/page semantics

Without that, `vsql` would be forced to compensate for executor weaknesses and
would stop being a clean SQL-to-query adapter.

So the strategic sequencing is:

1. make PollyDB query execution real
2. make planner/introspection output stable
3. let `vsql` consume that surface

## Near-Term Rule

Use this decision rule for upcoming work:

- if a change only helps one benchmark shape by a few milliseconds, treat it as optional
- if a change reduces generic read amplification or improves a reusable operator, prioritize it

In short:

`prefer reusable query operators over app-specific shortcuts.`
