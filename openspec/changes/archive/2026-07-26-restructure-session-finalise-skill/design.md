# Design — restructure session-finalise skill

## Context

Two Anthropic posts ([field guide to Claude Fable](https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns),
[new rules of context engineering](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models))
reset the assumptions `plugins/session-finalise/skills/session-finalise/SKILL.md` was written
under: prescriptive rules → judgment framing, upfront loading → progressive disclosure, and —
specific to this skill — *"Claude now automatically saves memories that are relevant to the
work and to you."* `proposal.md` covers the defects and the target shape; this document records
three decisions that need more than a line of justification: which parts of the current phase
order actually are a safety property, how the memory phase reshapes under harness-native
auto-memory, and the risk the `references/` split introduces on its own.

## Verified facts (current `SKILL.md`, 151 lines)

- Eight numbered phase sections (`### 1 Orient` … `### 8 Final report`).
- The phase/gate contract is rendered three times: the `###` sections, `## Quick reference`
  (lines 140–151), and `README.md`'s phase table (lines 26–35).
- Exactly **one** explicit ordering-as-safety statement exists in the file: line 59, "Do this
  **first**, so later cleanup can never destroy uncommitted work" — phase 2 (commit/stash) before
  phase 7 (cleanup).
- No other phase states an explicit dependency on another phase's position. Phases 3 (memory),
  4 (handoff), 5 (trackers), and 6 (summary) have no stated relationship to each other or to
  phase 1.

## Decision D1 — most of the numbered order is incidental, not safety

The skill's own header claims "Run the phases **in the order below** (the order is a safety
property)" (line 34), and the README repeats it ("the order is a safety property," line 23).
Reading the file end to end does not support that as written:

- **Genuinely load-bearing:** phase 2 before phase 7. Stated directly, and it's the only
  ordering constraint whose violation causes actual data loss — committing/stashing before
  cleanup means cleanup can't delete something that was never captured.
- **A data dependency dressed as ordering, not a distinct safety rule:** phase 1's instruction
  to "confirm with the user which are throwaway versus keep **before phase 7 deletes
  anything**" (lines 54–55). This isn't a second invariant — it's the same "preserve/confirm
  before destroy" rule applied to file identification instead of commits. It doesn't need its
  own numbered position; it needs the same invariant Phase 1 already serves by being read-only
  and first.
- **Incidental:** phases 3, 4, 5, and 6 relative to each other. Phase 5 (trackers) mentions
  linking "the commit/PR" in its mutation description, which reads better if phase 2 already
  ran — but nothing breaks if a tracker update is proposed first: the "confirm before each
  mutating call" gate catches a not-yet-existing commit reference as a quality issue, not a
  safety one. Phase 8 (report) trivially comes last because it reports on what happened, not
  because an earlier position would be unsafe.

Conclusion: the file's own top-line invariant — "preserve work before deleting anything, and
confirm every irreversible step" (line 21) — already states the one real constraint. The
8-step numbering doesn't add safety on top of it; it adds the appearance of a script that must
be followed verbatim, which is exactly the over-specification the architecture memo's point 2
warns is now a correctness bug rather than harmless scaffolding. Being honest about this: **most
of the phase order is incidental sequencing**, not a safety property, and the restructured
SKILL.md should say so by stating the invariant once and letting phase 2-before-7 fall out of
it, rather than asserting an 8-way ordering claim only one link of which is true.

## Decision D2 — the memory phase reshapes around harness-native auto-memory, keeps one fallback

Per the architecture memo point 5, the harness now supplies the memory directory path, the
`<slug>` derivation, the frontmatter schema, and the `MEMORY.md` index convention natively. The
skill's phase 3 currently re-specifies all four (SKILL.md lines 72–78) — pure duplication of
context the model already has, and it will drift the next time the harness's own convention
changes, since nothing keeps a plugin's copy of that convention in sync.

What phase 3 does *not* duplicate, and should keep, is the one instruction that isn't
harness-native: "read an existing file in the project's `memory/` dir first and copy its exact
frontmatter shape" (line 72) — this is the graceful-degradation path for a project whose memory
store doesn't yet demonstrate the schema. Dropping the schema recital but keeping the
copy-an-existing-file fallback means the skill still knows what to do when the store is empty
without asserting the schema as if it owned it.

The phase's remaining unique value, then, is reconciliation: what did auto-memory *not* capture
that this session established, and what does the memory store say that's now wrong given what's
on disk. That's a judgment task the harness doesn't perform on its own — auto-memory saves
*something*, but it has no mechanism for noticing that an existing file has gone stale. This is
the part of phase 3 worth keeping, and it's smaller than what it replaces.

**Risk:** if a project's harness build predates auto-memory, or auto-memory hasn't fired yet in
a given session, reconciliation against an empty `MEMORY.md` degrades to "propose saving
everything new" — which is the same behavior the old phase 3 had for a first-ever fact. No
regression, but worth stating explicitly in the spec (`No existing memory file to copy from`
scenario) rather than leaving it implicit.

## Decision D3 — the `references/` split risks becoming a reference nobody reads

The architecture memo names this directly in its closing verification section: "the failure
mode of a router+references split is a reference that never gets read, which a diff cannot
reveal." `project-scope` already has this bug in nominal form — its `references/*.md` content
is duplicated into the parent rather than being the sole home of the mechanics, so the split
does nothing. This proposal is explicit about not repeating that: task 2.2 requires grepping the
finished SKILL.md against every reference file to confirm no mechanic lives in both places, and
task 2.3 requires SKILL.md to name concretely *when* to read a given reference rather than a
generic "see references/" pointer.

That still doesn't guarantee the reference is consulted in practice — a router can name a
reference and the model can still reconstruct the mechanic from training-time familiarity with
similar checklists instead of reading the file, producing behavior that looks right until an
edge case the reference specifically covers (e.g. "remove the worktree **and** its
corresponding Claude Code project dir," a repo-specific rule with no generic equivalent) gets
silently skipped. That's why `tasks.md` 9.3 requires the end-to-end verification run to
deliberately exercise a reference-only mechanic and check it was actually applied, not just to
read the diff and assume the split works. A structural review of `SKILL.md` and `references/`
cannot substitute for that run.

## Open questions / non-goals

- **`description`/frontmatter trimming is out of scope** — tracked separately as
  `trim-skill-metadata` (memo P2). This proposal doesn't touch the always-on cost of the skill's
  frontmatter, only the always-loaded body.
- **Whether Orient (phase 1) should *always* run via a subagent is left to judgment**, not
  mandated. Session size and how noisy the read would be vary; hard-coding "always delegate"
  would reintroduce the same over-specification this proposal removes elsewhere (see `tasks.md`
  7.2).
- **No new external state, no hook changes.** `plugin.json` gets a version bump only;
  install⇄uninstall symmetry is unaffected — `/plugin uninstall` remains the complete revert,
  same as before this change.
