## 1. Remove the badge from the statusline script

- [x] 1.1 Delete the `caveman_badge()` helper and its explanatory comment block from
  `plugins/statusline/statusline-command.sh`.
- [x] 1.2 Delete the `caveman_badge` call at the end of the enriched render path, so the
  second line ends with the `c:`/`s:`/`w:` gauge block.
- [x] 1.3 Confirm no `caveman`, `CAVEMAN`, or `.caveman-*` reference survives in the
  script.

## 2. Remove the badge cases from the harness

- [x] 2.1 Delete cases `l`..`s` (badge render, hardening, control-byte strip, savings
  suffix, env opt-outs, fail-soft, lean-no-badge, whitelist pin), the `CAVEMAN_MODES`
  list, the `cm_stdin` helper, and the section banner from
  `plugins/statusline/tests/run.sh`.
- [x] 2.2 Delete the corresponding entries from the case-dispatch list at the bottom of
  the harness.
- [x] 2.3 Delete the now-unused `EXTRA_ENV` splice from `render()` along with its
  `shellcheck disable=SC2086`, since the caveman opt-out variables were its only caller.
- [x] 2.4 Update the harness summary line to name only the surviving capabilities.
- [x] 2.5 Run `bash plugins/statusline/tests/run.sh` — every remaining case passes.

## 3. Update the docs and version

- [x] 3.1 Remove the "Caveman badge" section from `plugins/statusline/README.md`.
- [x] 3.2 Drop the badge sentence from the statusline row in the root `README.md`.
- [x] 3.3 Add a `### Removed` entry under `## [Unreleased]` in `CHANGELOG.md` covering
  the segment, the two dead environment variables, and the guidance for users who still
  run caveman.
- [x] 3.4 Bump `plugins/statusline/.claude-plugin/plugin.json` to `0.7.0`.

## 4. Sync and archive

- [x] 4.1 Delete the `statusline-caveman-badge` capability from `openspec/specs/` via
  `openspec archive`.
- [x] 4.2 Archive this change into `openspec/changes/archive/` in the same PR.
