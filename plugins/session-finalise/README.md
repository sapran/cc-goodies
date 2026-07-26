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

A **skippable** checklist — Claude proposes only the phases the session actually needs and lets
you drop any. The one rule that's actually a safety property: nothing is destroyed or discarded
before it's saved and confirmed, so cleanup only runs once anything it could destroy has already
been committed, stashed, or confirmed as discardable. See the skill
([`skills/session-finalise/SKILL.md`](skills/session-finalise/SKILL.md)) for the phase list and
its `references/` for how each phase works.

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
