## Why

voice-notify can tell you what a *subagent* is doing, but it is silent about the other two
things that keep you waiting: a shell command that runs for minutes, and a session that has
stopped dead. A turn killed by an API error fires `StopFailure`, not `Stop`, so the plugin says
nothing at all and the session sits abandoned; a permission prompt is announced exactly once, so
missing that one cue means silence until you happen to look. Both cases waste the very time the
plugin exists to save — you stepped away precisely because you trusted it to call you back.

## What Changes

- **Speak long-running foreground commands.** `PostToolUse(Bash)` carries `duration_ms`, so a
  command that outran a configurable threshold announces itself on completion, named by its
  `description` — the same gate philosophy as the existing quiet-on-quick-turns rule, applied per
  command instead of per turn. `PostToolUseFailure` carries `is_timeout` and `is_interrupt`, so a
  timeout, an interruption and an ordinary failure are distinguishable by ear.
- **Speak a command that is still running.** A command in flight past a threshold gets a
  still-running cue. Because no harness event fires *during* a command, this needs a poller — but
  one **elected per session**, not one per `Bash` call: the first dispatch that wins a create-only
  lock becomes the session's watcher and exits once nothing is outstanding, so the cost is one
  sleeping process while commands run and zero when idle.
- **Speak background command completion.** A background `Bash` call returns
  `tool_response.backgroundTaskId`; the same id appears in `background_tasks` at `Stop`. Recording
  the id with its description at launch and noticing its absence at a later `Stop` names the
  finished command instead of blind-diffing. Reported at a turn boundary, so it can be late.
- **Speak a stalled turn.** Hook `StopFailure` (currently unhooked) and announce the API error
  that ended the turn, ignoring the duration gate — a turn that died matters at any length.
- **Speak an unanswered permission prompt more than once.** `PermissionRequest` arms a reminder
  that repeats on the watcher's poll until the prompt is resolved, disarmed by the matching
  `PostToolUse`/`PostToolUseFailure` or by `PermissionDenied`.
- **Reuse, not re-invent.** The description sanitiser, the speech lock, the composition/garnish
  machinery and the `$TMPDIR`-only state discipline are reused unchanged.
- **Explicitly unchanged:** a running `shell` task still does **not** count as outstanding work.
  Announcing a background command's completion and gating the turn-end sign-off stay separate
  decisions, so a long-lived server can never mute "All done". This preserves the block-list
  settled in 0.7.0.
- New env knobs only, all defaulted: `CLAUDE_VOICE_NOTIFY_CMD`,
  `CLAUDE_VOICE_NOTIFY_CMD_QUIET_UNDER`, `CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER`,
  `CLAUDE_VOICE_NOTIFY_NAG_EVERY`. No config file, no install command.

## Capabilities

### New Capabilities

- `voice-notify-command-cues`: the shell-command lifecycle as sound — a still-running cue for a
  command that outlives a threshold, a duration-gated completion cue naming the command and its
  outcome, background-command completion detected by task id across `Stop` events, the
  single-elected-watcher mechanism that makes mid-flight announcement possible, and the rule that
  none of it changes what counts as outstanding work.
- `voice-notify-blocked-session-cues`: the states in which the session is stuck waiting and would
  otherwise be silent — a turn ended by an API error (`StopFailure`), and a permission prompt that
  stays unanswered, which is re-announced on an interval until it is resolved.

### Modified Capabilities

- `voice-notify-agent-identity`: the sanitisation requirement is currently scoped to *agent*
  descriptions. It broadens to cover every model-authored description the plugin speaks, so a
  `Bash` call's `description` is sanitised, truncated and passed as a single quoted argument under
  the same rules and the same `CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX` limit.

## Impact

- `plugins/voice-notify/scripts/notify.sh` — new event arms (`cmd-start`, `cmd-result`,
  `stop-failure`, `perm-request`), the watcher loop, new phrase pools, new config parsing.
- `plugins/voice-notify/.claude-plugin/plugin.json` — new `StopFailure` and `PermissionRequest`
  hooks; `PreToolUse` gains a `Bash` matcher; the `PostToolUse`/`PostToolUseFailure` matcher
  widens from `Agent` to `*` so a permission prompt can be disarmed by any tool completing. This
  is the one real cost of the change: the script runs on every tool call, so it must exit on its
  first decision unless the tool is `Agent`/`Bash` or a permission marker exists.
- `plugins/voice-notify/README.md` and the root `README.md` — document the new cues and knobs.
- `plugins/voice-notify/tests/` — new cases for each cue, plus watcher election and exit.
- No new dependencies. Still `$TMPDIR`-only state, so `/plugin uninstall` remains the complete
  revert and no install/uninstall command is needed.
