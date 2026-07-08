## Why

The prior `distinguish-subagent-cue` change gave the subagent-*dispatch* state its own
voice, but its spike concluded `Stop` fires only at genuine turn-end (after every
`SubagentStop`) and so shipped **no** guard on the turn-end cue. That conclusion held for
**foreground/blocking** subagents — the model exercised at the time.

It does **not** hold for **background subagents**. In that mode the `Agent` tool dispatches
agents that run without blocking, and the main turn can end while they are still executing.
Claude Code's own docs confirm it: *"Stop hooks don't fire [waiting] because the subagent
runs in the background without blocking; `SubagentStop` fires when the background subagent
completes."* The observed symptom: the main session finishes a turn and can accept input
while its background agents are still working, and voice-notify speaks a turn-end sign-off
("All done", "Your turn") — a false "finished" for work that has not finished.

This change makes `Stop` aware of still-running background subagents and, when any are
in-flight, speaks a distinct **waiting** cue instead of the sign-off.

## What Changes

- **Track in-flight subagents** with two ephemeral `$TMPDIR` marker directories per session,
  written create-only so concurrent async hooks never race on a read-modify-write:
  - `PreToolUse(Agent)` (the existing dispatch arm) drops one uniquely-named *spawn* marker.
  - a new `SubagentStop` hook drops one *done* marker named by the event's unique `agent_id`
    (idempotent — a duplicate stop for the same agent overwrites the same file).
  - **in-flight = max(0, spawn_count − done_count).**
- **Branch the `Stop` cue on in-flight count**: when one or more subagents are still running,
  speak a new `WAITING_CORES` cue ("Still going — the helpers aren't done yet") **regardless
  of the duration gate**, instead of the turn-end sign-off. When none are in-flight, behaviour
  is exactly as today (duration gate + standard/long sign-off pools).
- **Foreground agents unchanged / no regression**: they emit every `SubagentStop` before
  `Stop`, so spawn == done → in-flight 0 → the normal sign-off still speaks.
- **Silence on subagent completion is preserved**: `SubagentStop` still speaks nothing; it
  only updates the ephemeral accounting.
- **Self-healing state**: at `Stop`, spawn/done markers older than a configurable TTL
  (default 3600s) are pruned, so a crashed or permission-denied agent that never emits
  `SubagentStop` cannot wedge the count into a permanent false "still working".
- **Config, env-var only** (no config file): the waiting cue honours the existing global mute
  and the existing subagent mute (`CLAUDE_VOICE_NOTIFY_SUBAGENT=off` disables the tracking and
  the cue, so `Stop` behaves exactly as before the change); one new knob
  `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` (seconds) governs the stale-marker prune.
- **Reuse existing machinery unchanged**: global mute, non-macOS no-op, `jq`-missing
  fallback, voice resolution, `compose()`/garnish/prosody, and ephemeral `$TMPDIR` state.

No breaking changes: with no new env vars set and no background subagents in flight, every
existing cue behaves identically.

## Capabilities

### Modified Capabilities

- `voice-notify-subagent-cues`: the turn-end reservation requirement changes from
  "suppress to silence when a premature `Stop` would fire mid-wait" to "speak a distinct
  waiting cue when subagents are in-flight at `Stop`"; the silence-on-completion and
  ephemeral-state requirements gain the `SubagentStop` accounting side-effect and the
  spawn/done marker directories; the configuration requirement gains the TTL knob. Two new
  requirements are added: in-flight subagent accounting, and the waiting-cue phrasing.

## Impact

- **Script** `plugins/voice-notify/scripts/notify.sh`: spawn-marker write in the existing
  `dispatch` arm; a new `subagent-stop` arm that writes a done marker keyed by `agent_id`
  and speaks nothing; an in-flight check + TTL prune + `WAITING_CORES` pool in the `stop`
  arm; parse `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL`.
- **Manifest** `plugins/voice-notify/.claude-plugin/plugin.json`: add a `SubagentStop` hook
  calling `notify.sh subagent-stop` (`async: true`, short timeout); bump `version`
  (minor — additive).
- **Tests** `plugins/voice-notify/tests/run.sh`: spawn/done accounting, in-flight → waiting
  cue (distinct from sign-off and dispatch pools), foreground-balances-to-sign-off,
  TTL prune, mute/no-op coverage for the new event.
- **Docs** `plugins/voice-notify/README.md` (new cue + TTL knob), root `README.md` and
  `CLAUDE.md` voice-notify lineup blurbs (now also a `SubagentStop` hook), marketplace
  `metadata.version`, and `CHANGELOG.md`.
- **No new runtime dependency** (`say`/`jq` only, as today).
