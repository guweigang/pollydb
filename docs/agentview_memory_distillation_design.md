# AgentView Memory Distillation Design

This note captures the current design direction for turning AgentView session
history into durable `pollydb` memory.

## Delivery Goals

The final delivery has two product surfaces.

### 1. Versioned Database

`pollydb` is the durable versioned database layer. It should be useful outside
AgentView and should provide:

- branch, commit, and root-hash based history
- typed tables with schema evolution
- replayable writes and auditable derived data
- FTS and vector indexes as database capabilities
- memory records stored as versioned derived records with source provenance

Acceptance criteria:

- raw source records are not overwritten by derived memory
- every memory can be traced back to source refs and a source root hash
- memory updates preserve older versions through supersedes/reinforces links
- database indexes can be rebuilt or migrated without rewriting application
  logic

### 2. Codex Session Application

`agentview` is the Codex session application built on `pollydb`. Its job is to
turn local Codex transcripts into a browseable, searchable, memory-aware product
surface.

Required capabilities:

- migrate Codex sessions into `pollydb`
- browse sessions in a TUI
- search sessions and entries through indexed paths
- view distilled memory
- provide memory context that can be passed to a large language model

Acceptance criteria:

- `agentview sync-codex` imports Codex sessions into the default store
- `agentview browse` can inspect sessions, transcripts, and search results
- `agentview memory list` shows active distilled memories
- `agentview memory search <query>` retrieves relevant memories
- `agentview context <query>` emits compact Markdown context for model prompts

The application should keep raw transcript browsing and model-facing memory
context as separate surfaces. Browsing is for humans; context output is for
agents.

The main lesson from the first real-session experiments is simple:

- do not embed every raw entry first
- do not rely on fixed entry limits as a quality mechanism
- do extract candidate memories before semantic clustering
- do treat memory as versioned derived data with source evidence

`pollydb` has a natural advantage here. It already combines full-text search,
vector search, typed schema capabilities, and versioned storage. That means a
new candidate memory does not have to be blindly appended. It can be checked
against existing memory through lexical and semantic signals, then committed as
an add, update, reinforcement, replacement, or contradiction with provenance.

## Research Notes

Several mature agent-memory systems converge on the same broad pattern:
extract salient memory first, then update and retrieve compact memory objects.

### Generative Agents

Generative Agents uses a memory stream of observations and retrieves from it
with a mixture of:

- recency
- importance
- relevance

Reflection is not run on every observation. It is triggered when accumulated
importance crosses a threshold. The generated reflections are higher-level
memories backed by cited source records.

Design implication for `pollydb`:

- raw session entries should stay as evidence
- salience should be scored before reflection
- reflections should cite exact source entries
- higher-level reflections may themselves become memory inputs later

Reference:

- https://research.google/pubs/generative-agents-interactive-simulacra-of-human-behavior/

### Mem0

Mem0 describes memory as an extraction and update pipeline. The system extracts
candidate memories from recent interaction context, then updates the memory
store instead of only appending new records. Its newer retrieval design also
combines semantic, keyword, and entity signals.

Design implication for `pollydb`:

- candidate extraction should happen before embedding-heavy work
- agent-generated facts and decisions should be first-class memory candidates
- retrieval and duplicate/update checks should be multi-signal, not vector-only

Reference:

- https://mem0.ai/research

### Zep / Graphiti

Zep's Graphiti engine represents memory as a temporal knowledge graph. It
ingests data as episodes, extracts entities and facts, preserves provenance, and
uses hybrid search over semantic, keyword, graph, and temporal signals. It also
models changing relationships over time.

Design implication for `pollydb`:

- AgentView sessions map naturally to episodes
- memory objects need timestamps and source refs
- updates should preserve history instead of overwriting meaning in place
- temporal validity and contradiction handling should become explicit over time

Reference:

- https://help.getzep.com/graphiti/getting-started/overview

### MemGPT

