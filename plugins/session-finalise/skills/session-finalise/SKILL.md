---
name: session-finalise
version: 0.2.0
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
Steps are **skippable** — in Orient, propose only the phases this session actually needs, and let
the user drop any. Run the phases **in the order below** (the order is a safety property).

**Output style:** terse by default (match the user's communication preference). But write **every
confirmation prompt and irreversible-action warning in full, plain prose** — these are the moments
the user must read carefully.

### 1. Orient — read-only

Snapshot the session, then summarize in one screen and propose which phases apply:

```bash
git status --short --branch
git worktree list
git log --oneline -5
```

Also note: files created/touched this session, and any tracker IDs (GitHub issue/PR numbers, Asana
task GIDs, Linear/Jira keys) mentioned in the conversation. Nothing here mutates state.

Don't trust memory alone for "what I created" — after a long or compacted session it's unreliable.
Derive candidate scratch files from `git status` untracked entries and **confirm with the user**
which are throwaway versus keep before phase 7 deletes anything.

### 2. Pending work — commit / stash (CONFIRM)

Do this **first**, so later cleanup can never destroy uncommitted work.

- Surface uncommitted changes. Group them into **separate logical commits** with conventional
  messages (`feat:`/`fix:`/`chore:`/`docs:`/`refactor:`/`test:`), or offer to `git stash`.
- **Never commit to `main`** — use `develop` or an existing dev branch; create one if needed.
- **Exclude scratch/throwaway files** from commits — they are removed in phase 7, not committed.
- **Never `git push` without explicit confirmation.** State exactly what will be pushed where.

### 3. Durable memory — always consider

Review the session for facts worth persisting across sessions (decisions, gotchas, non-obvious
config, user preferences). For each:

- **Read an existing file in the project's `memory/` dir first** and copy its exact frontmatter
  shape — do not assume a schema. (Project memory lives under `~/.claude/projects/<slug>/memory/`,
  indexed by `MEMORY.md`, where `<slug>` is the project path with `/` → `-`.) If the store is
  empty, use the standard frontmatter: `name`, `description`, and `metadata.type` — one of
  `user | feedback | project | reference`.
- One fact per file; check for an existing file to **update** rather than duplicating; link related
  memories. Add a one-line pointer in `MEMORY.md`.
- **Skip** anything already authoritative in code or git history — don't restate the repo.

### 4. Handoff — only if continuation is useful, or if asked

**Delegate to the existing skill** — invoke `remember` (it owns the `# Handoff` format and the
`.remember/remember.md` location). Do **not** hand-write that file yourself.

### 5. Trackers — detect, then adapt (project-aware, tracker-agnostic)

Do **not** assume a fixed tracker or mechanism. Detect what is reachable *right now*:

- **Available tools:** scan your own currently-available tools for tracker MCP servers (names
  matching `asana`, `github`, `linear`, `jira`, `gitlab`, `notion`, `clickup`, …).
- **Project config:** check `.mcp.json` and `.claude/settings*.json` `enabledPlugins`.
- **CLIs:** `command -v gh` (and any other tracker CLI the project uses).

Then, for each tracker referenced this session:

- **Integration wired (MCP tool or CLI)** → propose the concrete updates (status, comment, close,
  link the commit/PR) and apply them through that integration, **confirming before each mutating call.**
- **Nothing wired** → emit a plain-text checklist of the exact changes for the user to apply
  manually, and note which MCP/plugin would automate it next time.

Tracker rules that hold regardless of mechanism: **Asana edits contain no HTML**; when both a
GitHub MCP and `gh` are available, **prefer `gh`**. "Updating" a PR/issue/task means
comment / label / status / link — it **never** includes `git push`; pushing stays a separate
confirmed action in phase 2.

### 6. Session summary

A short recap of what was accomplished this session — distinct from the handoff (which is
forward-looking). Skip if the session was trivial.

### 7. Cleanup — CONFIRM each, runs LAST

- **Temp/scratch files** created this session → list them → confirm → remove.
- **Worktrees & branches** → `git worktree list`; identify merged/abandoned ones → confirm →
  remove the worktree, **and** remove its corresponding Claude Code project dir
  (`~/.claude/projects/<worktree-path-slug>/`, path with `/` → `-`), per the user's rule.

### 8. Final report

Terse summary: what each phase did, and what was skipped.

## Safety gates

- **Confirm before:** deleting any file, any commit, any push, removing a worktree, removing a
  Claude Code project dir.
- **Never** commit to `main`; **never** push without confirmation.
- Treat `.env` and credentials per the user's security rules — never echo secret values.
- If a step's preconditions don't hold (e.g. no uncommitted changes), say so and skip it; don't invent work.

## Common mistakes

- **Reimplementing the handoff** instead of delegating to `remember` → format drift. Delegate.
- **Hardcoding a tracker** (assuming `gh`, or assuming Asana is manual) → breaks when an MCP is
  wired at project scope. Always detect first.
- **Cleaning up before committing** → lost work. Commit/stash (phase 2) before cleanup (phase 7).
- **Inventing a memory frontmatter schema** instead of matching an existing file → inconsistent store.
- **Running every phase regardless** → noise. Propose only what applies; let the user skip.

## Quick reference

| Phase | Mutates? | Gate |
|-------|----------|------|
| 1 Orient | no | — |
| 2 Commit/stash | yes | confirm; never `main`; confirm push |
| 3 Durable memory | yes (memory store) | match existing schema |
| 4 Handoff | delegated | invoke `remember`; only if useful |
| 5 Trackers | maybe | detect first; confirm each mutation; no HTML in Asana |
| 6 Summary | no | — |
| 7 Cleanup | yes (deletes) | confirm each delete/removal |
| 8 Report | no | — |
