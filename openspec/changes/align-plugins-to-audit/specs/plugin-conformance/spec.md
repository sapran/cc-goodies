## ADDED Requirements

### Requirement: Destructive control commands disable model invocation

Every destructive or irreversible control command MUST declare `disable-model-invocation: true` in its frontmatter so the model cannot auto-invoke it via the SlashCommand tool; this applies to the `*-install` and `*-uninstall` commands, and manual user invocation MUST remain unaffected.

#### Scenario: Control command carries the guard

- **WHEN** a `statusline-install`, `statusline-uninstall`, `git-guard-uninstall`,
  `shell-guard-uninstall`, or `rtk-hook-uninstall` command file is loaded
- **THEN** its frontmatter contains `disable-model-invocation: true`

#### Scenario: Manual invocation still works

- **WHEN** the user types the control command's slash invocation
- **THEN** the command runs normally (the guard blocks only model auto-invocation)

### Requirement: Command descriptions stay within the length guideline

Every slash-command `description` SHALL be a verb-first phrase of roughly 60 characters or
fewer, with longer explanation moved into the command body, while remaining specific enough
to convey the command's purpose.

#### Scenario: Trimmed descriptions

- **WHEN** the `statusline-install`, `statusline-uninstall`, or `session-finalise` command
  is loaded
- **THEN** its `description` is ≤ ~60 characters, verb-first, and still conveys purpose

### Requirement: Plugin skills declare version and third-person descriptions

Every plugin `SKILL.md` SHALL declare a `version` in its frontmatter matching the plugin's
`plugin.json` version, and SHALL phrase its `description` in the third person ("This skill
should be used when…") while retaining its concrete trigger phrases and scenarios.

#### Scenario: Skill frontmatter carries version

- **WHEN** the `session-finalise` or `project-scope` `SKILL.md` is loaded
- **THEN** its frontmatter declares a `version` equal to the plugin's `plugin.json` version

#### Scenario: Third-person skill description

- **WHEN** the `session-finalise` or `project-scope` skill description is read
- **THEN** it is phrased in the third person and still lists its trigger phrases/scenarios

### Requirement: Hook handlers declare explicit timeouts

Every hook handler SHALL declare an explicit numeric `timeout`, including asynchronous
fire-and-forget hooks.

#### Scenario: voice-notify hooks have timeouts

- **WHEN** the `voice-notify` plugin manifest is loaded
- **THEN** each of its Notification and Stop hook handlers declares a numeric `timeout`

### Requirement: Skill bodies stay within the size guideline

A `SKILL.md` body SHALL stay under the ~3,000-word guideline, with detailed reference
material, quick-reference tables, and extensive examples moved into `references/` and
pointed to from `SKILL.md`; every referenced file SHALL exist.

#### Scenario: project-scope skill trimmed

- **WHEN** the `project-scope` `SKILL.md` is loaded after this change
- **THEN** its body is under ~3,000 words and references the externalized `references/`
  files, all of which exist on disk

### Requirement: Deliberate best-practice deviations are documented conventions

Where the marketplace deliberately deviates from a best-practice item, the deviation SHALL
be recorded as a convention in `CLAUDE.md` so it is an intentional, auditable choice rather
than silent drift.

#### Scenario: Documented exceptions present

- **WHEN** `CLAUDE.md` is read
- **THEN** it documents (a) alias commands omitting `allowed-tools` because execution lives
  in the delegated skill, (b) plugins shipping no per-plugin `LICENSE` because the repo-root
  `LICENSE` covers the monorepo, and (c) command files omitting HTML-comment maintainer
  blocks because the command body is itself the prompt