MemGPT frames memory as a hierarchy inspired by operating systems: limited fast
context backed by larger archival memory. It explicitly manages movement between
short-term and long-term memory.

Design implication for `pollydb`:

- raw transcripts, distilled memories, and retrieved context are separate tiers
- AgentView browsing and agent context assembly should not use the same surface
- distilled memory should be compact enough to load into working context

Reference:

- https://huggingface.co/papers/2310.08560

### Reflexion

Reflexion stores verbal reflections from task feedback. For coding agents, this
points toward preserving lessons such as root causes, failed assumptions,
constraints, and repair strategies.

Design implication for `pollydb`:

- "what failed and why" is often more durable than raw tool output
- root-cause memories deserve high priority
- reflections should avoid transient progress logs unless they explain an
  enduring lesson

Reference:

- https://huggingface.co/papers/2303.11366

### MemoryBank

MemoryBank introduces long-term memory with importance, time decay, and memory
update/reinforcement behavior.

Design implication for `pollydb`:

- memory should support reinforcement and decay-like ranking
- repeatedly confirmed memories should become stronger
- stale or contradicted memory should stay replayable but lose retrieval rank

Reference:

- https://huggingface.co/papers/2305.10250

## Open-Source Quality Patterns

The open-source memory ecosystem is moving away from "summarize everything and
append it" pipelines. The stronger systems use staged extraction, consolidation,
hybrid retrieval, and provenance.

### Mem0 v3-style extraction and retrieval

Mem0's newer open-source algorithm moved to a simpler extraction path:

```text
input conversation
  -> retrieve related existing memories for context
  -> one LLM call extracts distinct new facts
  -> exact hash dedup
  -> batch embedding
  -> entity extraction/linking
```

The important quality lesson is not "ADD-only forever"; `pollydb` has better
versioning primitives than a plain vector store, so we should still support
`revise`, `replace`, `reinforce`, and `contradict`. The reusable idea is that
the model should spend most of its capacity extracting clean, distinct memory
claims, while deterministic storage logic handles deduplication, linking, and
versioned update decisions.

Reusable ideas for AgentView:

- retrieve related memory before distillation so the model can avoid repeats
- extract distinct memory claims before writing any card
- hash normalized titles and summaries to block exact duplicates cheaply
- extract entities from each memory and use them as ranking/linking features
- use hybrid retrieval for both user queries and add/update checks

References:

- https://docs.mem0.ai/migration/oss-v2-to-v3
- https://github.com/mem0ai/mem0

### Graphiti-style temporal graph memory

Graphiti stores raw inputs as episodes, extracts entities and facts, and keeps
temporal validity for relationships. Its practical contribution is that
changing information is not treated as a destructive overwrite.

Reusable ideas for AgentView:

- treat Codex sessions as episodes
- keep every derived memory linked to source entries
- extract lightweight entities: file paths, commands, modules, libraries,
  project names, user preferences, constraints, and decisions
- model contradictions as temporal/versioned facts instead of silently deleting
  old memory
- use graph-like links even if the first implementation is table-backed rather
  than a full graph database

References:

- https://github.com/getzep/graphiti
- https://help.getzep.com/graphiti/getting-started/overview

### LangMem / LangGraph-style memory taxonomy

LangMem and LangGraph distinguish memory by both scope and type. The useful
types for AgentView are:

- semantic memory: durable facts, project rules, constraints, preferences
- episodic memory: examples of how a task was solved or failed
- procedural memory: reusable operating instructions and workflows

This taxonomy gives us a generic way to avoid domain-specific rules. Instead of
hardcoding "execution_context" or one project's vocabulary, the extractor should
ask whether a candidate is a fact, episode, procedure, decision, preference, or
constraint. If it fits none of these, it should usually be discarded.

Reusable ideas for AgentView:

- store memory type explicitly
- allow background consolidation instead of forcing memory writes in the hot
  path
- merge related memories periodically to avoid memory hoarding
- use type-aware retrieval: procedures and constraints should rank differently
  from episodic examples

