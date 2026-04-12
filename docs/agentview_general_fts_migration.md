# Agentview General FTS Migration

`agentview` now uses PollyDB's general FTS index capability instead of the older
Markdown-selector lexical index path.

For the current product scope, `agentview` uses a single primary full-text index:

- `entries_content_text_fts_idx`

It does not require a `content_md` FTS index to provide the main search
experience.

## Schema

The `entries` table search index should now be:

- `entries_content_text_fts_idx`

It replaces the older search path based on:

- `entries_fts_any_idx`
- `entries_fts_heading_idx`

The new index is declared as a normal PollyDB FTS index:

- `content_text` uses a direct text FTS index

## Query Path

`agentview` search now uses the unified PollyDB query entrypoint:

- `QueryRequest.general_fts`
- `POST /v1/query-plan-preview` with `general_fts`
- `POST /v1/query-rows` with `general_fts`

That means `agentview` is no longer maintaining a unique application-level FTS
projection model.

## Existing Local Stores

For an existing store such as:

- `/Users/guweigang/.agentview/pollydb`

the migration steps are:

1. Open the store so `register_or_update_table(entries_spec(true))` writes the new schema.
2. Run `agentview index-search` to rebuild the `content_text` FTS sidecar index.
3. Verify `query-schema` for `entries` now exposes `entries_content_text_fts_idx`.

## Notes

- `content_md` remains available as a stored Markdown field for transcript
  rendering and future structured Markdown features, but it is not part of the
  current `agentview` full-text search path.
- `agentview index-search` should no longer spend time backfilling Markdown just
  to satisfy search indexing.
- Search still keeps local post-filtering and ranking logic for session/source/kind
  filtering and result ordering.
