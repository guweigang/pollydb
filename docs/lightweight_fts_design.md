# Lightweight FTS Design

This document sketches a practical full-text-search subset for PollyDB.

The goal is not to build a full Lucene/Tantivy-class engine inside PollyDB.
The goal is to add a small, structurally compatible inverted-index layer that
works well with:

- typed tables
- Markdown-derived content
- field capability plugins
- current single-table query/planner APIs

## Why A Lightweight FTS Layer

PollyDB already supports:

- Markdown metric selectors
- Markdown value selectors
- planner-aware derived indexes

Those solve many structural and semantic lookup problems.
What they do not solve is generic keyword retrieval such as:

- find all memory entries that mention `pollydb`
- find entries that mention both `merge` and `markdown`
- find headings or paragraphs that start with `agent`

A lightweight FTS layer should complement, not replace, the selector/index
system.

## Non-Goals

This design does not aim to provide:

- BM25 or advanced scoring
- fuzzy matching
- typo tolerance
- regex queries
- wildcard queries beyond prefix
- complex nested boolean query trees
- multilingual linguistic analysis
- full phrase/proximity search in phase 1
- snippet highlighting

If those become mandatory, PollyDB should strongly consider an external search
engine bridge such as Tantivy rather than continuing to grow a custom engine.

## Phase 1 Query Forms

The recommended phase 1 query forms are:

- `term`
  - contains one normalized token
- `prefix`
  - contains a token with a given prefix
- `all`
  - contains all listed tokens
- `any`
  - contains any listed tokens
- `scoped_term`
  - contains a token inside a named Markdown scope
- `scoped_prefix`
  - contains a token prefix inside a named Markdown scope

Recommended Markdown scopes:

- `heading`
- `paragraph`
- `code_block`
- `list_item`

Possible future phase 2 query forms:

- `phrase_lite`
- `term_not`
- simple grouped boolean combinations

## Storage Model

Phase 1 should use a derived inverted index model rather than raw row scans.

Suggested logical structure:

- `fts_term`
  - normalized token
- `fts_scope`
  - optional scope such as `heading` or `paragraph`
- `doc_id`
  - row primary key
- `field_ref`
  - table + column + plugin scope

At the implementation level this can still be expressed using capability-backed
derived indexes, with one index entry per emitted token occurrence.

Conceptually:

```text
fts:<table>:<column>:<scope>:<term> -> [primary_key...]
```

This does not force a specific physical encoding yet.
It just fixes the lookup shape.

## Tokenization

Phase 1 tokenization should be intentionally simple and deterministic.

Recommended first pass:

- lowercase ASCII normalization
- split on whitespace and punctuation
- drop empty tokens
- optional minimum token length, for example `>= 2`

This is sufficient for:

- English-like identifiers
- URLs/hosts after secondary normalization
- code-ish tokens
- many operational memory search cases

It is not sufficient for:

- robust CJK segmentation
- stemming/lemmatization
- language-aware normalization

Those should remain future upgrades, not hidden assumptions.

## Relationship To Markdown

Markdown is the strongest first consumer for lightweight FTS.

The indexer should be able to emit tokens from:

- headings
- paragraphs
- list items
- code blocks

This keeps FTS aligned with the existing Markdown AST and selector model.

Example:

- `heading_text:2` remains a selector/value index
- `fts_scope=heading term=roadmap` becomes a text lookup

That separation is useful:

- selectors answer structural questions
- FTS answers lexical questions

## Suggested API Shape

Phase 1 does not need SQL syntax.

A storage-facing API could look like:

```v
pub enum FtsQueryKind {
	term
	prefix
	all
	any
}

pub struct FtsQuery {
pub:
	table_name string
	column_name string
	scope      string
	kind       FtsQueryKind
	terms      []string
	limit      int
}
```

This can later be adapted into:

- derived index lookups
- query planner metadata
- future `vsql` syntax

## Planner Integration

Lightweight FTS should integrate with the same planner/introspection model that
already exists for selectors.

That means future FTS capabilities should show up in:

- `TableQuerySchema`
- `QueryFieldSelectorCapability` or a sibling capability type
- `filter_shapes`
- `sample_explain`

For example:

- `fts.heading term roadmap`
  - `indexed=true`
  - strategy could be `index_exact`
- `fts.paragraph prefix agen`
  - `indexed=true`
  - strategy could be `index_prefix`

## Recommended Implementation Order

1. tokenizer utility
2. Markdown scoped token emitter
3. derived inverted index entries
4. exact term lookup
5. prefix term lookup
6. planner metadata exposure
7. optional `all` / `any` set-combination query helpers

## Why Not Start With Tantivy

Tantivy is attractive if you need:

- scoring
- phrase queries
- advanced boolean search
- mature analyzer chains

But it also brings:

- Rust toolchain dependency
- C ABI bridge work
- cross-language build complexity

For PollyDB's current stage, a lightweight FTS subset is a better first step if
the immediate goal is:

- searchable Agent memory
- keyword retrieval over Markdown
- tight integration with existing typed/index/query abstractions

## Escalation Point

If PollyDB later needs any two of the following, it should strongly consider a
dedicated external search backend or bridge:

- BM25/relevance ranking
- robust phrase search
- fuzzy matching
- multilingual analyzers
- complex boolean query trees
- search-time snippets/highlighting

That is the point where “lightweight FTS” turns into “search engine”.
