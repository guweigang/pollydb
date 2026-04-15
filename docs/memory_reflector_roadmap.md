# Memory Reflector Roadmap

This document captures the current direction for turning `pollydb` from a strong
local archive/search substrate into a true local-first agent memory engine.

It combines:

- the earlier memory-system ideas around local embedding, semantic recall, and
  versioned replay
- the newer Reflector proposal for background distillation
- the current implementation shape already present in this repository

The goal is to keep one coherent roadmap instead of letting memory, vector
search, graph linking, and replay evolve as separate side projects.

For the concrete schema declaration model behind vectorization and reflection,
see [memory_schema_capabilities.md](/Users/guweigang/Source/pollytree/docs/memory_schema_capabilities.md).

## Core Thesis

The memory system should not stop at:

- storing raw sessions
- lexical search
- nearest-neighbor retrieval

It should grow into a layered memory model:

1. raw memory
2. indexed memory
3. distilled memory
4. linked memory
5. replayable memory

In practical terms:

- raw conversation records stay durable and auditable
- embeddings make them semantically retrievable
- Reflector synthesizes higher-order memory from them
- semantic links turn related fragments into a graph
- replay surfaces let the agent and the user walk back to the exact originating
  evidence and repository version

## Principles

- Keep the raw source of truth.
- Treat summaries and reflections as derived layers.
- Keep all memory local-first by default.
- Make every higher-order memory object traceable back to exact source records.
- Preserve deterministic replay through stable ids, anchors, and root hashes.

## Current Position

The repository already has several important pieces in place.

### Storage and Structure

- content-addressed versioned storage
- branch / commit / merge / root-hash semantics
- native markdown ingestion and AST-aware persistence
- stable block ids, occurrence ids, anchors, and path hints
- `markdown` field support in typed tables

### Lexical Search

- SQLite FTS5 sidecar
- markdown-aware text extraction
- general FTS query path already used by `agentview`

### Semantic Retrieval

- markdown embedding target generation:
  - `block` targets for paragraph/code detail
  - `path` targets for heading-level semantic summaries
- optional `llama.cpp` embedding backend under `-d llama_cpp`
- PollyDB native vector records with:
  - target persistence
  - vector persistence
  - cosine top-k query
- end-to-end local smoke path:
  - markdown -> embedding -> PollyDB vector records -> semantic query

This means the project already moved beyond "could we do local memory?" into
"what higher-order memory structures should we build next?"

## Memory Layers

### Layer 1: Raw Memory

This is the immutable evidence layer.

Examples:

- imported AI session entries
- raw markdown documents
- tool output snapshots
- source-record references

This layer should remain the stable factual base for all later derivations.

### Layer 2: Indexed Memory

This layer makes raw memory queryable.

Current mechanisms:

- markdown selectors
- SQLite FTS5
- local embedding targets
- PollyDB vector records plus rebuildable ANN indexes

This is retrieval infrastructure, not interpretation.

### Layer 3: Distilled Memory

This is where memory becomes more useful than the sum of its raw records.

Distilled memory should include:

- summaries
- lessons learned
- decisions
- preferences
- unresolved questions
- recurring themes

This is the main responsibility of the future Reflector module.

### Layer 4: Linked Memory

This is the semantic graph layer.

At this layer, memory objects are not just rows or documents. They become nodes
connected by typed edges such as:

- `summarizes`
- `derived_from`
- `supports`
- `contradicts`
- `extends`
- `revises`
- `related_to`
- `same_topic_as`
- `detail_of`

### Layer 5: Replayable Memory

This layer supports "take me back there".

It should be possible to move from:

- a reflection
- a semantic hit
- a topic summary

back to:

- the exact markdown block or heading path
- the exact raw session records
- the exact `pollydb` version or root hash at the time that reflection was made

This is what turns search into real retrospective reasoning.

## Distillation: Memory "Compression" and "Elevation"

One of the key ideas is that memory should not remain trapped at the level of
raw turns.

There should be at least two directions of distillation:

### 1. Compression

Reduce many concrete records into a concise summary.

Examples:

- "what were we discussing last week about query planning?"
- "what conclusions did we reach about local embeddings?"

### 2. Elevation

Promote recurring patterns into higher-order memory.

Examples:

- "the user prefers local-first architecture"
- "semantic retrieval should remain derived, not source-of-truth"
- "summary nodes must not overwrite factual records"

This is not just summarization. It is the formation of durable working memory.

## Reflector Module

The next major capability should be a `Reflector` owned by a higher-level
`MemoryManager`.

### What Reflector Does

Reflector should:

- gather candidate records for reflection
- cluster related memory fragments
- generate distilled markdown outputs
- persist derived memory objects
- write typed semantic links back to source records

### Triggering

Reflector should run on derived-policy triggers rather than on every write.

Recommended triggers:

- idle-time trigger
- write-volume threshold trigger
- topic-drift trigger
- explicit "reflect now" command

The key idea is to keep raw ingest fast, and move reflective synthesis to a
background phase.

### Candidate Selection

Reflector should not look only at "most recent rows".

It should combine:

- temporal proximity
- semantic proximity from vector search
- structural proximity from markdown parent/anchor/path

