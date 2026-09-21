# Agent Note: Projects Carry User Titles, Never Filesystem Paths

Status: implemented

English | [中文](2026-09-21-projects-carry-user-titles-never-paths.zh.md)

## Problem

The session browser labelled a session that belonged to no project with the basename of that session's working directory. `workspaceLabel(cwd)` split the path and returned its last segment, and `deriveSearchResults` used it as the fallback for every session missing from the workspace membership map.

On a working host this invented project names out of incidental directories. A sidebar that should have shown the user's own projects instead showed one bucket per path the agent had ever run in: `/workspace`, `/root`, `/tmp`, `/etc/nixos/servers`, `/tmp/v41try`. None of those was a project anyone created. The user's complaint was literal: a row of weird folders littering the sidebar.

The defect was a naming decision, not a storage one. Projects are only ever created through the `workspace.create` RPC, which the GUI calls from an explicit create flow. Nothing auto-created a project from a cwd; the presentation layer merely *rendered* a path as though it were one, which made an implicit bucket indistinguishable from a user-created project.

## Decision

A row's project label comes only from a stored project title. A session outside every project carries the ungrouped label.

`workspaceLabel` and its path parsing are deleted. `deriveSearchResults` falls back to `UNGROUPED_LABEL` — the same constant that already named the ungrouped bucket in `groupByWorkspace` — so search results and grouped rows now name a project identically.

The ungrouped bucket stays: sessions legitimately run outside any project, and they still need a home. What is removed is the pretence that their directory is a project.

## Consequences

The sidebar can no longer display a project the user did not create, so no path can leak into a project name. A session started in `/root/server-work` now reports `Ungrouped`, and the only way to see a project name is to have created that project.

Two callers were relying on the removed behaviour and are updated in the same change: the merge-order expectation in `deriveSearchResults` asserted `workspace: 'c'` for a path-derived label, and the `workspaceLabel` unit block asserted POSIX and Windows basename extraction.

`EmptyHero`'s `workspaceLabel` is a different function in a different package and is deliberately untouched: it labels a directory the user explicitly picked in the new-session hero, where showing the chosen directory is the point. This note does not cover it.

## Alternatives considered

**Keep the path label but render it as secondary text.** Rejected: the sidebar already shows the session's own title, and a second path-derived string per row re-creates the litter in a smaller font. The requirement was to stop inventing projects, not to relabel them.

**Auto-create a real project the first time a cwd appears, then hide paths behind generated names.** Rejected outright by the requirement that projects are user created. A generated name would also be unstable — the same project would be named differently after a rename of its directory.

**Filter path-shaped labels in the component.** Rejected: it puts the decision in the presentation layer, where a second consumer of `deriveSearchResults` would not inherit it. The label's owner is the derivation, so the fallback changed there.

## Testing

`packages/client/ui-workspace/tests/tree.client.spec.ts` covers the new behaviour directly: a session in `/root/server-work` that belongs to no project is labelled `Ungrouped` in search results, while a session owned by a project labelled `Demo Project` reports that title. The path basename never appears.
