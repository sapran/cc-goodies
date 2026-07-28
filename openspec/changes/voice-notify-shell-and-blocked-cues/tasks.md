## 1. Config and shared plumbing

- [ ] 1.1 Add the new env knobs with digit-validated parsing beside the existing ones:
      `CLAUDE_VOICE_NOTIFY_CMD` (on/off), `CLAUDE_VOICE_NOTIFY_CMD_QUIET_UNDER` (60),
      `CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER` (45), `CLAUDE_VOICE_NOTIFY_NAG_EVERY` (60),
      `CLAUDE_VOICE_NOTIFY_NAG_MAX` (5) — malformed values fall back to the default
- [ ] 1.2 Add `$TMPDIR` path helpers for the new state: command start markers, announced
      markers, background task records, permission reminder records, watcher election
- [ ] 1.3 Extend the TTL pruning helper to cover the new marker kinds
- [ ] 1.4 Confirm the description sanitiser is callable for command descriptions with no change
      to its behaviour for agents (single shared path, per the modified identity spec)

## 2. Phrase pools

- [ ] 2.1 Add the command still-running pool, distinct from the subagent and sign-off pools
- [ ] 2.2 Add the command completion pools: success, failure, timed out, interrupted
- [ ] 2.3 Add the background-command completion pool, phrased so it does not imply immediacy
- [ ] 2.4 Add the stalled pool with per-cause variants (rate limit, overload, auth, billing,
      output limit) and a generic fallback
- [ ] 2.5 Add the permission-reminder pool, audibly a repeat rather than a fresh request

## 3. Foreground command completion

- [ ] 3.1 Add the `cmd-result` arm: read `duration_ms`, fall back to the start record, gate on
      `CMD_QUIET_UNDER`, speak the named completion cue through the speech lock
- [ ] 3.2 Route `PostToolUseFailure` for `Bash` to the failure phrasing, reading `is_timeout`
      and `is_interrupt` for the distinct cases
- [ ] 3.3 Always speak the completion cue when the command has an announced marker, whatever
      its duration; clear the marker afterwards
- [ ] 3.4 Never read `tool_input.command`; use the description or the anonymous fallback

## 4. Watcher and the still-running cue

- [ ] 4.1 Add the `cmd-start` arm: write the start marker (epoch + sanitised description) keyed
      by `tool_use_id`, then attempt the create-only election
- [ ] 4.2 Implement the watcher loop: poll, speak for un-announced markers past
      `CMD_RUNNING_AFTER`, speak due reminders, prune stale records
- [ ] 4.3 Exit the watcher when no start markers and no pending reminders remain
- [ ] 4.4 Bound the watcher's own lifetime below its declared hook timeout so it is never killed
      mid-cue; release the election on exit
- [ ] 4.5 Make the election reclaimable by age, mirroring the speech lock's reclaim

## 5. Background command completion

- [ ] 5.1 In the `cmd-result` arm, when `tool_response.backgroundTaskId` is present, record
      `id → description` and speak nothing (launch acknowledgement)
- [ ] 5.2 In the `stop` and `subagent-stop` arms, compare recorded ids against
      `background_tasks[].id`; speak and remove the records whose ids are gone
- [ ] 5.3 Leave records untouched when the event carries no task list
- [ ] 5.4 Verify the in-flight count is unchanged — `shell` stays excluded from the block-list
      and no busy marker is written for commands

## 6. Blocked-session cues

- [ ] 6.1 Add the `stop-failure` arm: speak the cause-named stalled cue, ignore the duration
      gate, and perform the same per-turn cleanup as the `stop` arm
- [ ] 6.2 Add the `perm-request` arm: write the reminder record (epoch, tool name, repeat count)
      keyed by `tool_use_id`, and elect a watcher if none is running
- [ ] 6.3 Speak reminders from the watcher every `NAG_EVERY` seconds, incrementing the repeat
      count, stopping at `NAG_MAX`
- [ ] 6.4 Disarm on the matching `PostToolUse`/`PostToolUseFailure` and on `PermissionDenied`
- [ ] 6.5 Clear all reminder records at `UserPromptSubmit`
- [ ] 6.6 Ensure reminders work while `CLAUDE_VOICE_NOTIFY_CMD=off`

## 7. Manifest wiring

- [ ] 7.1 Add `StopFailure` and `PermissionRequest` hooks
- [ ] 7.2 Add the `Bash` matcher to `PreToolUse` (`cmd-start`)
- [ ] 7.3 Widen `PostToolUse` and `PostToolUseFailure` to `*`, dispatching by tool name inside
      the script
- [ ] 7.4 Add the early-exit guard as the script's first decision for uninteresting tools
- [ ] 7.5 Set a timeout on the `cmd-start` hook large enough for the watcher's bounded lifetime
- [ ] 7.6 `jq empty` the manifest and `claude plugins validate plugins/voice-notify`

## 8. Tests

- [ ] 8.1 Duration gate: long command speaks, quick command silent, zero threshold always
      speaks, missing duration falls back to the start record
- [ ] 8.2 Outcomes: success, failure, timeout and interruption each produce distinct phrasing
- [ ] 8.3 Still-running: announced once only, never for a short command, disabled at zero
- [ ] 8.4 An announced command always reports completion, below threshold and on failure
- [ ] 8.5 Watcher: one election for a burst, exits when nothing outstanding, re-elected by a
      later command, abandoned election reclaimed by age
- [ ] 8.6 Background: launch acknowledgement silent, absent id speaks once, present id silent,
      no task list leaves records intact
- [ ] 8.7 The command string never reaches the stubbed `say`, including a command carrying a
      secret-looking value
- [ ] 8.8 In-flight accounting unchanged: a running background command still lets the sign-off
      speak and writes no busy marker
- [ ] 8.9 `StopFailure`: speaks per cause, ignores the duration gate, no sign-off, clears turn
      state, generic fallback without `jq`
- [ ] 8.10 Reminders: repeat on interval, name the tool, stop at `NAG_MAX`, disarm on approval,
      on denial and on a new prompt, per-prompt independence, work with the command path muted
- [ ] 8.11 Mutes and degradation: global mute, command mute, absent `say`, absent `jq`,
      malformed knobs
- [ ] 8.12 Early-exit: an uninteresting tool's `PostToolUse` does no work and speaks nothing

## 9. Docs and release hygiene

- [ ] 9.1 Update `plugins/voice-notify/README.md`: new cues in "What you'll hear", the five new
      knobs, sections for the watcher, background latency, and the reminder bound
- [ ] 9.2 Mirror the summary in the root `README.md` and the `CLAUDE.md` plugin table row
- [ ] 9.3 State explicitly in the README that the command string is never spoken
- [ ] 9.4 `bash -n` and `shellcheck` the script; run the full test harness
- [ ] 9.5 Bump `plugins/voice-notify/.claude-plugin/plugin.json` and the marketplace version,
      update `CHANGELOG.md`
