# session-finalise

End-of-session housekeeping for Claude Code. One checklist that **orchestrates the systems
you already have** — the per-project `memory/` store, the `remember` handoff skill, git, and
whatever task trackers are wired — then cleans up after itself. It doesn't reimplement memory
or handoffs; it drives them.

Core principle: **preserve work before deleting anything, and confirm every irreversible step.**

## How to invoke

Two entry points, same checklist:

- **Type `/session-finalise`** — the command, invoked by name. Pass optional notes, e.g.
  `/session-finalise skip cleanup` or `/session-finalise write a handoff`.
- **Just say it** — the bundled skill **auto-activates** when you signal a wrap-up ("let's
  wrap up", "we're done for today", "save state before I stop") or when loose ends are
  dangling (unsaved facts, uncommitted work, scratch files, stale worktrees, un-updated
  tracker tasks). Skills are model-invoked, so you don't have to remember the command.

## What it does

A **skippable, ordered** checklist — the order is a safety property (preserve before delete).
Claude proposes only the phases the session actually needs and lets you drop any:

| Phase | Mutates? | Gate |
|-------|----------|------|
| 1 Orient | no | snapshot `git status` / worktrees / recent log; nothing changes |
| 2 Commit / stash | yes | confirm; never `main`; confirm push |
| 3 Durable memory | yes (memory store) | match the existing frontmatter schema |
| 4 Handoff | delegated | invoke `remember`; only if a continuation is useful |
| 5 Trackers | maybe | detect what's wired first; confirm each mutation; no HTML in Asana |
| 6 Summary | no | short recap of the session |
| 7 Cleanup | yes (deletes) | confirm each file delete / worktree removal |
| 8 Report | no | terse summary of what ran and what was skipped |

Output is terse by default, but **every confirmation prompt and irreversible-action warning
is written in full prose** — those are the moments you must read carefully.

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install session-finalise@cc-goodies
```

The command and the auto-activating skill are available on install (restart or `/hooks`/
`/reload-plugins` to load them the first time).

## Uninstall

```text
/plugin uninstall session-finalise@cc-goodies
```

This plugin writes **nothing outside its own directory** — no `settings.json` edits, no
config files, no durable external state — so there is no dedicated `/…-uninstall` to run.
`/plugin uninstall` removes it completely (same as `voice-notify`).

## Requirements

- **`git`** — the Orient and Commit/stash phases shell out to it.
- A project **`memory/` store** and the **`remember`** skill are *orchestrated* if present,
  but are not hard dependencies — the relevant phases simply no-op or fall back to a manual
  checklist when they're absent.
- Cross-platform — no macOS-only tooling.

## License

MIT © Volodymyr Styran
