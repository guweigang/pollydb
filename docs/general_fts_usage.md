# General FTS Usage

This document describes the current PollyDB full-text search model as it exists
today.

The short version is:

- declare a normal PollyDB FTS index in schema
- let PollyDB maintain a rebuildable SQLite FTS5 sidecar
- discover that capability through `query-schema`
- execute searches through the unified `QueryRequest.general_fts` path

This is now the preferred lexical search path for large `string` and
`markdown` fields.

## What PollyDB Owns

PollyDB owns:

- schema declaration for FTS indexes
- validation of which column can produce searchable text
- rebuild and incremental maintenance lifecycle
- planner and capability metadata
- unified query request/response shape
- mapping FTS hits back to typed rows

SQLite FTS5 owns:

- tokenizer execution
- lexical query semantics
- postings and segment maintenance
- `bm25` ranking

That means callers use a PollyDB feature, not a raw SQLite table.

## Declaring FTS Indexes

### Plain Text

For a normal large text column:

```v
SchemaIndexDef.fts_with_options('content_text_fts_idx', 'content_text', FtsIndexOptions{
	tokenizer:      'unicode61 remove_diacritics 2'
	prefix_lengths: [2, 3, 4]
})!
```

This is the right default for:

- chat messages
- tool output
- session text
- document bodies already stored as plain text

### Markdown

For a Markdown column, declare a true FTS index instead of relying on selector
expansion as the main lexical path:

```v
SchemaIndexDef.fts_markdown('body_fts_idx', 'body', .visible_text)!
SchemaIndexDef.fts_markdown_with_options('body_code_fts_idx', 'body', .visible_text_with_code, FtsIndexOptions{
	tokenizer:      'unicode61 remove_diacritics 2'
	prefix_lengths: [2, 3, 4]
})!
```

Use:

- `.visible_text` when search should match what users see in rendered Markdown
- `.visible_text_with_code` when code blocks and inline code should also be
  searchable
- `.raw_markdown` only when raw source search is explicitly desired

## Discovering FTS Capability

Use `query.table_schema(...)` or `GET /v1/query-schema`.

General FTS indexes show up as normal index capabilities with:

- `is_fts`
- `fts_query_kinds`
- `fts_shapes`

`fts_shapes[*]` tells callers:

- which query kinds are supported
- which index backs the search
- which planner strategy will be used
- a sample explain payload

That means UIs and future `vsql` should discover lexical search from schema
metadata, not by hard-coding application-specific search rules.

## Executing FTS Queries

The preferred query path is the unified request shape:

```v
query.Request{
	table_name: 'docs'
	general_fts: query.GeneralFtsClause{
		index_name: 'content_text_fts_idx'
		kind: .all
		terms: ['sqlite', 'fts5']
	}
	select_columns: ['id', 'title', 'content_text']
	limit: 20
}
```

Supported query kinds are:

- `term`
- `prefix`
- `all`
- `any`

Use:

- `preview_query_plan_details(...)` or `POST /v1/query-plan-preview` to inspect
  the request-specific plan
- `query_page(...)` or `POST /v1/query-rows` to execute the search

Search results can include:

- projected rows
- `general_fts_hits`
- backend score
- snippet text

## Field Selectors vs General FTS

These are complementary features.

Use field selectors for structural questions such as:

- `heading_text:2`
- `link_host`
- `code_block_lang`
- numeric metrics like `links` or `code_blocks`

Use general FTS for lexical retrieval such as:

- free-text lookup over large text
- prefix search
- multi-term ranked search
- snippet-oriented result pages

The rule of thumb is:

- selectors answer structural queries
- general FTS answers lexical retrieval queries

## Sidecar And Lifecycle

FTS indexes are not source-of-truth data.

They are:

- derived from typed rows
- rebuildable
- maintained incrementally on row writes
- stored in a PollyDB-owned SQLite FTS5 sidecar

That means an application should treat them like normal derived indexes:

- schema registration creates or updates the capability
- rebuild logic can reconstruct the index from typed row data
- query callers should never write directly to the sidecar

## Agentview As A Consumer

`agentview` is now the first real consumer of this model.

For the current product scope it uses:

- `entries_content_text_fts_idx`

It intentionally does not require `content_md` FTS for the primary search path.

That is a product choice, not a limitation of the capability. PollyDB itself
supports general FTS as a reusable storage/query feature.

## Current Guidance

For new integrations:

1. declare a real FTS index in schema
2. expose it through `query-schema`
3. search it through `QueryRequest.general_fts`
4. keep selectors for structural access patterns

For historical selector-backed lexical paths:

- keep them only where backward compatibility still matters
- do not treat them as the preferred primary search path for new large-text
  retrieval
