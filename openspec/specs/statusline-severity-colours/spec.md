# statusline-severity-colours Specification

## Purpose
Colour each line-2 statusline usage gauge (`c:`, `s:`, `w:`) from its own value against
per-gauge severity thresholds — a four-tier green/yellow/amber/red ramp for the context gauge,
three-tier green/amber/red for the rate-limit gauges — drawn from a fixed 256-colour palette
with the critical tier bolded and the time suffixes kept neutral, so fill level reads at a
glance without changing the two-line layout, the single-`jq`-parse budget, or the degradation
rules.
## Requirements
### Requirement: Value-driven gauge severity colour

The statusline SHALL colour each line-2 usage gauge (`c:` context window, `s:` 5-hour session,
`w:` 7-day weekly) according to a severity scale selected from that gauge's own percentage
value: green (low) → amber (warning) → red (critical), with the context gauge interposing an
additional yellow tier between green and amber (green → yellow → amber → red). A gauge SHALL
NOT be rendered in a single value-independent colour: two gauges showing materially different
fill levels SHALL be distinguishable by colour alone.

#### Scenario: A low gauge renders green

- **WHEN** a gauge's value falls in its green band (e.g. `c:5%`)
- **THEN** that gauge's `label:NN%` token is rendered in the green tier colour

#### Scenario: The context gauge renders yellow in its second tier

- **WHEN** the context gauge's value falls in its yellow band (e.g. `c:30%`)
- **THEN** the `c:30%` token is rendered in the yellow tier colour, visibly distinct from both green and amber

#### Scenario: A warning-level gauge renders amber

- **WHEN** a gauge's value falls in its amber band (e.g. `s:58%`)
- **THEN** that gauge's token is rendered in the amber tier colour, visibly distinct from a green gauge on the same line

#### Scenario: A critical gauge renders red

- **WHEN** a gauge's value falls in its red band (e.g. `c:92%`)
- **THEN** that gauge's token is rendered in the red tier colour

### Requirement: Per-gauge severity thresholds

Each gauge SHALL evaluate its value against thresholds tuned to that gauge, not one shared
threshold set. The context gauge (`c:`) SHALL use four tiers: green below 25%, yellow from 25%
up to but not including 50%, amber from 50% up to but not including 75%, and red at 75% and
above. The 5-hour session gauge (`s:`) SHALL use three tiers: green below 50%, amber from 50%
up to but not including 80%, and red at 80% and above. The 7-day weekly gauge (`w:`) SHALL use
three tiers: green below 50%, amber from 50% up to but not including 75%, and red at 75% and
above. Each boundary SHALL be inclusive at its lower edge (the value at the boundary takes the
higher tier).

#### Scenario: Context gauge steps through four tiers

- **WHEN** the context gauge reads 24% it renders green; and **WHEN** it reads 25% it renders yellow; and **WHEN** it reads 50% it renders amber; and **WHEN** it reads 75% it renders red

#### Scenario: Session gauge uses three tiers

- **WHEN** the 5-hour session gauge reads 49% it renders green; and **WHEN** it reads 50% it renders amber; and **WHEN** it reads 80% it renders red

#### Scenario: Weekly gauge alarms soonest among the rate limits

- **WHEN** the 7-day weekly gauge reads 75% it renders red (a lower critical boundary than the 5-hour gauge's 80%)

### Requirement: 256-colour palette with bolded critical tier

The severity colours SHALL be drawn from a fixed 256-colour SGR palette so they remain legible
on a light terminal background where ANSI-16 yellow degrades to low contrast: green from colour
index 34, yellow from index 178 (a gold, legible on a light background, rather than a pure
yellow such as 226 which is not), amber from index 208, and red from index 196. The red
(critical) tier SHALL additionally be rendered bold, so the most urgent state carries a second,
colour-independent signal; the green, yellow, and amber tiers SHALL be rendered at normal
weight. A terminal that does not support 256-colour escapes SHALL still display the gauge
digits (uncoloured), never an error.

#### Scenario: Critical tier is bold as well as red

- **WHEN** a gauge is in its red band
- **THEN** its token is emitted with both the red 256-colour code and the bold attribute, while the green, yellow, and amber tiers carry no bold attribute

#### Scenario: Yellow and amber stay legible on a light background

- **WHEN** the statusline renders the context gauge's yellow tier or any gauge's amber tier on a light-background terminal
- **THEN** the yellow tier uses the gold index 178 and the amber tier uses the orange index 208 — neither uses ANSI-16 yellow — so both remain legible

### Requirement: Time suffixes rendered as neutral secondary text

The `⧗` elapsed-duration suffix and the `⟲` reset-countdown suffixes SHALL be rendered in a
neutral dim/secondary style (dim grey), not in any gauge severity colour, so that the
severity-coloured gauge percentage remains the primary figure. The suffix colour SHALL NOT vary
with the gauge's severity tier.

#### Scenario: Suffix stays neutral while its gauge is coloured by severity

- **WHEN** a gauge in its red band carries a time suffix (e.g. `s:85% ⟲40m`)
- **THEN** the `s:85%` token renders bold red while the `⟲40m` suffix renders in neutral dim grey, unchanged by the gauge's tier

### Requirement: Layout, performance, and degradation invariants preserved

The colouring SHALL operate within the existing two-line layout with no third line, no
relocation of segments, and no change to line 1 or to the `model (effort)` segment. Colour
selection SHALL add no `jq` invocation and no extra subprocess per gauge — it SHALL be pure
in-shell integer comparison — so the single-`jq`-parse-per-render budget is preserved. Each
gauge SHALL continue to render only when its source value is present, exactly as before; an
absent gauge SHALL render nothing, and the script SHALL add no new external write.

#### Scenario: Single jq parse and two-line layout preserved

- **WHEN** the statusline renders with all three gauges coloured by severity
- **THEN** the output is still two lines, line 1 and the `model (effort)` segment are unchanged, and the field-extraction `jq` is still invoked exactly once

#### Scenario: Absent gauge still renders nothing

- **WHEN** the stdin JSON omits a gauge's source value (e.g. no `rate_limits`)
- **THEN** that gauge is not rendered at all — the severity colouring introduces no placeholder — and the script exits successfully

#### Scenario: No new external writes

- **WHEN** the statusline script runs to completion
- **THEN** the only files it writes remain those within its private per-user cache directory under `$TMPDIR`, exactly as before this change

