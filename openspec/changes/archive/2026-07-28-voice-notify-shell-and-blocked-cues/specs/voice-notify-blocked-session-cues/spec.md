## ADDED Requirements

### Requirement: A turn ended by an API error is announced

When a turn ends because of an API error rather than normally, the harness fires a distinct
turn-failure event and does not fire the ordinary turn-end event. The plugin SHALL hook that
failure event and speak a **stalled** cue, so a session killed by a rate limit, an overload, an
authentication failure, or a billing problem does not sit abandoned in silence. The cue SHALL be
spoken regardless of the duration gate, because a turn that died is worth reporting however
briefly it ran.

#### Scenario: Stalled turn speaks

- **WHEN** a turn ends due to an API error
- **THEN** a stalled cue is spoken

#### Scenario: Stalled cue ignores the duration gate

- **WHEN** a turn ends due to an API error after running for less time than the quiet-on-quick-
  turns threshold
- **THEN** the stalled cue is still spoken

#### Scenario: No sign-off is spoken for a stalled turn

- **WHEN** a turn ends due to an API error
- **THEN** no turn-end sign-off is spoken for that turn, because the turn did not finish

### Requirement: The stalled cue names the cause

The stalled cue SHALL name the kind of failure that ended the turn where the payload identifies
one, so the user knows whether to wait, retry, or intervene. A rate limit, an overload, an
authentication failure, a billing problem and a request that exceeded the output limit are
distinguishable causes and SHALL be phrased distinguishably. An unrecognised or missing cause
SHALL fall back to a generic stalled phrase rather than being dropped.

#### Scenario: Rate limit is named

- **WHEN** the turn-failure payload identifies a rate limit
- **THEN** the spoken cue says so

#### Scenario: Authentication and billing failures are named

- **WHEN** the turn-failure payload identifies an authentication or billing failure
- **THEN** the spoken cue says so, distinctly from a transient overload

#### Scenario: Unknown cause falls back to a generic phrase

- **WHEN** the turn-failure payload carries no recognised cause, or `jq` is unavailable
- **THEN** a generic stalled cue is spoken rather than nothing

### Requirement: The stalled cue leaves no per-turn state behind

The turn-failure event SHALL perform the same per-turn cleanup the ordinary turn-end event
performs, so a turn that died does not leave state that misleads the next turn. In particular the
turn-start timestamp SHALL be consumed and any bookkeeping cleared exactly as at a normal turn
end.

#### Scenario: Turn timing state is cleared

- **WHEN** a turn ends due to an API error
- **THEN** the turn-start record is removed, so the next turn is timed from its own start

#### Scenario: Next turn behaves normally

- **WHEN** a new prompt follows a stalled turn
- **THEN** the ordinary duration gate and sign-off behaviour apply to it unchanged

### Requirement: An unanswered permission prompt is re-announced

A permission prompt is announced once when it appears; a user who missed that single cue is left
in silence while the session waits indefinitely. The plugin SHALL therefore arm a reminder when a
permission dialog is displayed and SHALL re-announce it every `CLAUDE_VOICE_NOTIFY_NAG_EVERY`
seconds (default approximately 60) while the prompt remains unresolved. The reminder SHALL name
the tool being requested where the payload provides it. Setting the interval to zero SHALL
disable reminders while leaving the original single announcement intact.

#### Scenario: Unanswered prompt is re-announced

- **WHEN** a permission prompt has been displayed and remains unresolved for longer than the
  configured interval
- **THEN** a reminder cue is spoken

#### Scenario: Reminder names the tool

- **WHEN** the reminder is spoken and the payload identified the requested tool
- **THEN** the cue names that tool

#### Scenario: Interval of zero disables reminders

- **WHEN** the reminder interval is configured as zero and a permission prompt is displayed
- **THEN** the original announcement is spoken and no reminder ever follows

#### Scenario: A prompt answered quickly is never re-announced

- **WHEN** a permission prompt is resolved before the configured interval elapses
- **THEN** no reminder is spoken

### Requirement: The reminder is disarmed when the prompt resolves

The reminder SHALL stop as soon as the permission prompt is resolved, by whichever route it
resolves. Approving the request causes the tool to run, so the tool's completion or failure event
carrying the same tool call identity SHALL disarm the reminder; denying it fires the permission
denial event, which SHALL likewise disarm it. A new user prompt SHALL also disarm every pending
reminder, because the user is demonstrably back at the keyboard.

#### Scenario: Approval disarms the reminder

- **WHEN** a permission prompt is approved and the tool call completes or fails
- **THEN** the reminder for that tool call is removed and no further reminder is spoken

#### Scenario: Denial disarms the reminder

