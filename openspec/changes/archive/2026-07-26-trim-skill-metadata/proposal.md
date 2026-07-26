## Why

A skill's `description` frontmatter is always-on context: the harness loads it in every
session in every project where the plugin is installed, because it's what the model reads to
decide whether to auto-activate the skill. A command's `description` and a marketplace entry's
`description` are the same shape of always-loaded metadata — surfaced in the command listing
and the plugin catalog respectively — not content read only on demand.

Both `project-scope` and `session-finalise` currently spend that budget on capability prose
rather than trigger surface. Measured directly from the frontmatter in this repo:

| Surface | project-scope | session-finalise |
|---|---|---|
| `SKILL.md` `description` | 92 words / 685 chars | 76 words / 478 chars |
| `/<name>` command `description` | 233 chars / 32 words | 42 chars / 5 words |
| marketplace.json entry `description` | 248 chars / 32 words | 193 chars / 20 words |

`project-scope`'s `SKILL.md` description is two sentences: a trigger clause with four example
phrases ("scope this project to security work", "trim my plugins for this theme", "reduce
per-turn token cost here", "which tools should this project have?"), followed by a 44-word
mechanism sentence — "It investigates currently-active resources, installed-but-disabled
plugins, AND plugins available in registered marketplaces; proposes per-bucket changes with
explicit consent; applies plugin changes via `claude plugins install|uninstall --scope
project` and writes `.claude/settings.json` (including `skillListingBudgetFraction`). Project
scope only — never touches global config." That second sentence is a capability essay, not
activation surface — it explains *how* the skill works, which is exactly what
`plugins/project-scope/README.md` already opens with. `project-scope` is the plugin whose
entire stated purpose is cutting per-turn token cost, so it is paying, in every session, the
tax it exists to eliminate.

Two prior findings compound this and are worth closing in the same pass:
- The `align-plugins-to-audit` change (archived 2026-06-21) trimmed three over-length command
  descriptions under the `plugin-conformance` "Command descriptions stay within the length
  guideline" requirement (`statusline-install`, `statusline-uninstall`, `session-finalise`)
  but never touched `/project-scope`'s, which the audit itself flagged (`docs/plugin-audit.md`
  §4, CMD-2: "~220–230-char descriptions" on both alias commands) and which still sits at 233
  characters today — past the requirement's own ~60-char guideline, and past the one fix that
  was actually applied.
- `project-scope`'s marketplace entry, at 248 characters, exceeds the ~50–200 char guideline
  (`MAN-5`, `docs/plugin-audit.md` Appendix A) that seeded `plugin-conformance` in the first
  place; `session-finalise`'s, at 193 characters, sits inside it. Neither surface has ever had
  a `plugin-conformance` requirement of its own.

Anthropic's field guide and context-engineering posts (see
`~/.claude/plans/how-would-you-improve-nested-cookie.md`, cross-cutting point 7) name this
pattern directly: progressive disclosure — load context only when needed — and the named
anti-pattern of exhaustive documentation stated upfront. A description needs enough trigger
surface for reliable auto-activation and nothing more; the capability narrative belongs in the
README, which both plugins already carry near-verbatim (`plugins/project-scope/README.md` and
`plugins/session-finalise/README.md` both open with the same capability explanation their
`SKILL.md` descriptions restate).

The tension that has to be handled honestly: trimming a description too far breaks
auto-activation, and a broken trigger is a worse regression than the token cost it would have
saved — the failure is silent, not an error. This change requires that trigger coverage be
*preserved*, not merely shortened, and that the result is *verified* by exercising the
retained phrases in a live session, not assumed from re-reading the trimmed text.

## What Changes

- **`project-scope` `SKILL.md` description**: drop the mechanism sentence (what the skill
  investigates, how it applies changes, that it writes `.claude/settings.json`); keep the
  trigger clause and its four example phrases intact.
- **`session-finalise` `SKILL.md` description**: review against the same bar. Its second
  sentence ("It should also be used when about to stop with loose ends dangling: …") is itself
  additional trigger surface, not mechanism prose, so this is a lighter edit than
  project-scope's — trim only what doesn't serve activation, if anything doesn't.
- **`/project-scope` command description**: trim to the ~60-char guideline already stated in
  `plugin-conformance`, closing the gap the prior `align-plugins-to-audit` change left open.
- **`project-scope` and `session-finalise` marketplace entries**: bring `project-scope`'s
  within the ~50–200 char `MAN-5` guideline; leave `session-finalise`'s as-is unless review
  finds slack.
- **No README changes are anticipated** — both READMEs already carry the capability prose
  being removed from the descriptions; add to a README only if a trim would otherwise strand
  a fact present nowhere else.
- **Verification, not assumption**: after each description edit, exercise the skill's
  documented natural trigger phrases in a live session and confirm auto-activation still
  fires, and record the `always_on` token delta from
  `~/.claude/plugins/plugin-catalog-cache.json` before and after.

## Capabilities

### Modified Capabilities

- `plugin-conformance`: the skill-description requirement gains a content rule (trigger
  surface only, capability prose deferred to the README) plus a preserve-and-verify obligation
  for trigger coverage when a description is edited; the command-description requirement's
  scenario now also covers `/project-scope`, closing a gap the prior audit-alignment change
  left open; a new requirement extends the same length-and-content discipline to marketplace
  entry descriptions, which previously had no `plugin-conformance` requirement despite being
  sourced from the same audit (`MAN-5`).

This change modifies `plugin-conformance` rather than adding a capability. The fit is natural,
not a stretch: that capability already exists specifically to hold marketplace-wide
description conventions derived from the audit, and already contains the two adjacent
requirements this change extends ("Command descriptions stay within the length guideline",
"Plugin skills declare version and third-person descriptions") — both governing the exact
three artifact types (skill frontmatter, command frontmatter, and now marketplace entries)
this change touches. No other capability under `openspec/specs/` (`git-guard-push-target`,
`gpt-search-plugin`, `plugin-best-practice-audit`, the `statusline-*` and `voice-notify-*`
capabilities) is about description conventions in general; they are each scoped to one
plugin's behavior.

## Impact

- **Files**: `plugins/project-scope/skills/project-scope/SKILL.md` (frontmatter only),
  `plugins/session-finalise/skills/session-finalise/SKILL.md` (frontmatter only),
  `plugins/project-scope/commands/project-scope.md` (frontmatter `description`),
  `.claude-plugin/marketplace.json` (two entries), both plugins' `README.md` (only if a trim
  would strand information), both `plugin.json` versions (patch bump), marketplace
  `metadata.version` (patch bump), `CHANGELOG.md`.
- **No behavior change**: no logic, hook, or workflow-body edit; this is metadata-only. The
  risk is entirely in auto-activation reliability, which is why verification is a required
  task rather than an optional follow-up.
- **No new capability, no new plugin, no durable external state** — install⇄uninstall
  symmetry is unaffected.
