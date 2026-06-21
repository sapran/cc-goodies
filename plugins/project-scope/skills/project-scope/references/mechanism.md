# Mechanism reference (canonical)

Two paradigms, chosen by whether a **project-install primitive exists** for the surface.

## Paradigm 1 — project-scoped install / uninstall (plugins)

Plugins are the only surface with a real per-project install primitive. Adding or removing a plugin *for this project* is an **install/uninstall** operation, not a settings toggle:

| Operation | Command | Effect |
|---|---|---|
| Add a plugin to this project | `claude plugins install <id> --scope project` | Installs (downloads if needed) and scopes the plugin to THIS project. The CLI records project-scope state in `.claude/settings.json` `enabledPlugins`. |
| Remove a plugin from this project | `claude plugins uninstall <id> --scope project` | Uninstalls the plugin from THIS project's scope only — user/global scope is untouched. |

Let the CLI own `enabledPlugins`. Do **not** hand-edit that key — run the install/uninstall commands and preserve whatever they write.

## Paradigm 2 — enable / disable (denylist & override in `.claude/settings.json`)

For surfaces with **no** project-install primitive — user-level standalone skills, and user-scope / Claude Desktop / claude.ai MCP servers. These are toggled off *for the project*, never "uninstalled":

| Surface | Key in `.claude/settings.json` | Effect |
|---|---|---|
| Skills (user-level standalone, e.g. `~/.claude/skills/*`) | `skillOverrides: { "skill-name": "user-invocable-only" }` | Hides from model's listing (saves per-turn tokens); `/skill-name` still works manually. Use `"off"` to also hide the slash command. |
| MCP servers (user-scope, `.mcp.json`, **Claude Desktop config**, or **claude.ai integrations**) | `deniedMcpServers: [{ "serverName": "..." }]` | Denylist takes precedence across all scopes. Matches by raw `serverName` (no `mcp__` prefix, no `claude_ai_` prefix). One key denies the server whether it reached CC via user-scope add, `.mcp.json`, Desktop config import, a Desktop-launched CC session, or a claude.ai remote integration — and wins even when `enableAllProjectMcpServers` is true. |
| Plugin-provided skills / MCPs | (governed by the plugin) | Follow their parent plugin's project install/uninstall — install the plugin to get them, uninstall to remove them. No separate key. |
| Skill-listing context budget | `skillListingBudgetFraction: 0.01` (1%) … `0.05` (5%) | Fraction of context window reserved for the skill listing. Lower = aggressive truncation = leaner per-turn cost. Higher = full descriptions visible = better skill matching. Default 0.01. |

## npm-based skills / tools

If a project uses any npm-based skills or tools, apply the **same project-scoped install/uninstall principle**: manage them with project-local `npm install <pkg>` / `npm uninstall <pkg>` (which writes the project's `package.json`/lockfile), never a global enable/disable toggle. This skill does not currently run an npm discovery pass; if such tools are in play, treat them under install/uninstall consistent with Paradigm 1.

## Reading the plugin universe (canonical data source)

**Read the on-disk catalog cache — do NOT pipe the CLI's `--json` stream.** `claude plugins list --available --json` serialises the entire marketplace pool (~330 KB / 1400+ lines). That far exceeds the agent's Bash output cap (~64 KB), so the stream arrives **truncated** and corrupts any downstream `jq` (`parse error: Unfinished string at EOF`). Query the cache file the CLI already maintains instead:

- **Path:** `~/.claude/plugins/plugin-catalog-cache.json` — refreshed by Phase 0's `marketplace update` (carries top-level `fetchedAt`).
- **Shape:** `.catalog.plugins["<id>@<marketplace>"]` →
  - `.marketplace_entry.{name, description, category}`
  - `.unique_installs` — popularity/health proxy. **Sort on this.** (This is the real field; there is no `installCount`.)
  - `.version`, `.source`
  - `.tokens["<model>"].{always_on, on_invoke}` — context cost in tokens. `always_on` loads into **every** turn (budget-relevant); `on_invoke` only when the component is invoked. Model keys seen: `claude-opus-4-7`, `claude-sonnet-4-6` — these can lag the session's model, so read the current model's key if present, else any opus key, else any key.
  - `.components.{skills,agents,commands,hooks,mcpServers,lspServers}[].chars.{always_on, on_invoke}` — per-component breakdown (note: `mcpServers` here means the plugin bundles its own MCP, which adds tool-listing budget on install).
- **Iron rule:** never emit the full pool through the tool. Always keyword-match + sort + slice **inside one `jq`** and print only the small survivor set. Reading the file server-side is fine; printing all of it is what truncates.

The authoritative installed/downloaded record is `~/.claude/plugins/installed_plugins.json` (`.plugins` object). For entries de-listed from the cache, the fallback is the on-disk manifest under `~/.claude/plugins/marketplaces/<marketplace>/.../plugin.json`.

Do **not** touch `~/.claude/settings.json` (global) — other projects must keep their full surface area.
