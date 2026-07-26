## Why

Two Anthropic posts reset the assumptions `project-scope` was written under (see the
approved architecture memo, `~/.claude/plans/how-would-you-improve-nested-cookie.md`):

- **A field guide to Claude Fable**: *"If you are too specific, Claude will follow your
  instructions even when a pivot may be more appropriate."* A hard-coded constant that was
  harmless scaffolding on a weaker model now actively suppresses better judgment on a
  stronger one.
- **The new rules of context engineering**: Anthropic removed 80%+ of Claude Code's own
  system prompt with no measurable loss — prescriptive rules → judgment framing, upfront
  loading → progressive disclosure. Named anti-patterns include defensive guardrails,
  exhaustive documentation, and repeated instructions across context layers.

`project-scope` is the marketplace's worst offender against both. Verified directly against
the source:

- `plugins/project-scope/skills/project-scope/SKILL.md` is 266 lines / 21,985 bytes
  (`wc -l -w -c`) — confirms the memo's "266-line / 21.5 KB monolith" figure.
- `references/mechanism.md` (46 lines) and `references/phase3-menu.md` (27 lines) exist, but
  SKILL.md still restates their content instead of only pointing at it — the progressive
  disclosure is nominal. Two concrete instances of the same fact stated in both places:
  - The `~64 KB` Bash output cap and the jq failure string `parse error: Unfinished string
    at EOF` appear both in SKILL.md's `## Red Flags — STOP` list (line 264: "exceeds the
    ~64 KB output cap, arrives truncated, and corrupts jq") and in
    `references/mechanism.md:33` ("That far exceeds the agent's Bash output cap (~64 KB)...
    corrupts any downstream `jq` (`parse error: Unfinished string at EOF`)").
  - The four budget options appear both in SKILL.md line 178 ("Choose: 1% / 2% / 3% / 5%")
    and in `references/phase3-menu.md`'s Q4 row (line 11: "1% — leanest (default)", "2% —
    balanced", "3% — generous", "5% — maximum").
  - This restructure is already tracked as an open item: `docs/plugin-audit.md:145` —
    *"`split-project-scope-skill` (optional) — move the Mechanism reference tables and the
    Phase-3 menu tables in `project-scope/SKILL.md` (3,996 words) into `references/` to get
    the always-loaded body under the 3,000-word guideline (SKILL-5)."*
- SKILL.md hard-codes six judgment-suppressing constants (each verified present — see
  **What Changes** below for exact line references), including a verbatim stopword list, a
  fixed top-15/top-10 candidate cap, fixed 1/2/3/5% budget options, and a 5-question
  overflow arbitration rule.
- SKILL.md's `## Red Flags — STOP` list (lines 256–266, six items) is the defensive-guardrail
  anti-pattern the second post names directly.
- The central ambiguity — what the user's theme actually means — is resolved by keyword
  matching against the stopword list (SKILL.md:94–121) and then arbitrated post-hoc by a
  5-question mega-menu (`references/phase3-menu.md:27`), the inverse of the field guide's
  prescription: ask about the ambiguity up front, one question at a time.

## What Changes

- **SKILL.md becomes a ~50-line router**: purpose, the consent invariant, the phase names,
  and pointers into `references/`. Nothing stays inlined that a reference file already
  holds.
- **`references/mechanism.md` becomes the sole home of CLI/cache/settings mechanics.**
  SKILL.md's "Mechanism reference (canonical)" section (lines 21–28) restates the two-
  paradigm classification and the three `.claude/settings.json` keys in prose immediately
  before pointing at this same file's tables — cut the restatement to the pointer.
- **`references/phase3-menu.md` becomes the sole home of the confirmation menu**, including
  the budget options SKILL.md currently repeats at line 178.
- **REMOVE six judgment-suppressing constants — each verified present in the source:**
  1. The verbatim stopword list (SKILL.md:98 — `the, and, for, to, of, in, with, a, an, by,
     on, at, or, is, this, that`, plus `all, things, etc`).
  2. The "avoid 2-letter substrings like `ai`" heuristic (SKILL.md:98).
  3. The top-15 marketplace survivor cap (SKILL.md:96, and the `.[:15]` slice at :110).
  4. The top-10-by-installs fallback (SKILL.md:119).
  5. The fixed 1%/2%/3%/5% budget options (SKILL.md:178; `references/phase3-menu.md:11`
     Q4 row) — replaced by judgment framing: state the context/precision trade-off, let the
     model propose a value, the user can always override.
  6. The 5-question overflow arbitration rule — "drop Q2 ... never Qci ... never Q4"
     (`references/phase3-menu.md:27`).
- **REPLACE the `## Red Flags — STOP` list (SKILL.md:256–266, six items) with one stated
  invariant**: project scope only; every install/uninstall/settings write is confirmed; on
  any edge case pick the conservative option.
- **Phase 1 inventory delegated to a subagent** with a defined structured return (see
  `design.md`). The ~330 KB / 1400-line `--json` stream, the ~64 KB Bash output cap, and the
  hard-coded jq failure string (all confirmed at `references/mechanism.md:33`) move out of
  the main session's context entirely — the subagent absorbs the noise and returns a small
  structured table.
- **Phase 3 ambiguity handling inverted.** Today: the theme is tokenized against the
  stopword list to pre-filter marketplace candidates (SKILL.md:94–121), and the central
  ambiguity is arbitrated after the fact by a 5-question mega-menu. New: a brief clarifying
  interview up front (one question at a time) about theme intent and the user's starting
  point, run before inventory, followed by a smaller confirmation menu after inventory. The
  existing empty-theme gate (SKILL.md:19, "If no theme is clear, ask once") generalizes into
  this interview rather than remaining a separate special case.
- **Phase 5 Verify becomes a checkable rubric.** Replace the current five-step prose
  checklist (SKILL.md:238–246) with a rubric: re-read `.claude/settings.json`, diff against
  the stated proposal, report mismatches.
- **No behaviour change.** Every apply-phase command (`claude plugins install|uninstall
  --scope project`, the `.claude/settings.json` keys and merge order in
  `references/mechanism.md`), every consent gate, and every "always keep"/conflict rule
  stays semantically identical. This restructures *how* the skill is instructed, not *what*
  it does.

**Explicitly out of scope:**

- The stale model-key lookup (`references/mechanism.md:40` — `claude-opus-4-7` /
  `claude-sonnet-4-6`) is a separate proposal, `fix-project-scope-model-keys`. This change
  restructures the surrounding prose in `references/mechanism.md` but does not touch the
  token-lookup logic itself. **Sequencing note:** both proposals edit `references/
  mechanism.md`; land one before the other and rebase to avoid a conflict — order is not
  prescribed here.
- Description/frontmatter trimming is the separate `trim-skill-metadata` proposal; SKILL.md's
  YAML frontmatter and `commands/project-scope.md`'s `description` field are untouched by
  this change.

## Capabilities

### Added Capabilities

- `project-scope-skill-structure` — the first formal spec for how the `project-scope`
  skill's *instructional structure* must behave: progressive disclosure with no duplication
  between SKILL.md and its references, judgment framing over fixed constants, ambiguity
  resolved by asking rather than by keyword heuristic, inventory isolated from the main
  session's context, the consent invariant, and behavioural equivalence with the skill as it
  exists today. No spec for this capability exists yet under `openspec/specs/`.

## Impact

- **`plugins/project-scope/skills/project-scope/SKILL.md`** — rewritten to a ~50-line
  router; six constants removed; `## Red Flags — STOP` replaced by one invariant statement;
  Phase 1 becomes a subagent dispatch; Phase 3 gains the up-front interview; Phase 5 becomes
  a rubric.
- **`plugins/project-scope/skills/project-scope/references/mechanism.md`** — absorbs the
  content SKILL.md no longer restates; gains a new section documenting the Phase 1 subagent
  return contract (structured/tabular content fits this file's existing role as the
  mechanics reference).
- **`plugins/project-scope/skills/project-scope/references/phase3-menu.md`** — absorbs the
  budget-options restatement from SKILL.md; the fixed overflow-arbitration rule is replaced
  by judgment guidance consistent with the smaller post-inventory confirmation menu.
- **`docs/plugin-audit.md:145`** — the tracked open item `split-project-scope-skill` is
  resolved by this change; the audit entry needs an update marking it done once implemented.
- **`plugins/project-scope/README.md`** — behavior-level content is expected to stay
  accurate, but line 25 ("If you don't give a theme, it asks for one before doing anything")
  should be reviewed once the up-front interview can span more than one question.
- **`CLAUDE.md`** (repo root) — the `project-scope` row describes behavior, not internal
  skill structure; no change expected, but review for drift once implemented.
- **`plugins/project-scope/.claude-plugin/plugin.json`** — version bump and a
  `CHANGELOG.md` entry at implementation time (no behavior change, but the skill body is
  substantially rewritten).
- **No change** to `plugins/project-scope/commands/project-scope.md` (out of scope, see
  `trim-skill-metadata`) and no change to the apply-phase CLI commands or
  `.claude/settings.json` schema — behaviour is required to be identical.
