## 1. SKILL.md — router rewrite (`skills/session-finalise/SKILL.md`)

- [ ] 1.1 Replace the "Run the phases in the order below (the order is a safety property)" framing (current line 34) with the stated invariant — nothing is destroyed or discarded before it is saved and confirmed — as the single ordering rule; keep phase names as short pointers, not a numbered script the model must follow verbatim.
- [ ] 1.2 Strip phase mechanics out of the body: the bash snapshot block, the memory frontmatter/path/index recital (lines 72–78), the tracker vendor-list scan (lines 90–91) and the Asana/`gh` rules (lines 102–103), the cleanup worktree/Claude-Code-project-dir procedure. Each moves to `references/` (task 2) or is dropped outright (tasks 3–5); none stays duplicated in SKILL.md.
- [ ] 1.3 Remove `## Common mistakes` (lines 131–138) — the defensive-guardrail anti-pattern; do not replace it with an equivalent list elsewhere in the plugin.
- [ ] 1.4 Remove `## Quick reference` (lines 140–151) — the in-file duplicate of the phase/gate contract. Confirm no other section re-renders the same table.
- [ ] 1.5 Re-verify `## Safety gates` (lines 123–129) survives intact or is folded into the invariant statement without losing any gate: confirm-before-delete/commit/push/worktree-removal, never `main`, credential handling, "don't invent work when preconditions don't hold."

## 2. `references/` — phase detail extraction

- [ ] 2.1 Create `skills/session-finalise/references/` with one file per phase (or grouped where a phase is thin), holding exactly the mechanics removed from SKILL.md in task 1.2: commit/stash procedure, handoff delegation note, tracker detection + mutation flow, cleanup procedure (including the worktree + Claude Code project dir removal rule).
- [ ] 2.2 Grep the finished SKILL.md against every new reference file to confirm no mechanic is present in both places — progressive disclosure must be real, not nominal (the failure mode `project-scope`'s `references/` already has, per the architecture memo point 3).
- [ ] 2.3 In SKILL.md, name concretely when each reference applies (e.g. "before a tracker mutation, read `references/trackers.md`") rather than a generic "see references/" pointer, so the split has a reason to be read rather than skipped.

## 3. Memory phase — reconciliation over schema recital

- [ ] 3.1 Rewrite phase 3 as reconciliation: read `MEMORY.md`, judge what this session established that no file records, and what recorded memory is now stale given what's observed on disk. Do not restate the `~/.claude/projects/<slug>/memory/` path, the `/` → `-` derivation rule, the `name`/`description`/`metadata.type` (`user|feedback|project|reference`) frontmatter schema, or the `MEMORY.md` index convention — the harness supplies all of it natively.
- [ ] 3.2 Keep the one piece of the old phase that isn't harness-native duplication: "read an existing file in the project's `memory/` dir first and copy its exact frontmatter shape" (line 72) as the bootstrap for the (harness-agnostic) case where no memory file yet exists for a given fact — reconciliation still needs this fallback.
- [ ] 3.3 Confirm "skip anything already authoritative in code or git history" (line 79) is preserved — it's a real judgment rule, not schema duplication.

## 4. Tracker detection — capability framing, not vendor enumeration

- [ ] 4.1 Rewrite the "Available tools" detection step (lines 90–91) to describe the capability sought — "a task-tracker tool or CLI is reachable in this session" — rather than a fixed substring list (`asana`, `github`, `linear`, `jira`, `gitlab`, `notion`, `clickup`). Judge a tool by what it claims to do, not by matching its name against an enumerated set.
- [ ] 4.2 Keep the rest of phase 5's structure unchanged in effect: project-config check (`.mcp.json`, `enabledPlugins`), CLI check (`command -v gh`, etc.), the wired/not-wired branch, and "confirm before each mutating call."
- [ ] 4.3 Confirm the rewritten detection step doesn't newly false-positive on an unrelated tool that merely mentions "task" or "issue" — a capability description needs enough specificity (reads/writes items with status, comments, or links) to stay precise without becoming a vendor list again.

## 5. Remove user-specific product rules

- [ ] 5.1 Delete "Asana edits contain no HTML" and "when both a GitHub MCP and `gh` are available, prefer `gh`" (lines 102–103) outright — do not relocate them into `references/` or the README. They stay in the user's own `~/.claude/CLAUDE.md`, where the Asana rule already lives.
- [ ] 5.2 Grep the finished plugin tree (`SKILL.md`, `references/`, `README.md`, `commands/session-finalise.md`) for residual mentions of Asana-specific or `gh`-preference wording to confirm none survived the move.

## 6. Final report — checkable rubric

- [ ] 6.1 Replace phase 8's "terse summary: what each phase did, and what was skipped" (lines 119–121) with a rubric a verification pass can apply mechanically: for each phase that was proposed, state whether it ran, what it changed (or why it was skipped), and whether every mutation in it was confirmed before it executed. Keep it terse in tone; make it checkable in structure.

## 7. Orient (phase 1) — subagent-delegable

- [ ] 7.1 State in SKILL.md (or the relevant reference) that Orient — a read-only survey (`git status`, `git worktree list`, `git log`, file/tracker-ID scanning) — is subagent-delegable, so its noisy output doesn't have to sit in the main context; a subagent can return a small structured summary instead.
- [ ] 7.2 Leave the choice of whether to actually delegate it to judgment (session size, how noisy the read is) rather than mandating a subagent every run — an unconditional rule here would repeat the over-specification this proposal is removing elsewhere.

## 8. Docs — README, command, manifest

- [ ] 8.1 `README.md`: remove the duplicated phase/gate table (lines 26–35); point at the skill for the phase list instead of restating it. Leave Install, Uninstall, Requirements, and License sections as-is (already accurate, no user-specific content, no external state).
- [ ] 8.2 `commands/session-finalise.md`: review "Follow that skill's phased checklist exactly" (line 8) — reword so it doesn't imply a rigid enumerated script the restructure just removed; it should point at the invariant-first skill, not promise verbatim phase-by-phase execution.
- [ ] 8.3 `.claude-plugin/plugin.json`: bump `version` past `0.2.1` per the repo's release convention. Leave `description`/`keywords` untouched — that trim is the separate `trim-skill-metadata` proposal.

## 9. Verification

- [ ] 9.1 `jq empty plugins/session-finalise/.claude-plugin/plugin.json` and `claude plugins validate plugins/session-finalise` both pass.
- [ ] 9.2 End-to-end run: in a scratch repo, create uncommitted work, a stale/merged worktree, and an unsaved durable fact (something worth persisting that no memory file yet records). Run `/session-finalise` and confirm: every mutating step (commit, push, tracker update, delete, worktree removal) still requires explicit confirmation; commit still never targets `main`; save/commit still happens before anything destructive; the memory phase reconciles (proposes the new fact, doesn't recite a schema) rather than skipping it.
- [ ] 9.3 During the same run, deliberately exercise at least one reference-only mechanic (e.g. the cleanup phase's "remove the worktree **and** its corresponding Claude Code project dir" rule) to confirm the router actually pulls in and applies `references/` content rather than the split producing a reference that never gets read.
- [ ] 9.4 Commit the change on a branch off `develop` (never `main`), one logical commit per section above where practical; open a draft PR per the repo's git workflow.
