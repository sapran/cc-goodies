## ADDED Requirements

### Requirement: Progressive disclosure with no duplication between router and references

SKILL.md SHALL function as a router: purpose, the consent invariant, the phase names, and
pointers into `references/`. Any mechanism, table, command form, or option list that a
`references/*.md` file documents SHALL be stated in exactly one place. When SKILL.md needs
that content during a phase, it SHALL point at the reference rather than restate it.

#### Scenario: A fact lives in exactly one file

- **WHEN** a mechanism, table, or option list documented in a `references/*.md` file is
  needed by a workflow phase
- **THEN** SKILL.md contains a pointer to that reference and does not restate the content
  inline

#### Scenario: Reference content changes without touching the router

- **WHEN** a command form, key name, or option list in a `references/*.md` file is updated
- **THEN** SKILL.md requires no corresponding edit, because it held no duplicate of that
  content

### Requirement: Judgment framing replaces fixed constants

The skill SHALL express selection, sizing, and arbitration decisions as judgment calls
informed by a stated rationale, not as hard-coded constants that override the model's
assessment of the case at hand. This applies to candidate-set sizing, fallback behaviour,
context-budget choices, and multi-question arbitration.

#### Scenario: Candidate-set sizing follows judgment, not a fixed cap

- **WHEN** the skill surfaces marketplace or installed-but-disabled candidates for a theme
- **THEN** it selects a set sized to the theme's actual relevance rather than truncating or
  padding to a fixed count, and states the rationale for the set size it chose

#### Scenario: Context-budget choice is proposed, not selected from a fixed list

- **WHEN** the skill proposes a `skillListingBudgetFraction` value
- **THEN** it states the context/precision trade-off and proposes a value the user can
  override with any valid fraction, rather than presenting only a fixed set of options

#### Scenario: Menu arbitration follows judgment, not a fixed drop order

- **WHEN** the confirmation menu risks exceeding a reasonable number of questions in one
  turn
- **THEN** the skill decides what to ask now versus confirm implicitly based on risk and
  reversibility of each bucket, never by a fixed, hard-coded drop order

### Requirement: Ambiguity resolved by asking, not by keyword heuristic

The skill SHALL resolve ambiguity about what the user's stated theme means through a direct,
up-front clarifying interview — one question at a time — before running inventory, rather
than through keyword/stopword matching against the theme text. The interview SHALL also
establish the user's starting point (what is already in place, what they are trying to
add versus remove).

#### Scenario: Theme intent is clarified before inventory

- **WHEN** the user's stated theme is ambiguous or under-specified
- **THEN** the skill asks a direct clarifying question before running Phase 1 inventory,
  rather than proceeding on a keyword-matched interpretation

#### Scenario: No keyword/stopword filtering of the theme

- **WHEN** the skill determines which marketplace or installed candidates are relevant to
  the theme
- **THEN** the determination is made by the model's judgment against the clarified theme,
  not by tokenizing the theme and matching against a stopword list

#### Scenario: A clear theme skips the interview

- **WHEN** the user's stated theme and starting point are already unambiguous
- **THEN** the skill proceeds directly to inventory without asking a clarifying question

### Requirement: Inventory isolated from the main session's context

Phase 1 inventory (currently-active, installed-but-disabled, and available-in-marketplace
tiers) SHALL run in a subagent that returns a small structured summary. The main session
SHALL NOT receive raw CLI listings, full catalog-cache query results, or the marketplace
`--json` stream; it SHALL receive only the structured return.

#### Scenario: Main session never sees the raw catalog stream

- **WHEN** Phase 1 inventory runs
- **THEN** the main session's context contains only the subagent's structured summary, not
  the raw `--json` stream, full CLI listings, or unfiltered catalog-cache query output

#### Scenario: Structured return carries what Phase 2 needs

- **WHEN** the subagent completes inventory
- **THEN** its return includes, per candidate, at minimum the tier, surface type, id,
  current state, description, and available token-cost data — sufficient for Phase 2's
  classification without a further read of raw sources

#### Scenario: Classification judgment stays in the main session

- **WHEN** keep/remove/install/skip decisions are made for an inventoried candidate
- **THEN** that classification is performed by the main session applying the theme and
  conflict rules, not delegated to the inventory subagent

### Requirement: Consent invariant preserved

Every plugin install, plugin uninstall, and `.claude/settings.json` write SHALL be confirmed
by the user before it is applied. This invariant SHALL hold regardless of how many
confirmation buckets are active in a given run, and SHALL be the single stated safety rule
replacing the current enumerated `## Red Flags — STOP` list.

#### Scenario: No write without confirmation

- **WHEN** the skill is about to install a plugin, uninstall a plugin, or write
  `.claude/settings.json`
- **THEN** it has already obtained explicit user confirmation for that specific bucket of
  changes

#### Scenario: Conservative default on edge cases

- **WHEN** the skill encounters an edge case not explicitly covered by its instructions
  (e.g. an ambiguous conflict, an unexpected menu-overflow shape)
- **THEN** it picks the more conservative option (fewer removals, fewer installs, asking
  rather than assuming) rather than proceeding on a guess

#### Scenario: Project scope only

- **WHEN** the skill applies any change
- **THEN** it writes only to the current project's scope (`--scope project`,
  `./.claude/settings.json`) and never to global or user-level configuration

### Requirement: Behavioural equivalence with the pre-restructure skill

For any given theme and user responses, the restructured skill SHALL produce the same
plugin install/uninstall operations, the same `.claude/settings.json` writes, and the same
verification outcomes as the skill produced before this change. This is a restructure of how
the skill is instructed, not a change to what it does.

#### Scenario: Same inputs, same applied changes

- **WHEN** the restructured skill and the pre-restructure skill are run against the same
  project state, the same theme, and equivalent user answers
- **THEN** the resulting `enabledPlugins` state and `.claude/settings.json` contents are the
  same

#### Scenario: Verification still confirms settings and scope

- **WHEN** Phase 5 verification runs after the restructure
- **THEN** it still confirms `.claude/settings.json` is valid JSON, still confirms each
  approved plugin's project-scope state, and still reports which changes require a session
  restart
