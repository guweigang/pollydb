# FTS Index Design

This document replaces the earlier "lightweight FTS inside PollyDB" direction.

The new direction is:

- PollyDB should expose a general-purpose FTS index capability at the schema and
  query layers
- the first backend should be SQLite FTS5
- Markdown selectors and structural projections should remain first-class, but
  they should not continue to act as the primary full-text path for large text
  retrieval

In short:

`PollyDB owns the FTS abstraction; SQLite FTS5 owns the first implementation.`

## Goals

The goal is to make full-text search:

- correct for large `string` and `markdown` fields
- stable across rebuilds
- incremental to maintain
- available through the normal PollyDB schema/index lifecycle
- reusable by all applications, not only `agentview`

That means a user should be able to declare an FTS index on a large text field
the same way they declare ordinary indexes or field-selector indexes today.

## Why This Direction

The previous "lightweight FTS" path assumed PollyDB would own:

- tokenization
- inverted index layout
- prefix handling
- ranking
- rebuild logic
- query semantics for lexical search

That is a large product surface by itself, and it is not the highest-value area
for PollyDB right now.

PollyDB's stronger differentiators are elsewhere:

- typed schemas
- versioned storage
- structured field support such as `markdown`
- selectors and derived projections
- future query planning across structured and lexical access paths

SQLite FTS5 already provides a mature and well-understood implementation for the
generic "I saw this text, now I want to search it" problem. PollyDB should use
that rather than reproducing the search-engine core inside the storage engine.

## Core Idea

FTS should become a first-class index kind in PollyDB.

Conceptually, users should be able to declare:

- `fts` on a large `string` column
- `fts` on a `markdown` column
- optional indexing options such as tokenizer, prefix support, and source text

Examples of the intended direction:

```v
SchemaIndexDef.fts('body_fts_idx', 'body')!
SchemaIndexDef.fts_text('content_text_fts_idx', 'content_text')!
SchemaIndexDef.fts_markdown('content_md_fts_idx', 'content_md', .visible_text)!
SchemaIndexDef.fts_with_options('notes_fts_idx', 'notes', FtsIndexOptions{
	tokenizer: 'unicode61'
	prefix_lengths: [2, 3, 4]
})!
```

These constructor names are illustrative. The important decision is the model:

- FTS is declared at schema level
- FTS indexes are derived and rebuildable
- FTS query APIs stay in PollyDB
- backend details remain hidden behind the FTS capability

## Non-Goals

This design does not attempt to make SQLite FTS5 the new source of truth.

FTS indexes should remain:

- derived from PollyDB row data
- disposable and rebuildable
- replaceable by a future backend if needed

This design also does not attempt to solve every future search need in phase 1.

Phase 1 does not need:

- custom search-engine internals inside PollyDB
- deep historical/time-travel lexical search
- cross-version BM25 semantics
- custom snippet rendering beyond what the backend already provides
- selector-aware semantic ranking

Those may become future reasons to add a new backend or a richer search layer,
but they are not prerequisites for making large text search correct now.

## Separation Of Responsibilities

### PollyDB owns

- FTS schema/index declarations
- validation of which columns can produce FTS material
- lifecycle rules for create, rebuild, update, and delete
- metadata and planner exposure
- query API shape
- mapping FTS hits back to typed rows
- coexistence with selectors, projections, and normal indexes

### SQLite FTS5 owns

- tokenizer execution
- postings storage and segment maintenance
- phrase and prefix semantics
- ranking primitives such as `bm25`
- snippets and highlights
- query parsing for lexical search

This split is intentional. It lets PollyDB present a coherent database model
without taking on the full implementation burden of a search engine.

## Supported Column Types

Phase 1 should focus on two source column classes.

### 1. Large `string` / text fields

These should index the raw text content directly.

Examples:

- chat message text
- session transcript text
- document body text
- tool output stored as plain text

### 2. `markdown` fields

These should index derived visible text, not the selector/index expansion that
currently powers the lightweight lexical path.

The key shift is:

- selectors continue to answer structural questions
- FTS indexes answer lexical retrieval questions

For a Markdown field, the FTS source material should usually be one of:

- `visible_text`
  - default; concatenate user-visible Markdown text
- `visible_text_with_code`
  - visible text plus fenced/inline code
- `raw_markdown`
  - raw source text, only when explicitly requested

The default should be `visible_text`, because it best matches the expectation:

`if I can see the words in the rendered document, I should be able to search them`

## Relationship To Field Selectors

FTS and field selectors should be complementary, not merged.

Field selectors remain the right model for:

- `heading_text:2`
- `link_host`
- `code_block_lang`
- numeric Markdown metrics such as `links`

FTS becomes the right model for:

