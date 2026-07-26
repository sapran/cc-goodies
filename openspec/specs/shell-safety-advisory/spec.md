# shell-safety-advisory Specification

## Purpose
TBD - created by archiving change trim-shell-safety-rules. Update Purpose after archive.
## Requirements
### Requirement: Advisory rule file scoped to system-specific facts

The advisory rule file (`rules/shell-safety.md`) SHALL carry only facts about what
`shell-guard` and `git-guard`'s pattern matching cannot see or do — hook blind spots
(encoding, indirection), hook-input semantics (e.g. `.cwd` resolution), and workflow
affordances the guards expose (the `!`-paste override) — not general shell or security
hygiene that a capable model already applies by default. General practice that
duplicates default model behaviour, behaviour the guards already enforce, or guidance
already covered by the user's own private rules SHALL NOT be restated in this file.

#### Scenario: New advisory text is proposed

- **WHEN** new text is proposed for addition to `rules/shell-safety.md`
- **THEN** it is accepted only if it states a fact about this system's hooks — a
  detection blind spot, hook-input semantics, or a workflow affordance the hooks
  expose — that a capable model cannot infer on its own

#### Scenario: Proposed text duplicates general hygiene or the user's own rules

- **WHEN** proposed advisory text restates guidance already covered by default
  Claude-5-generation model behaviour, by `shell-guard`/`git-guard` enforcement, or by
  the user's own private `~/.claude/rules/security.md`
- **THEN** the text is dropped from `rules/shell-safety.md` rather than restated

### Requirement: Advisory content stays in sync with what the guards actually catch

Any document that describes the advisory file's contents — `docs/shell-safety.md`'s
layered-defence table and `plugins/shell-guard/README.md`'s "Advisory companion"
section — SHALL accurately reflect what `rules/shell-safety.md` currently states. A
change that adds, removes, or reframes an item in `rules/shell-safety.md` SHALL update
every cross-reference elsewhere in the repo that paraphrases or restates that item, in
the same change.

#### Scenario: An item is removed from the advisory file

- **WHEN** an item is removed from `rules/shell-safety.md`
- **THEN** `docs/shell-safety.md` and `plugins/shell-guard/README.md` are checked for a
  restatement of that item, and updated so neither describes content the file no
  longer carries

#### Scenario: A new system fact is added to the advisory file

- **WHEN** an item describing a guard's blind spot, hook-input behaviour, or workflow
  affordance is added to `rules/shell-safety.md`
- **THEN** the fact is grounded in the guard's actual implementation (its script, or
  its own README/docs) before being asserted, not stated on assumption

### Requirement: Trimming advisory prose SHALL NOT weaken guard enforcement

Changes to `rules/shell-safety.md` operate on advisory prose only. Such a change SHALL
NOT remove, weaken, narrow, or otherwise alter the detection logic, block list, or
fail-open/fail-closed behaviour of `shell-guard` or `git-guard`. The reasoning that
motivates trimming this file — that a capable model no longer needs prompt-resident
guardrail text telling it not to do obviously dumb things — applies to prose told to
the model. It SHALL NOT be read as licence to thin the guards themselves: `shell-guard`
and `git-guard` are enforcement defending against the tail (a mis-parsed path, a
malformed variable, an injected instruction), not the median, and a smarter model is an
argument for a smaller guard, never for no guard.

#### Scenario: A guard-logic change is justified by this change's rationale

- **WHEN** a future change proposes removing or narrowing a `shell-guard` or
  `git-guard` detection rule and cites this change, or "the model no longer needs this
  guardrail," as justification
- **THEN** that proposal is out of scope for advisory-prose trimming and SHALL be
  evaluated on its own under the guards' own risk model (accidents vs. deliberate
  evasion, plan mode as the backstop) — this change does not license it

#### Scenario: This change's diff is reviewed

- **WHEN** a change under the `shell-safety-advisory` capability is reviewed
- **THEN** the diff touches only advisory/documentation files (`rules/shell-safety.md`,
  `docs/shell-safety.md`, plugin READMEs) and never
  `plugins/shell-guard/scripts/*.sh`, `plugins/git-guard/scripts/*.sh`, or either
  plugin's test suite

