# project-scope

Scope a project to a **theme**. Given a stated focus ("security review", "Claude Code
performance", "writing docs"), it inventories the Claude Code resources you have, judges each
one's relevance, and — with your explicit per-bucket consent — trims the project down to what's
relevant: uninstalls off-theme plugins from **project scope**, disables user-level skills and
MCP servers for the project, installs theme-relevant plugins (already-downloaded or from a
marketplace), and sets the project's skill-listing context budget.

The payoff is a **leaner per-turn context** and a tool surface matched to the work — without
touching your global setup. Everything is **project scope only**; your other projects keep
their full surface area.

## How to invoke

Two entry points, same workflow:

- **Type `/project-scope <theme>`** — the command, invoked by name. e.g.
  `/project-scope analyze and improve Claude Code performance`.
- **Just say it** — the bundled skill **auto-activates** when you ask to scope or trim a
  project's tools ("scope this project to security work", "trim my plugins for this theme",
  "reduce per-turn token cost here"). Skills are model-invoked, so you don't have to remember
  the command.

If you don't give a theme, it asks for one before doing anything.

## What it does

It works across **three friction tiers** and picks the right mechanism for each surface:

| Tier | Surface | Action |
|------|---------|--------|
| Currently active | plugins | uninstall off-theme ones at **project scope** (`claude plugins uninstall <id> --scope project`) |
| | user-level skills, MCP servers (incl. Claude Desktop / claude.ai) | **disable** for the project via `.claude/settings.json` (`skillOverrides`, `deniedMcpServers`) |
| Installed-but-disabled | plugins (already downloaded) | **install** relevant ones at project scope — no marketplace fetch |
| Marketplace-available | plugins | **propose** relevant ones (downloads + runs code → explicit consent) |

Plus the project's **`skillListingBudgetFraction`** — how much context the skill listing may use.

Safety is structural: it **prints the full proposal first**, then asks **per-bucket** via the
question menu, and only applies what you approve. Marketplace installs (which execute code)
always need explicit per-bucket consent. It never edits global `~/.claude/settings.json` and
never hand-edits `enabledPlugins` (the CLI owns that key). Output is terse; the proposal and
every consent prompt are spelled out in full.

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install project-scope@cc-goodies
```

The `/project-scope` command and the auto-activating skill are available on install (restart
or `/hooks` / `/reload-plugins` to load them the first time).

## Uninstall

```text
/plugin uninstall project-scope@cc-goodies
```

This plugin writes **nothing outside its own directory** on install — no `settings.json` edits,
no config files — so there is no dedicated `/…-uninstall` to run; `/plugin uninstall` removes it
completely (same as `voice-notify` and `session-finalise`).

> The settings it writes when you **run** it live in each scoped project's own
> `.claude/settings.json` — per-project only, never the global `~/.claude/settings.json` — and are
> deliberate, re-tunable choices — re-run `/project-scope` with
> a new theme, or hand off to `update-config`, to change them. They are not part of this
> plugin's install footprint, so uninstalling the plugin leaves already-scoped projects exactly
> as you set them.

## Requirements

- **`claude` CLI** — the plugin install/uninstall steps shell out to `claude plugins …`.
- **`jq`** — reads the plugin catalog cache and merges `.claude/settings.json`.
- Cross-platform; the Claude Desktop MCP inventory step is macOS-specific and **skips silently**
  elsewhere.

## License

MIT © Volodymyr Styran
