---
name: project-scope
version: 0.2.0
description: >-
  This skill should be used when the user wants to scope or trim THIS project's plugins, MCP
  servers, and skills to only those relevant for a stated theme — "scope this project to
  security work", "trim my plugins for this theme", "reduce per-turn token cost here", "which
  tools should this project have?". It investigates currently-active resources,
  installed-but-disabled plugins, AND plugins available in registered marketplaces; proposes
  per-bucket changes with explicit consent; applies plugin changes via `claude plugins
  install|uninstall --scope project` and writes `.claude/settings.json` (including
  `skillListingBudgetFraction`). Project scope only — never touches global config.
---

# Project Scope

Investigate the available Claude Code resources at three friction tiers — currently active, installed-but-disabled, and available-in-registered-marketplaces — evaluate each one's relevance for the user's stated theme in the **current project**, present the proposal to the user, ask explicit per-bucket consent for which plugins to **install** and **uninstall** at project scope and which user-level/Desktop tools to **disable**, then apply plugin changes with `claude plugins install|uninstall <id> --scope project` and write `.claude/settings.json` for the disable-only surfaces.

**The theme.** When invoked via `/project-scope <theme>`, the theme is the command argument. When the skill auto-activates from a natural request, the theme is whatever the user asked to scope the project for. If no theme is clear, ask once via AskUserQuestion (one short, free-form question) before proceeding — don't proceed without a theme.

## Mechanism reference (canonical)

Two paradigms, chosen by whether a **project-install primitive exists** for the surface:

- **Paradigm 1 — project-scoped install / uninstall (plugins).** Plugins are the only surface with a real per-project install primitive; add/remove via `claude plugins install|uninstall <id> --scope project`. Let the CLI own `enabledPlugins` — never hand-edit it.
- **Paradigm 2 — enable / disable (`.claude/settings.json`).** For surfaces with no project-install primitive (user-level standalone skills via `skillOverrides`; user-scope / Claude Desktop / claude.ai MCP servers via `deniedMcpServers`; skill-listing context via `skillListingBudgetFraction`). Toggled off *for the project*, never "uninstalled".

The canonical command/key tables, the npm-based-tools note, and the catalog-cache data source (`~/.claude/plugins/plugin-catalog-cache.json` shape, the `--json`-truncation iron rule, and `installed_plugins.json` fallback) live in **[references/mechanism.md](references/mechanism.md)** — read it before any inventory or apply step. Do **not** touch `~/.claude/settings.json` (global).

## Workflow

### Phase 0 — Refresh marketplaces

Before inventorying anything, refresh all configured marketplaces so the analysis works from current data:

```bash
claude plugins marketplace update
```

This is a single network call per registered marketplace (~5–30s total). It prevents two real failure modes that an offline cache produces:

- **Stale cache misses newly-published plugins** — Pass C proposes nothing relevant when the user is actually missing good candidates.
- **Stale cache lists de-listed plugins** — Phase 4 install fails mid-apply because the source no longer exists upstream, leaving a half-applied state.

If `marketplace update` reports failure for a *specific* marketplace (network, auth, repo gone), continue with the others and surface the failure in Phase 3A so the user sees which slice of the universe is stale. Do **not** abort — partial freshness is better than no freshness.

After update, proceed to Phase 1. The refreshed listings are written to the catalog cache (see references/mechanism.md) — Phase 1 reads that file, never the `--json` stream.

### Phase 1 — Inventory (three tiers)

Re-inventory on every run, even when the theme matches a prior run — the plugin/MCP universe and marketplace contents may have changed.

#### 1A. Currently active

Run in parallel:

