## 1. Parse the new fields (single jq)

- [x] 1.1 Extend the existing `jq -r '...'` selector in `statusline-command.sh` to also emit `cost.total_duration_ms`, `rate_limits.five_hour.resets_at`, and `rate_limits.seven_day.resets_at` (each with a `// ""` fallback), keeping it a single `jq` invocation
- [x] 1.2 Add matching `IFS= read -r` lines to the per-line read block so each new field lands in its own variable (`dur_ms`, `rl_5h_reset`, `rl_7d_reset`), preserving empty-field alignment

## 2. Shared time humaniser

- [x] 2.1 Add a pure-bash `humanize_secs()` helper that takes non-negative integer seconds and returns `<d>d<h>h` (≥1 day), `<h>h<m>m` (≥1 hour), or `<m>m` (<1 hour), with no spaces
- [x] 2.2 Guard non-numeric / empty input to the helper so it returns empty (no output) rather than erroring; use integer arithmetic only (no `date -d @epoch`)

## 3. Reset countdowns + epoch caching

- [x] 3.1 Extend the `claude-ratelimits.cache` write to store the two reset epochs alongside the two percentages (single line: `5h% 7d% 5h_epoch 7d_epoch`)
- [x] 3.2 Extend the cache read so that when the JSON omits `rate_limits`, the cached epochs are recovered into `rl_5h_reset` / `rl_7d_reset` (tolerating an old 2-field cache line as "epochs absent")
- [x] 3.3 Compute `remaining = epoch - $(date +%s)` for each window; when the epoch is present, numeric, and `remaining > 0`, set a `s_reset` / `w_reset` suffix via `humanize_secs`; otherwise leave it empty (stale/absent ⇒ no suffix)

## 4. Session duration

- [x] 4.1 Convert `dur_ms` to seconds (integer divide by 1000) and, when present and > 0, format it with `humanize_secs` into a `c_dur` suffix; empty/zero ⇒ no suffix

## 5. Render line 2

- [x] 5.1 Append `c_dur` as a dim `⧗`-prefixed suffix to the `c:` gauge (hourglass glyph, distinct from the resets' `⟲`)
- [x] 5.2 Append `s_reset` as a dim `⟲`-prefixed suffix to the `s:` gauge, and `w_reset` likewise to the `w:` gauge, only when each suffix is non-empty
- [x] 5.3 Confirm line 1 and the model/effort segment are untouched and the output is still exactly two lines

## 6. Documentation

- [x] 6.1 Update the `plugins/statusline/README.md` example block to show `c:42% ⧗1h23m  s:18% ⟲2h45m  w:5% ⟲3d4h`
- [x] 6.2 Update the Line-2 legend in the README to describe the `⧗` elapsed-duration suffix on `c:` and the `⟲` reset countdowns on `s:`/`w:`, noting they appear only when Claude Code reports the data

## 7. Verify

- [x] 7.1 `bash -n plugins/statusline/statusline-command.sh` and `shellcheck plugins/statusline/statusline-command.sh` pass
- [x] 7.2 Pipe synthetic stdin JSON with all new fields present and assert line 2 shows the duration and both `⟲` countdowns in the expected positions
- [x] 7.3 Pipe synthetic stdin with `rate_limits` and `cost.total_duration_ms` absent and assert line 2 matches the pre-change output (graceful degradation), exit 0
- [x] 7.4 Pipe a render whose `resets_at` is in the past and assert no `⟲` suffix is shown; pipe a follow-up render with `rate_limits` omitted after one with a future epoch and assert the countdown persists from cache
- [x] 7.5 Spot-check the humaniser boundaries: `3d4h` (multi-day), `2h45m` (sub-day), `23m` (sub-hour)
