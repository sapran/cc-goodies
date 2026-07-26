## ADDED Requirements

### Requirement: Dispatch cue names the delegated work

The subagent dispatch cue SHALL announce the purpose of the work being delegated, taken from
the dispatching tool call's `description`. The form SHALL scale with the size of the burst: a
single agent SHALL be named on its own; exactly two agents SHALL both be named; three or more
SHALL be announced as a count plus the first agent's purpose, so the utterance stays bounded
however large the fan-out. When no description can be resolved, the plugin SHALL fall back to
the existing anonymous dispatch cue rather than speaking a partial or empty phrase.

#### Scenario: Single agent is named

- **WHEN** one subagent is dispatched with description "Review script changes"
- **THEN** the dispatch cue names that purpose (e.g. "Handing off — review script changes")

#### Scenario: Two agents are both named

- **WHEN** two subagents are dispatched within the same debounce window
- **THEN** the dispatch cue names both purposes

#### Scenario: Large burst is counted, not enumerated

- **WHEN** five subagents are dispatched within the same debounce window
- **THEN** the cue announces the count and the first purpose only, and does not enumerate all
  five

#### Scenario: Unresolvable description falls back to the anonymous cue

- **WHEN** a subagent is dispatched but no description can be read from the payload
- **THEN** the existing anonymous subagent-working cue is spoken instead

### Requirement: Completion is voiced when the result returns to the parent

A subagent completion SHALL be voiced, naming the agent's purpose, at the point its result
becomes available to the parent session. For a **foreground** agent this SHALL be the
`PostToolUse` event on the dispatching tool, whose payload carries both the description and a
completed response. For a **background** agent this SHALL be `SubagentStop`, the first event
carrying both the agent's identity and its description. Each completed agent SHALL be voiced at
most once: the plugin SHALL determine which of the two events owns a given agent and stay silent
on the other. A `PostToolUse` that merely acknowledges an asynchronous launch SHALL NOT be
voiced as a completion.

#### Scenario: Foreground agent is voiced when its result returns

- **WHEN** a foreground subagent completes and `PostToolUse` reports a completed response
- **THEN** a completion cue naming that agent's purpose is spoken

#### Scenario: Background agent is voiced at its stop event

- **WHEN** a background subagent finishes and `SubagentStop` fires for it
- **THEN** a completion cue naming that agent's purpose is spoken

#### Scenario: Asynchronous launch acknowledgement is not a completion

- **WHEN** `PostToolUse` reports that a background agent was launched asynchronously
- **THEN** no completion cue is spoken for that event

#### Scenario: No agent is voiced twice

- **WHEN** both `SubagentStop` and `PostToolUse` are observed for the same agent
- **THEN** exactly one completion cue is spoken for that agent

### Requirement: Completion cue distinguishes success from failure

The completion cue SHALL differ audibly depending on whether the agent completed successfully
or did not. An agent whose result indicates failure, interruption, or an absent result SHALL be
announced with a phrase drawn from a pool distinct from the success pool, so the two outcomes
are distinguishable by ear without the user reading the transcript.

#### Scenario: Successful completion

- **WHEN** an agent completes with a successful result
- **THEN** the cue is drawn from the success pool (e.g. "Review script changes — done")

#### Scenario: Failed or interrupted completion

- **WHEN** an agent's result indicates failure or interruption
- **THEN** the cue is drawn from the distinct failure pool, not the success pool

### Requirement: Name cap bounds per-agent chatter

Individual completion cues SHALL be spoken only while the number of in-flight subagents is at or
below a configurable cap (`CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP`, default 3). While more than the
cap are in flight, individual completion cues SHALL be suppressed, and the plugin SHALL record
that naming was withheld for the current batch so the drain roll-up can cover it.

#### Scenario: Small fan-out names each completion

- **WHEN** three subagents are in flight and one finishes
- **THEN** its completion cue is spoken

#### Scenario: Large fan-out suppresses individual cues

- **WHEN** six subagents are in flight and one finishes
- **THEN** no completion cue is spoken for it, and the batch is marked as having suppressed
  naming

#### Scenario: Cap is configurable

- **WHEN** `CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP` is set to a different positive integer
- **THEN** that value governs the threshold instead of the default

### Requirement: Drain roll-up announces the batch finishing

When the in-flight subagent count reaches zero, the plugin SHALL speak a single roll-up cue
announcing that the delegated work is back — but only when something about the batch was left
unsaid: either a waiting cue was spoken during the turn, or the name cap suppressed individual
completion cues. When every agent in the batch was named individually, no roll-up SHALL be
spoken, because the final individual cue already served as the all-clear. The roll-up SHALL be
drawn from a pool distinct from the turn-end sign-off pools, so it never sounds like the session
finishing.

#### Scenario: Roll-up follows a waiting cue

- **WHEN** a waiting cue was spoken at a turn boundary and the last in-flight agent later
  finishes
- **THEN** a roll-up cue announcing that the helpers are back is spoken

#### Scenario: Roll-up covers a capped fan-out

