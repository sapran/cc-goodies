## MODIFIED Requirements

### Requirement: Model-authored descriptions are sanitised before being spoken

A description written by the model is untrusted free text and SHALL be sanitised before it
reaches the speech engine. This applies to every such description the plugin speaks — the
description of a delegated agent and the description of a shell command alike — so a single
sanitising path governs all model-authored speech. The plugin SHALL strip control characters,
collapse runs of whitespace, and truncate the result to `CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX`
characters (default approximately 60) at a word boundary. The description SHALL be passed as a
single quoted argument to the speech engine and SHALL NEVER be interpolated into a command
string, and any speech-engine command syntax embedded in it SHALL be neutralised so it cannot be
interpreted as a directive.

#### Scenario: Long description is truncated

- **WHEN** a description far exceeds the configured maximum length
- **THEN** the spoken purpose is truncated at a word boundary within that maximum

#### Scenario: Control characters and newlines are removed

- **WHEN** a description contains newlines, tabs, or control characters
- **THEN** the spoken purpose contains none of them and remains a single utterance

#### Scenario: Embedded speech directives are neutralised

- **WHEN** a description contains speech-engine command syntax
- **THEN** it is not interpreted as a directive by the speech engine

#### Scenario: Shell metacharacters are inert

- **WHEN** a description contains shell metacharacters or quotes
- **THEN** they are spoken or dropped as text and no shell expansion or command execution occurs

#### Scenario: A command description is sanitised identically

- **WHEN** a shell command's description contains control characters, speech-engine directive
  syntax, or shell metacharacters
- **THEN** it is sanitised, truncated and quoted under exactly the same rules as an agent
  description, with no separate or weaker path
