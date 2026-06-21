# plugin-best-practice-audit Specification

## Purpose
TBD - created by archiving change audit-plugin-best-practices. Update Purpose after archive.
## Requirements
### Requirement: Rubric derived from cross-checked authoritative sources

The audit SHALL derive its conformance rubric from the bundled `plugin-dev` skill set
and `plugin-validator` agent as the primary authority, validated against Anthropic's
official plugin and marketplace documentation. Every rubric item SHALL cite at least one
source. Where the primary source and the official documentation conflict, or one is
silent, the rubric SHALL record which source governs and the rationale.

#### Scenario: Every rubric item is sourced

- **WHEN** the rubric is produced
- **THEN** each item cites at least one authoritative source (a named `plugin-dev` skill,
  the `plugin-validator` agent, or a specific official doc section)

#### Scenario: Conflicts between sources are resolved explicitly

- **WHEN** the `plugin-dev` guidance and the official documentation disagree on an item,
  or only one addresses it
- **THEN** the rubric records the resolution (which source governs) and a one-line rationale

### Requirement: Rubric covers all plugin component dimensions

The rubric SHALL include items spanning every component dimension present in this
marketplace: marketplace registration, the plugin manifest, hooks, commands, skills,
agents, MCP integration, documentation/README, install⇄uninstall symmetry, naming and
directory-structure conventions, and machine validation.

#### Scenario: Each used component type has rubric coverage

- **WHEN** any plugin in the marketplace uses a component type (hook, command, skill,
  agent, or MCP server)
- **THEN** the rubric contains at least one item assessing that component type

### Requirement: Every plugin assessed against every applicable rubric item

The audit SHALL assess all seven plugins (`voice-notify`, `statusline`, `git-guard`,
`shell-guard`, `rtk-hook`, `session-finalise`, `project-scope`) plus the top-level
`marketplace.json`. Each applicable (plugin, rubric item) pair SHALL receive a verdict of
`pass`, `gap`, or `not-applicable`. Every `gap` SHALL carry file:line evidence and a
severity; every `not-applicable` SHALL carry a reason.

#### Scenario: Complete coverage matrix

- **WHEN** the audit completes
- **THEN** every plugin has a recorded verdict for every rubric item that applies to it

#### Scenario: Gaps are evidenced and severity-rated

- **WHEN** a verdict is `gap`
- **THEN** it includes file:line evidence and a severity rating

#### Scenario: Not-applicable verdicts are justified

- **WHEN** a rubric item is marked `not-applicable` for a plugin
- **THEN** a reason is recorded explaining why the item does not apply

### Requirement: Machine validation is run and recorded per plugin

The audit SHALL run `claude plugins validate` against each plugin and record its pass/fail
result as evidence alongside the manual rubric verdicts.

#### Scenario: Validator output captured

- **WHEN** a plugin is audited
- **THEN** the result of `claude plugins validate` for that plugin is captured in the report

### Requirement: Gap report triages findings without modifying plugins

The audit SHALL produce a single durable gap-report document that groups findings by
severity and proposes discrete follow-up changes to close them. The audit SHALL NOT modify
any plugin manifest, script, command, skill, README, or the `marketplace.json` entries.

#### Scenario: Findings triaged into follow-up work

- **WHEN** the gap report is produced
- **THEN** gaps are grouped by severity and each cluster names a proposed follow-up change

#### Scenario: No plugin files mutated

- **WHEN** the audit runs to completion
- **THEN** no file under `plugins/` and no `marketplace.json` entry has been modified

