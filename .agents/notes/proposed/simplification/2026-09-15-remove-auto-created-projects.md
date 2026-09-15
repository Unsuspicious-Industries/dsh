# Agent Note: Remove Auto-Created Projects From the Session Browser

Status: proposed

English | [中文](2026-09-15-remove-auto-created-projects.zh.md)

## Problem

The workspace registry invented one project per session `cwd` on first start. Bootstrap grouped the historical session headers by their recorded working directory and wrote a record per directory, titled `basename(path)`. On the deployed instance this produced seven folder sections — `/workspace` (41 sessions), `/root` (27), `/tmp` (13), `/etc/nixos/servers` (3), `/tmp/v41try` (3), `/root/server-work` (2), `/workspace/deepseek-harness` (1) — none of which the user created or wanted. A directory that a session happened to start in is not a unit of work: `/tmp` and a scratch checkout are incidental, and the section list grows with every new path.

The same derivation also decided session membership without the user: a historical session whose `cwd` matched a record was adopted into it. Both effects follow from treating a filesystem path as project identity, which is the wrong key for a feature the user is meant to drive.

## Proposal

`WorkspaceRegistry.bootstrap()` stops deriving projects. It marks the registry initialized and leaves order and membership untouched; a historical session that belongs to no project stays reachable in the session browser instead of being filed somewhere. Grouping-derived machinery that existed only to serve the derivation (`BootstrapGroup`, `compareHeaders`, `sessionSameIds`) is deleted with it.

`workspaceDomainSpec.version` moves from `2` to `3`. A registry written by the old bootstrap is rejected at open rather than migrated, which is what makes the removal complete: the seven existing records cannot reappear. Session logs are untouched by the version change — the directories stop being sections, and the sessions remain.

The deployment then deletes the two files the new version no longer owns, once, from `services/dsh/default.nix`: `storages/workspace.json` and `storages/session_projcache.json`, behind a versioned marker file, placed after the `/root/.dsh` seeding so a stale file cannot be copied back in. `sessions/`, `settings.yaml`, `credentials.env`, and `profiles/` are never touched.

The session browser keeps rendering unowned sessions: `WorkspaceBrowser.tsx` already routes them into its ungrouped account, so an empty registry shows every session in one list rather than an empty pane. That is the state this change ships; replacing the ungrouped section with the flat live list is separate work.

## Alternatives considered

- **Migrate the existing records into user-created projects.** They are all machine-generated from paths, so there is nothing to preserve. Migration would carry the litter forward under a new name and would need a rule for which of the seven a session belongs to.
- **Keep the derivation but mark its records hidden.** Leaves the durable state, the identity confusion, and the bootstrap reads; the browser would need to distinguish two kinds of project forever.
- **Delete only the files, without the version bump.** A surviving registry would still parse and could be re-seeded, and the bootstrap would recreate the same records on the next start.
- **Keep `path` as project identity and add a separate user-named label.** Two keys for one entity, and two projects could still not share a directory, which is a legitimate thing to want.

## Acceptance criteria

- With no projects defined, every session remains visible in the session browser in a single list.
- A registry stamped version 2 is refused at open with the version-mismatch error; a test asserts this.
- Bootstrap writes no project rows: with sessions present and none owned, `list()` returns empty and the stored state records `initialized` with an empty order.
- Existing projects are not silently joined by historical sessions that share their directory.
- `storages/workspace.json` and `storages/session_projcache.json` are absent after the deploy that lands this, while `sessions/` and `settings.yaml` are intact.

## Risks

- The change removes on-demand hiding of a recent session: visibility becomes derived from recency and starring, so a session cannot be dismissed before it ages out. That trade is deliberate and is the subject of the follow-on work on the live list.
- Refusing the old format means a user who had built real projects in a pre-rework registry would lose them. On this instance every record is machine-generated, which is what makes the version bump free; on any other instance it would not be.
- Unplaced sessions are unbounded in a way grouped ones were not: nothing yet distinguishes recent from stale in the single list, so the list length is the pre-existing session count until the live/archived split lands.
- A second process holding the registry open across the purge could rewrite the deleted file. The state-preparation unit runs before the web unit within the same system activation, so no old process survives it.
