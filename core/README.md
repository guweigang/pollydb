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

- source of truth still lives in `storage/`
- this directory is intentionally documentation-only for now
- it intentionally has no `.v` files yet because V's directory/module layout
  makes early splitting expensive and cycle-prone
- callers should continue importing `storage`
