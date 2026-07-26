## Why

Two Anthropic posts reset the assumptions `session-finalise` was written under: [A field guide to
Claude Fable](https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns) (output
quality is bottlenecked by unresolved unknowns, not capability) and
[The new rules of context engineering](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models)
(prescriptive rules → judgment framing, upfront loading → progressive disclosure, named
anti-patterns: defensive guardrails, exhaustive documentation, repetition across context layers).
The second post also states plainly: *"Claude now automatically saves memories that are relevant
to the work and to you."*

`plugins/session-finalise/skills/session-finalise/SKILL.md` (151 lines) predates both posts and
carries defects the posts name directly, each verified against the current file:

- **The 8-phase contract is encoded three times** — the `###` phase sections, the in-file
  `## Quick reference` table (lines 140–151), and a third rendering of the same table in
  `README.md` (lines 26–35). Post 2's "repetitive instructions across multiple context layers"
  anti-pattern, verbatim.
- **Phase 3 re-specifies memory mechanics the harness now supplies natively**: the
  `~/.claude/projects/<slug>/memory/` path with the `/` → `-` derivation rule, the frontmatter
  schema (`name` / `description` / `metadata.type` with its `user|feedback|project|reference`
  enum), and the `MEMORY.md` index convention (SKILL.md lines 72–78). That is duplicated
  harness-native context, and it will drift as the harness's own convention evolves.
- **Tracker detection fails closed on unlisted vendors.** It scans "for tracker MCP servers
  (names matching `asana`, `github`, `linear`, `jira`, `gitlab`, `notion`, `clickup`, …)"
  (line 91) — a fixed vendor list standing in for the actual capability being sought.
- **The plugin bakes in one user's product preferences**: "Asana edits contain no HTML" and
  "when both a GitHub MCP and `gh` are available, prefer `gh`" (line 102). Those are the
  operator's own tool preferences (already present in their private `~/.claude/CLAUDE.md`), not
  a rule every installer of this marketplace plugin should inherit.
- **`## Common mistakes`** (lines 131–138) is the defensive-guardrail anti-pattern named by
  post 2 — an anti-pattern list stacked on top of an already-explicit checklist.

The skill also states "the order is a safety property" (SKILL.md line 34, README.md line 23)
without distinguishing which part of the order actually is one. Reading the file shows only one
ordering constraint is explicitly load-bearing: phase 2 (commit/stash) must precede phase 7
(cleanup), stated directly at line 59 ("Do this first, so later cleanup can never destroy
uncommitted work"). The file already states the real invariant at the top — "preserve work
before deleting anything, and confirm every irreversible step" (line 21) — then buries it under
a numbered script that implies every step's position matters equally. It doesn't.

## What Changes

- **SKILL.md becomes a router** stating the invariant — nothing is destroyed or discarded before
  it is saved and confirmed — instead of an enumerated 8-step script. The ordering that follows
  from the invariant (preserve/save phases before the destructive cleanup phase) is stated once,
  as a consequence, not re-encoded as a rigid sequence.
- **Phase detail moves to `references/`**, loaded when a phase applies, so the always-loaded body
  shrinks and the phase mechanics live in exactly one place.
- **Phase 3 (memory) becomes reconciliation, not authorship from a schema**: read `MEMORY.md`,
  judge what this session established that no file records and what recorded memory is now
  stale. The frontmatter schema, the `<slug>` derivation rule, and the `MEMORY.md` index format
  are dropped from the skill — the harness now supplies them.
- **Tracker detection describes the capability being sought** ("a task-tracker tool or CLI is
  available in this session") instead of enumerating vendor substrings, so it doesn't fail
  closed on a tracker the list happens not to name.
- **User-specific product rules are removed from the plugin**: "Asana edits contain no HTML" and
  the `gh`-over-MCP preference. They belong in the operator's own `~/.claude/CLAUDE.md`, not in
  content shipped to every installer.
- **`## Common mistakes` and the duplicated Quick-reference table are removed.** The README stops
  re-rendering the phase table and instead points at the skill.
- **The final report becomes a checkable rubric** a verification pass can apply, rather than
  free-form prose.
- **Phase 1 (Orient) becomes subagent-delegable**: it is a noisy, read-only survey
  (`git status`, `git worktree list`, `git log`, file/tracker-ID scanning); running it in a
  subagent keeps that noise out of the main context and returns a small structured summary.
- **No safety posture changes.** Every mutation still confirms; commit still never targets
  `main`; push still never happens without explicit confirmation; cleanup still runs last,
  after the preserve/save phases. This is a restructure of instruction, not of the consent gates.

**Out of scope:** trimming the `SKILL.md` frontmatter `description` and other always-on metadata
is the separate `trim-skill-metadata` proposal (memo P2) and is not addressed here.

## Capabilities

### Added Capabilities

- `session-finalise-skill-structure`: the structural contract for how `session-finalise`'s
  SKILL.md, `references/`, and `README.md` divide the end-of-session checklist — invariant-first
  instruction, no duplicated phase contract across layers, reconciliation-based memory handling,
  capability-based tracker detection, no user-specific product preferences in plugin content, and
  preserved consent/ordering safety guarantees.

## Impact

- **Skill** `plugins/session-finalise/skills/session-finalise/SKILL.md`: rewritten as a router
  (invariant statement, phase names, pointers to `references/`); phase mechanics removed from the
  body.
- **New** `plugins/session-finalise/skills/session-finalise/references/`: one file per phase (or
  grouped where phases are thin), holding what SKILL.md currently inlines — commit/stash
  mechanics, the memory-reconciliation procedure, the handoff delegation note, tracker-capability
  detection and mutation flow, and the cleanup procedure.
- **Command** `plugins/session-finalise/commands/session-finalise.md`: unchanged in mechanism
  (still delegates to the skill); reviewed for wording that assumes the old phase-script shape.
- **Docs** `plugins/session-finalise/README.md`: drops the duplicated phase table; points at the
  skill instead of restating its contract.
- **Manifest** `plugins/session-finalise/.claude-plugin/plugin.json`: version bump only (the
  `keywords`/`description` fields are explicitly out of scope per `trim-skill-metadata`); no
  hooks, no new external state — install⇄uninstall symmetry is unaffected (`/plugin uninstall`
  remains the complete revert).
- **No new runtime dependency.** No new external files, no new config, no new hook.
