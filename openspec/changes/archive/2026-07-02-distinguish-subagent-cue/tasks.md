## 1. Spike — verify hook behaviour (blocking, before any wiring)

- [x] 1.1 Add a temporary logging hook (writes `hook_event_name` + key fields to a temp file) for `PreToolUse`, `SubagentStart`, `SubagentStop`, and `Stop`; do NOT speak anything yet. *(Done via the spike kit: a scratch-project `.claude/settings.json` logging to `~/vn-spike.log`.)*
- [x] 1.2 Run a real session that dispatches 3 parallel subagents; capture the event order to the temp log.
- [x] 1.3 Confirm the dispatch tool name (`Task` vs `Agent`) and that `PreToolUse` matches it; record the working matcher value. *(Result: tool name is `Agent`; matcher `Agent`.)*
- [x] 1.4 Determine whether `Stop` fires mid-turn during the subagent wait, and whether `Stop` double-fires after the last `SubagentStop`. Record findings in `design.md` Open Questions. *(Result: `Stop` fires once at true turn-end, after all `SubagentStop`; no mid-pause fire, no double-fire.)*
- [x] 1.5 Decide trigger source (`PreToolUse:<tool>` vs `SubagentStart`) and whether design decision D3's premature-`Stop` guard is needed. Remove the temporary logging hook. *(Trigger: `PreToolUse:Agent`, earliest signal. D3 not needed. Spike kit removed with `rm -rf ~/vn-spike ~/vn-spike.log`.)*

## 2. Script — dispatch arm + debounce (`scripts/notify.sh`)

- [x] 2.1 Add config parsing for `CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE` (default 10, digit-validated) and `CLAUDE_VOICE_NOTIFY_SUBAGENT` (default on), following the existing env→default pattern.
- [x] 2.2 Add a `SUBAGENT_CORES` phrase pool (distinct from `STOP_CORES`/`STOP_LONG_CORES`) and pick its garnish pool from the existing lead-ins.
- [x] 2.3 Add a `dispatch` case to the event switch: honour global mute, the new subagent mute, and the existing non-macOS no-op; resolve `session_id` via the existing helper.
- [x] 2.4 Implement the debounce: read `$TMPDIR/vn-<sid>.dispatch`; if `now - last < window` exit silently, else `speak "$(compose "$garnish" "$core")"` and (re)write the marker (epoch in file content, like `vn-<sid>.start`). Treat missing/corrupt marker as "speak".
- [x] 2.5 If the spike (1.4) requires it, implement D3: set an "active subagents" marker on dispatch, clear it at genuine turn-end, and have the `stop` arm suppress the sign-off while it is set. If not required, leave `Stop`/`SubagentStop` as-is (finishes silent). *(Spike showed `Stop` fires only at true turn-end → D3 not needed; `Stop`/`SubagentStop` left as-is, finishes silent.)*

## 3. Manifest — wire the hook(s) (`.claude-plugin/plugin.json`)

- [x] 3.1 Add the dispatch hook using the matcher confirmed in 1.3/1.5, calling `notify.sh` with the `dispatch` arg (`async: true`, short timeout), mirroring the existing hook entries. *(`PreToolUse` matcher `Agent`, `args:["dispatch"]`, `timeout:5`.)*
- [x] 3.2 If 2.5 ships the D3 guard, wire any extra event it needs (e.g. clearing the active marker); otherwise make no change to the `Stop` entry. *(D3 not shipped → `Stop` entry unchanged.)*
- [x] 3.3 Bump `plugins/voice-notify/.claude-plugin/plugin.json` `version` (minor — additive feature). *(`0.3.0` → `0.4.0`.)*
- [x] 3.4 `jq empty plugins/voice-notify/.claude-plugin/plugin.json` to confirm it still parses. *(Passes; `claude plugins validate` also passes.)*

## 4. Tests (`tests/run.sh`)

- [x] 4.1 Add `J_DISPATCH` fixture JSON and a `dispatch` run; assert a `SUBAGENT_CORES` phrase is spoken (with `GARNISH_PCT=0` for determinism).
- [x] 4.2 Assert debounce: two `dispatch` runs inside the window → exactly one cue; a run after the window → speaks again (drive the marker epoch via the existing temp dir, mirroring `stamp` as `dstamp`).
- [x] 4.3 Assert silence on subagent finish (no completion cue) and that the dispatch core is NOT a member of the `STOP_CORES`/`STOP_LONG_CORES` pools.
- [x] 4.4 Assert global mute, the new subagent mute, and non-macOS no-op all silence the `dispatch` event with clean exit.
- [x] 4.5 If D3 shipped, assert a mid-turn pause does not speak a sign-off while the active marker is set, and a true turn-end still speaks. *(D3 not shipped → no assertion needed; N/A.)*
- [x] 4.6 Run `bash -n` and `shellcheck` on `notify.sh`; run the full `tests/run.sh` green. *(`bash -n` OK, shellcheck clean, suite 25/25.)*

## 5. Docs + release

- [x] 5.1 Update `plugins/voice-notify/README.md`: new "still working on helpers" cue, the silence-on-finish behaviour, and the two new env vars in the config table. *(Added a "What you'll hear" bullet, a "Subagent hand-off cue" section, and two config rows.)*
- [x] 5.2 Update root `README.md` / `CLAUDE.md` voice-notify blurb only if the event lineup description changes. *(Both updated — the lineup gained `PreToolUse(Agent)`.)*
- [x] 5.3 Bump marketplace `metadata.version` in `.claude-plugin/marketplace.json` and add a `CHANGELOG.md` entry. *(`0.8.0` → `0.9.0`; entry added; marketplace voice-notify blurb updated.)*
- [x] 5.4 `claude plugins validate plugins/voice-notify` and `jq empty .claude-plugin/marketplace.json`. *(Both pass.)*
- [ ] 5.5 Follow the repo release flow (develop branch; user fast-forwards `main` from a terminal — the `Stop`/push guards block it from a session). *(Pending: commit on this branch → merge to develop → user FFs main. Not yet committed.)*
