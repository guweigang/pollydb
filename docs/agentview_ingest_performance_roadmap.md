# Agentview Ingest Performance Roadmap

This note captures the current state of `agentview` ingest/search performance on top of `pollydb`, and proposes the next round of structural work.

It is intentionally focused on the real Codex transcript workload:

- `~/.codex` session JSONL import
- `agentview sync-codex`
- `agentview index-search`
- `pollydb` typed row + index maintenance path

## Single Next Bet

The next phase should focus on exactly one performance line:

- make `split-backed` the preferred steady-state path for incremental `sync-codex`

Everything else is secondary for now.

In particular:

- do not spend the next round on first-import optimization
- do not spend the next round on `index-search` split-backed execution
- do not reopen the rejected split-apply variants (`prototype`, `delta`, naive per-index rebuild)

Why this is the highest-yield choice:

- real delta benchmarks already show `split-backed` wins on incremental `sync-codex`
- the same is not true for `index-search`, because markdown/field-selector index maintenance still forces a mixed fallback
- first import is still insert-heavy and already behaves better on the mixed path

So the most productive rule for the next round is:

`mixed for first import, split-backed for incremental sync, mixed fallback for selector-heavy search maintenance.`

## Current Situation

The project already moved past the original obvious bottlenecks:

- repeated full transcript scans during ingest
- per-entry markdown ingest on the hot path
- repeated full-table fallback reads in `agentview`
- repeated tree/item expansion costs in several storage paths
- some avoidable index/key allocation overhead in `TypedIndexedSchemaView`

The current baseline is materially better than the starting point, but the remaining cost is no longer dominated by one trivial mistake.

At this stage, the main lesson is:

`small local optimizations still help, but their gains are increasingly noisy and unstable compared to the effort required to find and validate them.`

That means the next round should prioritize structural optimization over micro-optimization.

## What The Recent Tuning Tells Us

The last tuning rounds established several useful facts:

1. `sync-codex` was not primarily blocked by reading `.jsonl`.
   Once repeated scans were removed, the dominant cost moved into the write/apply path.

2. The current `pollydb` typed apply path is still fundamentally "build a large in-memory mutation view, then rebuild sorted tree state".
   Local improvements reduced overhead inside that model, but the model itself is still expensive.

3. Several low-level hotspots are now "second-order" costs rather than "root-cause" costs.
   For example:
   - `fallback_ops_encode`
   - `fallback_ops_index`
   - `fallback_build_prepare_rows`
   - `fallback_build`

4. Some ideas that look correct in isolation do not survive end-to-end benchmarking.
   Recent examples included:
   - projected decode of old rows
   - alternative merge paths for unchanged rows
   - several key-merge shortcuts

So the path forward should not be:

- keep probing tiny hot spots indefinitely

Instead it should be:

- change the algorithmic shape of the write/update path
- improve the granularity of ingest
- keep benchmark layers separated so structural wins are easy to verify

## The Real Structural Bottlenecks

### 1. Session-Level Rewrite Model

`agentview sync-codex` still behaves like a session-oriented rewrite.

That is already much better than per-entry commits, but it still means:

- a session-level change rewrites many `entries`
- old index rows are removed and rebuilt in bulk
- the typed write path still sees a large mutation batch

This is acceptable for a first version, but it is not the end state for large transcript archives.

### 2. `apply_write_ops_with_map()` Is Still A Whole-Structure Mutation Strategy

The current strategy is roughly:

1. expand existing tree items into a mutable map
2. apply row/index mutations into the map
3. rebuild sorted KV state
4. rebuild tree structure

Even after many local optimizations, this remains expensive because:

- large maps are materialized
- many string-key and byte-key transitions still happen
- sorted rebuild remains a bulk cost

### 3. Search Indexing Is Still Split But Not Yet Cheap Enough

The current two-phase flow is already the right direction:

- `sync-codex`
- `index-search`

But the search side is still not fully incremental in the strongest possible sense.

