## MODIFIED Requirements

### Requirement: Plugin skills declare version and third-person descriptions

Every plugin `SKILL.md` SHALL declare a `version` in its frontmatter matching the plugin's
`plugin.json` version, and SHALL phrase its `description` in the third person ("This skill
should be used when…"). The description SHALL consist of the trigger phrases and activation
scenarios a model needs to decide whether to auto-activate the skill, and SHALL NOT restate
the skill's mechanism, implementation detail, or capability narrative — that content belongs
in the plugin's README, which is read on demand rather than loaded into every session. When a
description is edited to remove length or prose, every trigger phrase or activation scenario
it previously covered SHALL remain present (verbatim or in equivalent phrasing), and the edit
SHALL be verified by exercising the skill's natural trigger phrases in a live session and
confirming auto-activation still fires — not assumed from re-reading the trimmed text.

#### Scenario: Skill frontmatter carries version

- **WHEN** the `session-finalise` or `project-scope` `SKILL.md` is loaded
- **THEN** its frontmatter declares a `version` equal to the plugin's `plugin.json` version

#### Scenario: Third-person skill description

- **WHEN** the `session-finalise` or `project-scope` skill description is read
- **THEN** it is phrased in the third person and still lists its trigger phrases/scenarios

#### Scenario: Description carries trigger surface, not capability prose

- **WHEN** the `project-scope` or `session-finalise` `SKILL.md` description is read
- **THEN** it lists the phrases and scenarios that should activate the skill, and does not
  restate the mechanism or capability narrative the plugin's README already carries

#### Scenario: Trigger coverage preserved across an edit

- **WHEN** a skill's description is shortened to remove capability prose
- **THEN** the set of trigger phrases and activation scenarios it covers is unchanged from
  before the edit

#### Scenario: Activation verified, not assumed

- **WHEN** a skill description has been trimmed
- **THEN** the skill's auto-activation is exercised against its documented trigger phrases in
  a live session and confirmed to still fire, rather than inferred solely from re-reading the
  new text

### Requirement: Command descriptions stay within the length guideline

Every slash-command `description` SHALL be a verb-first phrase of roughly 60 characters or
fewer, with longer explanation moved into the command body, while remaining specific enough to
convey the command's purpose. It SHALL NOT restate mechanism or capability detail already
covered by the command body or the plugin's README — the description's only job is to let the
model and the user distinguish this command from others at a glance.

#### Scenario: Trimmed descriptions

- **WHEN** the `statusline-install`, `statusline-uninstall`, `session-finalise`, or
  `project-scope` command is loaded
- **THEN** its `description` is ≤ ~60 characters, verb-first, and still conveys purpose

#### Scenario: Alias command description defers to its skill

- **WHEN** a command's entire body delegates to a skill (e.g. `/project-scope`,
  `/session-finalise`)
- **THEN** its description states the command's purpose in one clause and does not duplicate
  the skill's own trigger phrases or mechanism narrative

## ADDED Requirements

### Requirement: Marketplace entry descriptions stay within the length guideline and defer capability detail to the README

Every `marketplace.json` plugin entry `description` SHALL stay within roughly 50–200
characters, explain the plugin's purpose in active voice, and SHALL NOT restate implementation
or mechanism detail that duplicates the plugin's README. The entry is loaded as part of the
always-on plugin catalog; the README is read on demand.

#### Scenario: Entry within the length guideline

- **WHEN** the `project-scope` or `session-finalise` marketplace entry is read
- **THEN** its `description` is within roughly 50–200 characters

#### Scenario: Entry states purpose, not mechanism

- **WHEN** a marketplace entry description is read
- **THEN** it conveys what the plugin does in one or two clauses and does not restate the
  step-by-step mechanism the plugin's README documents

#### Scenario: Consistent trim across surfaces

- **WHEN** a plugin's `SKILL.md` description, command description, and marketplace entry are
  compared
- **THEN** none of the three duplicates capability or mechanism prose that lives in the
  README, and each is sized to its own guideline (skill: trigger phrases and scenarios;
  command: ~60 characters; marketplace entry: ~50–200 characters)