- free-text retrieval over large text
- prefix and phrase search
- ranked multi-term search
- snippet and highlight generation

That means PollyDB should stop encouraging the current pattern where Markdown
selector expansion doubles as the primary lexical search mechanism.

## Schema Model

The current `SchemaIndexDef` model is centered on:

- ordinary scalar indexes
- JSON path indexes
- field-selector indexes

It should grow a distinct FTS branch rather than overloading field selectors
further.

Conceptually, the schema metadata should capture:

- index kind: `fts`
- source column
- source field plugin if needed
- source text mode
- tokenizer configuration
- prefix configuration
- whether the index is contentless/external or stores searchable text

A possible shape:

```v
pub enum SchemaIndexKind {
	ordinary
	json_path
	field_selector
	fts
}

pub enum FtsSourceKind {
	column_text
	field_text
}

pub enum MarkdownFtsTextMode {
	visible_text
	visible_text_with_code
	raw_markdown
}

pub struct FtsIndexOptions {
pub:
	tokenizer      string = 'unicode61'
	prefix_lengths []int
}

pub struct FtsSourceRef {
pub:
	kind        FtsSourceKind
	plugin_name string
	selector    string
	text_mode   string
}
```

The exact struct names are flexible, but the model should support:

- direct text columns
- plugin-derived text sources such as Markdown visible text
- backend-agnostic options

## Field Capability Extension

The current field capability registry already separates:

- field-selector index expansion
- derived projections
- external storage
- merge behavior

FTS should add another capability boundary for fields that can emit searchable
text material.

Conceptually:

```v
pub interface FieldTextSourceStrategy {
	plugin_name() string
	supports(column ColumnDef) bool
	validate_fts_text_mode(mode string) !
	extract_fts_text(database &PersistentDatabase, column ColumnDef, stored ColumnValue, mode string) !string
}
```

For `markdown`, this would provide the text that feeds SQLite FTS5.

This is important because it keeps:

- selector expansion
- projection computation
- external field loading
- FTS text extraction

as separate concerns.

That separation prevents the schema from continuing to blur "structural field
capability" and "lexical full-text material".

## Storage Model

Each typed table with FTS indexes should have a rebuildable search sidecar owned
by PollyDB.

Phase 1 can use one SQLite database file per PollyDB repository or per branch,
with one FTS5 virtual table per PollyDB FTS index.

Conceptually:

- PollyDB table: source of truth
- SQLite FTS table: derived lexical index

For a PollyDB table `notes` with an FTS index `body_fts_idx`, the backing SQLite
table might look conceptually like:

```sql
CREATE VIRTUAL TABLE body_fts_idx USING fts5(
  row_pk UNINDEXED,
  table_name UNINDEXED,
  column_name UNINDEXED,
  text,
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '2 3 4'
);
```

For richer ranking and filtering, the sidecar row may also carry unindexed
columns such as:

- branch name
- session id
- kind
- role
- timestamp

But the key invariant should remain:

- the sidecar is not authoritative
- the primary lookup target is still the PollyDB row primary key

## Lifecycle

FTS indexes should participate in the same high-level lifecycle as other
derived indexes.

### Create / Register

When a table spec with an FTS index is registered:

- PollyDB records the schema metadata
- PollyDB creates or migrates the corresponding SQLite sidecar structures
- PollyDB marks the FTS index as requiring build or rebuild when needed

### Rebuild

A rebuild should:

1. scan source rows from PollyDB
2. extract text material for each indexed row
3. repopulate the SQLite FTS table
4. update FTS state/version metadata in PollyDB

### Incremental update

On row put/update/delete:

- PollyDB determines whether an indexed FTS source changed
- if changed, it updates the corresponding sidecar row
- if deleted, it removes the sidecar row

### Failure handling

If sidecar maintenance fails:

- the source row write should not silently corrupt search state
- PollyDB should record that the FTS index is stale or needs rebuild
- query planning should be able to report degraded/stale status

## Metadata Tables

PollyDB already uses metadata/state tables in higher layers such as `agentview`.

The general FTS feature should standardize that concept instead of leaving it to
applications.

Useful metadata to track:

- FTS index version
- backend type and backend schema version
- last full rebuild timestamp
- stale / needs rebuild flag
- per-row search fingerprint for incremental maintenance

Conceptually this should live under PollyDB-owned metadata rather than
application-specific tables.

## Query Model

The current `FtsQuery` API is tied to:

- Markdown columns only
- the old scoped-token selector model

That API should be generalized so the caller asks for:

- table
- FTS index or source column
- lexical query
- optional filters
- optional projection columns

Conceptually:

