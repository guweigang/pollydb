# AgentView

`agentview` is a standalone session exploration layer for local AI agent transcripts.

Goals:

- keep session exploration decoupled from any single storage engine
- normalize local agent session sources into one canonical model
- make transcript listing, search, and reading work now
- leave room for a future TUI without changing the data model again

Current scope:

- Codex local sessions under `~/.codex`
- session discovery from `sessions/` and `archived_sessions/`
- title enrichment from `session_index.jsonl`
- transcript rendering from session JSONL files
- `pollydb`-backed local cache and query store
- incremental sync that skips unchanged sessions
- sync progress events surfaced through the CLI
- distilled memory records with source provenance
- CLI queries through `cmd/agentview_cli`
- a `term.ui` TUI browser for list/read/search flows

CLI supports:

- session list paging and filtering (`--offset`, `--limit`, `--query`, `--cwd-prefix`, `--no-archived`)
- transcript paging (`show <session_id> --offset N --limit N`)
- scoped search (`search <query> --session-id ID --offset N --limit N`)
- browse mode with auto-sync on empty stores (`browse`)
- memory listing and search (`memory list`, `memory search <query>`)
- memory preview and distillation (`memory preview`, `memory distill`)
- model-facing memory context output (`context <query>`, `memory context <query>`)

Browse mode supports:

- left/right pane navigation
- transcript reading with wrapped content and session metadata
- global entry search from `/`
- session text filtering from `f`
- session cwd-prefix filtering from `c`
- archived session toggle from `a`
- search results view with `Enter` to jump into the matched session entry
- help overlay from `h`

Current architecture:

- adapters normalize local sources like `~/.codex` into canonical session records
- `agentview` exposes a session-oriented model for list/read/search use cases
- the first backend is `pollydb`, used as a local cache plus query/index engine
- the store layer now exposes paging/filtering oriented APIs for future TUI work
- the TUI browser stays on top of the same store interface as the CLI
- memory is stored as versioned derived data in `pollydb`, separate from raw transcripts

Planned next steps:

- Claude and Copilot adapters
- richer tool-call correlation
- first-class memory page in the TUI browser
- saved search presets and session facets
- richer transcript navigation and tool-call drill-down
