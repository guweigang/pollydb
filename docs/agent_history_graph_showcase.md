# Agent History Graph Showcase

This is the thin productization wedge for PollyDB.

PollyDB stays the generic versioned database. AgentView is only a showcase
schema that demonstrates how agent-generated interpretations can be stored as
ordinary versioned rows with provenance.

## Shape

Raw AI session data lands in normal AgentView rows:

- `sessions`
- `entries`

Derived agent-work interpretation lands in four additional tables:

- `episodes`: one problem-solving process inside a session
- `episode_reports`: a concise report for the episode
- `episode_reasoning_nodes`: problem, hypothesis, evidence, action, decision,
  validation, and outcome nodes
- `episode_reasoning_links`: typed reasoning edges such as `led_to`,
  `supports`, `refutes`, `tests`, and `resolves`

Each derived row carries `derived_from_root_hash` and source refs back to raw
rows. Every save is a normal PollyDB commit, so graph extraction, user
correction, and model re-runs are versioned by the database instead of hidden in
application state.

## Boundary

AgentView owns the agent-specific schema and prompts.

PollyDB owns only the reusable substrate:

- typed rows
- branches, commits, and merges
- indexes
- source refs and derived rows
- replayable history

The first useful demo should be:

```text
sample Codex session
  -> AgentView rows
  -> one episode graph
  -> one commit
  -> inspect nodes, links, and source refs
```

This is intentionally smaller than a full AgentView product. It exists to prove
that PollyDB is a natural store for versioned, auditable agent-generated data.
