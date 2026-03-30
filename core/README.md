# Target Layer: core

This directory is the planned home for versioned tree and commit mechanics in
`pollydb`.

The staged migration plan keeps the current implementation in `storage/` until
the backend interfaces and package boundaries are stable enough to avoid V
module cycles.

Planned contents:

- `tree.v`
- `history.v`
- `repository.v`
- merge helpers

Current state:

- source of truth still lives in `storage/`
- this directory is intentionally documentation-only for now
- callers should continue importing `storage`