```v
pub enum FtsQueryBackendKind {
	default_
}

pub struct FtsQuery {
pub:
	table_name     string
	index_name     string
	query_text     string
	limit          int
	select_columns []string
}
```

A richer phase 2 shape could also include:

- phrase search mode
- explicit prefix mode
- ranking mode
- snippet settings
- structured post-filters

The important shift is this:

- callers should not need to know whether the backend is SQLite FTS5
- callers should not need to express Markdown selector names such as `fts` or
  `fts:heading` to perform general full-text search

## Planner Integration

Planner metadata should expose FTS as a distinct capability.

That metadata should answer questions like:

- which columns or indexes support full-text search
- which backend is active
- whether phrase search is available
- whether prefix search is available
- whether snippets/highlights are available
- whether the index is healthy, stale, or rebuilding

This should show up beside current selector/filter introspection rather than
pretending FTS is just another selector.

Conceptually, future schema/planner output might include:

- `fts_indexes[*]`
- supported query forms
- ranking support
- snippet support
- sample explain plans such as `sqlite_fts5_match`

## Query Execution

Phase 1 execution should be:

1. validate the requested FTS index against table schema
2. compile a backend query for SQLite FTS5
3. fetch ranked matching row primary keys from the sidecar
4. load typed rows from PollyDB
5. apply any remaining structured filters in PollyDB
6. return rows plus FTS hit metadata

Returned FTS metadata should be richer than the current score-only shape.

Useful hit payload:

- source row primary key
- backend score or rank
- matched terms if available
- snippet
- highlight ranges if available later

## Ranking

Phase 1 should use backend-provided lexical ranking.

For SQLite FTS5, that usually means:

- `bm25()`
- optionally mixed with lightweight application-level reranking

PollyDB should not try to define a universal ranking function in phase 1.

Instead:

- expose backend rank
- allow callers to do secondary reranking if needed
- keep the base FTS ordering stable and understandable

## Prefix, Phrase, And Snippets

A major reason for switching directions is to inherit mature search behavior.

Phase 1 should intentionally expose the things FTS5 already does well:

- term search
- phrase search
- prefix search
- ranking
- snippet/highlight support

These should be modeled as supported query features on the PollyDB FTS index,
not as ad hoc app-level behavior.

## Rebuild Policy

Rebuild should be explicit and predictable.

Recommended rules:

- ordinary row writes try incremental sidecar maintenance
- schema changes that affect FTS source material force rebuild
- backend option changes such as tokenizer or prefix lengths force rebuild
- a failed or interrupted maintenance cycle marks the index stale

Applications should be able to request:

- ensure indexes
- rebuild one index
- rebuild all FTS indexes for a table

without needing to know backend internals.

## AgentView As First Consumer, Not Special Case

`agentview` is still an excellent proving ground, but it should become only the
first consumer of the general feature.

That means:

- `agentview` should stop owning a unique FTS projection model
- `agentview` should declare/search normal PollyDB FTS indexes
- future apps with large `string` or `markdown` columns should reuse the same
  capability immediately

This is a key architecture boundary:

- application code chooses which fields deserve FTS
- PollyDB owns how those indexes are created and queried

## Migration From The Current Model

The current model has two FTS-specific assumptions that should be retired over
time:

1. Markdown lexical search is expressed as a selector-backed derived index
2. `FtsQuery` only accepts Markdown columns and Markdown scopes

Recommended migration:

### Phase 1

- keep current selector-backed lexical path working
- add a new schema-level FTS index kind
- add SQLite FTS5 backend support
- route new applications and large text fields to the new path

### Phase 2

- move `agentview` to the general FTS index kind
- keep Markdown selectors for structural predicates only
- reduce emphasis on `markdown_value(..., 'fts')`

### Phase 3

- deprecate selector-backed lexical FTS for primary retrieval
- keep selectors strictly for structural/semantic indexing

## Future Escalation Points

This design does not claim SQLite FTS5 will solve every future search problem.

A future backend becomes reasonable if PollyDB needs one or more of:

- search tightly bound to version history and time travel
- custom ranking deeply fused with tree/query semantics
- retrieval over chunk/layout structures rather than row text
- analyzer pipelines beyond SQLite FTS5's practical range

At that point, the advantage of this design is that PollyDB already owns the FTS
abstraction, so the backend can evolve without rewriting application schema.

## Recommended Next Steps

1. Extend `SchemaIndexDef` with a true FTS index kind
2. Add a field capability for extracting FTS text from complex field types
3. Generalize `FtsQuery` away from Markdown selector scopes
4. Add PollyDB-owned FTS metadata and rebuild lifecycle
5. Implement the first backend using SQLite FTS5
6. Migrate `agentview` to the general FTS capability as the first real consumer
