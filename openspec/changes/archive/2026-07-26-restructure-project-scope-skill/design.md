## Context

`project-scope` is a 266-line, single-file SKILL.md plus two `references/*.md` files that,
on inspection, are not the sole home of anything — SKILL.md restates their content before
pointing at them (see `proposal.md`'s **Why** for the two verified duplicate-fact
instances). This restructure has no behavioural target: every command, key, and consent
gate must produce the same effect after the change as before. The only thing moving is
*how the skill is instructed to reach that effect*, which makes the design problem almost
entirely about **where content lives** and **what a subagent is allowed to summarize away**.

## Decision D1 — over-specification is now a correctness issue, not a token tax

The field guide's operative claim: *"If you are too specific, Claude will follow your
instructions even when a pivot may be more appropriate."* Every constant this change removes
was originally scaffolding for a weaker model that needed a concrete number to anchor on.
Under that framing, "top 15" was a *default*, expected to be overridden by judgment when a
theme's natural candidate set is 6 or 40. Verified against the source, none of the six
constants read as defaults — they read as instructions (`.[:15]` is a hard slice, not a
suggestion; "drop Q2, never Qci, never Q4" is an algorithm, not a heuristic). A more capable
model executes an instruction literally, including when it's wrong for the case at hand — a
theme with 3 genuinely relevant marketplace plugins gets padded to fill the 15-slot cap
mentally, or a theme with 25 legitimate candidates gets silently truncated. The fix is not
"remove the number" — it's replacing the instruction with the *judgment call it was
standing in for* ("there is usually a natural cut well under 20" is a prior, not a rule).

## Decision D2 — the router/reference split boundary

Two content classes, one rule: **content that is genuinely reusable mechanism (a table, a
command, a schema, a data-source contract) lives in `references/` and is pointed at, never
restated. Content that is genuinely single-use narration (why this phase exists, what
question to ask next) stays in the router, because a reference file for a two-sentence
transition adds a hop with no reuse to justify it.**

Applied to the split at hand:

- `references/mechanism.md` — the two-paradigm table, the `.claude/settings.json` key
  table, the catalog-cache shape/path, the Bash-output-cap fact, and (new) the Phase 1
  subagent return contract. All reusable across phases (Phase 1 reads the cache shape,
  Phase 4 reads the settings keys, Phase 5 re-reads the same file to verify) — reused, so it
  belongs in one place, referenced by all.
- `references/phase3-menu.md` — the question/option tables. Reusable in the sense that both
  the up-front interview and the post-inventory confirmation draw from the same option
  vocabulary (budget tiers, bucket names) — stays a reference.
- SKILL.md (router) — the phase list, the consent invariant, and the up-front interview's
  *prompt* ("ask what the theme means and where the user is starting from, one question at a
  time") stay inline. There is nothing to reuse: it is asked exactly once per run, and its
  content is a instruction to exercise judgment, not a table to look up.

The router's ~50-line budget is a consequence of this rule, not a target hit by trimming
prose — if the split is done correctly, what remains in SKILL.md is short because narration
is short; padding it back up to hit a line count would reintroduce the anti-pattern.

## Decision D3 — the Phase 1 subagent return contract

Phase 1 today runs three tiers of inventory inline: currently-active (CLI listings, Desktop
config, `CLAUDE.md`, `settings.json`), installed-but-disabled (a catalog-cache `jq` query per
plugin, with token/category data), and available-in-marketplace (a keyword-filtered,
sorted, sliced catalog-cache query). None of the intermediate output — raw CLI listings, the
full disabled-plugin catalog rows, the pre-slice marketplace matches — is useful to the main
session once Phase 2's classification is done; only the classified result matters. That is
the shape of subagent-delegable work: bulk read, produce a small structured summary, discard
the rest.

**Contract** (documented in full in `references/mechanism.md`, not restated in SKILL.md):
the subagent receives the theme (post-interview) and the refreshed catalog-cache path, and
returns one row per candidate resource across all three tiers:

| Field | Meaning |
|---|---|
| `tier` | `1A` (active) / `1B` (installed-disabled) / `1C` (marketplace-available) |
| `surface` | `plugin` / `skill` / `mcp` |
| `id` | plugin id (`name@marketplace`), skill name, or MCP `serverName` |
| `state` | `active` / `disabled` / `available` |
| `description` | one-line, from the catalog entry or manifest |
| `always_on_tokens` | from `.tokens["<model>"].always_on` where resolvable |
| `unique_installs` | marketplace tier only |
| `bundles_mcp` | boolean — plugin ships its own MCP server |
| `category` | catalog category, if present |

The subagent does **not** classify keep/remove/install/skip — that judgment call (Phase 2)
stays in the main session, because it depends on the theme and the conflict rules
(global-CLAUDE.md mandates, "always keep" list) that are the main session's responsibility
to apply consistently. The subagent's job ends at "here is what exists," not "here is what
to do about it" — narrowing scope this way keeps the contract stable even as Phase 2's
judgment logic changes independently.

This directly retires the memo's cited failure mode: the ~330 KB / 1400-line `--json` stream
and the ~64 KB Bash-output cap are a subagent's problem to manage internally (it already has
to, since the constraint is architectural, not skill-specific); the main session never sees
either, and the jq-parse-error symptom this file currently warns about stops being something
the main session needs to recognize.

## Decision D4 — the known failure mode: a reference that never gets read

A router-plus-references split has one failure mode a diff review cannot catch: SKILL.md
correctly points at `references/mechanism.md` for the settings-key table, the file review
confirms the table is there and correct — but nothing confirms the skill *actually opens the
file* mid-run rather than proceeding from a stale or half-remembered notion of what it
contains. The old monolithic SKILL.md could not fail this way (everything was already
inline); the new structure can, silently, and a text diff of the change is blind to it,
because the failure is a *runtime* property (did the read happen) not a *content* property
(is the content correct).

This is why `tasks.md` requires an end-to-end run in a scratch project, not just a read-
through of the restructured files: the only way to confirm the reference actually gets read
is to watch the skill produce output that could only be correct if it had read the file (the
exact settings keys, the exact command forms, the exact budget-tier options) and to watch it
fail closed rather than confidently improvise if a reference were somehow unreachable.

## Non-goals

- No change to the apply-phase CLI commands, the `.claude/settings.json` schema, the
  conflict/always-keep rules, or the model-key token lookup (see `proposal.md`'s
  **Explicitly out of scope**).
- No new configuration surface. This is a content restructure; nothing here introduces an
  env var, a conf file, or a new dependency.
- No change to the skill's `description` frontmatter or the command's `description` field
  (`trim-skill-metadata`'s scope).
