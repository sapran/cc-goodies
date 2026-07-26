## 1. Manifest and event plumbing

- [x] 1.1 Add the `PostToolUse` hook with matcher `Agent` to `plugin.json`, invoking
  `notify.sh agent-result` (async, short timeout), and bump nothing else in the manifest
- [x] 1.2 Add the `agent-result` arm to `notify.sh`'s event dispatch, honouring the global mute,
  the `say` no-op, and `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` before doing any work
- [x] 1.3 Verify `jq empty` on the manifest and `bash -n` on the script

## 2. Configuration and helpers

- [x] 2.1 Add `CLAUDE_VOICE_NOTIFY_AGENT_NAMES` (default on), `..._AGENT_NAME_CAP` (default 3),
  and `..._AGENT_DESC_MAX` (default 60), each digit-validated with fallback to the default
- [x] 2.2 Add `sanitise_desc`: strip control characters, collapse whitespace, neutralise `say`
  `[[...]]` directive syntax, truncate at a word boundary to the configured maximum
- [x] 2.3 Add `speak_locked`: create-only `$TMPDIR` lock dir with an epoch stamp, bounded wait,
  drop-on-contention, and reclaim of an abandoned lock older than a bounded interval
- [x] 2.4 Route every existing `speak` call for agent cues through `speak_locked`

## 3. Purpose resolution

- [x] 3.1 Add `agents_dir` per-session record dir; write `<agent_id>` → description at the
  background `PostToolUse` (`tool_response.status == "async_launched"`)
- [x] 3.2 Add `resolve_purpose`: try the payload's `background_tasks` self-entry by `id`, then
  the `agents.d` record, then `agent_type`, then empty (anonymous)
- [x] 3.3 Add `inflight_from_payload`: count `background_tasks[] | select(.type == "subagent")`
  excluding the current `agent_id`; return non-zero status when the field is absent so callers
  fall back to marker counting
- [x] 3.4 Prune `agents.d` records by the existing TTL alongside the spawn/done dirs

## 4. Dispatch cue naming

- [x] 4.1 Read `tool_input.description` at `dispatch` and append it to a per-burst pending list
  in `$TMPDIR` (create-only entries, no read-modify-write)
- [x] 4.2 On the cue-speaking dispatch, compose from the pending list: 1 agent named, 2 named,
  ≥3 as count + first; fall back to the anonymous pool when the list yields no description
- [x] 4.3 Clear the pending list once the burst's cue is spoken

## 5. Completion cues

- [x] 5.1 At `agent-result` with `tool_response.status == "completed"` (foreground), speak a
  named completion cue using `tool_input.description`
- [x] 5.2 At `subagent-stop`, speak a named completion cue only when the agent is background —
  determined by a `background_tasks` self-entry or an `agents.d` record — so foreground agents
  are voiced exactly once, by `agent-result`
- [x] 5.3 Add the success and failure core pools; select failure when the response indicates
  failure, interruption, or an absent result
- [x] 5.4 Suppress the individual cue when in-flight exceeds `..._AGENT_NAME_CAP`, and record the
  suppression in per-turn batch state

## 6. Drain roll-up

- [x] 6.1 Set a per-turn "waiting cue spoken" flag when `Stop` speaks the waiting cue
- [x] 6.2 On the completion that brings in-flight to zero, speak a roll-up from its own pool when
  either the waiting flag or the suppression flag is set; then clear both
- [x] 6.3 Clear per-turn batch state at `start` (`UserPromptSubmit`) so flags never leak between
  turns

## 7. Notification routing

- [x] 7.1 Extend `classify()` to read `notification_type` when present and route
  `agent_completed` / `agent_needs_input` to their own subtypes, keeping wording-based matching
  as the fallback
- [x] 7.2 Render the agent's label from the message in the first person for those subtypes,
  preserving the existing neutral fallback for unrecognised wording

## 8. Tests

- [x] 8.1 Extend `tests/run.sh` fixtures with `background_tasks`-bearing `SubagentStop` payloads,
  foreground and background `PostToolUse` payloads, and burst dispatch payloads
- [x] 8.2 Cover dispatch naming: 1 / 2 / ≥3 forms and the no-description fallback
- [x] 8.3 Cover completion routing: foreground voiced once at `agent-result`, background voiced
  once at `subagent-stop`, `async_launched` silent, no double-speak
- [x] 8.4 Cover the name cap (named at/below, suppressed above) and both roll-up trigger paths,
  plus the no-roll-up case when every agent was named
- [x] 8.5 Cover purpose fallbacks (task-list entry → record → agent type → anonymous) and the
  marker fallback when `background_tasks` is absent
- [x] 8.6 Cover sanitisation: long, multiline, control-character, `[[slnc]]`-bearing, and
  shell-metacharacter descriptions
- [x] 8.7 Cover the mutes (`CLAUDE_VOICE_NOTIFY=off`, `..._SUBAGENT=off`, `..._AGENT_NAMES=off`),
  the missing-`jq` degradation, and the non-macOS no-op for the new events
- [x] 8.8 Cover lock serialisation: contended cue dropped, abandoned lock reclaimed
- [x] 8.9 Run the full suite plus `shellcheck` and `bash -n` and confirm all pass

## 9. Documentation

- [x] 9.1 Update `plugins/voice-notify/README.md`: the new cues, the foreground/background split,
  the roll-up rule, and the three new env vars in the configuration table
- [x] 9.2 Update the root `README.md` voice-notify entry and `CLAUDE.md`'s plugin table row to
  name the new hook set and behaviour
- [x] 9.3 Add the `CHANGELOG.md` entry under `[Unreleased]` and bump the plugin version line
  (the marketplace `.metadata.version` bumps at release, not here)
