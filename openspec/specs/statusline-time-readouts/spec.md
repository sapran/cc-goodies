# statusline-time-readouts Specification

## Purpose
TBD - created by archiving change add-statusline-resets-and-duration. Update Purpose after archive.
## Requirements
### Requirement: Rate-limit reset countdowns

The statusline SHALL render a countdown to reset beside each rate-limit gauge that is
displayed: the time remaining until the 5-hour session window resets, suffixed to the `s:`
gauge, and the time remaining until the 7-day weekly window resets, suffixed to the `w:`
gauge. Each countdown SHALL be computed as `resets_at - now`, where `resets_at` is the Unix
epoch (seconds) read from `rate_limits.five_hour.resets_at` and
`rate_limits.seven_day.resets_at` respectively in the statusline stdin JSON. Each countdown
SHALL be marked with a reset glyph (`⟲`) distinguishing it as a time-until-reset value, and
SHALL be rendered in a dim/secondary style so the gauge percentage remains the primary
figure.

#### Scenario: Session reset countdown renders next to s-gauge

- **WHEN** the stdin JSON reports `rate_limits.five_hour.used_percentage` greater than 0 and a `rate_limits.five_hour.resets_at` epoch that is in the future
- **THEN** line 2 renders the `s:` gauge immediately followed by a dim `⟲<remaining>` suffix (e.g. `s:18% ⟲2h45m`), where `<remaining>` is the humanised time until that epoch

#### Scenario: Weekly reset countdown renders next to w-gauge

- **WHEN** the stdin JSON reports `rate_limits.seven_day.used_percentage` greater than 0 and a `rate_limits.seven_day.resets_at` epoch that is in the future
- **THEN** line 2 renders the `w:` gauge immediately followed by a dim `⟲<remaining>` suffix (e.g. `w:5% ⟲3d4h`)

#### Scenario: Reset suffix is suppressed when its epoch is absent

- **WHEN** a gauge is shown but its corresponding `resets_at` field is absent from the stdin JSON and no cached epoch is available
- **THEN** that gauge renders its percentage with no `⟲` suffix, and no placeholder or error text is emitted

#### Scenario: A stale (past) reset epoch renders no countdown

- **WHEN** a `resets_at` epoch is present but is at or before the current time, so the computed remaining is zero or negative
- **THEN** no `⟲` suffix is rendered for that gauge (a lapsed window is treated as having no countdown to show)

### Requirement: Session elapsed duration

The statusline SHALL render the elapsed wall-clock duration of the current session as a
dim suffix to the context gauge (`c:`), sourced from `cost.total_duration_ms` in the
statusline stdin JSON (milliseconds since the session started). The duration SHALL be marked
with an hourglass glyph (`⧗`) distinct from the resets' `⟲` glyph: because elapsed time counts
up rather than down, it carries its own marker, while `⟲` remains reserved exclusively for
countdown-to-reset values — so each readout kind is visually distinct.

#### Scenario: Duration renders next to the context gauge

- **WHEN** the stdin JSON reports a `cost.total_duration_ms` greater than 0 and a `context_window.used_percentage`
- **THEN** line 2 renders the `c:` gauge immediately followed by a dim `⧗`-prefixed humanised elapsed duration, with no `⟲` glyph (e.g. `c:42% ⧗1h23m`)

#### Scenario: Duration is suppressed when absent or zero

- **WHEN** `cost.total_duration_ms` is absent, empty, or zero
- **THEN** the `c:` gauge renders with no duration suffix, and no placeholder or error text is emitted

### Requirement: Time humanisation format

Reset countdowns and the session duration SHALL share one humanisation of a non-negative
seconds value, producing a compact two-unit-or-fewer string: when the value is at least one
day it SHALL read `<d>d<h>h` (whole days and remaining whole hours); when at least one hour
but less than a day it SHALL read `<h>h<m>m` (whole hours and remaining whole minutes); when
less than one hour it SHALL read `<m>m` (whole minutes). The output SHALL contain no spaces
so it reads as a single token glued to its gauge.

#### Scenario: Multi-day value uses day+hour form

- **WHEN** a duration or countdown of 3 days and ~4 hours is formatted
- **THEN** the result is `3d4h`

#### Scenario: Sub-day value uses hour+minute form

- **WHEN** a duration or countdown of 2 hours and 45 minutes is formatted
- **THEN** the result is `2h45m`

#### Scenario: Sub-hour value uses minute form

- **WHEN** a duration or countdown of 23 minutes is formatted
- **THEN** the result is `23m`

### Requirement: Reset epochs persist across renders

The reset epochs SHALL be cached alongside the existing rate-limit percentage cache in the
script's private per-user `$TMPDIR` cache directory, so that a countdown stays live on
renders where the stdin JSON omits the `rate_limits` object. On such a render the statusline
SHALL recompute the remaining time from the cached epoch against the current time, rather
than dropping the countdown, and SHALL apply the same stale-epoch suppression rule. A freshly
reported epoch SHALL overwrite the cached value.

#### Scenario: Countdown survives a render with no rate_limits in JSON

- **WHEN** a prior render cached a future `resets_at` epoch and the current render's stdin JSON contains no `rate_limits` object
- **THEN** the statusline still renders the `⟲<remaining>` suffix, with `<remaining>` recomputed from the cached epoch against the current time

#### Scenario: Fresh epoch overwrites the cache

- **WHEN** the stdin JSON reports a new `resets_at` epoch for a window
- **THEN** the cached epoch for that window is replaced with the newly reported value

### Requirement: Layout and performance invariants are preserved

The new readouts SHALL be added within the existing two-line statusline layout — inline as
suffixes to their respective gauges on line 2 — without introducing a third line, relocating
existing segments, or altering line 1. The script SHALL continue to parse the stdin JSON in a
single `jq` invocation: the new fields (`cost.total_duration_ms`,
`rate_limits.five_hour.resets_at`, `rate_limits.seven_day.resets_at`) SHALL be emitted by the
same single parse that already extracts the existing fields, not by an additional `jq` call.

#### Scenario: Layout remains two lines

- **WHEN** the statusline renders with duration and both reset countdowns present
- **THEN** the output is still two lines, line 1 is unchanged, and the new values appear only as inline suffixes to the `c:`, `s:`, and `w:` gauges on line 2

#### Scenario: Single jq parse is preserved

- **WHEN** the statusline script processes one render's stdin
- **THEN** it invokes `jq` to extract the rendered fields exactly once for the field-extraction step, emitting the three new fields within that same invocation

### Requirement: Graceful degradation and no new dependencies

The change SHALL add no runtime dependency beyond the existing `jq` and `git`, and SHALL not
write any durable state outside the script's existing private `$TMPDIR` cache. Every new
field SHALL be optional: any combination of present/absent duration and reset fields SHALL
render without error, omitting only the suffixes whose source data is unavailable, so the
statusline never hard-fails a render.

#### Scenario: All new fields absent degrades to prior behaviour

- **WHEN** the stdin JSON contains no `cost.total_duration_ms` and no `rate_limits` object, and no epochs are cached
- **THEN** line 2 renders exactly as it did before this change — gauges with no time suffixes — and the script exits successfully

#### Scenario: No new external writes

- **WHEN** the statusline script runs to completion
- **THEN** the only files it writes are within its private per-user cache directory under `$TMPDIR`, as before this change