This avoids producing shallow summaries that are only chronological.

### Reflector Outputs

At minimum Reflector should produce:

- `summary_md`
- `insight_md`
- `link_set`

Suggested reflection kinds:

- `summary`
- `synthesis`
- `lesson`
- `decision`
- `plan`

### Storage Model

Reflections should be persisted as derived objects, not as edits to raw memory.

Recommended fields:

- `reflection_id`
- `reflection_kind`
- `title`
- `summary_md`
- `insight_md`
- `source_refs`
- `parent_ref`
- `topic_key`
- `derived_from_root_hash`
- `created_at`
- `supersedes_reflection_id?`

Important rule:

- raw memory is factual
- reflection memory is interpretive

Those layers must never be conflated.

## Semantic Linking

The graph layer should be built from two edge families.

### 1. Structural Edges

Derived deterministically from existing data:

- markdown parent-child relationships
- heading path membership
- session ordering
- reflection -> source references

These edges are stable and inexpensive.

### 2. Semantic Edges

Derived from embeddings and reflection:

- nearest-neighbor similarity
- topic membership
- summary/detail relation
- contradiction/revision relation

These edges are more fluid and may be recomputed over time.

### Why Both Matter

Structural edges answer:

- "where did this come from?"
- "what contains this?"

Semantic edges answer:

- "what is this like?"
- "what else belongs to this idea?"

The useful memory graph needs both.

## Visual Replay and Query

The long-term experience should not be a flat list of search hits.

It should support:

- asking a semantic question
- landing on a topic-level reflection or heading-path memory
- expanding into supporting blocks
- walking back to the original raw session or markdown source
- jumping to the exact anchor and version

That suggests a replay/query experience with at least three views:

### 1. Topic View

Shows:

- distilled summaries
- related reflections
- major semantic neighbors

### 2. Evidence View

Shows:

- the concrete supporting blocks
- timestamps / sessions / source refs
- why each item was linked or retrieved

### 3. Timeline / Branch View

Shows:

- when a topic emerged
- how it changed
- which reflections superseded older ones
- which source root hash each interpretation depended on

## Proposed Data Model

The exact schema can evolve, but the conceptual model should be:

### Raw Tables

- `memory_sessions`
- `memory_entries`
- `memory_sources`

### Derived Tables

- `memory_embedding_targets`
- `memory_reflections`
- `memory_topics`
- `memory_links`

### Sidecars / Indexes

- SQLite FTS5 sidecar for lexical search
- USearch or another ANN backend as a rebuildable vector index

## Recommended Near-Term Architecture

For now, the architecture should look like this:

- `MemoryManager`
  - ingests raw memory
  - stores markdown
  - builds embedding targets
  - writes PollyDB vector records
  - schedules reflection jobs

- `Reflector`
  - selects candidate memory clusters
  - generates distilled markdown
  - writes reflection nodes
  - writes semantic links

- `ReplayQuery`
  - performs lexical + vector retrieval
  - expands reflection/evidence neighborhoods
  - returns replayable result sets with anchors and version references

## Roadmap

### M1: Retrieval Foundation

Status:

- mostly in place

Goals:

- stabilize markdown embedding targets
- stabilize llama.cpp local embedding path
- keep vector index derived and rebuildable

Exit criteria:

- markdown can be indexed into vectors locally
- semantic nearest-neighbor results are useful on real memory workloads

### M2: Reflection Storage

Goals:

- define reflection schema
- persist derived markdown reflections
- keep source refs and root-hash provenance

Exit criteria:

- one reflection can point to many evidence records
- every reflection can replay back to source anchors

### M3: Semantic Link Graph

Goals:

- define typed link schema
- write structural edges
- write semantic edges from top-k neighbor selection

Exit criteria:

- memory neighborhoods can be expanded without re-running whole-search from scratch

### M4: Replay Query API

Goals:

- query by text
- return topic hits + evidence hits
- support anchor-aware replay and source traversal

Exit criteria:

- a semantic question can return both summary-level and evidence-level answers

### M5: Reflector Automation

Goals:

- idle-time reflection
- threshold-based reflection
- local summarization flow
- supersession/versioning for reflections

Exit criteria:

- new memory gradually condenses into higher-order memory without manual curation

### M6: ANN Backend Upgrade

Goals:

- replace the simple PollyDB vector-record scan path with a stronger ANN backend such
  as USearch
- keep `pollydb` ownership of ids, metadata, and rebuild policy

Exit criteria:

- query latency stays low as memory volume grows

### M7: Visual Retrospective Experience

Goals:

- topic browser
- evidence expansion
- timeline/version replay
- reflection supersession browsing

Exit criteria:

- the system supports practical "what did we decide, why, and when?" review

## Immediate Next Bet

The single most useful next implementation step is:

- define and persist reflection nodes plus their source references

Why this is the best next move:

- retrieval is already working
- raw-vs-derived layering is now clear
- reflection nodes create the bridge from search to memory graph
- replay becomes far more useful once a summary node can lead back to evidence

In other words:

- vector search finds relevant fragments
- reflection turns fragments into memory
- links and replay turn memory into an explorable reasoning surface

That is the transition from archive to memory engine.
