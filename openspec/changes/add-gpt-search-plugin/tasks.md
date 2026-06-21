## 1. Scaffold the plugin

- [x] 1.1 Create `plugins/gpt-search/.claude-plugin/plugin.json` (name `gpt-search`, version, description, author = Volodymyr Styran / github.com/sapran, SPDX `license` MIT, keywords e.g. `gpt`, `search`, `research`, `codex`, `mcp`, `cache`); no `hooks` key
- [x] 1.2 Create `plugins/gpt-search/skills/gpt-search/SKILL.md` with the body carried verbatim from `~/.claude/skills/gpt-search/SKILL.md`, frontmatter `name: gpt-search` + trigger-shaped `description:`
- [x] 1.3 Add the graceful-degradation note to the skill: if `mcp__codex__codex` is unavailable, tell the user to install the Codex MCP and stop — do not hard-fail
- [x] 1.4 Add the cache-teardown note to the skill: how to clear `.claude/cache/search/`
- [x] 1.5 Create `plugins/gpt-search/commands/gpt-search.md` as a thin alias (frontmatter `description`, `argument-hint`) whose body says "use the `gpt-search` skill" and forwards the query via `$ARGUMENTS`; ensure no leftover "this command" self-references in the skill
- [x] 1.6 Confirm no `.mcp.json` is present anywhere under `plugins/gpt-search/`

## 2. Plugin README (install ⇄ uninstall symmetry)

- [x] 2.1 Write `plugins/gpt-search/README.md` with what-it-is, usage (`/gpt-search <query>`), and the cache behavior
- [x] 2.2 Document the **Prerequisite**: Codex MCP (`mcp__codex__codex` / `mcp__codex__codex-reply`); plugin ships no `.mcp.json`, user brings their own
- [x] 2.3 Document **Install** (`/plugin marketplace add` → `/plugin install gpt-search@cc-goodies`) and **Uninstall** (`/plugin uninstall` is the full revert — no hook, no shared-config edits) sections
- [x] 2.4 Document clearing `.claude/cache/search/` as an optional, user-driven cleanup step

## 3. Register and mirror across the marketplace

- [x] 3.1 Add a `gpt-search` entry to `.claude-plugin/marketplace.json` `plugins` array (`name`, `source: ./plugins/gpt-search`, `description`)
- [x] 3.2 Bump `metadata.description` lineup in `marketplace.json` to include gpt-search
- [x] 3.3 Add the plugin to the root `README.md` (overview + Install/Uninstall mirror)
- [x] 3.4 Add a `CHANGELOG.md` entry (Keep a Changelog format)
- [x] 3.5 Add a row to the `CLAUDE.md` plugin table describing gpt-search (skill + command; Codex MCP prerequisite)

## 4. Validate

- [x] 4.1 `jq empty plugins/gpt-search/.claude-plugin/plugin.json && jq empty .claude-plugin/marketplace.json`
- [x] 4.2 `claude plugins validate plugins/gpt-search`
- [x] 4.3 Confirm the skill `description` is trigger-shaped and the command forwards `$ARGUMENTS`; re-read the migrated `SKILL.md` against the source to confirm behavior is preserved

## 5. Commit

- [x] 5.1 Commit on `develop` with a conventional message (e.g. `feat(gpt-search): add Codex-MCP web-research plugin`); confirm before any push

## 6. Post-merge follow-up (out of scope for repo edits — track separately)

- [x] 6.1 Fast-forward `develop`→`main`, push `main` with raw git (rtk proxy bypasses git-guard) — with explicit user confirmation
- [x] 6.2 User runs `/plugin marketplace update` + `/plugin install gpt-search@cc-goodies`
- [x] 6.3 After the plugin is installed, remove the local `~/.claude/skills/gpt-search/` duplicate to avoid a name collision