1. `claude plugins list` — installed plugins with their scope (user/project) and enable state. Shows which plugins are already project-installed vs. only user-installed.
2. `claude mcp list` — currently active **CC-native** MCP servers (user-scope adds + `.mcp.json`). Does **not** enumerate Claude Desktop app MCPs.
3. **Claude Desktop app MCPs** — read the Desktop config separately:
   ```bash
   test -f "$HOME/Library/Application Support/Claude/claude_desktop_config.json" && \
     jq -r '.mcpServers | keys[]?' "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
   ```
   Each returned name is a candidate alongside `claude mcp list` results; `deniedMcpServers` (matched by raw `serverName`) is the kill switch for all of them. **If the config is absent or unreadable** (Linux, fresh macOS, non-Desktop install): skip this step silently — CC-native inventory is sufficient. Two MCP surfaces share this denylist, with different `serverName` forms:
   1. **Local Desktop config** (`claude_desktop_config.json` keys under `mcpServers`, e.g. `codex`, `ollama`, `libai`) — `serverName` = the bare key, copied verbatim.
   2. **claude.ai remote integrations** (org-level Asana / Gmail / HubSpot / Ahrefs / Drive / Calendar / Context7) — never in the Desktop config, never in `claude mcp list`; they appear **only** as `mcp__claude_ai_<Name>__*` tools in the session's available-tools listing, so detect them by scanning that listing for the prefix. `serverName` = the display name with the leading "claude.ai " preserved (reverse-derive from the tool segment: `mcp__claude_ai_Google_Drive__*` → `"claude.ai Google Drive"`).
   Also inventory any other `mcp__<server>__*` tool not produced by an enabled plugin (no `mcp__plugin_*` prefix) — a user-scope or Desktop MCP. If a Desktop name collides with a user-scope MCP of the same `serverName`, one denylist entry kills both — don't duplicate it.
4. The list of available skills is already in the session-start `<system-reminder>` block — extract names from there. Skills with a `plugin:` prefix are governed by their plugin's enable state.
5. Read `./CLAUDE.md` if it exists — project context.
6. Read `./.claude/settings.json` if it exists (merge target — do NOT overwrite blindly). Read `./.claude/settings.local.json` only to know the permission allowlist already exists; leave it alone.

#### 1B. Installed-but-disabled plugins

Get the disabled set from the text listing (it carries scope + status reliably and is small):

```bash
claude plugins list | awk '/❯/{id=$2} /Status:.*disabled/{print id}' | sort -u
```

These are low-friction install candidates — already downloaded, so `claude plugins install <id> --scope project` scopes them in with **no** marketplace fetch. Fetch all their descriptions, categories, install counts, and per-turn token cost in **one** cache query (no per-plugin file reads):

```bash
CAT="$HOME/.claude/plugins/plugin-catalog-cache.json"
jq -r --argjson ids '["feature-dev@claude-plugins-official","mcp-apps@claude-plugins-official"]' '
  .catalog.plugins as $p | $ids[] | . as $id | ($p[$id] // {}) as $e |
  "\($id)\t[\($e.marketplace_entry.category // "?")]\taon=\((($e.tokens // {}) | to_entries[0].value.always_on) // "?")\t\($e.marketplace_entry.description // "NOT IN CATALOG")"
' "$CAT"
```

For any row printing `NOT IN CATALOG` (de-listed plugins — e.g. some third-party security plugins), fall back to reading that single plugin's `plugin.json` manifest on disk. Only the cache-misses need a file read — not all of them.

Do **not** pre-filter Pass B by id keyword-match — plugin ids and theme tokens often use different vocabulary (e.g. theme "improve performance" vs. plugin id `skill-creator`). Read all descriptions and let the model judge.

#### 1C. Available in registered marketplaces (pre-filter, then evaluate)

The cache holds ~200+ entries. **Do NOT emit them all** — that truncates the output AND burns tokens. Tokenize → keyword-match → sort → slice in **one** server-side `jq`, printing only the top 15 survivors:

1. **Tokenize the theme** — split the theme on whitespace, lowercase, drop stopwords (`the`, `and`, `for`, `to`, `of`, `in`, `with`, `a`, `an`, `by`, `on`, `at`, `or`, `is`, `this`, `that`) plus near-empty filler (`all`, `things`, `etc`). Join the survivors into a regex alternation (`skill|agent|plugin|mcp|...`); use word-ish tokens (avoid 2-letter substrings like `ai` that over-match).
2. **Match + sort + slice** in a single query against the cache file:

