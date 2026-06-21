## 1. Severity colour helper

- [x] 1.1 Add a pure-bash variadic `gauge_sgr <value> <min:sgr>...` helper to `statusline-command.sh` that walks ascending `min:sgr` tier tokens and echoes the SGR params for the highest tier whose `min` the value reaches, defaulting to green `38;5;34` below the first token (split `min` with `${tier%%:*}`, colour with `${tier#*:}` — the colour's `;` never collides with the single `:` delimiter)
- [x] 1.2 Guard non-numeric / empty `value` in the helper by treating it as green, so a malformed value never errors, consistent with the script's fail-soft posture; positional `"$@"` + integer `-ge` comparisons only (bash 3.2 / BSD safe)

## 2. Integer value for the context gauge

- [x] 2.1 Inside the existing `[ -n "$used" ]` render block, compute `used_int=$(printf '%.0f' "$used")` once so the context gauge has an integer to threshold on (the `s:`/`w:` gauges already have `rl_5h_int` / `rl_7d_int`)

## 3. Colour the three gauges by severity

- [x] 3.1 Replace the flat `\033[35m` (magenta) on the `c:` gauge `printf` with `\033[$(gauge_sgr "$used_int" 25:'38;5;178' 50:'38;5;208' 75:'1;38;5;196')m` (four-tier green/yellow/amber/red), keeping the `c:NN%` token and `\033[0m` reset intact
- [x] 3.2 Replace the flat magenta on the `s:` gauge with `\033[$(gauge_sgr "$rl_5h_int" 50:'38;5;208' 80:'1;38;5;196')m` (three-tier)
- [x] 3.3 Replace the flat magenta on the `w:` gauge with `\033[$(gauge_sgr "$rl_7d_int" 50:'38;5;208' 75:'1;38;5;196')m` (three-tier)

## 4. Neutralise the time suffixes

- [x] 4.1 Change the `⧗` duration suffix colour from `2;35` (dim magenta) to `2;37` (dim grey)
- [x] 4.2 Change both `⟲` reset-countdown suffix colours (`s:` and `w:`) from `2;35` to `2;37`

## 5. Documentation

- [x] 5.1 Update the `plugins/statusline/README.md` Line-2 legend to describe the per-gauge severity colours and their green/amber/red thresholds, and that the time suffixes are neutral dim grey
- [x] 5.2 Keep the README static example block representative (it can show one tier state); note that gauge colour reflects fill level

## 6. Verify

- [x] 6.1 `bash -n plugins/statusline/statusline-command.sh` and `shellcheck plugins/statusline/statusline-command.sh` pass
- [x] 6.2 Pipe synthetic stdin with `c`/`s`/`w` values straddling each gauge's boundaries and assert the emitted SGR code matches the expected tier per gauge — green `38;5;34`, yellow `38;5;178` (context gauge only), amber `38;5;208`, red `1;38;5;196` — including the inclusive lower edges (`c:25`→yellow, `c:50`→amber, `c:75`→red, `s:80`→red, `w:75`→red)
- [x] 6.3 Assert a red-band gauge carries the bold attribute and green/amber do not
- [x] 6.4 Assert a gauge in the red band still renders its `⟲`/`⧗` suffix in `2;37` (neutral grey), unaffected by the gauge tier
- [x] 6.5 Pipe stdin omitting `rate_limits` and assert the `s:`/`w:` gauges render nothing (degradation unchanged) and the output is still exactly two lines with line 1 untouched
- [x] 6.6 Confirm `jq` is still invoked exactly once for field extraction (no new parse) and no new files are written outside the `$TMPDIR` cache
