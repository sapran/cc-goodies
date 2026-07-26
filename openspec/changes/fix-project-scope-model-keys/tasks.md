## 1. Model-key resolution — reference doc (`skills/project-scope/references/mechanism.md`)

- [ ] 1.1 Replace the token-cost paragraph's "Model keys seen: `claude-opus-4-7`,
      `claude-sonnet-4-6` … read the current model's key if present, else any opus key, else any
      key" text with the three-step resolution procedure from `design.md` (exact match → family
      match → unavailable), with no hard-coded model-key strings.
- [ ] 1.2 State explicitly that a family-match or unavailable result MUST be disclosed wherever
      the figure is surfaced — name the key actually used, or say the figure is unavailable —
      never silently substituted.
- [ ] 1.3 Note that a skill's Bash/jq tool calls receive no injected model-identity payload
      (unlike the hook JSON contract or the statusLine command's `.model.display_name`), so the
      resolution key must come from the model stating its own known model id before querying the
      cache, not from anything a script can detect on disk or in the environment.

## 2. Apply resolution in the skill body (`skills/project-scope/SKILL.md`)

- [ ] 2.1 Phase 1B jq query (currently
      `taon=\((($e.tokens // {}) | to_entries[0].value.always_on) // "?")`, an arbitrary
      first-key read with no model-awareness): pass the resolved model key in as a `jq --arg`,
      look it up by key, fall through family match, then unavailable — per 1.1 — and mark the
      output row when the key used isn't an exact match for the session's model.
- [ ] 2.2 Pass B / Pass C prose ("Factor in each candidate's `always_on` token cost…", "Weigh each
      candidate's `always_on` token cost…") and the Phase 3A proposal printout (per-plugin
      `always_on` figures and the "sum of always_on … ≈ N tokens/turn" budget note): update
      wording so any figure shown to the user carries the resolved-key disclosure when it isn't
      an exact match, and so the budget sum excludes unavailable figures rather than treating
      them as zero.
- [ ] 2.3 Confirm no other phase changes: inventory (1A/1C), install/uninstall (Phase 4A),
      settings.json merge (Phase 4B), verify (Phase 5), and hand-off (Phase 6) are untouched by
      this proposal.

## 3. Verify against the live catalog cache

- [ ] 3.1 Re-confirm current key shape before implementing:
      `jq -r '.catalog.plugins | to_entries | map(.value.tokens // {} | keys) | add | unique' ~/.claude/plugins/plugin-catalog-cache.json`
      — as of this proposal, returns exactly `["claude-opus-4-7", "claude-sonnet-4-6"]`; note if
      that has changed (a Claude-5-generation key may since have been added).
- [ ] 3.2 Run the updated Phase 1B query under a live Claude-5-generation session against the
      real cache; confirm the output discloses "no exact match" / names the family-matched key,
      rather than silently reporting Opus-4.7/Sonnet-4.6 figures as the session's own.
- [ ] 3.3 Exercise the exact-match path: point the query at a scratch copy of the cache with the
      running session's own model key added to one entry's `.tokens`, and confirm that entry's
      figure is reported with no disclosure caveat (the caveat is match-conditional, not
      always-on noise).
- [ ] 3.4 Confirm an entry with no matching key at all (neither exact nor family) reports
      "unavailable" and is excluded from the Phase 3A budget sum rather than silently dropped or
      counted as zero.

## 4. Docs + release

- [ ] 4.1 Bump `plugins/project-scope/.claude-plugin/plugin.json` `version` (`0.2.1` → `0.2.2`,
      patch — bug fix, no new behavioural surface).
- [ ] 4.2 `jq empty plugins/project-scope/.claude-plugin/plugin.json` and
      `claude plugins validate plugins/project-scope` — both pass.
- [ ] 4.3 Add a `CHANGELOG.md` entry describing the fix (wrong-model token figures silently
      reported under Claude-5-generation sessions); bump marketplace `metadata.version` in
      `.claude-plugin/marketplace.json` per the repo's release flow.
- [ ] 4.4 Commit on the change branch, push, open a draft PR to `develop`. (Archive + `main` FF
      happen after review, per the repo release flow.)
