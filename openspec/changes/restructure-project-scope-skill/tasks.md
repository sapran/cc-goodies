## 1. SKILL.md — rewrite to a router

- [ ] 1.1 Rewrite SKILL.md to ~50 lines: purpose, the consent invariant, the phase names, and
      pointers into `references/mechanism.md` and `references/phase3-menu.md`. Preserve the
      frontmatter (`name`, `version`, `description`) unchanged — out of scope, see
      `trim-skill-metadata`.
- [ ] 1.2 Cut the "Mechanism reference (canonical)" section's prose restatement (lines 21–28)
      down to a single pointer at `references/mechanism.md` — no re-description of the two
      paradigms or the settings keys.
- [ ] 1.3 Delete Phase 1C's tokenize/keyword-match block (SKILL.md:94–121) in favour of the
      subagent dispatch (see section 4); confirm the stopword list, the "avoid 2-letter
      substrings like `ai`" heuristic, the `.[:15]` cap, and the top-10 fallback are gone from
      SKILL.md.
- [ ] 1.4 Cut the Phase 3A budget-option restatement (line 178, "Choose: 1% / 2% / 3% / 5%")
      to a pointer at `references/phase3-menu.md`'s Q4 row.
- [ ] 1.5 Replace `## Red Flags — STOP` (lines 256–266) with one stated invariant: project
      scope only; every install/uninstall/settings write is confirmed; on any edge case pick
      the conservative option.
- [ ] 1.6 Confirm nothing removed from SKILL.md silently drops behaviour: every command form,
      key name, and rule that existed inline now has a live pointer to where it lives instead.

## 2. references/mechanism.md — sole home of CLI/cache/settings mechanics

- [ ] 2.1 Confirm the two-paradigm table, the `.claude/settings.json` key table, the
      npm-based-tools note, and the catalog-cache data source section are complete enough that
      SKILL.md needs no restatement (cross-check against section 1.2).
- [ ] 2.2 Add the Phase 1 subagent return contract as a new section (schema per `design.md`
      Decision D3: `tier`, `surface`, `id`, `state`, `description`, `always_on_tokens`,
      `unique_installs`, `bundles_mcp`, `category`).
- [ ] 2.3 Leave the model-key token-lookup section (line 40) untouched — out of scope, see
      `fix-project-scope-model-keys`; note the sequencing dependency in the PR description if
      that proposal lands first.

## 3. references/phase3-menu.md — sole home of the confirmation menu

- [ ] 3.1 Confirm the question/option tables (Q1, Qci, Q2, Q3, Q4) remain the canonical
      source SKILL.md points at, with no duplicate copy left in SKILL.md.
- [ ] 3.2 Remove the fixed 5-question overflow arbitration rule ("drop Q2, never Qci, never
      Q4"); replace with judgment guidance: decide what to ask now versus confirm implicitly
      based on each bucket's risk and reversibility, while preserving the consent invariant
      (every install/uninstall/settings write is still confirmed, per spec section
      "Consent invariant preserved").
- [ ] 3.3 Confirm the smaller post-inventory confirmation menu (after the Phase 3 interview
      inversion, section 5) is reflected here — fewer buckets are expected to carry genuine
      ambiguity by the time this menu runs.

## 4. Phase 1 — subagent delegation

- [ ] 4.1 Replace the inline three-tier inventory (1A/1B/1C) with a single subagent dispatch
      that receives the clarified theme and the refreshed catalog-cache path.
- [ ] 4.2 Define the dispatch prompt so the subagent runs the existing CLI listings, Desktop
      config read, and catalog-cache queries (per `references/mechanism.md`'s data-source
      section) internally and returns only the structured table (section 2.2's schema) — no
      raw `--json` stream, no full CLI dump, and no unfiltered catalog rows reach the main
      session.
- [ ] 4.3 Confirm the main session still reads `./CLAUDE.md` and `./.claude/settings.json`
      itself (needed for Phase 2's conflict rules and Phase 4's merge target) rather than via
      the subagent, since those inform judgment calls the main session owns.
- [ ] 4.4 Confirm Phase 2's classification (keep/remove/install/skip, "always keep",
      conflict-with-global-CLAUDE.md) stays in the main session, consuming the subagent's
      structured return rather than raw sources.

## 5. Phase 3 — invert ambiguity handling

- [ ] 5.1 Add an up-front clarifying interview before inventory: one question at a time about
      theme intent and the user's starting point (what's already in place, add vs. remove).
      Generalize the existing empty-theme gate (SKILL.md:19) into this interview rather than
      keeping it as a separate special case.
