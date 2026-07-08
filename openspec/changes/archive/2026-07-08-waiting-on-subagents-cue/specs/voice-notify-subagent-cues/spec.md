## MODIFIED Requirements

### Requirement: Turn-end cue reserved for true turn-end

The `Stop` turn-end sign-off SHALL be spoken only when control truly returns to the human with
no subagents still running. When `Stop` fires while one or more subagents are still in-flight
(the main turn ended but background subagents keep working), the plugin SHALL NOT speak a
turn-end sign-off; it SHALL instead speak a distinct **waiting** cue announcing that work is
still outstanding. Because the salient event is a turn boundary with work unfinished, the
waiting cue SHALL be spoken regardless of the duration gate (`CLAUDE_VOICE_NOTIFY_QUIET_UNDER`).
When no subagents are in-flight at `Stop`, the existing turn-end behaviour (duration gate,
standard/long sign-off pools) SHALL be unchanged.

#### Scenario: Real turn-end speaks the sign-off

- **WHEN** a turn genuinely ends with no subagents in-flight
- **THEN** the existing turn-end sign-off is spoken, subject to the existing duration gate

#### Scenario: Turn boundary with subagents in-flight speaks the waiting cue

- **WHEN** `Stop` fires while one or more subagents are still running (in-flight > 0)
- **THEN** a waiting cue is spoken and no turn-end sign-off is spoken for that `Stop`

#### Scenario: Waiting cue ignores the duration gate

- **WHEN** `Stop` fires with subagents in-flight after a turn shorter than
  `CLAUDE_VOICE_NOTIFY_QUIET_UNDER`
- **THEN** the waiting cue is still spoken (the gate suppresses only the no-work sign-off)

#### Scenario: Foreground subagents do not trigger the waiting cue

- **WHEN** all dispatched subagents complete (each `SubagentStop` observed) before `Stop`
- **THEN** in-flight is zero and the normal turn-end sign-off is spoken, not the waiting cue

### Requirement: Silence on subagent completion

A subagent completing (`SubagentStop`) SHALL NOT produce a spoken cue. The event SHALL,
however, update the ephemeral in-flight accounting (recording that one subagent has finished),
so that a later `Stop` can tell whether work is still outstanding. Per-completion cues remain
suppressed so a large fan-out does not become chatter.

#### Scenario: Subagent finish is silent

- **WHEN** a single subagent finishes
- **THEN** no cue is spoken for that completion, and the in-flight accounting records the finish

#### Scenario: Many parallel finishes stay silent

- **WHEN** several parallel subagents finish in quick succession
- **THEN** no completion cues are spoken for any of them

#### Scenario: Duplicate completion counts once

- **WHEN** `SubagentStop` is observed more than once for the same `agent_id`
- **THEN** the accounting records that agent as finished exactly once (idempotent)

### Requirement: Ephemeral, self-cleaning debounce and active-subagent state

State used to debounce dispatch cues or to track in-flight subagents SHALL be ephemeral
per-session state under the system temp directory, written create-only or overwritten within
the plugin's own logic. In-flight tracking SHALL use two per-session marker directories — one
for subagent spawns, one for completions — such that concurrent asynchronous hooks never
perform a read-modify-write on shared state. The plugin SHALL write nothing outside the system
temp directory and its own plugin directory, so that `/plugin uninstall` remains a complete
revert with no teardown command. Stale markers (older than a configurable TTL) SHALL be pruned
so that a subagent that never reports completion cannot wedge the in-flight count; missing or
corrupt state SHALL degrade harmlessly (treated as "no recent cue" / "none in-flight" /
"speak"), never erroring.

#### Scenario: State lives only in temp

- **WHEN** the plugin records a spawn or a completion
- **THEN** the only files written are under the system temp directory, keyed to the session

#### Scenario: Stale or missing state is harmless

- **WHEN** `Stop` fires with no marker directories present, or with stale/corrupt markers
- **THEN** in-flight resolves to zero (or to the count of non-stale markers) and the run
  completes without error

#### Scenario: Stale spawn marker is pruned

- **WHEN** a spawn marker is older than the configured TTL and its subagent never reported
  completion
- **THEN** the marker is pruned at `Stop` and does not keep the plugin in a permanent
  "still working" state

### Requirement: Subagent cue configuration is env-var only and degrades cleanly

All behaviour SHALL be governed by environment variables following the existing precedence
(env var → built-in default), introducing no configuration file. The events SHALL honour the
existing global mute (`CLAUDE_VOICE_NOTIFY=off`), the non-macOS no-op (no `say`), and the
missing-`jq` fallback, exactly as the existing events do. The dedicated subagent mute
(`CLAUDE_VOICE_NOTIFY_SUBAGENT=off`) SHALL disable the whole subagent path — the dispatch cue,
the in-flight accounting, and the waiting cue — so that `Stop` behaves exactly as it did before
in-flight tracking existed. A TTL knob (`CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL`, seconds) SHALL
govern stale-marker pruning with a sensible default so the feature works with no configuration.

#### Scenario: Global mute wins

- **WHEN** `CLAUDE_VOICE_NOTIFY=off` is set
- **THEN** no dispatch or waiting cue is spoken, regardless of the new logic

#### Scenario: Subagent mute disables the whole path

- **WHEN** `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` is set but the global mute is not
- **THEN** no spawn/done markers are written, no waiting cue is spoken, and `Stop` speaks its
  turn-end sign-off exactly as before in-flight tracking existed, while turn-end and
  notification cues still work

#### Scenario: Non-macOS no-op preserved

- **WHEN** the `say` command is unavailable
- **THEN** the `subagent-stop` event exits cleanly without speaking or erroring

#### Scenario: Defaults require no configuration

- **WHEN** none of the new environment variables are set
- **THEN** the plugin uses built-in defaults (TTL ≈3600s, subagent path on) and works without
  any configuration

## ADDED Requirements

### Requirement: In-flight subagent accounting

The plugin SHALL maintain a per-session count of in-flight subagents so the `Stop` cue can tell
whether background work is still outstanding. Each subagent dispatch (`PreToolUse` on the
`Agent` tool) SHALL record one spawn; each subagent completion (`SubagentStop`) SHALL record
one completion keyed by the event's unique `agent_id`. The in-flight count SHALL be
`max(0, spawns − completions)` over the non-stale markers, clamped so it never goes negative.
The spawn record SHALL be written for every dispatch, independent of whether the dispatch cue
itself is debounced into silence.

#### Scenario: Dispatch increments, completion decrements

- **WHEN** two subagents are dispatched and one later completes
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
