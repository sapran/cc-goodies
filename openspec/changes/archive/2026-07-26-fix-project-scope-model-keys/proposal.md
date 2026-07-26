## Why

`project-scope`'s catalog-cache reference, `skills/project-scope/references/mechanism.md`, documents
the token-cost field like this (line 40):

> `.tokens["<model>"].{always_on, on_invoke}` — context cost in tokens. `always_on` loads into
> **every** turn (budget-relevant); `on_invoke` only when the component is invoked. Model keys
> seen: `claude-opus-4-7`, `claude-sonnet-4-6` — these can lag the session's model, so read the
> current model's key if present, else any opus key, else any key.

Under Claude-5-generation sessions (Opus 5 = `claude-opus-5`, Fable 5 = `claude-fable-5`, Sonnet 5 =
`claude-sonnet-5`) the "current model's key if present" branch can never match either hard-coded
key, so the documented fallback — "else any opus key, else any key" — fires silently. The skill
then reports another model's `always_on`/`on_invoke` figures as if they belonged to the running
session, in a plugin whose entire purpose (per its own description) is per-turn token-budget
decisions.

The actual implementation is worse than the documented fallback: `SKILL.md`'s Phase 1B jq query
(line 86) doesn't implement "current model, else opus, else any" at all — it reads
`(($e.tokens // {}) | to_entries[0].value.always_on)`, i.e. whichever key happens to sort first in
the JSON object, with no model-awareness whatsoever. The mechanism doc describes a fallback chain
the skill body doesn't actually run.

**Live verification against the real cache** (read-only, this session):

```
$ ls -la ~/.claude/plugins/plugin-catalog-cache.json
600  /Users/user/.claude/plugins/plugin-catalog-cache.json  397.1K
$ jq -r '.catalog.plugins | to_entries | map(.value.tokens // {} | keys) | add | unique' \
    ~/.claude/plugins/plugin-catalog-cache.json
["claude-opus-4-7", "claude-sonnet-4-6"]
```

The cache exists, is readable, and every plugin's `.tokens` object carries exactly those two keys
— no Claude-5-generation key exists anywhere in the file today. This session is itself running as
Sonnet 5 (`claude-sonnet-5`), so `project-scope` would hit the silent-fallback branch right now,
not hypothetically.

## What Changes

- **MODIFIED** — `references/mechanism.md`'s token-cost section: drop the hard-coded "keys seen"
  list and the silent "else any opus key, else any key" fallback; replace with a documented
  resolution procedure (see `design.md`) that always discloses which key's figures are shown.
- **MODIFIED** — `SKILL.md` Phase 1B's jq query and the Pass B / Pass C / Phase 3A prose that
  reference `always_on` cost: select by the resolved model key instead of `to_entries[0]`, and
  surface the disclosure when the resolved key isn't an exact match for the session's own model.
- **ADDED** — a requirement that no fallback or non-matching figure is ever presented as the
  session's own without saying so.
- No change to any other phase: inventory (1A/1C), install/uninstall, MCP denylist,
  `skillListingBudgetFraction`, or the settings.json write path are untouched.

## Capabilities

### Added Capabilities

- `project-scope-token-reporting` — new spec (no existing spec of this name in `openspec/specs/`).
  Governs how the skill resolves the session's model key against the catalog cache and discloses
  the result when reporting per-plugin token costs.

## Impact

- **Reference doc** `plugins/project-scope/skills/project-scope/references/mechanism.md`: the
  token-cost paragraph (~line 40).
- **Skill body** `plugins/project-scope/skills/project-scope/SKILL.md`: the Phase 1B jq query
  (~line 86) and the Pass B / Pass C / Phase 3A prose that surfaces `always_on` figures to the
  user.
- **Manifest** `plugins/project-scope/.claude-plugin/plugin.json`: version bump (0.2.1 → 0.2.2,
  patch — bug fix, no behavioural surface added).
- **No script/hook/test changes** — `project-scope` ships no `scripts/` or `tests/` directory;
  verification is a live jq query against the real catalog cache plus a scratch-project run.
- **No new runtime dependency** (`jq` only, as today).
