## Why

The `gpt-search` skill — deep web research via the Codex MCP with project-local cache reuse — currently lives only as a personal skill at `~/.claude/skills/gpt-search/`. It is undistributable, unversioned, and absent from the `cc-goodies` marketplace where the user's other migrated skills (`session-finalise`, `project-scope`) already live. Folding it into the marketplace makes it installable, versioned, documented, and uninstallable like every other plugin.

## What Changes

- Add a new `gpt-search` plugin under `plugins/gpt-search/`, packaged with the established skill→plugin migration pattern: an auto-activating `skills/gpt-search/SKILL.md` (the full research-and-cache body) plus a thin `/gpt-search` command alias under `commands/`.
- Carry the skill body across verbatim in behavior, with two documentation-level additions: a **graceful-degradation note** (if the Codex MCP tools are absent, tell the user to install the Codex MCP rather than hard-failing) and a **cache-teardown note** (how to clear `.claude/cache/search/`).
- Register the plugin in `.claude-plugin/marketplace.json` and bump the marketplace `metadata.description` lineup.
- Mirror the plugin across the root `README.md`, `CHANGELOG.md`, and the `CLAUDE.md` plugin table, with both **Install** and **Uninstall** sections (install⇄uninstall symmetry).
- Document the **Codex MCP prerequisite** (`mcp__codex__codex` / `mcp__codex__codex-reply`) in the plugin README — the plugin ships **no** `.mcp.json`; the user brings their own Codex MCP. This keeps the plugin portable and avoids duplicating/conflicting with an existing Codex MCP setup.
- No hook, no durable external state: `/plugin uninstall` is the full revert (matching `session-finalise`).

## Capabilities

### New Capabilities
- `gpt-search-plugin`: a marketplace plugin that provides Codex-MCP-backed deep web research from a Claude Code session — query → cache-reuse check → Codex MCP research call → formatted-and-cached result — packaged as an auto-activating skill plus a thin command alias, with a documented Codex MCP prerequisite and graceful degradation when it is absent.

### Modified Capabilities
<!-- None. This change adds a new plugin; it does not alter the requirements of plugin-conformance or plugin-best-practice-audit. The new plugin is expected to satisfy the existing plugin-conformance spec as a consequence, not by changing it. -->

## Impact

- **New files**: `plugins/gpt-search/.claude-plugin/plugin.json`, `plugins/gpt-search/skills/gpt-search/SKILL.md`, `plugins/gpt-search/commands/gpt-search.md`, `plugins/gpt-search/README.md`.
- **Edited files**: `.claude-plugin/marketplace.json` (new plugin entry + lineup description bump), root `README.md`, `CHANGELOG.md`, `CLAUDE.md` (plugin table).
- **Runtime dependency**: the Codex MCP server (`mcp__codex__codex`, `mcp__codex__codex-reply`) — documented as a prerequisite, not bundled. No new repo dependencies.
- **External state at runtime**: project-local cache `.claude/cache/search/*.md`, created on use (not on install); documented teardown, exempt from the install⇄uninstall teardown rule like an ephemeral cache.
- **Post-merge follow-up (outside this change's repo edits)**: publish (`develop`→`main`), user installs `gpt-search@cc-goodies`, then removes the local `~/.claude/skills/gpt-search/` duplicate to avoid a name collision.
