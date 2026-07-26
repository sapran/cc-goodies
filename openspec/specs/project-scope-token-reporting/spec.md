# project-scope-token-reporting Specification

## Purpose
TBD - created by archiving change fix-project-scope-model-keys. Update Purpose after archive.
## Requirements
### Requirement: Dynamic model-key resolution

The skill SHALL resolve per-plugin token-cost figures against the catalog cache's `.tokens`
object using the session's own model identity, obtained from the model's own self-knowledge (no
hard-coded model-key list). Resolution SHALL proceed: (1) an exact match between the session's
known model id and a `.tokens` key; (2) if none, a match on model family (`opus`, `sonnet`,
`fable`, `haiku`) against an available key; (3) if none, no figure is resolved. The skill SHALL
NOT select a key by arbitrary object order (e.g. "the first key present") and SHALL NOT hard-code
a fixed pair of model-key strings as the only keys it looks for.

#### Scenario: Exact key match

- **WHEN** the catalog cache's `.tokens` object for a plugin contains a key equal to the
  session's own model id
- **THEN** the skill reports that key's `always_on`/`on_invoke` figures as the session's own cost

#### Scenario: No exact key, family match available

- **WHEN** no `.tokens` key equals the session's own model id, but a key shares the model's
  family word (e.g. session is `claude-sonnet-5`, cache has `claude-sonnet-4-6`)
- **THEN** the skill resolves to that family key's figures rather than treating the plugin as
  having no cost data

#### Scenario: No exact or family key

- **WHEN** no `.tokens` key matches the session's model exactly or by family
- **THEN** the skill does not resolve any figure for that plugin from an unrelated key

### Requirement: Explicit disclosure when a non-exact key is used

Whenever the skill reports a token-cost figure resolved from anything other than an exact match
for the session's own model, it SHALL name the key whose figures are being shown, wherever that
figure is surfaced to the user (Phase 1B inventory output, Pass B/C evaluation, the Phase 3A
proposal printout). Figures resolved from an exact match SHALL be reported without a disclosure
caveat.

#### Scenario: Family-match figure is labelled

- **WHEN** a reported `always_on`/`on_invoke` figure was resolved via the family-match step
- **THEN** the output naming that figure also names the resolved key (e.g. "sonnet-4-6, not the
  running model") so the reader knows it is not necessarily this session's own cost

#### Scenario: Exact-match figure carries no caveat

- **WHEN** a reported figure was resolved via an exact key match
- **THEN** the output states the figure with no fallback disclosure, since it is the session's
  own cost

#### Scenario: Unresolved figure is stated as unavailable

- **WHEN** no key resolves for a plugin (neither exact nor family match)
- **THEN** the skill reports that plugin's token cost as unavailable rather than omitting it
  silently or leaving a stale/blank figure that could be misread as zero cost

### Requirement: No fallback figure presented as authoritative

The skill SHALL NOT present a token-cost figure drawn from a non-matching model's key as if it
were an authoritative measurement of the running session's own cost. This applies everywhere a
token figure factors into a decision presented to the user — Pass B/C's "weigh `always_on` cost
against theme value" judgment and the Phase 3A budget note ("sum of `always_on` … ≈ N
tokens/turn") SHALL carry the same disclosure as the figures they're built from; an unlabelled
non-exact figure feeding a budget sum is still an undisclosed fallback.

#### Scenario: Budget sum built from mixed-resolution figures is flagged

- **WHEN** the Phase 3A per-turn budget sum includes one or more plugins whose figures were
  resolved via family match (not exact), rather than only unavailable ones
- **THEN** the printed sum notes that it includes non-exact figures, instead of presenting the
  total as a precise measurement of the running session's own cost

#### Scenario: Unavailable figures are excluded from the budget sum, not treated as zero

- **WHEN** one or more plugins' token costs are unresolved (unavailable)
- **THEN** those plugins are excluded from the numeric budget sum and named separately as
  unmeasured, rather than counted as zero cost

