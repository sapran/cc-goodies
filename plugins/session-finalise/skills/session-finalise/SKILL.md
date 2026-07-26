---
name: session-finalise
version: 0.2.1
description: >-
  This skill should be used when wrapping up, closing out, or ending a work session —
  "finalise the session", "wrap up", "we're done for today", "let's close out", "save state
  before I stop". It should also be used when about to stop with loose ends dangling: durable
  facts not yet saved to memory, a handoff not written, uncommitted or unpushed work, scratch/temp
  files left behind, stale or merged git worktrees, or tracker tasks (GitHub/Asana/Linear/Jira/etc.)
  left un-updated.
---

# Session Finalise

## Overview

End-of-session housekeeping. **Orchestrates the systems that already exist** — the per-project
`memory/` store, the `remember` handoff skill, git, and whatever task trackers are wired — then
cleans up. It does **not** reimplement memory or handoffs; it drives them.

Core principle: **preserve work before deleting anything, and confirm every irreversible step.**

## When to use

- User signals wrap-up: "finalise", "wrap up", "we're done", "close out", "before I stop".
- Loose ends before stopping: unsaved facts, uncommitted work, scratch files, stale worktrees, tasks left un-updated.

**Not for:** a mid-session checkpoint with no cleanup (use `remember` alone), or a session where nothing changed.

## How to run

Treat this as a **checklist, not a script.** Create one todo per *applicable* phase (use TodoWrite).
Propose only the phases this session actually needs, and let the user drop any.

**The invariant — the only ordering rule that actually matters:** nothing is destroyed or
discarded before it is saved and confirmed. Concretely: Cleanup runs only once any work it could
destroy — uncommitted changes, untriaged scratch files — has already been surfaced and
committed, stashed, or explicitly confirmed as discardable. Beyond that one dependency, the
phases below have no required relative order: Durable memory, Handoff, Trackers, and Summary can
run in whatever order suits the session, since none of them can destroy prior work.

**Output style:** terse by default (match the user's communication preference). But write **every
confirmation prompt and irreversible-action warning in full, plain prose** — these are the moments
the user must read carefully.

### Orient — read-only

Snapshot the session and propose which phases apply. Nothing here mutates state. Read
`references/orient.md` for the snapshot commands and for identifying scratch files — they need
to be confirmed throwaway-versus-keep before Cleanup can remove anything.

### Commit / stash (CONFIRM)

Surface uncommitted work and capture it — commit or stash — before Cleanup runs. Read
`references/commit.md` for the commit-grouping, branch, and push-confirmation rules.

### Durable memory

Reconcile the project's `MEMORY.md` against what this session established, rather than
authoring from a schema. Read `references/memory.md`.

### Handoff

Only if continuation is useful, or if asked. Read `references/handoff.md` — it delegates to the
`remember` skill rather than hand-writing the handoff file.

### Trackers

Detect what task-tracker capability is reachable this session, then adapt. Read
`references/trackers.md` before proposing or applying any tracker mutation.

### Summary

A short recap of what was accomplished this session — distinct from the handoff (which is
forward-looking). Skip if the session was trivial.

### Cleanup (CONFIRM each)

Remove temp/scratch files and stale worktrees, each confirmed individually. Read
`references/cleanup.md` before removing anything — it covers the worktree-plus-Claude-Code-project-dir
rule this phase must not skip.

### Final report

For each phase that was proposed this run, state: whether it ran, what it changed (or why it
was skipped), and — for any phase that mutated something — whether every mutation in it was
confirmed before it executed. Terse in tone; checkable in structure.

## Safety gates

- **Confirm before:** deleting any file, any commit, any push, removing a worktree, removing a
  Claude Code project dir.
- **Never** commit to `main`; **never** push without confirmation.
- Treat `.env` and credentials per the user's security rules — never echo secret values.
- If a step's preconditions don't hold (e.g. no uncommitted changes), say so and skip it; don't invent work.