- **WHEN** a permission prompt is denied
- **THEN** the reminder for that tool call is removed and no further reminder is spoken

#### Scenario: A new prompt disarms every reminder

- **WHEN** the user submits a new prompt
- **THEN** all pending permission reminders are removed

#### Scenario: Reminders are per prompt

- **WHEN** two permission prompts are pending and one is resolved
- **THEN** only the resolved one's reminder stops; the other continues until it too is resolved

### Requirement: Reminders are bounded and self-healing

Reminders SHALL be bounded so an unattended session does not speak indefinitely overnight. A
reminder SHALL stop after `CLAUDE_VOICE_NOTIFY_NAG_MAX` repeats (default approximately 5), and a
reminder record older than the configured TTL SHALL be pruned regardless. A reminder record left
behind by a killed process SHALL therefore never produce speech forever, and its presence SHALL
never block the plugin's other cues.

#### Scenario: Reminders stop after the configured maximum

- **WHEN** a permission prompt has been re-announced the configured maximum number of times and
  is still unresolved
- **THEN** no further reminder is spoken for it

#### Scenario: Stale reminder record is pruned

- **WHEN** a reminder record is older than the configured TTL
- **THEN** it is pruned and produces no further speech

#### Scenario: An orphaned record does not disturb other cues

- **WHEN** a reminder record remains after its prompt was resolved without a disarm event
- **THEN** the other cues behave normally and the record ages out

### Requirement: Reminders do not depend on the command path being enabled

The reminder is produced by the same elected watcher that produces the still-running command cue.
Because the two features are independently useful, arming a reminder SHALL elect a watcher when
none is running, independently of whether the command path is muted. Muting the command path
SHALL silence command cues only, never permission reminders.

#### Scenario: Reminders work with the command path muted

- **WHEN** the command mute is set and a permission prompt goes unanswered past the interval
- **THEN** the reminder is still spoken

#### Scenario: Arming a reminder elects a watcher

- **WHEN** a permission prompt is displayed while no watcher is running
- **THEN** a watcher is elected so the reminder can be produced

#### Scenario: The watcher exits when the last reminder resolves

- **WHEN** the last pending reminder is disarmed and no command is outstanding
- **THEN** the watcher exits

### Requirement: Distinct phrasing for the stalled and reminder states

The stalled cue and the permission reminder SHALL each be drawn from a phrase pool distinct from
the turn-end sign-off pools, the subagent pools, the command pools, and the first-announcement
attention pool, so neither is mistaken by ear for a normal turn end or for a fresh request. Each
SHALL be assembled through the existing composition (optional leading garnish joined to a core by
a brief prosody pause), the prosody pause SHALL never be voiced as literal text, and both SHALL
be serialised through the existing speech lock.

#### Scenario: Stalled cue is not a sign-off

- **WHEN** the stalled cue is spoken
- **THEN** its core is drawn from the stalled pool and not from the turn-end sign-off pool

#### Scenario: Reminder sounds like a reminder

- **WHEN** a permission reminder is spoken
- **THEN** its core conveys that this is a repeat of a request already made, distinct from the
  first announcement's phrasing

#### Scenario: Composition reused

- **WHEN** either cue is spoken with a garnish selected
- **THEN** the cue is `<garnish><pause><core>` with the pause inaudible as text, exactly as for
  the other cues

### Requirement: Blocked-session cue configuration is env-var only and degrades cleanly

All behaviour SHALL be governed by environment variables following the existing precedence (env
var → built-in default), introducing no configuration file and no install command. Both events
SHALL honour the existing global mute, the non-macOS no-op, and the missing-`jq` fallback exactly
as the existing events do. Numeric knobs SHALL be validated so a malformed value falls back to
its default rather than breaking the hook. Reminder state SHALL be ephemeral per-session state
under the system temp directory, written create-only or within uniquely named entries, so nothing
is written outside the temp directory and the plugin's own directory and `/plugin uninstall`
remains a complete revert.

#### Scenario: Global mute wins

- **WHEN** the global mute is set
- **THEN** neither the stalled cue nor any reminder is spoken

#### Scenario: Non-macOS no-op preserved

- **WHEN** the speech command is unavailable
- **THEN** both events exit cleanly without speaking or erroring

#### Scenario: Missing jq still speaks a generic stalled cue

- **WHEN** `jq` is unavailable and a turn ends due to an API error
- **THEN** the generic stalled cue is spoken rather than nothing

#### Scenario: Malformed configuration falls back to defaults

- **WHEN** a numeric knob is set to a non-numeric value
- **THEN** the built-in default is used and the hook completes normally

#### Scenario: State lives only in temp

- **WHEN** a reminder is armed
- **THEN** the only files or directories written are under the system temp directory, keyed to
  the session
