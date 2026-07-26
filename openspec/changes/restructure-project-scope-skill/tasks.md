## 1. SKILL.md — rewrite to a router

- [x] 1.1 Rewrite SKILL.md to ~50 lines: purpose, the consent invariant, the phase names, and
      pointers into `references/mechanism.md` and `references/phase3-menu.md`. Preserve the
      frontmatter (`name`, `version`, `description`) unchanged — out of scope, see
      `trim-skill-metadata`. **Outcome: 91 lines** (frontmatter 13 + body 78, word-wrapped
      prose). Frontmatter byte-identical to before. Not literally 50, but every task 1.2–1.6
      requirement below is met and design.md's own caveat ("a consequence of the rule, not a
      target hit by trimming prose") applies — padding back up would be the anti-pattern.
- [x] 1.2 Cut the "Mechanism reference (canonical)" section's prose restatement (lines 21–28)
      down to a single pointer at `references/mechanism.md` — no re-description of the two
      paradigms or the settings keys. Now one line: "**Mechanics** (...): references/
      mechanism.md — read it before Phase 1 or Phase 4."
- [x] 1.3 Delete Phase 1C's tokenize/keyword-match block (SKILL.md:94–121) in favour of the
      subagent dispatch (see section 4); confirm the stopword list, the "avoid 2-letter
      substrings like `ai`" heuristic, the `.[:15]` cap, and the top-10 fallback are gone from
      SKILL.md. Verified via grep: none present anywhere in the file (also confirmed absent
      from the new mechanism.md 1C section — replaced by judgment-based relevance, not moved
      elsewhere verbatim).
- [x] 1.4 Cut the Phase 3A budget-option restatement (line 178, "Choose: 1% / 2% / 3% / 5%")
      to a pointer at `references/phase3-menu.md`'s Q4 row. Phase 3 entry now just points at
      the reference; the fixed 4-option list itself was also replaced there (see 3.2/task
      "Context-budget choice is proposed, not selected from a fixed list").
- [x] 1.5 Replace `## Red Flags — STOP` (lines 256–266) with one stated invariant: project
      scope only; every install/uninstall/settings write is confirmed; on any edge case pick
      the conservative option. Now `## Invariant`, one paragraph.
