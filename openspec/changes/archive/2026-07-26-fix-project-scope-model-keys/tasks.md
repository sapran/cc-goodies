## 1. Model-key resolution — reference doc (`skills/project-scope/references/mechanism.md`)

- [x] 1.1 Replace the token-cost paragraph's "Model keys seen: `claude-opus-4-7`,
      `claude-sonnet-4-6` … read the current model's key if present, else any opus key, else any
      key" text with the three-step resolution procedure from `design.md` (exact match → family
      match → unavailable), with no hard-coded model-key strings. Done: rewrote the `.tokens[...]`
      bullet in `references/mechanism.md`.
- [x] 1.2 State explicitly that a family-match or unavailable result MUST be disclosed wherever
      the figure is surfaced — name the key actually used, or say the figure is unavailable —
      never silently substituted. Done: added as the closing sentence of the same bullet.
- [x] 1.3 Note that a skill's Bash/jq tool calls receive no injected model-identity payload
      (unlike the hook JSON contract or the statusLine command's `.model.display_name`), so the
      resolution key must come from the model stating its own known model id before querying the
      cache, not from anything a script can detect on disk or in the environment. Done: added as
      its own paragraph referencing the hook/statusLine contract by name.

## 2. Apply resolution in the skill body (`skills/project-scope/SKILL.md`)

- [x] 2.1 Phase 1B jq query (currently
      `taon=\((($e.tokens // {}) | to_entries[0].value.always_on) // "?")`, an arbitrary
      first-key read with no model-awareness): pass the resolved model key in as a `jq --arg`,
      look it up by key, fall through family match, then unavailable — per 1.1 — and mark the
      output row when the key used isn't an exact match for the session's model. Done: query now
      takes `--arg model`/`--arg family` (model stated by the model itself beforehand) and emits
      `aon=<n>`, `aon=<n> (via <key>, not <model>)`, or `aon=unavailable`.
- [x] 2.2 Pass B / Pass C prose ("Factor in each candidate's `always_on` token cost…", "Weigh each
      candidate's `always_on` token cost…") and the Phase 3A proposal printout (per-plugin
      `always_on` figures and the "sum of always_on … ≈ N tokens/turn" budget note): update
      wording so any figure shown to the user carries the resolved-key disclosure when it isn't
      an exact match, and so the budget sum excludes unavailable figures rather than treating
      them as zero. Done: both Pass B/C paragraphs and the Phase 3A print template updated.
- [x] 2.3 Confirm no other phase changes: inventory (1A/1C), install/uninstall (Phase 4A),
      settings.json merge (Phase 4B), verify (Phase 5), and hand-off (Phase 6) are untouched by
      this proposal. Confirmed: diff to SKILL.md is limited to Phase 1B, Pass B/C prose, and
      Phase 3A's print template; Phases 1A/1C/4A/4B/5/6 and phase3-menu.md are unchanged.

## 3. Verify against the live catalog cache

- [x] 3.1 Re-confirm current key shape before implementing:
      `jq -r '.catalog.plugins | to_entries | map(.value.tokens // {} | keys) | add | unique' ~/.claude/plugins/plugin-catalog-cache.json`
      — as of this proposal, returns exactly `["claude-opus-4-7", "claude-sonnet-4-6"]`; note if
      that has changed (a Claude-5-generation key may since have been added). Re-ran live: still
      returns exactly `["claude-opus-4-7", "claude-sonnet-4-6"]` — unchanged.
- [x] 3.2 Run the updated Phase 1B query under a live Claude-5-generation session against the
      real cache; confirm the output discloses "no exact match" / names the family-matched key,
      rather than silently reporting Opus-4.7/Sonnet-4.6 figures as the session's own. Ran with
      `MODEL="claude-sonnet-5"` (this session) against two real plugin ids: output was
      `aon=899 (via claude-sonnet-4-6, not claude-sonnet-5)` and
      `aon=1334 (via claude-sonnet-4-6, not claude-sonnet-5)`. The OLD `to_entries[0]` query on
      the same ids returned `aon=1216` / `aon=1880` — Opus-4.7's figures, unconditionally,
      mislabelled as the session's own.
- [x] 3.3 Exercise the exact-match path: point the query at a scratch copy of the cache with the
      running session's own model key added to one entry's `.tokens`, and confirm that entry's
      figure is reported with no disclosure caveat (the caveat is match-conditional, not
      always-on noise). Ran against a `/tmp` scratch copy with `tokens["claude-sonnet-5"] =
      {always_on: 777, on_invoke: 5000}` added to one entry: output was bare `aon=777`, no
      caveat.
- [x] 3.4 Confirm an entry with no matching key at all (neither exact nor family) reports
      "unavailable" and is excluded from the Phase 3A budget sum rather than silently dropped or
      counted as zero. Ran with `MODEL="claude-haiku-5"` (family "haiku", absent from the real
      cache entirely) against the real cache: output was `aon=unavailable`. Phase 3A prose
      updated to exclude such rows from the numeric sum and name them separately (see SKILL.md
      CONTEXT BUDGET block).

## 4. Docs + release

- [x] 4.1 Bump `plugins/project-scope/.claude-plugin/plugin.json` `version` (`0.2.1` → `0.2.2`,
      patch — bug fix, no new behavioural surface). Also bumped the mirrored `version:` in
      `SKILL.md` frontmatter (0.2.1 → 0.2.2) to keep the two in sync — not called out explicitly
      in this task but the two were previously identical.
- [x] 4.2 `jq empty plugins/project-scope/.claude-plugin/plugin.json` and
      `claude plugins validate plugins/project-scope` — both pass. Confirmed: `jq empty` exits
      clean, `claude plugins validate` reports "Validation passed".
- [ ] 4.3 Add a `CHANGELOG.md` entry describing the fix (wrong-model token figures silently
      reported under Claude-5-generation sessions); bump marketplace `metadata.version` in
      `.claude-plugin/marketplace.json` per the repo's release flow. NOT done here — explicitly
      out of scope for this implementation pass (handled centrally; `marketplace.json` and
      `CHANGELOG.md` are off-limits per task instructions).
- [ ] 4.4 Commit on the change branch, push, open a draft PR to `develop`. (Archive + `main` FF
      happen after review, per the repo release flow.) NOT done here — this pass runs no git
      commands per task instructions; git/commit/PR steps are the caller's responsibility.