The first build remains heavy, and the data model is not yet optimized for row-level search material reuse.

## Next Stage Goals

The next stage should aim for three product-level outcomes:

1. `sync-codex` feels predictably fast on large local archives.
2. `index-search` becomes clearly incremental and cheap after the first build.
3. performance work becomes benchmark-driven at the right layer instead of relying on whole-flow noise.

## Recommended Workstreams

The sections below remain useful background, but they are no longer equal-priority candidates.
The active choice is to push only the `split-backed incremental sync-codex` line until it is clearly product-ready.

## Workstream A: Entry-Level Incremental Ingest

This is the most important product-facing improvement.

Today, change detection is already better than before, but it is still too coarse.

The next step is to introduce a more granular ingest state:

- session fingerprint
- entry fingerprint
- indexed-search-material fingerprint

Suggested additions:

- `entry_ingest_state`
  - `session_id`
  - `entry_id` or stable `seq_key`
  - source fingerprint
  - stored row fingerprint
- `entry_search_state`
  - `entry_id`
  - search-material fingerprint
  - index version

Outcome:

- session changes no longer imply rewriting all entries
- index backfill can operate at entry granularity
- `sync-codex` becomes "append/update changed entries" instead of "rewrite changed session"

## Workstream B: Replace Map-Rebuild With A More Targeted Mutation Strategy

This is the most important storage-facing improvement.

`apply_write_ops_with_map()` should not remain the final long-term strategy for large batches.

There are two realistic directions:

### Option B1: Partitioned Bulk Mutation

Keep the current typed write model, but mutate by sorted key partitions instead of one giant map.

That would look like:

- sort changed row/index keys
- scan only overlapping key ranges from the current tree
- rebuild only the affected sorted spans
- stitch unchanged spans back together

This is still a rebuild-based design, but it stops pretending the entire table is one mutation unit.

### Option B2: Leaf-Oriented Patch Apply

Move closer to a B-tree-style patch strategy:

- locate affected leaves
- decode only those leaves
- apply inserts/removes inside those leaves
- rebuild only changed leaf path(s)

This is more invasive, but it is probably the right direction if `pollydb` wants to support high-throughput typed local OLTP-style updates in addition to bulk append cases.

Recommendation:

- start with `Option B1`
- treat `Option B2` as the longer-term engine evolution

`Option B1` is more likely to produce a big win without rewriting the storage engine all at once.

## Workstream C: Separate Benchmark Layers

This work should happen in parallel with algorithm changes.

Right now benchmarking exists, but the next stage needs clearer layers:

### Bench 1: Typed Apply Hot Path

This already started with:

- `agentview bench-write-path`

It should be extended to test:

- insert-only
- mixed update
- delete-heavy
- small vs. large existing tree
- varying index counts

### Bench 2: Tree Build Only

Add a dedicated benchmark that measures:

- `Tree.build_sorted(...)`
- `Tree.build_sorted_bulk_with_timings(...)`
- leaf build
- internal build

without any typed schema logic involved.

### Bench 3: Agentview Ingest Model

Keep `bench-codex`, but use it only for:

- end-to-end validation
- regression checks
- user-facing timing

and not as the primary tool for tuning inner loops.

Outcome:

- micro tuning becomes measurable
- structural changes become obvious
- noisy full-flow regressions stop wasting time

## Workstream D: Search-Material Reuse

On the search side, the next structural win is to stop treating search preparation as a separate expensive "recompute text material" stage whenever possible.

Suggested direction:

- introduce a normalized per-entry search payload
- store it once
- reuse it for:
  - transcript preview
  - search snippet generation
  - FTS rebuild

That would reduce repeated markdown/text preparation and make `index-search` more cache-friendly.

## Recommended Execution Order

## Updated Priority

### Phase 1: Finish The Winning Path

- keep first full `sync-codex` on mixed
- keep `index-search` on mixed whenever selector-heavy indexes are involved
- continue improving split-backed steady-state for incremental `sync-codex`
- add/keep delta-style benchmarks that mutate a small number of real session files and measure the second sync

