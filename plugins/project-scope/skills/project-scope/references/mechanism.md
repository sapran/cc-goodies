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
  - `.tokens["<model>"].{always_on, on_invoke}` — context cost in tokens. `always_on` loads into **every** turn (budget-relevant); `on_invoke` only when the component is invoked. The set of `.tokens` keys present in the cache is **not fixed** — it reflects whichever models have been priced as of the last catalog refresh, and lags the session's own model generation. Resolve the key to use with a three-step procedure, never by picking whichever key happens to sort first:
    1. **Exact match** — a `.tokens` key equal to the session's own model id. Report its figures with no caveat.
    2. **Family match** — no exact key, but a key sharing the model's family word (`opus`, `sonnet`, `fable`, `haiku`, …) exists. Report that key's figures, but name the key used (e.g. "via claude-sonnet-4-6, not claude-sonnet-5") so the reader knows it's a different generation's cost.
    3. **No match** — neither exact nor family key exists. Report the cost as unavailable; never substitute an unrelated family's number.

     A skill's Bash/jq tool calls receive **no injected model-identity payload** — unlike the hook JSON contract (`.tool_input`, `.cwd`, `.tool_name`, …) or the statusLine command's `.model.display_name`, nothing on disk or in the environment tells a script which model is running this session. The resolution key in step 1/2 above must therefore come from the model stating its own known model id as a literal *before* constructing the jq query (pass it in via `--arg`), not from anything a script detects. A family-match or unavailable result MUST be disclosed wherever the figure is surfaced — never silently substituted as if it were the session's own cost.
  - `.components.{skills,agents,commands,hooks,mcpServers,lspServers}[].chars.{always_on, on_invoke}` — per-component breakdown (note: `mcpServers` here means the plugin bundles its own MCP, which adds tool-listing budget on install).
- **Iron rule:** never emit the full pool through the tool. Always keyword-match + sort + slice **inside one `jq`** and print only the small survivor set. Reading the file server-side is fine; printing all of it is what truncates.

The authoritative installed/downloaded record is `~/.claude/plugins/installed_plugins.json` (`.plugins` object). For entries de-listed from the cache, the fallback is the on-disk manifest under `~/.claude/plugins/marketplaces/<marketplace>/.../plugin.json`.

Do **not** touch `~/.claude/settings.json` (global) — other projects must keep their full surface area.
