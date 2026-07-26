## 1. Baseline measurement

- [ ] 1.1 Re-verify the current word/char counts against the working tree before editing:
      `project-scope` and `session-finalise` `SKILL.md` descriptions, the `/project-scope` and
      `/session-finalise` command descriptions, and both `marketplace.json` entries.
- [ ] 1.2 Record each plugin's `always_on` token figure from
      `~/.claude/plugins/plugin-catalog-cache.json` as the pre-change baseline (the
      plugin-level `.tokens["<model>"].always_on`, and, where present, the
      `.components.skills[].chars.always_on` / `.components.commands[].chars.always_on`
      breakdown). If `cc-goodies` isn't present in the local cache, add/update the marketplace
      first so there is something to measure.

## 2. Trim skill frontmatter descriptions

- [ ] 2.1 `plugins/project-scope/skills/project-scope/SKILL.md`: remove the mechanism sentence
      ("It investigates … Project scope only — never touches global config."); keep the
      trigger clause and its four example phrases verbatim or in equivalent phrasing.
- [ ] 2.2 `plugins/session-finalise/skills/session-finalise/SKILL.md`: review both sentences
      against the trigger-surface-only bar; trim only content that is not itself an activation
      condition.
- [ ] 2.3 Confirm both descriptions still open "This skill should be used when…" (third
      person, per the existing `plugin-conformance` requirement) and both frontmatter
      `version` fields still match `plugin.json`.

## 3. Trim command and marketplace descriptions

- [ ] 3.1 `plugins/project-scope/commands/project-scope.md`: shorten `description` to ~60
      characters, verb-first, dropping the restated mechanism clause; leave `argument-hint`
      unchanged.
- [ ] 3.2 `.claude-plugin/marketplace.json`: shorten the `project-scope` entry to within
      ~50–200 characters; leave the `session-finalise` entry as-is unless review finds slack.
- [ ] 3.3 Diff every trimmed description against its plugin's `README.md`; if a trim would
      strand a fact present nowhere else, add it to the README — do not restore it to the
      description.

## 4. Verify trigger coverage (do not assume from the text)

- [ ] 4.1 For `project-scope`, exercise each of its four documented trigger phrases (plus 1–2
      natural paraphrases) in a live session and confirm the skill still auto-activates.
- [ ] 4.2 For `session-finalise`, exercise each of its documented wrap-up phrases and at least
      one loose-ends scenario, and confirm auto-activation still fires.
- [ ] 4.3 Confirm `/project-scope` and `/session-finalise` still invoke correctly by explicit
      name (unaffected by description trims in principle, but confirm no frontmatter parse
      regression).

## 5. Measure the token delta

- [ ] 5.1 Re-read `~/.claude/plugins/plugin-catalog-cache.json` after the edits (refresh the
      cache if it doesn't pick up the change) and record the post-change `always_on` figures
      next to the 1.2 baseline.
- [ ] 5.2 Confirm the delta is a reduction that roughly tracks the char/word reduction recorded
      in the proposal; if it doesn't move, treat that as a signal the cache wasn't refreshed —
      not as a pass.

## 6. Validation

- [ ] 6.1 `jq empty plugins/project-scope/.claude-plugin/plugin.json
      plugins/session-finalise/.claude-plugin/plugin.json .claude-plugin/marketplace.json`
- [ ] 6.2 `claude plugins validate plugins/project-scope` and `claude plugins validate
      plugins/session-finalise`

## 7. Docs + release

- [ ] 7.1 Bump `plugins/project-scope/.claude-plugin/plugin.json` and
      `plugins/session-finalise/.claude-plugin/plugin.json` versions (patch: `0.2.1` →
      `0.2.2`); keep each `SKILL.md` `version` in sync.
- [ ] 7.2 Bump marketplace `metadata.version` (patch) in `.claude-plugin/marketplace.json` and
      add a `CHANGELOG.md` entry.
- [ ] 7.3 Commit on the change branch, push, open a draft PR to `develop`. (Archive + `main`
      FF happen after review, per the repo release flow.)
