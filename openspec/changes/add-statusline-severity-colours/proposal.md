## Why

The statusline's three usage gauges on line 2 — `c:` (context window used), `s:`
(5-hour session limit used), `w:` (7-day weekly limit used) — are rendered in a single flat
magenta regardless of value, so a gauge at 5% looks identical to one at 95%. Colour, the one
channel a status gauge most wants for at-a-glance severity, currently encodes nothing: the
viewer must read and compare three numbers to learn what a glance should tell them. The prior
change (`add-statusline-resets-and-duration`) explicitly deferred "alerting/thresholds" and
"colour changes to the gauges"; this is that deferred follow-up.

## What Changes

- **Colour each gauge by its own value** via per-gauge severity thresholds, using a fixed
  256-colour palette (`38;5;…`) so the steps stay legible on a light terminal background where
  ANSI-16 yellow degrades to low-contrast olive. The context gauge — the fastest-moving,
  most-watched figure — uses a finer **four-tier** ramp; the two rate-limit gauges stay
  three-tier:
  - `c:` (context — fast-moving, watched closely): **green** `<25%`, **yellow** `25–49%`, **amber** `50–74%`, **red** `≥75%`
  - `s:` (5-hour — scarcer): **green** `<50%`, **amber** `50–79%`, **red** `≥80%`
  - `w:` (7-day — scarcest): **green** `<50%`, **amber** `50–74%`, **red** `≥75%`
- **Pair colour with weight at the critical step.** The red tier renders **bold**
  (`1;38;5;196`) so the most urgent state carries a second, colour-independent signal —
  legible under colour-blindness and on low-contrast themes. Green (`38;5;34`), yellow/gold
  (`38;5;178` — a light-background-legible yellow, not the near-invisible pure yellow), and
  amber (`38;5;208`) render at normal weight.
- **Drop the time suffixes to neutral dim grey.** The `⧗` duration and `⟲` reset countdowns
  move from dim magenta (`2;35`) to the dim grey (`2;37`) already used for the line-1 prompt
  snippets, so the now-severity-coloured gauge percentage stays the primary figure and the
  suffix reads as plainly secondary. This still satisfies the time-readouts spec's existing
  "dim/secondary style" requirement, so no spec requirement changes.
- **Touch nothing else.** Line 1 (`user@host`, cwd, branch/worktree, prompts) and the
  line-2 `model (effort)` segment keep their current colours. The two-line layout, the
  single-`jq`-parse budget, and every graceful-degradation rule are preserved.

No new dependency, no new data source, no new external writes: the change reads percentage
values the script already parses, maps each to an SGR colour with a pure-bash helper, and
adjusts existing `printf` colour codes. `/plugin uninstall` remains the full revert.

## Capabilities

### New Capabilities

- `statusline-severity-colours`: The statusline colours each line-2 usage gauge from its own
  value against per-gauge severity thresholds — a four-tier green→yellow→amber→red ramp for the
  context gauge, three-tier green→amber→red for the rate-limit gauges — drawn from a fixed
  256-colour palette with the critical (red) tier bolded, while keeping the gauge percentage
  the primary figure by rendering the time suffixes in neutral dim grey — all within the
  existing two-line layout, single-`jq`-parse budget, and graceful-degradation rules.

### Modified Capabilities

<!-- None. The only adjacent spec, statusline-time-readouts, requires the time suffixes be
     "dim/secondary"; dim grey still satisfies that, so no existing REQUIREMENT changes. The
     gauge colours themselves were never spec'd (they predate openspec), so this is greenfield. -->

## Impact

- **Code:** `plugins/statusline/statusline-command.sh` — add a pure-bash `gauge_sgr` helper
  that takes a value plus ascending `min:sgr` tier tokens and emits the SGR colour params for
  the highest matched tier (the same helper serves the four-tier context gauge and the
  three-tier rate-limit gauges); compute an integer context value (`used_int`) alongside the
  existing `rl_5h_int`/`rl_7d_int`; swap the three flat-magenta gauge `printf` colours for
  `gauge_sgr` calls with each gauge's thresholds; change the two `⧗`/`⟲` suffix codes from
  `2;35` to `2;37`.
- **Docs:** `plugins/statusline/README.md` — note the gauge severity colours and per-gauge
  thresholds in the Line-2 legend (the static example block can keep one representative state).
- **Dependencies:** none added. Still `jq` + `git`; pure-bash colour mapping, no extra process
  per gauge.
- **Compatibility:** purely visual. 256-colour escapes are near-universally supported by modern
  terminals; a terminal that ignores them simply shows the digits uncoloured — no breakage.
- **Install/uninstall:** unchanged — no new setup step and no new durable external state, so the
  install ⇄ uninstall symmetry holds with `/plugin uninstall` as the full revert.
- **Out of scope:** line-1 colour changes, the `model (effort)` colours, colouring the time
  suffixes by severity, configurable/user-tunable thresholds, and the `⧗` glyph's font-rendering
  (a tofu-box in some fonts) — a separate, non-colour concern.
