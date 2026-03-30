# Target Layer: db

This directory is the planned home for database-facing semantics in `pollydb`.

The staged migration plan keeps the current implementation in `storage/` until
the backend interfaces and package boundaries are stable enough to avoid V
module cycles.

Planned contents:

- `database.v`
- `engine.v`
- `schema.v`
- `types.v`
- `view.v`
- `projector.v`

Current state:

- source of truth still lives in `storage/`
- this directory is intentionally documentation-only for now
- callers should continue importing `storage`
