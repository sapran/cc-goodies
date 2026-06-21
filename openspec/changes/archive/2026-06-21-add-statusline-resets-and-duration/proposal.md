## Why

The `statusline` plugin already surfaces three *usage* gauges on line 2 — `c:` (context
window used), `s:` (5-hour session limit used), `w:` (7-day weekly limit used) — but only
as percentages. A percentage answers "how much is left," never "when does it free up."
When the session or weekly limit is climbing, the question that actually changes behaviour
is *when does it reset* — and that data already arrives in the same statusline stdin JSON
(`rate_limits.five_hour.resets_at`, `rate_limits.seven_day.resets_at`), unused. Likewise
`cost.total_duration_ms` is present but undisplayed, so there is no at-a-glance sense of
how long the current session has been running.

## What Changes

- **Add a reset countdown after the `s:` gauge** — render the time until the 5-hour
  session window resets, glued to the gauge as a dim suffix (e.g. `s:18% ⟲2h45m`).
- **Add a reset countdown after the `w:` gauge** — same, for the 7-day weekly window
  (e.g. `w:5% ⟲3d4h`).
- **Add session elapsed duration after the `c:` gauge** — render wall-clock time since the
  session started, from `cost.total_duration_ms`, as a dim suffix marked with an hourglass
  glyph (e.g. `c:42% ⧗1h23m`). Elapsed time counts up, so it gets its own `⧗` glyph rather
  than the resets' `⟲`: each readout kind is marked, while `⟲` still uniquely means
  countdown-to-reset — keeping the two visually distinct.
- **Keep the existing two-line layout.** The new values sit inline next to the gauge each
  belongs to; no third line, no relocation of existing segments. Line 1 is untouched.
- **Degrade exactly as the gauges already do.** A reset suffix appears only when its
  window's reset timestamp is present; the duration appears only when `total_duration_ms`
  is present and non-zero. Missing fields render nothing — never a placeholder or error.
- **Persist reset timestamps in the existing cache** so the countdowns stay live across
  renders where the JSON omits `rate_limits` (mirroring how the gauge percentages are
  already cached), recomputing "time remaining" from the cached epoch each render.
- **Update the plugin README** sample output and Line-2 legend to document the three new
  readouts.

No new dependencies, no new data source, no new external writes: the change reads two
already-present epoch fields plus one duration field, formats them, and extends the
script's existing private `$TMPDIR` cache. `/plugin uninstall` remains the full revert.

## Capabilities

### New Capabilities

- `statusline-time-readouts`: The statusline renders time-based companions to its usage
  gauges — session elapsed duration beside the context gauge, and reset countdowns beside
  the 5-hour and 7-day rate-limit gauges — each sourced from the statusline stdin JSON,
  each degrading silently when its source field is absent, all within the existing two-line
  layout and single-`jq`-parse performance budget.

### Modified Capabilities

<!-- None. No existing statusline spec exists in openspec/specs/; this is the first
     spec to cover statusline rendering behaviour. -->

## Impact

- **Code:** `plugins/statusline/statusline-command.sh` — extend the single `jq` selector to
  also emit `cost.total_duration_ms`, `rate_limits.five_hour.resets_at`, and
  `rate_limits.seven_day.resets_at`; add a shared seconds→`XdYh`/`XhYm`/`Xm` humaniser; cache
  the two reset epochs alongside the existing percentage cache; extend the line-2 render.
- **Docs:** `plugins/statusline/README.md` — refresh the example block and the Line-2 legend.
- **Dependencies:** none added. Still `jq` + `git`, still macOS-tuned with graceful
  degradation elsewhere.
- **Install/uninstall:** unchanged — no new setup step, no new durable external state, so the
  documented install ⇄ uninstall symmetry holds with `/plugin uninstall` as the full revert.
- **Out of scope:** absolute clock-time rendering, alerting/thresholds, colour changes to the
  gauges, and any line-1 changes.
