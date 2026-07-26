## MODIFIED Requirements

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

### Requirement: In-flight subagent accounting

The plugin SHALL maintain a per-session view of in-flight subagents so the `Stop` cue can tell
whether background work is still outstanding, and so completion cues can be capped and rolled
up. When the hook payload provides the harness's in-flight task list, that list SHALL be the
authoritative source: in-flight is the number of subagent entries in it, excluding the entry for
the agent whose completion is being handled. When the payload does not provide that list, the
plugin SHALL fall back to marker counting: each subagent dispatch records one spawn, each
completion records one completion keyed by the event's unique `agent_id`, and in-flight is
`max(0, spawns − completions)` over the non-stale markers, clamped so it never goes negative.
The spawn record SHALL be written for every dispatch, independent of whether the dispatch cue
itself is debounced into silence.

#### Scenario: Task list is authoritative when present

- **WHEN** a completion event carries the harness's in-flight task list
- **THEN** in-flight is derived from that list rather than from marker counts

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

## REMOVED Requirements

### Requirement: Silence on subagent completion

**Reason**: The requirement mandated that a subagent completion never speaks, which is exactly
the gap this change closes — a user who stepped away learned what was delegated but never that
it came back. Completions are now voiced by purpose, with a configurable cap replacing blanket
silence as the defence against fan-out chatter.

**Migration**: The behaviour is superseded by the "Completion is voiced when the result returns
to the parent" and "Name cap bounds per-agent chatter" requirements in the new
`voice-notify-agent-identity` capability. The idempotency guarantee it carried (a duplicate
`SubagentStop` for the same `agent_id` counts once) is preserved by the in-flight accounting
requirement above. Users who prefer the old silence can set
`CLAUDE_VOICE_NOTIFY_AGENT_NAMES=off`, which restores anonymous dispatch cues and silent
completions.
