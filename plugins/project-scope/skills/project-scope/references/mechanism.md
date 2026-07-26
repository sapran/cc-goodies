# Mechanism reference (canonical)

Two paradigms, chosen by whether a **project-install primitive exists** for the surface.

## Paradigm 1 — project-scoped install / uninstall (plugins)

Plugins are the only surface with a real per-project install primitive. Adding or removing a plugin *for this project* is an **install/uninstall** operation, not a settings toggle:

| Operation | Command | Effect |
|---|---|---|
| Add a plugin to this project | `claude plugins install <id> --scope project` | Installs (downloads if needed) and scopes the plugin to THIS project. The CLI records project-scope state in `.claude/settings.json` `enabledPlugins`. |
| Remove a plugin from this project | `claude plugins uninstall <id> --scope project` | Uninstalls the plugin from THIS project's scope only — user/global scope is untouched. |

Let the CLI own `enabledPlugins`. Do **not** hand-edit that key — run the install/uninstall commands and preserve whatever they write.

If an uninstall reports nothing to remove, the plugin was only user-installed, not project-scoped — treat it as already-absent and stop there. Never fall back to a global uninstall (dropping `--scope project`) to force it off; that removes the plugin from every project, not just this one.

## Paradigm 2 — enable / disable (denylist & override in `.claude/settings.json`)

For surfaces with **no** project-install primitive — user-level standalone skills, and user-scope / Claude Desktop / claude.ai MCP servers. These are toggled off *for the project*, never "uninstalled":

| Surface | Key in `.claude/settings.json` | Effect |
|---|---|---|
| Skills (user-level standalone, e.g. `~/.claude/skills/*`) | `skillOverrides: { "skill-name": "user-invocable-only" }` | Hides from model's listing (saves per-turn tokens); `/skill-name` still works manually. Use `"off"` to also hide the slash command. |
| MCP servers (user-scope, `.mcp.json`, **Claude Desktop config**, or **claude.ai integrations**) | `deniedMcpServers: [{ "serverName": "..." }]` | Denylist takes precedence across all scopes. Matches by raw `serverName` (no `mcp__` prefix, no `claude_ai_` prefix). One key denies the server whether it reached CC via user-scope add, `.mcp.json`, Desktop config import, a Desktop-launched CC session, or a claude.ai remote integration — and wins even when `enableAllProjectMcpServers` is true. |
| Plugin-provided skills / MCPs | (governed by the plugin) | Follow their parent plugin's project install/uninstall — install the plugin to get them, uninstall to remove them. No separate key. |
| Skill-listing context budget | `skillListingBudgetFraction: 0.01` (1%) … `0.05` (5%) | Fraction of context window reserved for the skill listing. Lower = aggressive truncation = leaner per-turn cost. Higher = full descriptions visible = better skill matching. Default 0.01. |

Disabling an MCP server for this project is always the `deniedMcpServers` write above — never
`claude mcp remove -s user <name>`. That command deletes the server globally, for every project,
not just this one; never run it as a silent fallback — it needs the user's own explicit,
separate confirmation first.

`.claude/settings.local.json` (the permission allowlist) is a separate concern — read it only
to confirm it exists, never write to it.

## Writing `.claude/settings.json`

Include the schema reference at the top of the file — `"$schema":
"https://json.schemastore.org/claude-code-settings.json"` — whether merging into an existing file
or creating a new one.

Use `Edit` to add or merge keys when the file already exists; use `Write` only for first-time
creation, and create the `.claude/` directory first if it doesn't exist yet.

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

## Phase 1 — inventory subagent

Re-run this inventory on every invocation, even when the theme matches a prior run in this
session — the plugin/MCP universe and marketplace contents may have changed since, and a stale
in-context inventory would defeat Phase 0's marketplace refresh.

Dispatch inventory to a subagent (general-purpose is sufficient) rather than running it in the
main session. A fresh subagent has no memory of this skill being loaded, so the dispatch prompt
must be self-contained: pass it the clarified theme, the refreshed catalog-cache path (above),
and this file's own path so it can re-read any section below itself.

### What the subagent gathers, per tier

**1A — currently active.** Run in parallel: `claude plugins list` (installed plugins, scope,
enable state); `claude mcp list` (CC-native MCP servers — does not enumerate Claude Desktop app
MCPs); the Claude Desktop config, if present:

```bash
test -f "$HOME/Library/Application Support/Claude/claude_desktop_config.json" && \
  jq -r '.mcpServers | keys[]?' "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
```

