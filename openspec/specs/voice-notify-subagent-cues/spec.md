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
finished), distinguishing this state by ear from the turn-end "your turn" cue.

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

### Requirement: Silence on subagent completion

A subagent completing mid-turn (`SubagentStop`) SHALL NOT produce a cue under the default
configuration. The chosen design announces only the *start* of the subagent-working state;
per-completion cues are suppressed so a large fan-out does not become chatter.

#### Scenario: Subagent finish is silent

- **WHEN** a single subagent finishes while the main agent continues working
- **THEN** no cue is spoken for that completion

#### Scenario: Many parallel finishes stay silent

- **WHEN** several parallel subagents finish in quick succession
- **THEN** no completion cues are spoken for any of them

### Requirement: Turn-end cue reserved for true turn-end

The `Stop` "your turn" cue SHALL be spoken only when control truly returns to the human at
the end of a turn, and SHALL NOT be spoken as a side effect of the main agent pausing while
subagents run. Where the platform fires `Stop` only at genuine turn-end this requirement is
satisfied with no added logic; where `Stop` (or `SubagentStop`) would otherwise emit a
premature "your turn" mid-turn, that cue SHALL be suppressed until the turn actually ends.

#### Scenario: Real turn-end speaks

- **WHEN** a turn genuinely ends and control returns to the human (after any subagents have
  finished and the main agent has produced its final response)
- **THEN** the existing turn-end "your turn" cue is spoken, subject to the existing
  duration gate

#### Scenario: Subagent pause does not announce "your turn"

- **WHEN** the main agent dispatches subagents and pauses while they run, mid-turn
- **THEN** no turn-end "your turn" cue is spoken for that pause; only the subagent-working
  cue (if within policy) is heard

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

State used to debounce dispatch cues or track active subagents SHALL be ephemeral per-session
state under the system temp directory, written and removed (or overwritten) within the
plugin's own logic. The plugin SHALL write nothing outside the system
temp directory and its own plugin directory, so that `/plugin uninstall` remains a complete
revert with no teardown command. Missing or stale state SHALL degrade harmlessly (treated as
"no recent cue" / "speak"), never erroring.

#### Scenario: State lives only in temp

- **WHEN** the debounce records that a dispatch cue was spoken
- **THEN** the only file written is under the system temp directory, keyed to the session

#### Scenario: Stale or missing state is harmless

- **WHEN** a dispatch event fires with no debounce file present, or with a stale/corrupt one
- **THEN** the cue is treated as eligible to speak and the run completes without error

### Requirement: Subagent cue configuration is env-var only and degrades cleanly

All new behaviour SHALL be governed by environment variables following the existing
precedence (env var → built-in default), introducing no configuration file. The new event
SHALL honour the existing global mute (`CLAUDE_VOICE_NOTIFY=off`), the non-macOS no-op (no
`say`), and the missing-`jq` fallback, exactly as the existing events do. A dedicated mute
for just the subagent cue SHALL be available so a user can keep turn-end/notification cues
while silencing the subagent cue. New knobs (at least the debounce window and the subagent
mute) SHALL each have a sensible default so the feature works with no configuration.

#### Scenario: Global mute wins

- **WHEN** `CLAUDE_VOICE_NOTIFY=off` is set
- **THEN** no subagent-working cue is spoken, regardless of the new logic

#### Scenario: Subagent cue muted independently

- **WHEN** the dedicated subagent mute is set but the global mute is not
- **THEN** no subagent-working cue is spoken, while turn-end and notification cues still work

#### Scenario: Non-macOS no-op preserved

- **WHEN** the `say` command is unavailable
- **THEN** the subagent dispatch event exits cleanly without speaking or erroring

#### Scenario: Defaults require no configuration

- **WHEN** none of the new environment variables are set
- **THEN** the plugin uses built-in defaults (debounce window ≈10s, subagent cue on) and
  works without any configuration
```

