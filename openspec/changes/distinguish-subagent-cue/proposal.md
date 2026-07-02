## Why

voice-notify only voices the `Stop` event ("your turn") and `Notification` (needs you).
It has no signal for the *other* pause state: when the main agent dispatches subagents
and pauses while they run. To the ear those two states are indistinguishable — a long
silence, then eventually "your turn" — so a user who stepped away cannot tell "still
working, stay away" from "finished, come back." Worse, if Claude Code emits `Stop` while
the main agent is merely suspended on subagents (event timing the docs do not pin down),
the user hears a premature "your turn" for work that has not actually finished. This change
gives the subagent-working state its own voice and keeps "your turn" honest.

## What Changes

- Add a **debounced dispatch cue**: when the main agent dispatches one or more subagents,
  voice-notify speaks a single, distinct "still working on helpers" cue, then stays quiet.
- **Debounce a burst**: several subagents dispatched together (or in quick succession)
  collapse to **one** spoken cue within a short window — no per-subagent chatter.
- **Stay silent on subagent finish** (`SubagentStop`): a subagent completing mid-turn
  produces no cue; only the real turn-end speaks.
- **Reserve the `Stop` "your turn" cue for true turn-end**: it is not spoken as a side
  effect of the main agent pausing on subagents. (Verified by spike; suppression added only
  if Claude Code actually fires `Stop` mid-turn during a subagent wait.)
- New env-var knobs, following the existing precedence and the no-config-file rule:
  a debounce window and an independent mute for the subagent cue.
- Reuse the existing machinery unchanged — mute, non-macOS no-op, voice resolution,
  `compose()`/garnish/prosody, and ephemeral `$TMPDIR` state.

No breaking changes: default-on behaviour for existing events (`Stop`, `Notification`,
`UserPromptSubmit` timing) is preserved.

## Capabilities

### New Capabilities

- `voice-notify-subagent-cues`: routing and phrasing for the subagent-working state — a
  debounced dispatch cue distinct from the turn-end and attention cues, silence on subagent
  completion, the rule that "your turn" speaks only at true turn-end, and the ephemeral
  debounce/active-subagent state plus env-var configuration that governs them.

### Modified Capabilities

<!-- None. The new behaviour reuses voice-notify-phrasing's compose/garnish/mute/no-op
     machinery without changing any of its requirements; the subagent-aware routing lives
     entirely in the new capability. -->

## Impact

- **Plugin manifest** `plugins/voice-notify/.claude-plugin/plugin.json`: add hook
  wiring for subagent dispatch (a `PreToolUse` matcher on the dispatch tool and/or
  `SubagentStart`) and, if the spike requires it, keep/adjust the `Stop` wiring. Bump
  `version`.
- **Script** `plugins/voice-notify/scripts/notify.sh`: new event arms (e.g. `dispatch`,
  optionally `subagent-stop`), a debounce check against an ephemeral `$TMPDIR` file, a new
  phrase pool, and a small amount of plumbing — no change to existing event behaviour.
- **Tests** `plugins/voice-notify/tests/run.sh`: cases for the dispatch cue, debounce
  collapse, silence-on-finish, mute/no-op coverage for the new event.
- **Docs** `plugins/voice-notify/README.md` (+ root `README.md` if the lineup blurb
  changes) and the marketplace `version`.
- **External dependency / unknowns**: the exact dispatch tool name (`Task` vs `Agent`) and
  whether `Stop`/`SubagentStop` fire as the docs imply are unverified — a spike resolves
  them before implementation. No new runtime dependency (`say`/`jq` only, as today).
