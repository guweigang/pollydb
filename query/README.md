## Query Module

`query/` is the dedicated facade for PollyDB query-facing APIs.

Current role:

- host app-level query entrypoints
- own stable query-facing type names such as `Request`, `Filter`, and `FtsRequest`
- keep business and CLI callers from binding directly to `storage` query methods
- provide a migration seam while storage internals are still being extracted

Current limitation:

- query request/plan/result types are currently re-exported aliases over `storage`
- `storage` still carries compatibility query methods for now

Near-term rule:

- new application/query orchestration code should import `query`
- `storage` should only grow storage-engine and repository concerns