References:

- https://github.com/langchain-ai/langmem
- https://docs.langchain.com/oss/python/langgraph/memory

### Letta / MemGPT-style memory tiers

Letta separates always-visible core memory, searchable recall memory, and
archival memory. This matters for quality because not every good memory should
be injected into every prompt.

Reusable ideas for AgentView:

- keep raw transcripts as recall memory, not prompt-ready memory
- keep distilled cards as archival memory
- later build a small "core memory" surface for stable user/project preferences
- let context assembly decide which tier is appropriate for a model call

References:

- https://docs.letta.com/guides/agents/architectures/memgpt
- https://docs.letta.com/guides/agents/memory
- https://docs.letta.com/guides/agents/context-hierarchy/
- https://docs.letta.com/guides/agents/archival-memory/

### Quality gates that should become first-class

From these systems, AgentView should promote quality checks from scattered
heuristics into explicit stages:

- `claim_extraction`: convert segment evidence into atomic memory claims
- `claim_typing`: classify each claim as semantic, episodic, procedural, or
  discard
- `evidence_check`: require source refs for every claim
- `novelty_check`: compare against existing memory with normalized hash, FTS,
  vectors, and entities
- `conflict_check`: detect whether new evidence revises or contradicts existing
  memory
- `card_synthesis`: produce a compact card only after claims pass the above
  gates
- `critic_check`: reject cards with vague titles, unsupported sections,
  conversation filler, progress chatter, or test-run bookkeeping

This gives us a general quality architecture: deterministic gates protect the
database, while the model is used for language understanding and synthesis.

## Proposed Pipeline

AgentView memory distillation should be a staged pipeline.

```text
raw session entries
  -> salience extraction
  -> streaming topic segmentation
  -> memory distillation
  -> add/update/merge decision
  -> versioned persistence
  -> retrieval indexes
```

The important ordering is that salience extraction comes before full embedding
and reflection work.

## Stage 1: Salience Extraction

This stage reads entries in chronological order and emits candidate memory
events. It should be cheap enough to run during or shortly after sync.

Candidate memory types:

- `decision`: a durable choice, agreement, direction, or architecture decision
- `constraint`: a boundary, requirement, policy, environment limit, or user
  preference that should guide future work
- `root_cause`: a diagnosis explaining why something failed or behaved oddly
- `procedure`: a repeatable workflow, command sequence, or operating pattern
- `artifact`: a durable output such as a feature, file, schema, API, or test
- `preference`: a stable user preference about communication, design, tools, or
  implementation style
- `unresolved_issue`: an open question, blocker, regression, or risk
- `fact`: a stable factual statement about the project, environment, or user

The extractor should also emit non-memory classifications for observability:

- `transient_status`
- `tool_noise`
- `raw_log`
- `shell_prompt`
- `large_output`
- `duplicate_status`
- `low_information`

This is not domain-specific customization. These are generic memory act types.
Different domains should map their own content into the same generic slots.

## Stage 2: Streaming Topic Segmentation

Segmentation should be chronological and incremental.

The algorithm should not start by globally clustering the full session. Instead:

1. Read candidate memory events in order.
2. Start a segment with the first salient event.
3. Add the next event if it belongs to the same topic.
4. When topic drift is detected, close the current segment.
5. Distill the closed segment.
6. Continue with the next segment.

Topic affinity can use cheap signals first:

- shared entities or symbols
- shared files, commands, APIs, or identifiers
- lexical overlap through FTS terms
- entry adjacency and speaker turn structure
- candidate memory type compatibility

Embedding can be used after the cheap gate, not as the first pass over every
raw entry.

## Stage 3: Distillation

Each segment should produce a structured memory document:

```markdown
# Title

Short summary.

## Key Decisions

- ...

## Important Constraints

- ...

## Evidence

- source entry refs
```

Optional sections should only appear when supported by evidence. The distiller
must not fill empty decisions or constraints just to satisfy a template.

