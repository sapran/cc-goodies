# voice-notify-subagent-cues Specification

## Purpose

Give the subagent-working state its own voice, distinct from a real turn-end. When the main
agent dispatches subagents and pauses while they run, voice-notify speaks a single, debounced
"still working" cue; a subagent *finishing* is silent, and the `Stop` "your turn" cue is
reserved for genuine turn-end. This lets a user who has stepped away tell "still working, stay
away" from "finished, come back" by ear. All behaviour is env-var only and backed by ephemeral
`$TMPDIR` state, so `/plugin uninstall` remains a complete revert.
## Requirements
### Requirement: Debounced subagent dispatch cue

The plugin SHALL speak a single cue announcing the subagent-working state when the main agent
dispatches one or more subagents and pauses while they run. A burst of dispatches that occur
within a configurable debounce window (default approximately 10 seconds) SHALL collapse to
exactly one spoken cue; a later dispatch separated from the previous one by more than the
window MAY speak again. The cue SHALL announce that work continues (the main agent is not
finished), distinguishing this state by ear from the turn-end "your turn" cue. When agent
naming is enabled and a purpose can be resolved, the cue SHALL also name the delegated work as
defined by the `voice-notify-agent-identity` capability; when naming is disabled or no purpose
can be resolved, the cue SHALL be the anonymous form.

#### Scenario: First dispatch speaks

- **WHEN** a subagent dispatch event fires and no dispatch cue has been spoken within the
  debounce window
- **THEN** a single subagent-working cue is spoken and the debounce window is (re)started

#### Scenario: Burst collapses to one

- **WHEN** several subagents are dispatched together or in quick succession, all within the
  debounce window
- **THEN** only one subagent-working cue is spoken for the whole burst, not one per subagent

#### Scenario: Later dispatch outside the window may speak again

- **WHEN** a further dispatch occurs more than the debounce window after the previous cue
- **THEN** the plugin MAY speak the subagent-working cue again (a new burst), not stay
  permanently silent for the rest of the turn

#### Scenario: Collapsed burst is still named

- **WHEN** several subagents are dispatched within the debounce window and naming is enabled
- **THEN** the single spoken cue reflects the whole burst (count and purpose) rather than only
  the first agent's dispatch

### Requirement: Turn-end cue reserved for true turn-end

The `Stop` turn-end sign-off SHALL be spoken only when control truly returns to the human with
no background work still running. When `Stop` fires while one or more units of agent-like
background work are still in-flight — subagents, a workflow, a teammate, a cloud session, an MCP
task, or any other type the accounting counts as outstanding — the plugin SHALL NOT speak a
turn-end sign-off; it SHALL instead speak a distinct **waiting** cue announcing that work is
still outstanding. Because the salient event is a turn boundary with work unfinished, the
waiting cue SHALL be spoken regardless of the duration gate (`CLAUDE_VOICE_NOTIFY_QUIET_UNDER`).
When nothing is in-flight at `Stop`, the existing turn-end behaviour (duration gate,
standard/long sign-off pools) SHALL be unchanged.

#### Scenario: Real turn-end speaks the sign-off

- **WHEN** a turn genuinely ends with nothing in-flight
- **THEN** the existing turn-end sign-off is spoken, subject to the existing duration gate

#### Scenario: Turn boundary with subagents in-flight speaks the waiting cue

- **WHEN** `Stop` fires while one or more subagents are still running (in-flight > 0)
- **THEN** a waiting cue is spoken and no turn-end sign-off is spoken for that `Stop`

#### Scenario: Turn boundary with a workflow in-flight speaks the waiting cue

- **WHEN** `Stop` fires while a workflow is still running and no subagent is
- **THEN** a waiting cue is spoken and no turn-end sign-off is spoken for that `Stop`

#### Scenario: Waiting cue ignores the duration gate

- **WHEN** `Stop` fires with work in-flight after a turn shorter than
  `CLAUDE_VOICE_NOTIFY_QUIET_UNDER`
- **THEN** the waiting cue is still spoken (the gate suppresses only the no-work sign-off)

#### Scenario: Foreground subagents do not trigger the waiting cue

- **WHEN** all dispatched subagents complete (each `SubagentStop` observed) before `Stop`
- **THEN** in-flight is zero and the normal turn-end sign-off is spoken, not the waiting cue

### Requirement: Distinct phrasing for the subagent-working state

The subagent dispatch cue SHALL be drawn from a phrase pool distinct from the turn-end
sign-off pool and the attention/notification pools, so the three states sound different. The
cue SHALL be assembled through the existing composition (optional leading garnish joined to a
core by a brief prosody pause) so it varies in wording and cadence like the other cues, and
the prosody pause SHALL never be voiced as literal text.

#### Scenario: Dispatch cue is not a sign-off

