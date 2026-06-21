## 1. Phrasing core (script-only, no manifest change)

- [x] 1.1 Add a `compose()` helper to `notify.sh`: draw one core (always) and one garnish with probability `CLAUDE_VOICE_NOTIFY_GARNISH_PCT` (default 40); when garnish drawn, join `garnish + pause + core`, else emit bare core
- [x] 1.2 Add the prosody pause constant (macOS `say` `[[slnc 250]]`) used by `compose()`; verify it is never spoken as literal text
- [x] 1.3 Define small per-context pools as bash-3.2-safe newline lists fed to the existing `pick()`: `Stop` cores (standard + long-turn), garnishes (brisk / gentle / neutral)
- [x] 1.4 Route `Notification` by message subtype (permission / idle-waiting / neutral fallback) selecting the matching garnish pool and first-person core
- [x] 1.5 Rewrite the first-person reason transform as an allow-list (known shapes only); remove the catch-all `gsub("Claude"; "I")`; unrecognised / missing-`jq` / empty ⇒ neutral fallback
- [x] 1.6 Repoint the `stop` and `notification` `case` arms to `compose()`; keep mute switch, non-macOS no-op, voice resolution, and `pick()` intact

## 2. Duration gate (adds one hook + ephemeral state)

- [x] 2.1 Add a `UserPromptSubmit` hook to `plugin.json` invoking `notify.sh start` (async, short timeout)
- [x] 2.2 In `notify.sh`, handle `start`: read `session_id` from stdin JSON, guard against empty id, write `epoch_seconds` to `$TMPDIR/vn-<session_id>.start`
- [x] 2.3 In the `stop` arm: read `session_id`, read the start file, compute elapsed, then remove the start file
- [x] 2.4 Apply the gate: elapsed below `CLAUDE_VOICE_NOTIFY_QUIET_UNDER` (default 20) ⇒ exit silently; at/above ⇒ speak; unknown/missing/garbled ⇒ speak with default pool (fail-audible)
- [x] 2.5 When elapsed is known and above threshold, select the long-turn core pool for duration-relative phrasing

## 3. Configuration & docs

- [x] 3.1 Implement env precedence (env var → default) for `CLAUDE_VOICE_NOTIFY_QUIET_UNDER` and `CLAUDE_VOICE_NOTIFY_GARNISH_PCT`; no conf file, no `source`
- [x] 3.2 Confirm existing knobs unchanged: `CLAUDE_VOICE`, `CLAUDE_VOICE_NOTIFY=off`
- [x] 3.3 Update `plugins/voice-notify/README.md`: new env table rows, duration-gate behaviour (quiet on short turns, set threshold to 0 to speak every turn), updated "what you'll hear"
- [x] 3.4 Bump `plugins/voice-notify/.claude-plugin/plugin.json` version; update `.claude-plugin/marketplace.json` description, root `README.md`, and `CHANGELOG.md` if user-visible

## 4. Validation

- [x] 4.1 `bash -n plugins/voice-notify/scripts/notify.sh` and `shellcheck` clean
- [x] 4.2 `jq empty` on `plugin.json` and `.claude-plugin/marketplace.json`
- [x] 4.3 Synthetic-stdin tests (with `say` stubbed) asserting spoken vs silent and pool choice: permission / idle / neutral notification; Stop below / at / above threshold; unknown duration; missing-`jq`; non-macOS no-op; `CLAUDE_VOICE_NOTIFY=off` — `plugins/voice-notify/tests/run.sh`, 15/15 pass
- [x] 4.4 Confirm no writes outside the plugin dir and `$TMPDIR`; `/plugin uninstall` leaves nothing behind
- [ ] 4.5 Manual listen-through on macOS across each subtype to confirm cadence/prosody sound natural — **user step** (requires actually invoking `say`; not auto-run)
