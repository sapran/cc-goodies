## 1. Broaden the authoritative in-flight count

- [ ] 1.1 Change the `jq` filter in `inflight_payload()` from `select(.type == "subagent")` to a
      block-list that keeps every entry whose type is neither `shell` nor `monitor`
- [ ] 1.2 Update the function's header comment to state the block-list rule and why unknown types
      count as outstanding
- [ ] 1.3 Add a comment on `inflight_markers()` recording that the fallback deliberately tracks
      only `Agent` dispatches, and why extending it is not worth doing

## 2. Add the busy marker

- [ ] 2.1 Add a `busy_file()` path helper alongside the other `$TMPDIR` state helpers
- [ ] 2.2 Add a `set_busy <sid> <count>` helper that writes the marker when the count is above
      zero and removes it when the count is zero
- [ ] 2.3 Call `set_busy` from the `stop` arm after the authoritative count is resolved
- [ ] 2.4 Call `set_busy` from the `subagent-stop` arm after its count is resolved
- [ ] 2.5 Call `set_busy` from the `agent-result` arm after its count is resolved
- [ ] 2.6 Delete the marker in the `start` arm, so a new user prompt always clears it
- [ ] 2.7 Add an `is_busy <sid>` helper that reports true only when the marker exists and is
      newer than `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL`

## 3. Gate the idle notification

- [ ] 3.1 In the `notification` arm, after `classify`, exit without speaking when the subtype is
      `idle` and `is_busy` reports true
- [ ] 3.2 Verify by inspection that `permission`, `agent_input`, `agent_done` and `neutral` are
      unaffected
- [ ] 3.3 Ensure the gate is skipped entirely when `CLAUDE_VOICE_NOTIFY_SUBAGENT=off`

## 4. Tests

- [ ] 4.1 Add helpers to `tests/run.sh` for building a `background_tasks` payload of a given type
      and for reading/writing the busy marker
- [ ] 4.2 `Stop` with only a `workflow` task speaks the waiting cue, not a sign-off
- [ ] 4.3 `Stop` with only a `shell` task speaks the normal sign-off
- [ ] 4.4 `Stop` with only a `monitor` task speaks the normal sign-off
- [ ] 4.5 `Stop` with a `teammate` task, and with a `cloud session` task, speaks the waiting cue
- [ ] 4.6 `Stop` with an unrecognised task type speaks the waiting cue
- [ ] 4.7 `Stop` with work outstanding writes the busy marker; a following idle notification is
      silent
- [ ] 4.8 `Stop` with an empty task list deletes the busy marker; a following idle notification
      speaks
- [ ] 4.9 A permission notification still speaks while the busy marker is set
- [ ] 4.10 The `start` event deletes the busy marker
- [ ] 4.11 A busy marker older than the TTL is ignored and the idle cue speaks
- [ ] 4.12 With `CLAUDE_VOICE_NOTIFY_SUBAGENT=off`, no marker is written and the idle cue speaks
- [ ] 4.13 Run the whole suite and confirm every pre-existing case still passes

## 5. Checks and documentation

- [ ] 5.1 `bash -n` and `shellcheck` clean on `scripts/notify.sh` and `tests/run.sh`
- [ ] 5.2 `jq empty` clean on the plugin manifest and the marketplace manifest
- [ ] 5.3 Update the plugin README: the waiting-cue section covers all background-work kinds and
      names the two exclusions; add the idle-notification suppression
- [ ] 5.4 Update the root README and the `CLAUDE.md` plugin table row for `voice-notify`
- [ ] 5.5 Add the CHANGELOG entry
- [ ] 5.6 Bump `plugins/voice-notify/.claude-plugin/plugin.json` to 0.7.0 and the marketplace
      `metadata.version`
