## Context

`plugins/statusline/statusline-command.sh` renders a two-line statusline. Line 2 today is:

```
Opus 4.8 (xhigh)  c:42%  s:18%  w:5%
```

— model, effort, then three percentage gauges: `c:` context-window used
(`context_window.used_percentage`), `s:` 5-hour session limit used
(`rate_limits.five_hour.used_percentage`), `w:` 7-day weekly limit used
(`rate_limits.seven_day.used_percentage`). The script's design constraints are explicit in
its header: **one** `jq` parse per render, bounded transcript reads, short-lived caches, and
clean degradation when a dependency or field is missing (it targets macOS bash 3.2 and BSD
userland but must not hard-fail elsewhere).

The statusline stdin JSON already carries three fields this script reads but does not
display:

- `cost.total_duration_ms` — wall-clock since session start, milliseconds.
- `rate_limits.five_hour.resets_at` — Unix epoch (seconds) when the 5-hour window resets.
- `rate_limits.seven_day.resets_at` — Unix epoch (seconds) when the 7-day window resets.

The `rate_limits` object appears only for Claude.ai Pro/Max subscribers and only after the
first API response in a session; each window may be independently absent. The script already
caches the two gauge percentages (`$cache_dir/claude-ratelimits.cache`) precisely because
`rate_limits` is intermittently absent between renders.

## Goals / Non-Goals

**Goals:**

- Show, beside the `s:` and `w:` gauges, how long until each window resets (countdown).
- Show, beside the `c:` gauge, how long the current session has run (elapsed).
- Stay within the existing two-line layout and the single-`jq`-parse budget.
- Keep countdowns live across renders where `rate_limits` is absent, by caching the epochs.
- Degrade to today's exact output when the new fields are unavailable.

**Non-Goals:**

- Absolute clock-time / day-of-week rendering of resets (countdown chosen instead).
- A third statusline line or any relocation of existing segments or line 1.
- Alerting, colour changes, or threshold-based emphasis on the gauges.
- Sourcing reset/usage data from anywhere other than the statusline stdin JSON.

## Decisions

### D1 — Countdown, not absolute clock time

Render `⟲2h45m` / `⟲3d4h`, not `⟲17:30` / `⟲Wed09:00`. **Why:** the actionable question is
"how long until I can resume," which a countdown answers directly; an absolute time forces a
mental subtraction. Countdown is also format-portable — a clock for the 7-day window needs
day-of-week and is locale-sensitive, whereas a countdown is pure arithmetic on epoch
seconds. *Alternative considered:* absolute clock, and "both" (countdown + parenthesised
clock); rejected as wider on narrow terminals and not worth the formatting cost. (User-confirmed.)

### D2 — Inline suffixes, two lines preserved

Each new value is a dim suffix glued to the gauge it describes (`c:42% 1h23m`,
`s:18% ⟲2h45m`, `w:5% ⟲3d4h`). **Why:** smallest change to a deliberately lean layout;
preserves the existing line-1/line-2 structure; the reset reads as belonging to its gauge.
*Alternatives considered:* a regrouped limits cluster with a divider, and a dedicated third
line; both rejected to keep the footprint at two lines. (User-confirmed.)

### D3 — Distinct per-kind glyphs: `⧗` for elapsed, `⟲` for resets

Reset countdowns carry the `⟲` glyph; the session duration carries an hourglass `⧗`. **Why:**
duration counts *up* (elapsed) and the limits count *down* (until reset). Reusing `⟲` on the
duration would imply the context window "resets," which it does not — so duration gets its own
marker instead. Each readout kind is thus glyph-marked while `⟲` stays unique to
countdown-to-reset, letting both share one humaniser without reading ambiguously. `⧗`
(U+29D7) is single-width and monospace-safe, matching the existing `⟲` aesthetic and the
script's column-alignment math. *Alternative considered:* leaving duration bare (no glyph),
and a double-width watch emoji (`⌚`); the bare form lost the at-a-glance "this is elapsed
time" cue, and the emoji is double-width with a variation selector that risks misaligning the
line. (User-confirmed.)

### D4 — One shared seconds→human formatter, two units max, no spaces

A single helper formats a non-negative integer seconds value: `≥1d → <d>d<h>h`,
`≥1h → <h>h<m>m`, else `<m>m`. Used for both the elapsed duration (`total_duration_ms/1000`)
and each reset countdown (`resets_at − now`). **Why:** one code path, consistent look, and a
two-unit cap keeps every token short enough to glue to a gauge. Implemented in pure bash
integer arithmetic (no `date -d @epoch`, which is GNU-only and absent on the macOS BSD `date`
this script targets). "now" comes from `date +%s`, already used elsewhere in the script for
cache-mtime checks — no new dependency.

### D5 — Extend the existing rate-limit cache to carry the two epochs

The percentage cache file currently stores two integers (`5h% 7d%`). Extend its single line
to also hold the two reset epochs (`5h% 7d% 5h_epoch 7d_epoch`). On a render where the JSON
omits `rate_limits`, read the cached epoch and recompute the countdown against `now`. **Why:**
mirrors the existing percentage-persistence mechanism, so countdowns behave like the gauges
they attach to. A stale 2-field cache from a prior version simply yields empty epochs (no
countdown) until the next fresh render repopulates it — forward/backward safe. The duration
needs no cache: `cost.total_duration_ms` is present on every render.

### D6 — New fields ride the single `jq` parse

Add `cost.total_duration_ms`, `rate_limits.five_hour.resets_at`, and
`rate_limits.seven_day.resets_at` as additional lines in the existing `jq -r '...'` selector,
read into new variables by the same per-line `read` block. **Why:** the script's stated
performance invariant is one parse per render; a second `jq` call to fetch the new fields
would violate it for no benefit.

### D7 — Stale-epoch and non-numeric guards

If a computed countdown is ≤ 0 (the reset moment has passed), render no suffix — a lapsed
window has nothing to count down to. If a `resets_at` value is non-numeric (defensive against
the field arriving as an ISO string or milliseconds rather than epoch seconds), treat it as
absent and render no suffix rather than printing garbage. **Why:** the field schema is sourced
from current docs but should be verified against a live render; failing closed to "no suffix"
keeps a schema surprise from corrupting the line.

## Risks / Trade-offs

- **Reset field shape differs from the documented `resets_at` epoch-seconds** (e.g. arrives as
  milliseconds or an ISO-8601 string) → numeric-guard each value (D7) so a mismatch renders
  nothing rather than garbage; verify against one live Pro/Max render during implementation
  before finalising the format.
- **Width on narrow terminals** — line 2 gains up to three short tokens → accepted by the
  inline-layout choice (D2); each token is ≤ ~7 chars and only appears when its data exists.
- **Clock skew between `date +%s` and the server-side reset epoch** → countdown may be off by
  the skew; acceptable for an at-a-glance readout, and no worse than the gauge percentages'
  own staleness between renders.
- **Cache-format change to `claude-ratelimits.cache`** → a line written by the old script
  (two fields) is read by the new script as "epochs absent"; the new four-field line is
  longer but still a single `read`. No migration needed; the file is ephemeral `$TMPDIR`
  state that self-heals on the next fresh render.
- **bash 3.2 / BSD `date` portability** — formatter and "now" use only integer arithmetic and
  `date +%s`, both available on the macOS target and on Linux; no GNU-only `date -d`.
