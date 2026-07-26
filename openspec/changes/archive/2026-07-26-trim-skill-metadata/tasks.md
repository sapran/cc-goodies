## 1. Baseline measurement

- [x] 1.1 Re-verified against the working tree (two restructure commits landed first but left
      these fields untouched, as expected): project-scope SKILL.md description 685 chars/92
      words; session-finalise SKILL.md description 478 chars/76 words; `/project-scope` command
      description 233 chars/32 words; `/session-finalise` command description 42 chars/5 words
      (already compliant, per proposal); marketplace `project-scope` entry 248 chars/32 words;
      marketplace `session-finalise` entry 193 chars/20 words. All match the proposal's
      pre-restructure figures exactly — confirmed these surfaces were genuinely untouched.
- [ ] 1.2 NOT DONE — verified `cc-goodies` has no entry anywhere in
      `~/.claude/plugins/plugin-catalog-cache.json` (`jq '.catalog.plugins | keys[]'` over all
      255 cached plugins: zero matches for `project-scope`/`session-finalise`/`sapran`). Per
      the task prompt's explicit instruction, did not add/update the marketplace to manufacture
      an entry (that mutates global user state outside this change's scope and outside my
      authorization) — leaving unchecked rather than inventing a figure.

## 2. Trim skill frontmatter descriptions

- [x] 2.1 `plugins/project-scope/skills/project-scope/SKILL.md`: removed the mechanism sentence
      ("It investigates … Project scope only — never touches global config."); the trigger
      clause and its four example phrases are byte-identical (verified via `git diff` — only
      the deleted lines changed, the retained lines show no diff markers).
- [x] 2.2 `plugins/session-finalise/skills/session-finalise/SKILL.md`: reviewed both sentences
      against the trigger-surface-only bar. Finding: both sentences are already pure trigger
      phrases/activation scenarios with no mechanism or capability prose (unlike project-scope,
      there is no "it orchestrates/writes/applies…" clause to remove) — left byte-for-byte
      unchanged. Zero edit is the correct outcome here, not a skipped step.
- [x] 2.3 Both descriptions still open "This skill should be used when…" (third person).
      Frontmatter `version` fields were found OUT OF SYNC with `plugin.json` on both skills pre
      -existing (project-scope SKILL.md said 0.2.2 vs plugin.json 0.3.0; session-finalise
      SKILL.md said 0.2.1 vs plugin.json 0.3.0 — both stale from the prior restructure commits,
      unrelated to this change) — fixed by setting both to the new 0.3.1 (see 7.1).

## 3. Trim command and marketplace descriptions

- [x] 3.1 `plugins/project-scope/commands/project-scope.md`: `description` shortened 233→58
      chars, verb-first ("Scope project plugins, MCP servers, and skills to a theme."),
      mechanism clause dropped; `argument-hint` unchanged.
- [x] 3.2 `.claude-plugin/marketplace.json`: `project-scope` entry shortened 248→144 chars
      (within ~50–200); `session-finalise` entry (193 chars) left as-is — already compliant,
      no slack found worth trimming.
- [x] 3.3 Diffed every trimmed clause against `plugins/project-scope/README.md`: the mechanism
      sentence's content (three-tier investigation, per-bucket consent, `claude plugins
      install|uninstall --scope project`, `.claude/settings.json` writes,
      `skillListingBudgetFraction`) is already documented there (README lines ~5, ~30-39,
      ~41-45). No fact was stranded; no README edit made, matching the proposal's expectation.

## 4. Verify trigger coverage (do not assume from the text)

- [x] 4.1 project-scope: `git diff` proves the four trigger phrases are byte-identical
      before/after (only the trailing mechanism sentence was deleted; no diff markers touch the
      trigger clause). Supplementary check: a fresh haiku-model agent, given ONLY the new
      description text cold (no other context), judged all 4 verbatim trigger phrases + 2
      natural paraphrases as YES-activate and a negative-control ("what's the weather today?")
      as NO. True harness-level live activation could NOT be exercised in this environment:
      `project-scope@cc-goodies` is explicitly disabled in this machine's global
      `~/.claude/settings.json` (`"project-scope@cc-goodies": false`), confirmed by its absence
      from this very subagent's own available-skills listing — no session here has the skill
      loaded to fire. Did not enable it globally to test, since that mutates user machine state
      outside this change's authorization.
- [x] 4.2 session-finalise: description is byte-for-byte unchanged (see 2.2/4.1 diff evidence),
      so there is no edit to regress trigger coverage. `session-finalise@cc-goodies` IS enabled
      globally and was present in this subagent's own live skill listing throughout this task,
      confirming the (unedited) description is currently being served to real sessions without
      issue.
- [x] 4.3 `claude plugins validate plugins/project-scope` and `claude plugins validate
      plugins/session-finalise` both pass (see §6); frontmatter for both commands and both
      skills parses cleanly — no regression.

## 5. Measure the token delta

- [ ] 5.1 NOT DONE — blocked by 1.2 (no baseline exists to diff against; `cc-goodies` is absent
      from `~/.claude/plugins/plugin-catalog-cache.json` on this machine).
- [ ] 5.2 NOT DONE — same reason; no baseline, no delta to confirm.

## 6. Validation

- [x] 6.1 `jq empty plugins/project-scope/.claude-plugin/plugin.json
      plugins/session-finalise/.claude-plugin/plugin.json .claude-plugin/marketplace.json` — all
      three OK.
- [x] 6.2 `claude plugins validate plugins/project-scope` and `claude plugins validate
      plugins/session-finalise` — both `✔ Validation passed`.

## 7. Docs + release

- [x] 7.1 Bumped `plugins/project-scope/.claude-plugin/plugin.json` and
      `plugins/session-finalise/.claude-plugin/plugin.json` 0.3.0 → 0.3.1 (current values were
      already 0.3.0 from the immediately-prior restructure commits, not the stale 0.2.1/0.2.2
      this task text was written against); both `SKILL.md` `version` fields synced to 0.3.1
      (also fixing the pre-existing drift noted in 2.3).
- [ ] 7.2 NOT DONE by design — out of scope per the task prompt: "Do NOT touch
      `.metadata.version`... the version bump is handled centrally after you" and "Do NOT edit
      `CHANGELOG.md`."
- [ ] 7.3 NOT DONE by design — out of scope per the task prompt: "Run NO git commands that
      mutate state... I handle all committing." No commit/push/PR performed.
