# Target Layer: core

This directory is the planned home for versioned tree and commit mechanics in
`pollydb`.

The staged migration plan keeps the current implementation in `storage/` until
the backend interfaces and package boundaries are stable enough to avoid V
module cycles and awkward cross-directory module coupling.

Planned contents:

- `tree.v`
- `history.v`
- `repository.v`
- merge helpers

Current state:

- source of truth still mostly lives in `storage/`
- this directory now hosts a very small set of cycle-safe shared helpers used by
  both `storage/` and `query/`
- larger backend/data-structure migrations are still intentionally postponed
  until the package boundaries are stable enough
- callers should continue importing `storage` or `query` rather than `core`
