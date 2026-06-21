## Why

The best-practice audit ([`docs/plugin-audit.md`](../../../docs/plugin-audit.md)) confirmed
15 findings — all minor/nit, all convention or documentation drift. This change closes the
mechanical gaps, implements the two judgment items per the audit's recommendation, and
records the remaining deliberate deviations as documented house conventions so future
plugins inherit them rather than re-tripping the same audit items.

## What Changes

- **CMD-6** — add `disable-model-invocation: true` to the 5 destructive control commands
  (`statusline-install`, `statusline-uninstall`, `git-guard-uninstall`,
  `shell-guard-uninstall`, `rtk-hook-uninstall`).
- **CMD-2** — trim 3 over-length command descriptions to the ~60-char guideline
  (`statusline-install`, `statusline-uninstall`, `session-finalise`), preserving meaning.
- **SKILL-2** — add a `version` key to both `SKILL.md` frontmatters (`session-finalise`,
  `project-scope`), matching each plugin's `plugin.json` version.
- **SKILL-3** — reword both skill descriptions to third person, keeping every trigger
  phrase and scenario.
- **HOOK-8** — add explicit numeric `timeout` to `voice-notify`'s two hook handlers.
- **SKILL-5** — split `project-scope/SKILL.md` (~3,996 words): move the canonical mechanism
  reference and Phase-3 menu tables into `references/`, dropping the always-loaded body
  under the ~3,000-word guideline.
- **CMD-3 / VAL-6 / CMD-12** — recorded in `CLAUDE.md` as intentional conventions (alias
  commands omit `allowed-tools` because execution lives in the delegated skill; the
  repo-root `LICENSE` covers the monorepo so plugins ship no per-plugin `LICENSE`; command
  files omit HTML-comment maintainer blocks because the body is itself the prompt).

## Capabilities

### New Capabilities

- `plugin-conformance`: the ongoing best-practice requirements every cc-goodies plugin must
  satisfy — control-command invocation guards, command/skill frontmatter discipline, hook
  timeouts, skill-body size, and the documented deviations — derived from the audit.

### Modified Capabilities

<!-- None. plugin-best-practice-audit (the audit capability) is unchanged; this change acts on its findings. -->

## Impact

- **Files:** command frontmatter (6 `.md`), skill frontmatter + body (2 `SKILL.md` + new
  `project-scope/skills/.../references/`), `voice-notify` manifest, and `CLAUDE.md`.
- **Delivery:** implemented across seven conflict-free per-plugin branches
  (`align/<plugin>`) plus central `CLAUDE.md` edits on `develop`; each branch validated with
  `claude plugins validate` and merged to `develop`.
- **No behavior regressions:** `disable-model-invocation` only stops *model* auto-invocation
  of control commands — manual `/command` use is unaffected.
