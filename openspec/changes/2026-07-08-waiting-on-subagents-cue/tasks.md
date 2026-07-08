## 1. Script — in-flight accounting + waiting cue (`scripts/notify.sh`)

- [x] 1.1 Parse `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` (default 3600, digit-validated), following the existing env→default pattern.
- [x] 1.2 Add helpers: `spawn_dir()`/`done_dir()` (per-sid `$TMPDIR` paths), a create-only marker writer (`mark`, epoch content), a prune-by-content step (`prune_dir`), and a globbing file counter (`count_dir`).
- [x] 1.3 Add a `WAITING_CORES` phrase pool, distinct from `STOP_CORES`/`STOP_LONG_CORES` and `SUBAGENT_CORES`; route through `compose()` with `NEUTRAL_GARNISH`.
- [x] 1.4 In the `dispatch` arm, after the mute/say guards and `session_id`, write one uniquely-named spawn marker **unconditionally** (before the debounce, so every spawn counts even when the cue is debounced).
- [x] 1.5 Add a `subagent-stop` arm: honour global mute + `say` + `CLAUDE_VOICE_NOTIFY_SUBAGENT`; write one done marker named by sanitized `agent_id` (unique fallback if absent); speak nothing.
- [x] 1.6 In the `stop` arm, after consuming the start file: if `CLAUDE_VOICE_NOTIFY_SUBAGENT` is on, prune both dirs by TTL, compute in-flight; if in-flight > 0 speak a `WAITING_CORES` cue (bypassing the duration gate) and exit; else fall through to the existing gate + sign-off pools unchanged.

## 2. Manifest — wire `SubagentStop` (`.claude-plugin/plugin.json`)

- [x] 2.1 Add a `SubagentStop` hook (matcher `*`) calling `notify.sh` with `subagent-stop` (`async: true`, `timeout: 5`), mirroring the existing entries.
- [x] 2.2 Bump `plugins/voice-notify/.claude-plugin/plugin.json` `version` (`0.4.0` → `0.5.0`, minor — additive).
- [x] 2.3 `jq empty plugins/voice-notify/.claude-plugin/plugin.json` and `claude plugins validate plugins/voice-notify` — both pass.

## 3. Tests (`tests/run.sh`)

- [x] 3.1 `dispatch` writes a spawn marker under `vn-<sid>.spawn.d/`; `subagent-stop` writes a done marker under `vn-<sid>.done.d/` keyed by `agent_id` and is idempotent on repeat. (Added `mkdir` to the isolated PATH; added marker helpers + `J_SUBSTOP` fixture.)
- [x] 3.2 `stop` with spawn > done → a `WAITING_CORES` phrase is spoken, and it is NOT a member of `STOP_CORES`/`STOP_LONG_CORES` nor `SUBAGENT_CORES`.
- [x] 3.3 Waiting cue bypasses the duration gate: a quick turn (< `QUIET_UNDER`) with in-flight > 0 still speaks.
- [x] 3.4 Foreground balance: spawn == done → the standard sign-off speaks (no regression); zero markers → unchanged behaviour (existing gate tests still green).
- [x] 3.5 TTL prune: a spawn marker older than the TTL is ignored → `stop` falls back to the normal sign-off, and the stale marker is removed.
- [x] 3.6 `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` disables accounting + waiting cue (Stop signs off despite an in-flight marker); global mute + non-macOS no-op silence `subagent-stop` with clean exit and no marker.
- [x] 3.7 `bash -n` + `shellcheck` on `notify.sh` clean; full `tests/run.sh` green (38/38).

## 4. Docs + release

- [x] 4.1 `plugins/voice-notify/README.md`: the waiting cue ("What you'll hear" + a new "Waiting-on-subagents cue" section), the `SubagentStop` hook, and the `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` knob in the config table.
- [x] 4.2 Root `README.md` + `CLAUDE.md` voice-notify blurbs: lineup now includes a `SubagentStop` hook and the waiting-at-turn-boundary cue.
- [x] 4.3 Bump marketplace `metadata.version` (`0.9.0` → `0.10.0`) in `.claude-plugin/marketplace.json` + voice-notify blurb; add a `CHANGELOG.md` entry.
- [x] 4.4 `claude plugins validate plugins/voice-notify` and `jq empty .claude-plugin/marketplace.json` — both pass.
- [ ] 4.5 Commit on the change branch, push, open a draft PR to `develop`. (Archive + `main` FF happen after review, per the repo release flow.)