- **WHEN** the subagent-working cue is spoken
- **THEN** its core is drawn from the subagent pool (e.g. "Spinning up some helpers, back in
  a bit") and not from the turn-end sign-off pool (e.g. "Your turn.")

#### Scenario: Composition reused

- **WHEN** the subagent-working cue is spoken with a garnish selected
- **THEN** the cue is `<garnish><pause><core>` with the pause inaudible as text, exactly as
  for the other cues

### Requirement: Ephemeral, self-cleaning debounce and active-subagent state

State used to debounce dispatch cues, to track in-flight subagents, to record dispatched agents'
purposes, to remember per-turn cue bookkeeping, or to serialise speech SHALL be ephemeral
per-session state under the system temp directory, written create-only or overwritten within
the plugin's own logic. State that concurrent asynchronous hooks may write SHALL be structured
so that no read-modify-write on shared state is required — marker directories with uniquely
named entries, or create-only directories. The plugin SHALL write nothing outside the system
temp directory and its own plugin directory, so that `/plugin uninstall` remains a complete
revert with no teardown command. Stale entries (older than a configurable TTL) SHALL be pruned
so that a subagent that never reports completion cannot wedge the in-flight count; missing or
corrupt state SHALL degrade harmlessly (treated as "no recent cue" / "none in-flight" /
"speak"), never erroring.

#### Scenario: State lives only in temp

- **WHEN** the plugin records a spawn, a completion, an agent's purpose, or takes the speech lock
- **THEN** the only files or directories written are under the system temp directory, keyed to
  the session

#### Scenario: Stale or missing state is harmless

- **WHEN** `Stop` fires with no marker directories present, or with stale/corrupt markers
- **THEN** in-flight resolves to zero (or to the count of non-stale markers) and the run
  completes without error

#### Scenario: Stale spawn marker is pruned

- **WHEN** a spawn marker is older than the configured TTL and its subagent never reported
  completion
- **THEN** the marker is pruned at `Stop` and does not keep the plugin in a permanent
  "still working" state

#### Scenario: Stale purpose record is pruned

- **WHEN** a recorded agent purpose is older than the configured TTL
- **THEN** it is pruned and does not accumulate across sessions

### Requirement: Subagent cue configuration is env-var only and degrades cleanly

All behaviour SHALL be governed by environment variables following the existing precedence
(env var → built-in default), introducing no configuration file. The events SHALL honour the
existing global mute (`CLAUDE_VOICE_NOTIFY=off`), the non-macOS no-op (no `say`), and the
missing-`jq` fallback, exactly as the existing events do. The dedicated subagent mute
(`CLAUDE_VOICE_NOTIFY_SUBAGENT=off`) SHALL disable the whole subagent path — the dispatch cue,
the in-flight accounting, the completion cues, the drain roll-up, and the waiting cue — so that
`Stop` behaves exactly as it did before in-flight tracking existed. A TTL knob
(`CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL`, seconds) SHALL govern stale-marker pruning with a sensible
default so the feature works with no configuration.

#### Scenario: Global mute wins

- **WHEN** `CLAUDE_VOICE_NOTIFY=off` is set
- **THEN** no dispatch, completion, roll-up, or waiting cue is spoken, regardless of the new
  logic

#### Scenario: Subagent mute disables the whole path

- **WHEN** `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` is set but the global mute is not
- **THEN** no spawn/done/purpose records are written, no completion, roll-up, or waiting cue is
  spoken, and `Stop` speaks its turn-end sign-off exactly as before in-flight tracking existed,
  while turn-end and notification cues still work

#### Scenario: Non-macOS no-op preserved

- **WHEN** the `say` command is unavailable
- **THEN** the `subagent-stop` and agent-result events exit cleanly without speaking or erroring

#### Scenario: Defaults require no configuration

- **WHEN** none of the new environment variables are set
- **THEN** the plugin uses built-in defaults (TTL ≈3600s, subagent path on, naming on, name cap
  3) and works without any configuration

### Requirement: In-flight subagent accounting

The plugin SHALL maintain a per-session view of in-flight background work so the `Stop` cue can
tell whether work is still outstanding, and so completion cues can be capped and rolled up. When
the hook payload provides the harness's in-flight task list, that list SHALL be the
authoritative source: in-flight is the number of entries in it that represent agent-like work,
excluding the entry for the agent whose completion is being handled. An entry counts as
agent-like work unless its type is a background shell command or a monitor; those two SHALL be
excluded, because both are commonly long-lived and neither returns a result the way an agent
does. The exclusion SHALL be expressed as a block-list, so a task type introduced by a future
harness version counts as outstanding work by default rather than being silently ignored. When
the payload does not provide that list, the plugin SHALL fall back to marker counting: each
subagent dispatch records one spawn, each completion records one completion keyed by the event's
unique `agent_id`, and in-flight is `max(0, spawns − completions)` over the non-stale markers,
clamped so it never goes negative. The spawn record SHALL be written for every dispatch,
independent of whether the dispatch cue itself is debounced into silence.

#### Scenario: Task list is authoritative when present

- **WHEN** a completion event carries the harness's in-flight task list
- **THEN** in-flight is derived from that list rather than from marker counts

#### Scenario: A running workflow counts as outstanding work

- **WHEN** the task list contains an entry of type `workflow` and no subagent entries
- **THEN** in-flight is one, not zero

#### Scenario: Other agent-like work counts as outstanding

- **WHEN** the task list contains an entry of type `teammate`, `cloud session`, `MCP task`,
  `dream` or `auto-mode scan`
- **THEN** that entry is counted as outstanding work

#### Scenario: Unknown task types count as outstanding

- **WHEN** the task list contains an entry whose type the plugin does not recognise
- **THEN** that entry is counted as outstanding work, so an unfamiliar type can never produce a
  false all-clear

#### Scenario: Background shells and monitors are excluded

- **WHEN** the task list contains only entries of type `shell` and `monitor`
- **THEN** in-flight is zero, so a long-lived background command or monitor does not mute the
  turn-end sign-off for the rest of the session

#### Scenario: Finishing agent is excluded from its own count

- **WHEN** a completion event carries a task list that still contains the finishing agent's own
  entry
- **THEN** that entry is excluded, so an agent is never counted as waiting on itself

#### Scenario: Falls back to markers when the list is absent

- **WHEN** a completion or turn-end event carries no in-flight task list
- **THEN** the marker counting is used and behaves exactly as before

#### Scenario: Dispatch increments, completion decrements

- **WHEN** two subagents are dispatched and one later completes, with no task list available
- **THEN** the in-flight count is one (two spawns minus one completion)

#### Scenario: Debounced dispatch still counts

- **WHEN** several subagents are dispatched within the dispatch-cue debounce window (so only
  one cue is spoken)
- **THEN** every dispatched subagent is recorded as a spawn, not just the one that spoke

#### Scenario: Count clamps at zero

- **WHEN** completions recorded exceed spawns recorded (e.g. after a mute toggle)
- **THEN** the in-flight count resolves to zero rather than a negative number

### Requirement: Distinct phrasing for the waiting-at-turn-boundary state

The waiting cue SHALL be drawn from a phrase pool distinct from the turn-end sign-off pools,
the subagent-dispatch pool, and the attention/notification pools, so all four states sound
different by ear. It SHALL be assembled through the existing composition (optional leading
garnish joined to a core by a brief prosody pause), and the prosody pause SHALL never be voiced
as literal text.

#### Scenario: Waiting cue is not a sign-off and not a dispatch cue

- **WHEN** the waiting cue is spoken
- **THEN** its core is drawn from the waiting pool (e.g. "Still going — the helpers aren't done
  yet") and not from the turn-end sign-off pool nor the subagent-dispatch pool

#### Scenario: Composition reused

- **WHEN** the waiting cue is spoken with a garnish selected
- **THEN** the cue is `<garnish><pause><core>` with the pause inaudible as text, exactly as for
  the other cues

### Requirement: Idle notification is silent while background work is outstanding

The idle `Notification` cue ("waiting for your input") SHALL NOT be spoken while agent-like
background work is outstanding, because that cue asserts the session is idle when it is not.
Since the `Notification` payload carries no in-flight task list, the plugin SHALL record the
outstanding state itself: whenever an event that does carry the authoritative list is handled,
the plugin SHALL write a per-session **busy marker** if the resulting count is above zero and
SHALL delete that marker if the count is zero. The `Notification` handler SHALL consult the
marker and exit without speaking when it is present and not stale. Only the idle subtype SHALL
be gated; permission requests, background-agent completion reports and background-agent
needs-input reports SHALL continue to speak, because each remains true and actionable while
work is outstanding. The marker SHALL be deleted when a new user prompt arrives, and SHALL be
ignored once older than the in-flight marker lifetime, so a marker left behind by a killed
process can never mute the idle cue permanently. When the subagent path is disabled
(`CLAUDE_VOICE_NOTIFY_SUBAGENT=off`) the marker SHALL be neither written nor consulted.

#### Scenario: Idle cue suppressed while work is outstanding

- **WHEN** a turn ends with background work in-flight, and an idle `Notification` follows
- **THEN** nothing is spoken for that notification

#### Scenario: Idle cue speaks once the work has drained

- **WHEN** an event carrying the authoritative list resolves the count to zero, and an idle
  `Notification` follows
- **THEN** the idle cue is spoken as before

#### Scenario: Actionable notifications still speak while work is outstanding

- **WHEN** the busy marker is present and a permission request, a background-agent completion,
  or a background-agent needs-input notification arrives
- **THEN** that cue is spoken normally

#### Scenario: A new user prompt clears the marker

- **WHEN** the user submits a new prompt
- **THEN** the busy marker is deleted, because the user is demonstrably back at the keyboard

#### Scenario: A stale marker does not mute the idle cue

- **WHEN** the busy marker is older than the in-flight marker lifetime
- **THEN** it is ignored and the idle cue is spoken

#### Scenario: Disabling the subagent path disables the suppression

- **WHEN** `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` and an idle `Notification` arrives
- **THEN** the idle cue is spoken, and no busy marker is written by any event