- [ ] 5.2 Confirm the post-inventory confirmation menu (Phase 3B) is now genuinely smaller —
      it should be resolving residual specifics (which candidates, which budget), not the
      theme's meaning, which the interview already settled.
- [ ] 5.3 Confirm a clear, unambiguous theme still skips the interview and proceeds directly
      to inventory (per the spec's "clear theme skips the interview" scenario).

## 6. Phase 5 — verify rubric

- [ ] 6.1 Replace the five-step prose checklist (SKILL.md:238–246) with a checkable rubric:
      re-read `.claude/settings.json`, diff against the proposal the user approved, report
      mismatches.
- [ ] 6.2 Confirm the rubric still covers what the prose checklist covered: JSON validity,
      plugin project-scope state (Pass A/B/C), MCP denial/connection state, the written
      `skillListingBudgetFraction`, and which changes need a session restart.

## 7. Docs

- [ ] 7.1 Update `docs/plugin-audit.md:145` to mark `split-project-scope-skill` resolved
      (with a pointer to this change) rather than leaving it listed as an open optional item.
- [ ] 7.2 Review `plugins/project-scope/README.md` line 25 ("If you don't give a theme, it
      asks for one before doing anything") for accuracy against the up-front interview, which
      may now span more than one question.
- [ ] 7.3 Review the `project-scope` row in root `CLAUDE.md` for drift; update only if the
      behavior-level description no longer matches (expected: no change needed).
- [ ] 7.4 Add a `CHANGELOG.md` entry once implemented.

## 8. Verification

- [ ] 8.1 Record `on_invoke` tokens for `project-scope` from
      `~/.claude/plugins/plugin-catalog-cache.json` (`.catalog.plugins["project-scope@<marketplace>"]
      .tokens["<model>"].on_invoke`) before making any change.
- [ ] 8.2 After implementation, refresh the catalog cache and record `on_invoke` again;
      confirm it decreased and note the delta in the PR description.
- [ ] 8.3 Run the restructured skill end-to-end in a scratch project with a clear theme:
      confirm it skips the interview, dispatches the Phase 1 subagent, produces the same
      class of proposal (uninstalls/disables/installs/budget), asks for confirmation on every
      write, and that the applied `.claude/settings.json` and plugin scope match what was
      approved.
- [ ] 8.4 Run the restructured skill end-to-end in a scratch project with a deliberately
      ambiguous theme: confirm the up-front interview actually fires and asks about intent
      and starting point before inventory, not after.
- [ ] 8.5 Confirm the reference-never-read failure mode (`design.md` Decision D4) did not
      occur: verify the applied settings/commands match `references/mechanism.md`'s
      documented keys and command forms exactly, not an improvised approximation.
- [ ] 8.6 `jq empty plugins/project-scope/.claude-plugin/plugin.json && jq empty
      .claude-plugin/marketplace.json`; `claude plugins validate plugins/project-scope`.

## 9. Release

- [ ] 9.1 Bump `plugins/project-scope/.claude-plugin/plugin.json` `version`.
- [ ] 9.2 Commit on the change branch, push, open a draft PR to `develop`. (Archive + `main`
      fast-forward happen after review, per the repo release flow.)
