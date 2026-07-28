## Why

When a turn ends with background work still running, voice-notify speaks a sign-off ("that took
a bit, but it's done") or, a minute later, "I'm waiting for your input" — while sub-agents or a
workflow are still doing the job. Both cues tell the user the opposite of the truth, which is
the one thing a spoken notification must never do.

Two causes, both verifiable against Claude Code 2.1.220:

1. The `Stop` handler counts only in-flight entries whose `type` is `subagent`. The harness
   reports nine kinds — `subagent`, `workflow`, `shell`, `monitor`, `MCP task`, `teammate`,
   `dream`, `auto-mode scan`, `cloud session` — so a running **workflow** resolves to zero
   in-flight and the sign-off fires. The plugin's marker fallback misses it too, because those
   markers are fed by a hook matched on the `Agent` tool and a workflow is not an `Agent` call.
2. The `Notification` payload carries no in-flight task list at all — the harness attaches
   `background_tasks` only to `Stop` and `SubagentStop`. So the idle cue has no way to know
   anything is running and always speaks as though the session were idle.

## What Changes

- Broaden the authoritative in-flight count so it covers **all** kinds of background work the
  harness reports, except `shell` and `monitor`. A block-list rather than an allow-list: a task
  type introduced later counts by default, which errs toward "still working" — the safe
  direction, and the one the script already takes elsewhere.
  - `shell` is excluded because a `run_in_background` command is often a long-lived server;
    counting it would silence the sign-off for the rest of the session.
  - `monitor` is excluded for the same reason, and because it never returns a result the way an
    agent does.
- Record a per-session **busy marker** whenever an authoritative count is read and it is above
  zero; delete it when the count is zero. `Stop` and `SubagentStop` both carry the real list, so
  the marker is refreshed continuously.
- Suppress the plain idle `Notification` cue while that marker is present and recent. Permission
  requests, "an agent needs your input", and agent-completion notifications keep speaking — only
  the "I'm waiting for your input" cue is gated, because that is the only one that is false while
  work is outstanding.
- Clear the busy marker when a new user prompt arrives, and age it out, so it can never mute the
  idle cue permanently.
- No new hooks, no new configuration keys. `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` continues to
  disable the whole path, including the new marker.

Not a breaking change: every cue that was correct before stays correct, and the mute and
configuration surface is unchanged.

## Capabilities

### New Capabilities

None. The change extends behaviour already owned by two existing capabilities.

### Modified Capabilities

- `voice-notify-subagent-cues`: the in-flight accounting requirement is widened from "subagent
  entries" to "background-work entries, excluding shells and monitors", and gains a new
  requirement covering the busy marker and the suppression of the idle cue while background work
  is outstanding.
- `voice-notify-phrasing`: the idle routing scenario becomes conditional — the gentle
  waiting-for-input cue applies only when no background work is outstanding.

## Impact

- `plugins/voice-notify/scripts/notify.sh` — the `inflight_payload` filter, the `stop`,
  `subagent-stop`, `notification` and `start` arms, plus the new marker helper.
- `plugins/voice-notify/tests/run.sh` — new cases for each background-work type, the two
  exclusions, and the marker lifecycle.
- `plugins/voice-notify/README.md`, root `README.md`, `CLAUDE.md` plugin table, `CHANGELOG.md`.
- Version bump for `plugins/voice-notify/.claude-plugin/plugin.json` and the marketplace
  metadata version.
- No dependency changes. `jq` remains the only parsing dependency and its absence still degrades
  to the marker fallback.
