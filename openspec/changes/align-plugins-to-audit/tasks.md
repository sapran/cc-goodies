## 1. Central (develop) — conventions + scaffolding

- [x] 1.1 Document the three deliberate deviations in `CLAUDE.md` (CMD-3 alias `allowed-tools`
      omission, VAL-6 monorepo root-LICENSE convention, CMD-12 no HTML-comment blocks).
- [x] 1.2 Commit the `CLAUDE.md` conventions and the umbrella OpenSpec change on `develop`.
- [x] 1.3 Create seven worktrees with branches `align/<plugin>` off `develop` (sequentially).

## 2. Per-plugin branches (parallel)

- [x] 2.1 `align/statusline`: add `disable-model-invocation: true` to `statusline-install.md`
      + `statusline-uninstall.md` (CMD-6); trim both descriptions to ~60 chars (CMD-2);
      `claude plugins validate`; commit. (372186f, d65c888)
- [x] 2.2 `align/git-guard`: add `disable-model-invocation: true` to `git-guard-uninstall.md`
      (CMD-6); validate; commit. (71107be)
- [x] 2.3 `align/shell-guard`: add `disable-model-invocation: true` to
      `shell-guard-uninstall.md` (CMD-6); validate; commit. (4cf5ac8)
- [x] 2.4 `align/rtk-hook`: add `disable-model-invocation: true` to `rtk-hook-uninstall.md`
      (CMD-6); validate; commit. (b15e30b)
- [x] 2.5 `align/voice-notify`: add numeric `timeout` to both hook handlers in `plugin.json`
      (HOOK-8); validate; commit. (f60b740)
- [x] 2.6 `align/session-finalise`: trim `session-finalise.md` description (CMD-2); add
      `version` to `SKILL.md` (SKILL-2); reword skill description to third person (SKILL-3);
      validate; commit. (d9e31c8, ac86897)
- [x] 2.7 `align/project-scope`: add `version` to `SKILL.md` (SKILL-2); third-person
      description (SKILL-3); split body into `references/` under ~3,000 words (SKILL-5);
      validate + verify references resolve; commit. (0fefb2b, 0be2aa4)

## 3. Integrate + verify

- [x] 3.1 Review each branch (`git log`/`git diff`) and merge with `--no-ff` into `develop`.
- [x] 3.2 Run `claude plugins validate` on every plugin + the marketplace on merged `develop`.
      (All 8 pass; marketplace's pre-existing metadata.repository warning is unrelated.)
- [x] 3.3 Remove the seven worktrees and delete the merged `align/*` branches.
- [x] 3.4 Confirm the spec's `plugin-conformance` requirements are all satisfied on `develop`.
      (5 control commands guarded, 2 hook timeouts, 2 skill versions + third-person, refs
      resolve, deviations documented in CLAUDE.md.)