```bash
CAT="$HOME/.claude/plugins/plugin-catalog-cache.json"
jq -r '
  .catalog.plugins | to_entries
  | map(select(
      (.value.marketplace_entry.name + " " + (.value.marketplace_entry.description // ""))
      | ascii_downcase | test("KEYWORD1|KEYWORD2|KEYWORD3")
    ))
  | sort_by(-(.value.unique_installs // 0))
  | .[:15]
  | .[] | "\(.value.unique_installs // 0)\t[\(.value.marketplace_entry.category // "?")]\t\(.key)\t\(.value.marketplace_entry.description // "")"
' "$CAT"
```

3. `unique_installs` is the popularity/health proxy — abandoned/de-listed plugins sink naturally. (The field is `unique_installs`, **not** `installCount` — the latter is always null and silently sorts everything to 0.)
4. **Exclude already-installed ids** (from `installed_plugins.json` or the Phase 1A list) so Pass C proposes only genuinely new plugins.
5. The model now evaluates this small filtered set, reading only the descriptions of the ~15 survivors.

If the keyword pre-filter produces zero matches, fall back to the **top 10 plugins overall by `unique_installs`** and flag clearly that nothing matched the theme.

(Marketplace freshness is handled in Phase 0 — the cache's `fetchedAt` reflects the last refresh.)

### Phase 2 — Evaluate (three passes)

#### Pass A: trim the active set
For each currently-active plugin/MCP/skill, classify as **keep** or **remove** based on the theme. The removal mechanism depends on the surface:
- **Plugins** → project-scope **uninstall** (`claude plugins uninstall <id> --scope project`).
- **User-level standalone skills** (e.g. `~/.claude/skills/*`) → **disable** via `skillOverrides`.
- **MCP servers** (user-scope, Claude Desktop, claude.ai integrations) → **disable** via `deniedMcpServers`.

Treat Claude Desktop app MCPs (from Phase 1A step 3) as first-class candidates here — they consume tool-listing budget in CC sessions just like user-scope MCPs and deserve theme-based scoping. The presence of dozens of `mcp__claude_ai_Ahrefs__*` / `mcp__claude_ai_HubSpot__*` tools in an unrelated project is the typical motivation for denying them.

#### Pass B: surface installed-but-disabled candidates worth installing
For each installed-but-disabled plugin (full set, not pre-filtered), read its description from the cache (Pass 1B query; `plugin.json` only for cache-misses). Classify as **install** (`claude plugins install <id> --scope project` — already downloaded, no fetch) or **leave out**. Factor in each candidate's `always_on` token cost: a plugin that loads heavy always-on context every turn needs a stronger theme justification than a near-zero-cost one, and one that bundles its own MCP server adds tool-listing budget on install.

#### Pass C: surface marketplace candidates worth proposing
For each of the ~15 filtered marketplace plugins, classify as **propose-install** (`claude plugins install <id> --scope project` — downloads from the marketplace **and** executes plugin code locally) or **skip**. Be conservative — only propose plugins whose value is clear and theme-aligned. Weigh each candidate's `always_on` token cost and any bundled MCP servers (extra tool-listing budget every turn) against its theme value — a high-`always_on` plugin that's only tangentially relevant is a skip.

#### Conflict rule (applies to all passes)

If the user's global `~/.claude/CLAUDE.md` (or `~/.claude/rules/*.md`) declares a resource as authoritative or always-on (e.g. mempalace as cross-session memory, ollama for token-saving, caveman at session start), prefer **keep** and never silently remove.

#### Always keep (never propose removing)

- `superpowers:using-superpowers` — meta-skill that establishes skill discipline.
- `update-config` — needed to re-tune the scope later.
- `project-scope` itself (this skill).
- Anything mandated by global CLAUDE.md.

### Phase 3 — Present the proposal, then ask the user

This phase has two sub-steps. Order matters: print first, then ask.

#### 3A. Print the full proposal as structured text (BEFORE any AskUserQuestion call)

```
Proposed scoping for theme: <theme>

UNINSTALL — plugins, project scope (claude plugins uninstall <id> --scope project):
  Plugins: <list>     # removed from THIS project only; user/global scope untouched

DISABLE — user-level / Desktop tools (denylist & override, save context tokens):
  Skills:  <list>     # skillOverrides → user-invocable-only — still callable via /<name>
  MCPs (CC-native + Desktop): <list>     # deniedMcpServers
  MCPs (claude.ai integrations): <itemize each; e.g. "claude.ai Asana", "claude.ai Gmail", ...>
    # Each gets its own granular toggle in the menu below (up to 4 shown as tickboxes;
    # overflow goes through the Customize text path).

INSTALL — already downloaded, scope into project (claude plugins install <id> --scope project):
  <list of plugins — one-line description + always_on token cost (+ "bundles MCP" flag if any)>

INSTALL — from marketplace, downloads + scopes into project (claude plugins install <id> --scope project):
  <list of plugins — one-line description + unique_installs + always_on token cost (+ "bundles MCP" flag if any)>
  ⚠ Each install executes plugin code locally — explicit consent required.

CONTEXT BUDGET (skillListingBudgetFraction):
  Current: <current value or "default 1%">
  Choose: 1% / 2% / 3% / 5%
  Per-turn context note: sum of always_on across the proposed enabled set ≈ <N> tokens/turn.
```

This way the user sees **everything** the model is proposing before the AskUserQuestion menu loads. Per-item natural-language overrides are supported — the user can reply "looks good but skip X" between this print and the apply phase.

#### 3B. AskUserQuestion call

Construct **one** AskUserQuestion call with up to 4 questions, skipping any whose bucket is empty: Q1 removals (single-select), Qci claude.ai integrations to keep allowed (multiSelect — only if Pass A has a claude.ai MCP), Q2 installs of already-downloaded plugins, Q3 installs from marketplace (only if Pass C non-empty), and Q4 the skill-listing context budget. **Always include Q4**; for it, "Other" lets the user supply a custom value (convert % → fraction, validate >0 ≤1). On "Customize", take the natural-language follow-up next turn; default to "Skip" if none.

The full question/option tables and the Qci multiSelect semantics (default-deny tickboxes, the >4-server overflow handling, and the 5-question budget rule that drops Q2 but **never** Qci or Q4) live in **[references/phase3-menu.md](references/phase3-menu.md)** — read it before constructing the call.

#### Conflict / global-mandate flagging

If a Pass A removal conflicts with a global CLAUDE.md rule (e.g. proposing to uninstall a globally-mandated plugin, or disable mempalace or ollama), do NOT include it in the proposal silently. Either omit it or surface it explicitly with the conflict noted: `mempalace MCP — global CLAUDE.md says authoritative; recommend KEEP`. The user can override but must do so deliberately.

### Phase 4 — Apply

Plugin changes go through the CLI (install/uninstall `--scope project`); the disable-only surfaces (skills, MCPs, budget) are written into `.claude/settings.json`. Run plugin operations FIRST, then merge the settings file — so the CLI's `enabledPlugins` writes are already on disk when you merge.

#### 4A. Apply plugin install / uninstall (project scope)

Run sequentially. Order: uninstalls first, then installs.

1. **Uninstall** each Pass A plugin the user approved for removal (Q1):
   ```bash
   claude plugins uninstall <id> --scope project
   ```
   Removes the plugin from THIS project's scope only; user/global scope is untouched. If the plugin was only user-installed and the command reports nothing to remove, treat it as already-absent and continue — never fall back to a global `uninstall` (that affects every project).

2. **Install** each approved Pass B plugin (Q2 — already downloaded) and Pass C plugin (Q3 — from marketplace):
   ```bash
   claude plugins install <id> --scope project              # Pass B and Pass C
   claude plugins install <id>@<marketplace> --scope project  # Pass C, pin the marketplace if the id is ambiguous
   ```
   Pass C installs download and execute plugin code locally — only run the ones the user explicitly approved (Q3). Each install can prompt for trust; run them one at a time.

If any install or uninstall fails (network, permission, invalid manifest, trust declined), abort the apply phase and report — don't write a half-applied settings.json. Do **not** hand-edit `enabledPlugins`; these commands own it.

#### 4B. Write/merge `.claude/settings.json` (disable-only surfaces + budget)

Read existing `./.claude/settings.json` **after** 4A has run (the CLI may have just rewritten `enabledPlugins`). **Merge**, do not replace:

- `enabledPlugins` — **do not hand-edit.** It is managed by the install/uninstall `--scope project` commands in 4A. Preserve whatever the CLI wrote; never strip or churn its entries.
- `skillOverrides` — set `"user-invocable-only"` for every user-level standalone skill to disable (preserves `/<name>` access). Use `"off"` only if the user explicitly wants the slash command hidden too. (Plugin-provided skills are handled by uninstalling their plugin in 4A — do not list them here.) For a plugin-prefixed skill, key on the bare name as it appears in the system-reminder listing.
- `deniedMcpServers` — array of `{ "serverName": "<name>" }` objects. For claude.ai integrations, the answer to **Qci** decides each entry independently: a server NOT ticked in Qci → add `{ "serverName": "claude.ai <Name>" }`; a server TICKED in Qci → omit (kept allowed). Non-claude.ai MCPs follow Q1's all/customize/skip answer as before. Merge into any pre-existing `deniedMcpServers` array — do not drop entries unrelated to this run.
- `skillListingBudgetFraction` — set to user's Q4 choice (0.01 / 0.02 / 0.03 / 0.05 / custom). Always write this even if the user picked the default — it documents the project's chosen tier.
- Preserve every other top-level key the file already contains (permissions, hooks, env, etc.).

Always include the JSON Schema reference at the top:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  ...
}
```

Use the `Edit` tool to add/merge keys when the file exists, `Write` only for first-time creation; create the `.claude/` directory first if it's absent.

### Phase 5 — Verify

Run in parallel and report results:

1. `jq -e . .claude/settings.json > /dev/null && echo "valid"` — JSON syntax.
2. Confirm each approved plugin is now project-installed (Pass B/C) or gone from project scope (Pass A). Prefer the text form (the `--json` form can truncate on a large installed set): `claude plugins list | awk '/(<plug1>|<plug2>)@/{n=$2} /Status:/{print n, $0}'`, or read `installed_plugins.json`. The grep form `claude plugins list | grep -A3 -E "(<plug1>|<plug2>)@"` is fine for a quick visual check.
3. `claude mcp list` — confirm denied CC-native servers are gone, kept ones remain connected, newly-installed plugins' MCPs (if any) appear. Note: Claude Desktop app MCPs may not appear in this list even when allowed; verify their denial by grepping `deniedMcpServers` in the written settings.json AND by confirming their `mcp__<name>__*` tools are absent from the next session's tool list (requires a restart of CC).
4. Report `skillListingBudgetFraction` value written.
5. State which changes are live now vs. which need a session restart. **Plugin install/uninstall and MCP changes apply to the running session immediately; `skillOverrides` and `skillListingBudgetFraction` changes only show up at the next `claude` start in this directory.**

### Phase 6 — Hand-off

End-of-turn summary (≤3 sentences):

- Counts: N plugins installed / M plugins uninstalled (project scope) / X skills disabled / Y MCPs denied / budget fraction Z%.
- What needs a session restart (skill listing, budget fraction).
- That disabled skills remain manually callable via `/<name>`, and that this only affects the current project.

## Red Flags — STOP

Destructive or silent-failure mistakes. If you are about to do any of these, stop:

- **Hand-editing `enabledPlugins`** in `.claude/settings.json` — the install/uninstall `--scope project` verbs own that key; hand-editing fights the CLI's bookkeeping.
- **Editing global `~/.claude/settings.json`, or `.claude/settings.local.json`** — project scope only; the latter is the permissions allowlist, a separate concern.
- **`claude mcp remove -s user <name>` as a fallback without explicit confirmation** — that is a global removal affecting every project.
- **Installing a Pass C marketplace plugin without explicit per-plugin consent** — installing downloads and executes remote code.
- **Piping the full `claude plugins list --available --json` pool** — it exceeds the ~64 KB output cap, arrives truncated, and corrupts jq; read `plugin-catalog-cache.json` and filter server-side.
- **Claiming success without running Phase 5 verification.**
- **Uninstalling or disabling `superpowers:using-superpowers`, `update-config`, `project-scope`, or anything mandated by global CLAUDE.md.**
