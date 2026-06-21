## ADDED Requirements

### Requirement: Composed phrasing from garnish and core

The spoken cue SHALL be assembled by a single composition that joins an optional
leading interjection ("garnish") with a mandatory "core" phrase. The garnish SHALL be
omitted on a configurable fraction of fires (default approximately 60% omitted / 40%
spoken) so that the cadence varies between bare and led-in forms. The same composition
SHALL serve both the `Stop` and `Notification` events; for `Notification` the core is the
attention reason, for `Stop` the core is a sign-off.

#### Scenario: Garnish present

- **WHEN** the composer fires and the garnish draw selects "spoken"
- **THEN** the cue is `<garnish><pause><core>` (e.g. "Heads up — I need your permission to use Bash")

#### Scenario: Garnish omitted

- **WHEN** the composer fires and the garnish draw selects "omitted"
- **THEN** the cue is the bare `<core>` (e.g. "Done.") with no leading interjection

#### Scenario: Variety from small pools

- **WHEN** the composer runs repeatedly across a session
- **THEN** consecutive cues vary in both garnish presence and phrase selection, drawing
  multiplicative variety from small per-context pools rather than one flat list

### Requirement: Context-subtype pool routing

The phrase pools SHALL be selected by the context of the event so that tone fits the
situation. For `Notification`, the cue SHALL be routed by the message subtype: a
permission request, an idle/waiting-for-input prompt, or an unrecognised message
(neutral fallback). For `Stop`, the cue SHALL be routed by turn length when that
information is available (short vs long).

#### Scenario: Permission request routing

- **WHEN** a `Notification` message indicates Claude needs permission
- **THEN** the cue uses the brisk garnish/core pool and speaks the specific reason in the
  first person (e.g. "Quick one — I need your permission to use Bash")

#### Scenario: Idle/waiting routing

- **WHEN** a `Notification` message indicates Claude is waiting for input
- **THEN** the cue uses the gentle pool (e.g. "Whenever you're ready — I'm waiting for your input")

#### Scenario: Unrecognised message fallback

- **WHEN** a `Notification` message matches no known subtype, or `jq` is unavailable, or
  the message is empty
- **THEN** the cue falls back to a neutral attention phrase (e.g. "Hey — I need your attention")

### Requirement: First-person reason rendering is robust

When rendering a `Notification` reason in the first person, the transform SHALL NOT
produce ungrammatical output for messages it does not recognise. A catch-all replacement
that could mangle unrelated occurrences of the assistant's name SHALL be avoided; only
known message shapes are rewritten, and anything else falls through to the neutral
fallback.

#### Scenario: Unknown wording is not mangled

- **WHEN** the `Notification` message contains the assistant's name in wording the
  transform does not explicitly handle
- **THEN** the cue is either left grammatically intact or replaced with the neutral
  fallback — never emitted as a broken fragment

### Requirement: Prosody pause for natural cadence

When the platform TTS supports inline prosody, the composition SHALL insert a short pause
between the garnish and the core so the cue sounds spoken rather than read. The pause
SHALL be a no-op (gracefully ignored or absent) where the TTS engine does not support it,
and SHALL never appear as literal characters in the spoken output.

#### Scenario: Pause inserted on supported engine

- **WHEN** a garnish-present cue is spoken on macOS `say`
- **THEN** a brief silence separates the garnish from the core, and no pause markup is
  audible as text

### Requirement: Duration gate suppresses cues on quick turns

The `Stop` cue SHALL be suppressed when the just-finished turn is shorter than a
configurable threshold (default approximately 20 seconds), on the basis that the user is
likely still present. When the elapsed time is at or above the threshold, the `Stop` cue
SHALL be spoken. When the elapsed time cannot be determined, the `Stop` cue SHALL be
spoken (fail-audible, never silently swallowed).

#### Scenario: Quick turn stays silent

- **WHEN** a turn finishes and its measured duration is below the threshold
- **THEN** no `Stop` cue is spoken

#### Scenario: Long turn speaks

- **WHEN** a turn finishes and its measured duration is at or above the threshold
- **THEN** a `Stop` cue is spoken

#### Scenario: Unknown duration speaks

- **WHEN** a turn finishes but no start time is available (e.g. first turn, missing state)
- **THEN** a `Stop` cue is spoken using the default (duration-agnostic) sign-off pool

### Requirement: Duration-relative phrasing

When turn duration is known and the `Stop` cue is spoken, the core sign-off pool SHALL be
selected to reflect the duration: a long turn draws from a pool acknowledging the wait
(e.g. "Okay, that took a bit — all done"), a shorter (but above-threshold) turn draws
from the standard pool.

#### Scenario: Long turn acknowledges the wait

- **WHEN** a spoken `Stop` cue follows a turn well above the threshold
- **THEN** the core is drawn from the long-turn pool that acknowledges elapsed time

### Requirement: Ephemeral, self-cleaning duration state

The duration gate SHALL persist only ephemeral per-session state under the system temp
directory, written when a turn starts and removed (or overwritten) when it ends. The
plugin SHALL write nothing outside the system temp directory and its own plugin
directory, so that `/plugin uninstall` remains a complete revert and no teardown command
is required.

#### Scenario: State lives only in temp

- **WHEN** the duration gate records a turn start
- **THEN** the only file written is under the system temp directory, keyed to the session,
  and it is removed or overwritten when the turn ends

#### Scenario: Stale or missing state is harmless

- **WHEN** a session ends without a matching start file, or a stale start file remains
- **THEN** the gate degrades to the unknown-duration path (cue spoken) without error

### Requirement: Configuration stays env-var only and degrades cleanly

All new behaviour SHALL be governed by environment variables following the existing
precedence (env var → built-in default), with no configuration file introduced. The
existing mute (`CLAUDE_VOICE_NOTIFY=off`), voice override (`CLAUDE_VOICE`), non-macOS
no-op, and missing-`jq` fallback behaviours SHALL be preserved. New knobs SHALL include at
least the duration threshold and the garnish frequency, each with a sensible default.

#### Scenario: Mute still wins

- **WHEN** `CLAUDE_VOICE_NOTIFY=off` is set
- **THEN** no cue is spoken for any event, regardless of the new phrasing or duration logic

#### Scenario: Non-macOS no-op preserved

- **WHEN** the `say` command is unavailable
- **THEN** the script exits cleanly without speaking or erroring, for every event

#### Scenario: Defaults require no configuration

- **WHEN** none of the new environment variables are set
- **THEN** the plugin uses built-in defaults (garnish ≈40%, threshold ≈20s) and works
  without any configuration
