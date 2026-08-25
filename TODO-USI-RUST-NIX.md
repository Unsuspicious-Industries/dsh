# USI Rust + Nix Rewrite Backlog

This is a planned rewrite, not a reason to destabilize the running DSH service.
The current TypeScript service remains the supported path until every acceptance
criterion below is met in a parallel implementation.

- [ ] Define a Rust daemon boundary for session persistence, model streaming,
  retries, and cancellation. Preserve the current OpenAI-compatible and
  Anthropic/Codex route contracts.
- [ ] Implement a Rust session supervisor with durable restart recovery:
  sessions must survive daemon restarts, and a failed model/tool call must
  produce a durable error event instead of silently ending the turn.
- [ ] Move the unified USI door's health, retry ladder, rate-cap tracking, and
  model catalog into a small Rust service with deterministic integration tests.
- [ ] Define a Nix flake package for the Rust daemon, static frontend assets,
  and a NixOS module. No fixed-output install step may depend on mutable
  global npm/corepack state.
- [ ] Build a compatibility test harness against existing DSH JSONL sessions:
  replay, tool calls, model selection, subagent lifecycle, cancellation, and
  recovery must match before migration.
- [ ] Add status telemetry: live session count, interrupted/recovered turns,
  model retries, restart count, catalog freshness, and the exact deployed
  revision.
- [ ] Run the Rust daemon in shadow mode against recorded sessions, compare
  output/event invariants, then migrate one service host at a time.

## Non-Negotiable Acceptance Criteria

- A DSH process restart never loses a persisted session or leaves the web UI in
  a crash loop.
- A model outage never changes the caller's selected model silently; retries
  and reroutes are recorded in the session event log.
- `nix build .#dsh` is reproducible and `nix flake check` validates the package
  and NixOS module without requiring a developer's local state.
- Deployments remain `commit + push`; `usi-daemon` performs the switch and
  rollback health gate. No manual hot patches are part of the steady-state
  workflow.