- [x] 1.6 Confirm nothing removed from SKILL.md silently drops behaviour: every command form,
      key name, and rule that existed inline now has a live pointer to where it lives instead.
      Cross-checked every Red Flag item and Phase 1A/4A/4B specific (incl. the
      `.claude/settings.local.json` read-only note, which had no natural home in the trimmed
      router — restored in mechanism.md's Paradigm 2 section instead).

## 2. references/mechanism.md — sole home of CLI/cache/settings mechanics

- [x] 2.1 Confirm the two-paradigm table, the `.claude/settings.json` key table, the
      npm-based-tools note, and the catalog-cache data source section are complete enough that
      SKILL.md needs no restatement (cross-check against section 1.2). Confirmed — untouched,
      already sufficient; only addition was the settings.local.json line (see 1.6).
- [x] 2.2 Add the Phase 1 subagent return contract as a new section (schema per `design.md`
      Decision D3: `tier`, `surface`, `id`, `state`, `description`, `always_on_tokens`,
      `unique_installs`, `bundles_mcp`, `category`). Added `## Phase 1 — inventory subagent`
      with the tier-by-tier gathering instructions (moved from old SKILL.md 1A/1B/1C, 1C
      rewritten to judgment-based sizing) plus the `### Return contract` table, exact schema.
- [x] 2.3 Leave the model-key token-lookup section (line 40) untouched — out of scope, see
      `fix-project-scope-model-keys`. **Verified byte-for-byte unchanged** (lines 40–45 of the
      pre-existing "Reading the plugin universe" section); the exact `--arg model`/`--arg
      family` jq script from that fix was relocated (not restated) from old SKILL.md into the
      new "1B" subsection, preserving exact→family→unavailable resolution and disclosure.

## 3. references/phase3-menu.md — sole home of the confirmation menu

- [x] 3.1 Confirm the question/option tables (Q1, Qci, Q2, Q3, Q4) remain the canonical
      source SKILL.md points at, with no duplicate copy left in SKILL.md. Confirmed via grep.
- [x] 3.2 Remove the fixed 5-question overflow arbitration rule ("drop Q2, never Qci, never
      Q4"); replace with judgment guidance: decide what to ask now versus confirm implicitly
      based on each bucket's risk and reversibility, while preserving the consent invariant.
      New `## Menu overflow` section: Q2 is a *reasonable default candidate* to fold (stated
      rationale), not a mandatory drop; Qci/Q4 still called out as never-fold (consent
      invariant, not a fixed order for their own sake).
- [x] 3.3 Confirm the smaller post-inventory confirmation menu (after the Phase 3 interview
      inversion, section 5) is reflected here — Q1–Q4 unchanged in shape (they resolve
      residual specifics: which candidates, which budget) since the interview now absorbs
      theme-meaning ambiguity before this menu ever runs.

## 4. Phase 1 — subagent delegation

- [x] 4.1 Replace the inline three-tier inventory (1A/1B/1C) with a single subagent dispatch
      that receives the clarified theme and the refreshed catalog-cache path. Done —
      SKILL.md Phase 1 is a 5-line dispatch instruction.
- [x] 4.2 Define the dispatch prompt so the subagent runs the existing CLI listings, Desktop
      config read, and catalog-cache queries internally and returns only the structured table
      — no raw `--json` stream, no full CLI dump, no unfiltered catalog rows reach the main
      session. mechanism.md's new Phase 1 section documents exactly what the subagent must be
      told to do (self-contained: theme, catalog path, and mechanism.md's own path passed in).
- [x] 4.3 Confirm the main session still reads `./CLAUDE.md` and `./.claude/settings.json`
      itself rather than via the subagent. SKILL.md Phase 1: "Read `./CLAUDE.md` and
      `./.claude/settings.json` yourself — Phase 2 and Phase 4 need them directly."
- [x] 4.4 Confirm Phase 2's classification stays in the main session, consuming the
      subagent's structured return rather than raw sources. SKILL.md Phase 2 operates on
      "each returned candidate"; mechanism.md's return contract explicitly states the
      subagent "does not classify... that judgment stays with the main session."

## 5. Phase 3 — invert ambiguity handling

- [x] 5.1 Add an up-front clarifying interview before inventory: one question at a time about
      theme intent and the user's starting point. Generalized the old empty-theme gate
      (SKILL.md:19) into the purpose section's "Theme & starting point" paragraph, ahead of
      the `## Workflow` phase list (i.e. runs before Phase 1).
- [x] 5.2 Confirm the post-inventory confirmation menu (Phase 3B) is now genuinely smaller —
      confirmed: it only carries which-candidates/which-budget questions (see 3.3).
- [x] 5.3 Confirm a clear, unambiguous theme still skips the interview and proceeds directly
      to inventory. Stated explicitly: "a theme and starting point that are already clear
      skip straight to Phase 1."

## 6. Phase 5 — verify rubric

- [x] 6.1 Replace the five-step prose checklist (SKILL.md:238–246) with a checkable rubric:
      re-read `.claude/settings.json`, diff against the proposal the user approved, report
      mismatches. Now 5 checkboxes under `### Phase 5 — Verify`.
- [x] 6.2 Confirm the rubric still covers what the prose checklist covered: JSON validity,
      plugin project-scope state (Pass A/B/C), MCP denial/connection state, the written
      `skillListingBudgetFraction`, and which changes need a session restart. All 5 present
      as rubric items (MCP connection-state detail folded into "deniedMcpServers ... reflect
      the approved buckets; live MCP connections match").

## 7. Docs

- [x] 7.1 Update `docs/plugin-audit.md:145` to mark `split-project-scope-skill` resolved
      (with a pointer to this change). Struck through, "**Done**" note added pointing at
      `restructure-project-scope-skill`.
- [x] 7.2 Review `plugins/project-scope/README.md` line 25 for accuracy against the up-front
      interview. Updated: "If the theme or your starting point is ambiguous, it asks — one
      direct question at a time — before doing anything; a clear theme skips straight to
      inventory."
- [x] 7.3 Review the `project-scope` row in root `CLAUDE.md` for drift. Reviewed — it
      describes behavior-level outcomes only (auto-activation, consented install/uninstall,
      settings.json keys, project-scope-only, install footprint), none of which changed. No
      edit made, matching the "expected: no change needed" note.
- [ ] 7.4 Add a `CHANGELOG.md` entry once implemented. **Not done** — explicitly out of scope
      per the implementation brief ("Do NOT edit ... CHANGELOG.md — handled centrally at the
      end").

## 8. Verification

- [ ] 8.1 Record `on_invoke` tokens for `project-scope` from
      `~/.claude/plugins/plugin-catalog-cache.json` before making any change. **Not done** —
      this machine's local catalog cache (`~/.claude/plugins/plugin-catalog-cache.json`, 255
      entries) has no `cc-goodies`/`project-scope` entry at all; the marketplace isn't
      registered here, only `claude-plugins-official`. No baseline was measurable.
- [ ] 8.2 After implementation, refresh the catalog cache and record `on_invoke` again;
      confirm it decreased. **Not done** — same blocker as 8.1; requires an environment with
      cc-goodies actually installed/registered as a marketplace.
- [ ] 8.3 Run the restructured skill end-to-end in a scratch project with a clear theme.
      **Not done** — requires a live Claude Code session with the updated plugin installed;
      not achievable from a file-editing pass in this worktree.
- [ ] 8.4 Run the restructured skill end-to-end with a deliberately ambiguous theme. **Not
      done** — same blocker as 8.3.
- [ ] 8.5 Confirm the reference-never-read failure mode did not occur. **Not done** (depends
      on 8.3/8.4's live run); static review instead confirmed every pointer in SKILL.md
      resolves to real, non-empty content in the target reference file (see 1.6, 3.1).
- [x] 8.6 `jq empty plugins/project-scope/.claude-plugin/plugin.json && jq empty
      .claude-plugin/marketplace.json`; `claude plugins validate plugins/project-scope`. Both
      ran clean: `plugin.json OK`, `marketplace.json OK`, `✔ Validation passed`.

## 9. Release

- [x] 9.1 Bump `plugins/project-scope/.claude-plugin/plugin.json` `version`. 0.2.2 → 0.3.0
      (minor bump, per the implementation brief).
- [ ] 9.2 Commit on the change branch, push, open a draft PR to `develop`. **Not done** —
      explicitly out of scope: "Run NO git commands that mutate state ... I handle all
      committing."
