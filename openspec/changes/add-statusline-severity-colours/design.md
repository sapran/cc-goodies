## Context

`plugins/statusline/statusline-command.sh` renders a two-line statusline. Line 2 today is:

```
Opus 4.8 (xhigh)  c:5% ⧗4m  s:58% ⟲1h10m  w:19% ⟲2d11h
```

— `model (effort)`, then three percentage gauges, each optionally suffixed with a dim time
readout. All three gauges are printed in one flat colour, magenta (`\033[35m`), and the
suffixes in dim magenta (`\033[2;35m`), regardless of value. The gauges:

| gauge | source field | meaning |
|-------|--------------|---------|
| `c:` | `context_window.used_percentage` | context window used |
| `s:` | `rate_limits.five_hour.used_percentage` | 5-hour session limit used |
| `w:` | `rate_limits.seven_day.used_percentage` | 7-day weekly limit used |

The script's design constraints are explicit in its header: **one** `jq` parse per render,
short-lived caches, pure-bash arithmetic, and clean degradation when a field is missing. It
targets macOS bash 3.2 / BSD userland but must not hard-fail elsewhere. The script already
sanitises each gauge to an integer (`rl_5h_int`, `rl_7d_int`; `used` via `printf '%.0f'` at
render time), which is exactly the value a threshold comparison needs.

The observed terminal (from the reference screenshot) uses a **light background**, on which
ANSI-16 yellow (`33`) degrades to a low-contrast olive — already visible in the line-1
`[develop]` branch token.

## Goals / Non-Goals

**Goals:**

- Colour each gauge from its own value so fill level reads at a glance without comparing digits.
- Use thresholds tuned per gauge to what its number means (context finest-grained and
  earliest-warning; rate limits coarser).
- Stay legible on a light terminal background.
- Pair the critical tier with a second, colour-independent signal (weight).
- Stay within the two-line layout, the single-`jq`-parse budget, and every degradation rule.

**Non-Goals:**

- Line-1 colours, the `model (effort)` colours, or any layout change.
- Colouring the `⧗`/`⟲` time suffixes *by severity* (they move to neutral grey, not a gauge hue).
- User-configurable thresholds or palette (fixed values this change; revisit only if asked).
- Fixing the `⧗` glyph's font-rendering tofu-box — a separate, non-colour concern.

## Decisions

### D1 — Colour is driven by each gauge's own value