Success criteria:

- incremental `sync-codex` stays measurably faster with `--split-backed`
- the split-backed path is stable enough to be enabled with a clear heuristic
- no regression to first-import behavior

### Phase 2: Only Then Revisit Search

- revisit split-native handling for markdown/field-selector indexes
- only after `sync-codex` steady-state is settled

This is intentionally deferred, because the current benchmarks do not show a clear win yet.

### Phase 1

- extend benchmark layers
- add typed apply benchmark cases for insert/update/delete mixes
- add tree-only build benchmark

### Phase 2

- add entry-level ingest/search state
- make `sync-codex` incremental at entry granularity
- make `index-search` incremental at entry granularity

### Phase 3

- prototype partitioned bulk mutation for `apply_write_ops_with_map()`
- compare against current map-rebuild strategy using the new benchmark layers

### Phase 4

- design and prototype row/index tree separation
- use that split layout to reduce rebuild scope before attempting leaf-oriented patch apply

### Phase 5

- if row/index separation is still insufficient, begin leaf-oriented patch apply design

## Practical Rule Going Forward

Use this decision rule for future performance work:

- if a change saves a few milliseconds only under one benchmark shape, treat it as optional
- if a change reduces algorithmic work or mutation scope, prioritize it

In other words:

`prefer removing work over making existing work slightly faster`

## Summary

There is still significant optimization space.

But the remaining value is no longer in endless local hot-path tuning.

The next serious gains will come from:

- finer-grained ingest
- more local mutation scope
- benchmark separation
- reduced rebuild surface

That is the right next stage for `agentview + pollydb`.

## Agentview As The Query-Layer Litmus Test

`agentview browser` has now become more than an application benchmark.
It is the best current litmus test for whether `pollydb` already has a database-grade query layer.

That matters because the browser workload is unusually honest:

- session list is a "latest N" read
- transcript is a "single partition / ordered page" read
- search is a "structured filter + FTS" read
- all three are interactive and user-visible

This workload does **not** tolerate:

- index paths that still perform large read amplification
- covering indexes that still behave like row lookups
- planner/executor gaps hidden behind a generic storage abstraction
- "it uses an index, therefore it must be fast" assumptions

The recent 1.5G real-store benchmark showed exactly that:

- browser list used an index but still remained too slow
- transcript used an index but still remained too slow
- search required explicit FTS/index lifecycle management before it could even be evaluated fairly

So the right interpretation is:

- `agentview` is not "just one app with special needs"
- it is the first realistic proof point that exposes whether the `pollydb` query layer is truly mature

If `pollydb` can satisfy `agentview browser`, then it is much more likely to satisfy future higher-level consumers as well.

## Why This Work Directly Benefits VSQL

The same gaps exposed by `agentview browser` are exactly the gaps that would make a future `vsql` layer feel thin or unreliable.

`vsql` does **not** mainly need more storage features.
It needs a stronger execution layer above versioned storage.

The key capabilities are:

- real covering scan execution
- projection pushdown
- reverse/top-N/range index scan
- stable `EXPLAIN` / planner introspection
- lower read amplification between versioned trees and typed rows

Without those capabilities, `vsql` would inherit the same problems:

- legal queries that still feel unexpectedly heavy
- planner choices that cannot be explained cleanly
- index-backed requests that still pay too much generic tree traversal cost

So the strategic rule should be:

- use `agentview` to force the `pollydb` query layer to become real
- let `vsql` consume that mature query layer instead of reinventing it

In short:

`agentview` is the proving ground; `vsql` is the downstream beneficiary.`

## Query-Layer Priorities Before More App-Specific Work

If the goal is to raise `pollydb` from "good versioned storage" to "good queryable versioned database", the next priorities should be:

1. make index execution cheap in practice, not just available in principle
2. reduce read amplification between typed queries and the underlying versioned tree layout
3. keep split-backed work focused on the proven winning path:
   - incremental `sync-codex`
4. defer app-specific browser special cases until the generic query layer is stronger

This keeps the work aligned with the long-term platform:

- better `agentview`
- better `vsql`
- fewer one-off shortcuts

## Next Highest-ROI Structural Cut: Split Row And Index Trees

The recent tuning rounds make one thing increasingly clear:

`the current mixed-key tree is now the main structural reason why local improvements keep hitting diminishing returns.`

Today a typed table stores:

- row entries
- typed secondary index entries
- selector-derived index entries

inside one logical sorted keyspace.

That means even a mutation workload that is mostly "row updates plus a few changed index entries" still pays for:

- one mixed mutation map
- one mixed sorted-merge phase
- one mixed tree rebuild

Partitioned rebuild improved this model and should be kept, but it is still operating inside a layout that couples row keys and index keys too tightly.

### Why This Is The Biggest Remaining Gain

The current hot-path costs line up with the mixed-tree design:

- `fallback_ops_index`
- `fallback_build_prepare_rows`
- `fallback_build_prepare_keys_merge`
- `fallback_build`

These are no longer mostly "encoding mistakes" or "avoidable clones".

They are increasingly the cost of:

1. generating row and index mutations in the same apply pass
2. merging row and index keys into the same sorted structure
3. rebuilding one tree that mixes all mutation kinds together

As long as rows and indexes share one rebuild surface, many local wins will stay small and workload-dependent.

### Target Layout

The next storage shape should split one typed table into:

- one row tree
- zero or more index trees

For a table `entries`, the logical layout becomes:

- `entries.rows`
  - primary-key row payloads
- `entries.index.updated_at_idx`
  - scalar secondary index entries
- `entries.index.entries_fts_any_idx`
  - FTS entries
- `entries.index.entries_fts_heading_idx`
  - markdown-heading FTS entries

In other words:

- row mutations rebuild the row tree only
- index mutations rebuild only the affected index tree(s)

### Expected Product-Level Wins

This split should produce larger gains than another round of inner-loop tuning because it removes work instead of polishing the same work.

Expected outcomes:

1. large update-heavy workloads stop rebuilding one oversized mixed structure
2. tables with many indexes scale more like:
   - row cost
   - plus changed-index cost
   instead of one blended bulk cost
3. `sync-codex` entry-level incremental ingest benefits more directly because unchanged rows stop dragging unrelated index key ranges through the same rebuild path
4. `index-search` becomes easier to optimize independently because search trees are already physically separate

### Proposed Migration Path

This should be done in small steps instead of a full rewrite.

#### Step 1: Introduce A Split Table View

Keep typed table semantics unchanged, but change the physical representation from:

- one `TableView`

to something conceptually like:

- `TypedTableStorage`
  - `rows_tree`
  - `index_trees map[string]Tree`

The public query API can remain table-oriented while the backing storage becomes split.

#### Step 2: Keep Reads Backward-Compatible

Add a compatibility layer so current typed schema logic still asks for:

- get row by primary key
- lookup index entries

without knowing yet whether those values come from one tree or multiple trees.

This reduces migration risk.

#### Step 3: Split The Apply Path

Replace today's mixed mutation path with:

1. row mutation collection
   - insert/update/delete primary rows
2. index mutation collection
   - per-index add/remove/update entries
3. independent apply
   - rebuild row tree
   - rebuild only changed index trees

This is the first stage where we should expect a major performance jump.

#### Step 4: Keep Partitioned Rebuild As A Per-Tree Strategy

Partitioned rebuild should not be thrown away.

Instead:

- use partitioned rebuild for the row tree
- use partitioned rebuild for each changed index tree

That makes today's work reusable instead of disposable.

### Benchmark Plan For This Cut

This design should be judged with the benchmark layers that already exist.

#### Typed Apply

Extend `bench-write-path` and `bench-write-matrix` to compare:

- mixed-tree apply
- split-tree apply

under:

- `update + 1 index`
- `update + 6 indexes`
- `mixed + 6 indexes`

The most important signal is whether multi-index update workloads start scaling materially better.

#### Tree Only

Use `bench-tree-build` to ensure any row-tree and index-tree improvements are not being hidden by unrelated typed logic.

#### End To End

Use `bench-codex` only after typed-path wins are already visible.

The desired end-to-end effect is:

- smaller `sync-codex apply`
- cheaper second sync for changed sessions
- less coupling between transcript ingest and search-tree maintenance

### What Not To Do

To stay focused on ROI, avoid spending the next rounds on:

- more key-string micro-tuning
- more one-off merge shortcuts in the mixed tree
- more fallback timing decomposition unless a new structural change needs proof

Those paths taught us a lot, but they are no longer the highest-value frontier.

### Recommendation

The next serious engineering push should be:

1. keep the current partitioned rebuild implementation as the stable baseline
2. design a split typed table storage model with row and index trees separated
3. prototype split apply on `bench-write-path`
4. only then decide whether leaf-oriented patch apply is still necessary

If this works, it should deliver bigger wins than another long round of hot-loop tuning.

## What The Split-Apply Prototypes Already Ruled Out

The split-table work is no longer just a design sketch.

Two concrete prototype paths have already been implemented and benchmarked:

- `split_apply_prototype`
  - apply rows first
  - then rebuild every changed index tree from the updated rows tree
- `split_apply_delta`
  - apply rows first
  - then issue fine-grained per-row put/delete mutations to each changed index tree
- `split_apply_batched`
  - apply rows first
  - collect index mutations per index in memory
  - then apply one batched rebuild per changed index tree

Those experiments were useful because they ruled out two tempting but wrong directions.

### Prototype 1: Row Apply + Full Index Rebuild

This path is structurally simple, but benchmark data showed it is still worse than staying on the mixed-tree write path and materializing split storage afterward.

Representative result on `update + 6 indexes`:

- `apply`: about `150ms`
- `split_materialize`: about `97ms`
- `apply_plus_split`: about `248ms`
- `split_apply_prototype`: about `431ms`

Conclusion:

- physically separated row/index trees are not enough by themselves
- rebuilding every index tree after each write batch is still too expensive

### Prototype 2: Per-Row Delta Apply Into Each Index Tree

This path is closer to the intended end state, but with the current `Tree` implementation it performs far worse than expected.

Representative result on `update + 6 indexes`:

- `apply`: about `214ms`
- `apply_plus_split`: about `339ms`
- `split_apply_delta`: about `8994ms`

Representative result on `mixed + 6 indexes`:

- `apply`: about `202ms`
- `apply_plus_split`: about `353ms`
- `split_apply_delta`: about `5175ms`

Conclusion:

- per-row incremental mutation on separate index trees is not viable on the current tree engine
- the cost of many tiny `put/delete` operations dominates any benefit from physical separation

### The Important Lesson

These results do **not** mean split storage was a mistake.

They mean:

- `row/index split layout` is still the right structural direction
- but **neither**
  - `full rebuild every index tree`
  - **nor**
  - `apply tiny mutations into every index tree one by one`
  is the right execution strategy

This is valuable because it narrows the search space.

### Prototype 3: Per-Index Batched Mutation

This third path is the first split-apply strategy that behaves like a plausible bridge to the desired design.

Representative result on `update + 6 indexes`:

- `apply`: about `166ms`
- `split_materialize`: about `104ms`
- `apply_plus_split`: about `270ms`
- `split_apply_prototype`: about `463ms`
- `split_apply_delta`: about `6634ms`
- `split_apply_batched`: about `363ms`

Representative result on `mixed + 6 indexes`:

- `apply`: about `168ms`
- `split_materialize`: about `109ms`
- `apply_plus_split`: about `277ms`
- `split_apply_prototype`: about `434ms`
- `split_apply_delta`: about `4042ms`
- `split_apply_batched`: about `388ms`

Conclusion:

- `split_apply_batched` is materially better than the two naive split paths
- but the current implementation still loses to `apply + split_materialize`
- so the direction looks promising, but the implementation is not yet good enough

### The Most Important New Signal: Steady-State Split Layout

The previous comparison still started from a mixed-backed view, which means `split_apply_batched` was paying an upfront split-materialization cost before doing useful work.

Once benchmarked on an already split-backed view, the picture changes:

Representative result on `update + 6 indexes`:

- `apply`: about `156ms`
- `apply_plus_split`: about `250ms`
- `split_apply_batched`: about `317ms`
- `split_apply_batched_steady`: about `224ms`

Representative result on `mixed + 6 indexes`:

- `apply`: about `152ms`
- `apply_plus_split`: about `250ms`
- `split_apply_batched`: about `322ms`
- `split_apply_batched_steady`: about `200ms`

This is the first benchmark result showing:

- the split direction is not only theoretically cleaner
- it can already beat `apply + split_materialize`
- **if the store is already physically split**

That is the strongest evidence so far that row/index separation is still the right high-ROI path.

### What The Bridge Benchmark Ruled Out

One more experiment matters for productization:

- `split_apply_batched_bridge`
  - start from an already split-backed view
  - apply with `split_apply_batched`
  - then materialize back into one mixed tree for compatibility

Representative result on `update + 6 indexes`:

- `apply`: about `137ms`
- `apply_plus_split`: about `233ms`
- `split_apply_batched_steady`: about `216ms`
- `split_apply_batched_bridge`: about `397ms`

Representative result on `mixed + 6 indexes`:

- `apply`: about `183ms`
- `apply_plus_split`: about `287ms`
- `split_apply_batched_steady`: about `213ms`
- `split_apply_batched_bridge`: about `399ms`

Conclusion:

- steady split-backed apply is promising
- but bridging back to mixed layout is too expensive
- so the productive next step is **not** "use split internally, then merge back"
- the productive next step is to let split-backed layout become a real steady-state working representation

### Working-Set-Level Split Steady State

The strongest signal so far is no longer the single-view benchmark, but the working-set-level benchmark.

Representative result on `update + 6 indexes`:

- `apply`: about `145ms`
- `apply_plus_split`: about `240ms`
- `split_apply_batched_steady`: about `221ms`
- `split_working_set_apply`: about `210ms`

Representative result on `mixed + 6 indexes`:

- `apply`: about `156ms`
- `apply_plus_split`: about `258ms`
- `split_apply_batched_steady`: about `228ms`
- `split_working_set_apply`: about `212ms`

This matters because:

- it is closer to a real steady-state product workflow than the single-view prototype
- it still beats `apply + split_materialize`
- and it confirms that the payoff survives one more step toward a realistic lifecycle

At this point the evidence is strong enough to justify a real migration path toward split-backed working representations.

## The Next Worthwhile Split Strategy

The next high-ROI split experiment should be:

- keep row/index trees physically separate
- collect row changes first
- collect index mutations per index in batches
- for each changed index:
  - build one batched mutation set
  - apply partitioned rebuild only to the affected spans of that index tree

In short:

`per-index batched mutation + per-index partitioned rebuild`

That is the remaining split strategy most likely to beat:

- current mixed-tree apply
- current `apply + split_materialize`

because it avoids the two bad extremes:

- not rebuilding every index tree wholesale
- not issuing thousands of tiny incremental tree mutations either

## Updated Recommendation

The split-tree roadmap should now be read as:

1. keep the current mixed-tree partitioned rebuild path as the stable baseline
2. keep split storage abstraction and materialization support
3. stop investing in:
   - full index-tree rebuild split apply
   - per-row index-tree delta apply
4. invest next in:
   - per-index mutation batching
   - per-index partitioned rebuild

This is now the highest-value structural optimization frontier.