- **WHEN** a fan-out larger than the name cap drains to zero without any waiting cue having been
  spoken
- **THEN** a roll-up cue is spoken, because individual naming had been suppressed

#### Scenario: Fully named batch gets no roll-up

- **WHEN** a batch within the name cap drains to zero and every completion was named
- **THEN** no roll-up cue is spoken

#### Scenario: Roll-up is not a sign-off

- **WHEN** the roll-up is spoken
- **THEN** its core comes from the roll-up pool, not the turn-end sign-off pool

### Requirement: Agent purpose resolution degrades through a fallback chain

The plugin SHALL resolve a finishing agent's purpose by trying, in order: the agent's own entry
in the harness-provided in-flight task list (matched on the agent's identifier), then an
ephemeral per-agent record written when the agent was dispatched, then the agent's type name,
and finally an anonymous phrase. Each step SHALL be optional, so a payload that omits a field —
including any Claude Code version that does not provide the in-flight task list at all — SHALL
degrade to a less specific cue rather than to silence or an error.

#### Scenario: Purpose read from the in-flight task list

- **WHEN** a background agent finishes and its own entry is present in the payload's in-flight
  task list
- **THEN** the description from that entry is used as the spoken purpose

#### Scenario: Purpose read from the dispatch record

- **WHEN** the agent's entry is absent from the in-flight task list but a dispatch record exists
  for its identifier
- **THEN** the description from that record is used

#### Scenario: Falls back to the agent type

- **WHEN** neither the task-list entry nor the dispatch record yields a description but the
  agent's type is known
- **THEN** the cue names the agent type instead of a purpose

#### Scenario: Falls back to an anonymous cue

- **WHEN** no description and no agent type can be resolved
- **THEN** an anonymous completion cue is spoken and no error occurs

### Requirement: Model-authored descriptions are sanitised before being spoken

An agent description is untrusted, model-authored free text and SHALL be sanitised before it
reaches the speech engine. The plugin SHALL strip control characters, collapse runs of
whitespace, and truncate the result to `CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX` characters (default
approximately 60) at a word boundary. The description SHALL be passed as a single quoted
argument to the speech engine and SHALL NEVER be interpolated into a command string, and any
speech-engine command syntax embedded in it SHALL be neutralised so it cannot be interpreted as
a directive.

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

### Requirement: Concurrent cues are serialised

Because several agents can finish simultaneously, the plugin SHALL serialise spoken cues so two
cues never overlap and render each other unintelligible. Serialisation SHALL use ephemeral
create-only state so concurrent asynchronous hooks never perform a read-modify-write. A cue that
cannot acquire the right to speak within a short bounded wait SHALL be dropped rather than
queued, so a burst never produces a backlog of stale cues. Serialisation state SHALL be
self-healing: a holder that never releases SHALL be reclaimed after a bounded interval rather
than silencing the plugin permanently.

#### Scenario: Simultaneous completions do not overlap

- **WHEN** two agents finish at the same moment and both would speak
- **THEN** the cues are spoken one after the other, not concurrently

#### Scenario: Contended cue is dropped, not queued

- **WHEN** a cue cannot acquire the right to speak within the bounded wait
- **THEN** that cue is dropped and no backlog accumulates

#### Scenario: Abandoned serialisation state is reclaimed

- **WHEN** serialisation state is left behind by a process that never released it
- **THEN** it is reclaimed after a bounded interval and later cues are spoken normally

### Requirement: Agent-identity configuration is env-var only and degrades cleanly

All new behaviour SHALL be governed by environment variables following the existing precedence
(env var → built-in default), introducing no configuration file and writing nothing outside the
system temp directory and the plugin's own directory. Setting
`CLAUDE_VOICE_NOTIFY_AGENT_NAMES=off` SHALL disable naming entirely and restore the previous
anonymous dispatch cue and silent completions. The existing global mute, subagent mute,
non-macOS no-op, and missing-`jq` fallback SHALL all continue to apply, with a missing `jq`
degrading to the anonymous cues rather than erroring. Non-numeric or empty values for the
numeric knobs SHALL fall back to their defaults.

#### Scenario: Naming can be turned off

- **WHEN** `CLAUDE_VOICE_NOTIFY_AGENT_NAMES=off` is set
- **THEN** dispatch cues are anonymous, no completion cues or roll-ups are spoken, and the
  waiting cue and sign-off behave as before

#### Scenario: Subagent mute still disables the whole path

- **WHEN** `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` is set
- **THEN** no dispatch, completion, or roll-up cue is spoken and no agent state is recorded

#### Scenario: Missing jq degrades to anonymous cues

- **WHEN** `jq` is unavailable
- **THEN** descriptions cannot be read, anonymous cues are spoken, and no error occurs

#### Scenario: Non-macOS stays a no-op

- **WHEN** the speech command is unavailable
- **THEN** every new event exits cleanly without speaking or erroring

#### Scenario: Invalid numeric configuration falls back to defaults

- **WHEN** a numeric knob is set to an empty or non-numeric value
- **THEN** the built-in default is used and the run completes without error