Quality requirements:

- title describes the actual topic, not conversational filler
- summary is compact and specific
- decisions are durable choices, not transient progress
- constraints are real boundaries, not generic statements
- every claim is traceable to source entries
- uncertainty should remain visible when evidence is weak

## Stage 4: Memory Add vs Update

This is where `pollydb` has a strong architectural advantage.

A new distilled memory should be compared with existing memory before it is
persisted. `pollydb` can use both FTS and vectors for this:

- FTS finds exact or near-exact lexical overlap: names, paths, commands,
  identifiers, APIs, and project terms.
- Vector search finds semantic similarity even when wording changes.
- Source refs and timestamps show whether the new memory is newer evidence for
  an existing topic.
- Versioned storage records how memory changed instead of losing history.

The update decision should be one of:

- `add`: no sufficiently related memory exists
- `reinforce`: the new evidence confirms an existing memory
- `merge`: the new memory and an existing memory describe the same topic and
  should become one stronger memory
- `revise`: the new memory changes details but does not invalidate the old one
- `replace`: the new memory supersedes the old one
- `contradict`: the new memory conflicts with an existing memory and both need
  temporal/provenance tracking

This turns memory distillation from append-only summarization into versioned
knowledge maintenance.

## Stage 5: Versioned Persistence

Memory objects should be committed as derived records with explicit provenance.

Minimum metadata:

- memory id
- topic key
- memory type
- confidence
- source entry refs
- source root hash or commit id
- created timestamp
- valid-from timestamp when known
- supersedes or reinforces links when applicable

Because `pollydb` already has branch, commit, and replay-oriented storage, memory
evolution can be auditable:

- a reflection can be traced back to exact session entries
- a revised memory can point to the previous memory version
- contradictions can be represented instead of silently overwritten
- rebuilds can regenerate derived memory from raw source records

## Stage 6: Retrieval

Runtime memory retrieval should be hybrid:

- FTS for exact project terms, paths, commands, and identifiers
- vector search for semantic similarity
- recency for recent active work
- importance for durable decisions and constraints
- reinforcement count for repeatedly confirmed memory
- graph/source links for provenance and related memories

The retrieval target should be distilled memory first, with raw source entries
available for drill-down. Raw transcript retrieval remains useful, but it should
not be the only context surface for agents.

## Practical Algorithm Sketch

```text
for session in recent_sessions:
  for entry in chronological_entries(session):
    event = classify_salience(entry)
    record gate decision for observability

    if event is not memory-worthy:
      continue

    if current_segment is empty:
      start segment with event
      continue

    if same_topic(current_segment, event):
      append event to segment
      continue

    memory = distill(current_segment)
    persist_with_add_update_check(memory)
    start segment with event

  flush current_segment
```

The key property is that the system discovers topic boundaries while reading. It
does not need to globally cluster the entire session before producing useful
memory.

## Observability Requirements

Every distillation run should be inspectable.

At minimum, a quality probe should print:

- sessions scanned
- raw entries scanned
- entries skipped by reason
- candidate memories by type
- segments created
- memories added
- memories updated
- memories reinforced
- memories rejected
- elapsed time by stage

For each produced memory, it should print:

- title
- summary
- key decisions
- important constraints
- source refs
- add/update decision
- nearest existing memory candidates with FTS/vector scores

This avoids fake confidence. If no memory is produced, the reason should be
visible.

## Near-Term Implementation Plan

1. Add a pre-embedding salience gate for AgentView entries.
2. Print candidate/skip statistics in the memory quality probe.
3. Feed only memory-worthy candidates into streaming segmentation.
4. Add hybrid existing-memory lookup before persistence.
5. Represent add/update decisions in persisted memory metadata.
6. Use `pollydb` versioning to link revised or reinforced memories.

The first milestone should prove that a real AgentView session can be scanned
quickly and that the retained candidates match human expectations before any
expensive embedding or generation step runs.