Absent or unreadable (Linux, fresh macOS, non-Desktop install) → skip silently, CC-native
inventory is sufficient. Two MCP surfaces share the `deniedMcpServers` denylist under different
`serverName` forms: local Desktop config keys (bare key, e.g. `codex`) and claude.ai remote
integrations (never in the Desktop config or `claude mcp list`; detect them by scanning the
subagent's own available-tools listing for the `mcp__claude_ai_<Name>__*` prefix, then
reverse-derive `serverName` as `"claude.ai <Name>"`). Also inventory any other
`mcp__<server>__*` tool not produced by an enabled plugin (no `mcp__plugin_*` prefix). A Desktop
name colliding with a user-scope MCP of the same `serverName` is one denylist entry, not two.

A correctly-denied Claude Desktop MCP is easy to misjudge as a failure: it never appeared in
`claude mcp list` to begin with, so its absence there proves nothing either way. Verify its
denial instead by confirming the `deniedMcpServers` entry is present in the written
settings.json and that its `mcp__<name>__*` tools are gone from the tool list — which only takes
effect next session, after a restart.

The available-skills list is in the session-start system-reminder; skills with a `plugin:`
prefix are governed by their plugin's enable state.

**1B — installed but disabled.**

```bash
claude plugins list | awk '/❯/{id=$2} /Status:.*disabled/{print id}' | sort -u
```

These are low-friction install candidates (already downloaded — `claude plugins install <id>
--scope project` scopes them in with no marketplace fetch). Fetch descriptions/categories/
install-counts/token-cost in one cache query, never per-plugin file reads except for
cache-misses. Read all descriptions — do not pre-filter by id keyword-match; plugin ids and
theme vocabulary often diverge (theme "improve performance" vs. plugin id `skill-creator`).

Resolve token cost with the three-step procedure above (exact → family → unavailable). State
your own model id as a literal first — same self-knowledge constraint as any other tool call,
nothing on disk or in the environment provides it:

```bash
CAT="$HOME/.claude/plugins/plugin-catalog-cache.json"
MODEL="claude-sonnet-5"          # <- your own self-reported model id, stated above, not detected
FAMILY=$(printf '%s' "$MODEL" | cut -d- -f2)
jq -r --argjson ids '["feature-dev@claude-plugins-official","mcp-apps@claude-plugins-official"]' \
      --arg model "$MODEL" --arg family "$FAMILY" '
  .catalog.plugins as $p | $ids[] | . as $id | ($p[$id] // {}) as $e |
  ($e.tokens // {}) as $tok |
  ( if ($tok | has($model)) then {aon: $tok[$model].always_on, note: ""}
    elif ($tok | keys | map(select(test($family))) | length) > 0 then
      ($tok | keys | map(select(test($family))) | .[0]) as $fk |
      {aon: $tok[$fk].always_on, note: " (via \($fk), not \($model))"}
    else {aon: null, note: ""}
    end
  ) as $res |
  "\($id)\t[\($e.marketplace_entry.category // "?")]\taon=\($res.aon // "unavailable")\($res.note)\t\($e.marketplace_entry.description // "NOT IN CATALOG")"
' "$CAT"
```

A row's `aon=` value carries its own disclosure: a bare number is an exact match; `(via <key>,
not <model>)` is a family match — always name it; `unavailable` means neither matched — never
treat it as zero cost. `NOT IN CATALOG` rows (de-listed plugins) fall back to reading that
single plugin's `plugin.json` manifest on disk.

**1C — available in marketplace.** The cache holds ~200+ entries — reading all of them inside
this subagent call is fine; it's discarded when the subagent returns, and nothing here is
printed through the parent session's tool output (the failure mode this file's iron rule warns
about is emitting the pool *to the parent*, not reading it internally). Read every entry's
name/description/category/`unique_installs`, exclude ids already covered by 1A/1B, and judge
relevance against the theme yourself — no stopword tokenization, no fixed slice count. A
natural cut is usually well under 20 candidates, but let the theme decide the size; sort
survivors by `unique_installs`. If nothing is genuinely relevant, say so plainly rather than
padding the return with marginal candidates.

### Return contract

One row per candidate across all three tiers — this is what the subagent returns to the main
session; it does not classify keep/remove/install/skip, that judgment stays with the main
session applying the theme and the conflict/always-keep rules:

| Field | Meaning |
|---|---|
| `tier` | `1A` (active) / `1B` (installed-disabled) / `1C` (marketplace-available) |
| `surface` | `plugin` / `skill` / `mcp` |
| `id` | plugin id (`name@marketplace`), skill name, or MCP `serverName` |
| `state` | `active` / `disabled` / `available` |
| `description` | one-line, from the catalog entry or manifest |
| `always_on_tokens` | from `.tokens["<model>"].always_on`, resolved per the three-step procedure, with its disclosure note |
| `unique_installs` | marketplace tier only |
| `bundles_mcp` | boolean — plugin ships its own MCP server |
| `category` | catalog category, if present |