Each gauge picks its colour from a three-tier severity scale — green (low) → amber (warning)
→ red (critical) — evaluated against *its own* percentage. **Why:** a status gauge's primary
job is at-a-glance severity; a flat colour wastes the one channel best suited to encode it, so
a 95%-full gauge currently looks identical to a 5% one. *Alternative considered:* per-gauge
fixed hues (a distinct base colour per gauge so they're told apart without labels) plus
brightness-by-severity — rejected as more colour noise for no gain, since the `c:`/`s:`/`w:`
labels already disambiguate. (User-confirmed.)

### D2 — Fixed 256-colour palette, not ANSI-16

Use 256-colour SGR escapes with fixed indices — green `38;5;34`, yellow/gold `38;5;178`,
amber `38;5;208`, red `38;5;196` — rather than the ANSI-16 `32`/`33`/`31` the rest of the
script uses. **Why:** on the user's light background, ANSI-16 yellow renders as a
near-illegible olive (the `[develop]` token demonstrates it), and a *warning* tier that can't
be read defeats the feature. The indices were chosen for contrast on light **and** dark
backgrounds: amber `208` is an orange, and the yellow tier deliberately uses the gold `178`
(#d7af00) rather than a pure yellow (`226` ≈ #ffff00), which is invisible on white. The
trade-off — fixed indices ignore a terminal theme's palette remaps — is accepted deliberately
in exchange for predictable legibility of the severity signal. (User-confirmed: 256-colour
over ANSI-16.) A terminal that doesn't support 256-colour ignores the escape and shows the
digits uncoloured — no breakage.

### D3 — Per-gauge thresholds; a finer four-tier ramp for the context gauge

The gauges measure different things, so their boundaries — and the context gauge's tier
*count* — differ. `c:` uses a four-tier ramp (adds a yellow step); `s:`/`w:` stay three-tier:

| gauge | green | yellow | amber | red |
|-------|-------|--------|-------|-----|
| `c:` (context window used) | `< 25%` | `25–49%` | `50–74%` | `≥ 75%` |
| `s:` (5-hour session used) | `< 50%` | — | `50–79%` | `≥ 80%` |
| `w:` (7-day weekly used) | `< 50%` | — | `50–74%` | `≥ 75%` |

**Why:** the context window is the fastest-moving gauge and the one watched most closely within
a session as it climbs toward compaction, so it earns a graduated, quartile-style four-step
ramp that signals fill early and often (green → yellow at a quarter → amber at half → red at
three-quarters). The 5-hour and 7-day rate limits move slowly and are scarcer, so a coarser
three-tier scale suffices: green until half, amber past it, red when genuinely constrained (the
weekly window, least recoverable, soonest at 75%). *Note:* this **overrides** the earlier
working assumption that `c:` should be the *most tolerant* gauge — at the user's direction it
is now the **finest-grained and earliest-warning** one. *Alternative considered:* one uniform
three-tier set for all gauges — rejected: it cannot express the context gauge's desired early,
graduated warning. (User-directed: four-tier `c:` at 25/50/75; `s:`/`w:` unchanged.)

### D4 — Red tier renders bold (colour + weight redundancy)

The critical (red) tier is emitted as `1;38;5;196` (bold); green and amber stay normal weight.
**Why:** the most urgent state should not depend on hue alone — bold gives a second signal that
survives colour-blindness, a washed-out theme, or a quick glance. Bolding only the red tier
keeps the weight contrast meaningful (everything-bold would erase it) and reserves the heaviest
emphasis for the one state that warrants action.

### D5 — Time suffixes drop to neutral dim grey

The `⧗` duration and `⟲` reset suffixes move from dim magenta (`2;35`) to dim grey (`2;37`),
the same dim grey line 1 already uses for prompt snippets. **Why:** once the gauge percentage
is severity-coloured it becomes the figure the eye should land on; a magenta suffix would
compete, whereas neutral grey reads as plainly secondary and ties the "contextual extra"
styling together across both lines. This still satisfies the `statusline-time-readouts` spec's
existing requirement that the suffixes be "dim/secondary style so the gauge percentage remains
the primary figure" — dim grey *is* dim/secondary — so no existing spec REQUIREMENT changes.

### D6 — A pure-bash variadic `gauge_sgr` helper, inside the single-`jq` budget

Add `gauge_sgr <value> <min:sgr>...` that walks ascending `min:sgr` tier tokens and echoes the
SGR params for the highest tier whose `min` the value reaches, defaulting to green (`38;5;34`)
below the first token. One helper thus serves both the four-tier context gauge and the
three-tier rate-limit gauges — the tier count is simply how many tokens a call passes:

- `c:` → `gauge_sgr "$used_int" 25:'38;5;178' 50:'38;5;208' 75:'1;38;5;196'`
- `s:` → `gauge_sgr "$rl_5h_int" 50:'38;5;208' 80:'1;38;5;196'`
- `w:` → `gauge_sgr "$rl_7d_int" 50:'38;5;208' 75:'1;38;5;196'`

**Why:** colour selection is integer comparison — no `jq`, no subprocess, no new dependency —
so the one-parse-per-render invariant is untouched, and the `min:sgr` form keeps each call
self-documenting (threshold and colour sit together) while avoiding duplicated tier logic. The
`min` is split with `${tier%%:*}` and the colour with `${tier#*:}`; the colour's own `;`
separators never collide with the single `:` delimiter. The context gauge needs an integer to
compare; compute `used_int=$(printf '%.0f' "$used")` once inside the existing `[ -n "$used" ]`
block (the `s`/`w` gauges already have `rl_5h_int`/`rl_7d_int`). The helper guards a
non-numeric/empty value by treating it as green, consistent with the script's fail-soft
posture. bash 3.2-safe: positional `"$@"`, parameter expansion, and integer `-ge` only — no
arrays.

### D7 — Degradation is unchanged; colour rides on top of existing gates

Each gauge already renders only inside its presence guard (`[ -n "$used" ]`,
`[ "${rl_5h_int:-0}" -gt 0 ]`, `[ "${rl_7d_int:-0}" -gt 0 ]`). The colour change adds nothing
to those gates — an absent gauge still renders nothing; a present one just chooses its colour
from its value. No new failure mode, no new external write, no layout change.

## Risks / Trade-offs

- **Fixed 256-colour indices ignore terminal-theme remaps** → accepted in D2 for predictable
  light/dark legibility; the chosen indices (`34`/`178`/`208`/`196`) are mid-saturation and
  read on both backgrounds.
- **Threshold boundaries are judgement calls** → they encode a usage-risk opinion, not a fact;
  fixed (not user-tunable) this change to keep scope minimal — revisit as a follow-up only if
  the defaults annoy in practice.
- **256-colour support assumption** → near-universal in modern terminals; the documented
  fallback is uncoloured digits, never breakage.
- **Bold red may read as heavy** → intentional; it is the single action-warranting state and
  the weight is the point.
- **bash 3.2 / BSD portability** → `gauge_sgr` uses only integer `-ge` comparisons and `printf`;
  no arrays, no GNU-only tooling. Matches the script's existing portability bar.
