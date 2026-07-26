## Why

Today a subagent fan-out is voiced anonymously: one generic "Spinning up some helpers" at
dispatch, and **silence** on every completion. A user who has stepped away hears that *some*
work was delegated, never *what*, and never learns when it came back — the only echo is a
waiting cue at `Stop`, after which the all-clear never arrives. With multi-agent work now the
norm, the cues carry almost no information about the session they describe.

Claude Code's hook payloads already carry everything needed to fix this — the agent's
`description` at dispatch, and (verified live on 2.1.220) the finishing agent's own entry,
description included, inside `SubagentStop.background_tasks`. voice-notify simply never reads
them.

## What Changes

- **Dispatch cues name the work.** The `PreToolUse`/`Agent` cue speaks the agents' purposes:
  one agent by name, two named in full, three or more as a count plus the first
  ("Three helpers, starting with review script changes").
- **Completions are voiced, not silent.** **BREAKING** relative to the current spec, which
  mandates silence on `SubagentStop`. A finishing agent is announced by its purpose
  ("Review script changes — done") while at most `CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP` (default
  3) agents are in flight; above the cap individual cues stay suppressed to avoid chatter.
- **A new `PostToolUse`/`Agent` hook** voices *foreground* agents at the moment their results
  return to the parent session, and records the `agentId → description` join for background
  agents from the `async_launched` dispatch acknowledgement.
- **Success and failure sound different** — an agent that did not complete gets its own cue.
- **A roll-up announces the batch draining** ("All five helpers are back") when in-flight
  reaches zero *and* something was left unsaid — either a waiting cue promised it, or the name
  cap suppressed the individual cues. A fan-out whose agents were each named individually gets
  no roll-up, since the last name already served as the all-clear.
- **In-flight tracking moves to the harness's `background_tasks`** (authoritative, and it
  retires the TTL-wedge failure mode), keeping the existing marker counting as the fallback for
  Claude Code versions that do not send the field.
- **Concurrent cues are serialised** through an ephemeral lock so two agents landing together
  do not talk over each other — a collision that could not happen while completions were silent.
- **Background-agent notifications are classified**: `agent_completed` and `agent_needs_input`
  stop collapsing into the generic "I need your attention."
- New env vars: `CLAUDE_VOICE_NOTIFY_AGENT_NAMES` (`off` restores the 0.5.0 anonymous cues),
  `CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP`, `CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX`.

## Capabilities

### New Capabilities

- `voice-notify-agent-identity`: naming dispatched and finishing agents by their purpose —
  description extraction from the hook payloads, sanitisation of model-authored text before it
  reaches `say`, the name cap, the drain roll-up, and cue serialisation.

### Modified Capabilities

- `voice-notify-subagent-cues`: completion is no longer required to be silent; the dispatch cue
  gains named phrasing; in-flight accounting is redefined on `background_tasks` with marker
  counting demoted to a fallback.
- `voice-notify-phrasing`: the `Notification` subtype routing gains the `agent_completed` and
  `agent_needs_input` types instead of falling through to the neutral pool.

## Impact

- `plugins/voice-notify/.claude-plugin/plugin.json` — new `PostToolUse`/`Agent` hook entry.
- `plugins/voice-notify/scripts/notify.sh` — new `agent-result` event arm; rewritten `dispatch`,
  `subagent-stop` and `stop` arms; description extraction, sanitisation, lock, and new pools.
- `plugins/voice-notify/tests/run.sh` — cases for naming, the cap, the roll-up, foreground vs
  background routing, the `background_tasks` fallback, and sanitisation.
- `plugins/voice-notify/README.md` and the root `README.md` — the new cues and env vars.
- `CHANGELOG.md` and both version lines at release time.
- No new runtime dependency; `jq` remains recommended-not-required, and a missing `jq` degrades
  to the current anonymous cues. Non-macOS stays a clean no-op. All state remains ephemeral
  `$TMPDIR`, so `/plugin uninstall` is still a complete revert.
