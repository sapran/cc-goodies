# gpt-search

Deep web research from a Claude Code session, backed by the **Codex MCP**, with a project-local
cache so you don't pay for the same search twice. It's a thin wrapper around your Codex MCP: it
checks a per-project cache first, runs the research only on a miss, then formats and stores the
result for reuse.

## How to invoke

Two entry points, same skill:

- **Type `/gpt-search <query>`** — the command, invoked by name. e.g.
  `/gpt-search OSCP exam format 2026`.
- **Just say it** — the bundled skill **auto-activates** for web research, finding recent
  information, or anything that reads like a search. Skills are model-invoked, so you don't have
  to remember the command.

## What it does

1. **Check the cache.** Globs `.claude/cache/search/*.md`, parses each file's YAML frontmatter
   (`query`, `date`, `keywords`), and scores keyword overlap against your query. On a relevant
   hit (>50%) it asks — via `AskUserQuestion` — whether to **reuse** the cached result,
   **re-search** (delete and refetch), or treat it as a **new query**.
2. **Research on a miss.** Calls the Codex MCP (`mcp__codex__codex`) read-only, asking for 3+
   authoritative sources with publication dates and source URLs.
3. **Format & cache.** Writes a self-contained Markdown file to
   `.claude/cache/search/YYYY-MM-DD_<topic>.md` with YAML frontmatter, and returns the summary
   plus the cache path. Use `mcp__codex__codex-reply` to go deeper on the same conversation.

## Prerequisite: the Codex MCP

This plugin depends on the **Codex MCP** server at runtime — the
`mcp__codex__codex` and `mcp__codex__codex-reply` tools. It ships **no `.mcp.json`**: you bring
your own Codex MCP (it's provided by the `codex` plugin / MCP server). This keeps the plugin
portable and avoids duplicating or conflicting with a Codex MCP you already run.

If the Codex MCP is absent, the skill **degrades gracefully** — it tells you the Codex MCP is
required and how to add it, rather than hard-failing the session. A cached result may still be
returned, but a fresh search needs the Codex MCP.

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install gpt-search@cc-goodies
```

The command and the auto-activating skill are available on install (restart or `/hooks`/
`/reload-plugins` to load them the first time). Make sure your Codex MCP is configured — see
**Prerequisite** above.

## Uninstall

```text
/plugin uninstall gpt-search@cc-goodies
```

This plugin ships **no hook** and writes **nothing outside its own directory** at install time —
no `settings.json` edits, no config files, no durable external state — so there is no dedicated
`/…-uninstall` to run. `/plugin uninstall` removes it completely (same as `session-finalise`).

The only thing it ever writes is the project-local cache, created **on use**, not on install.
Clearing it is an **optional, user-driven** step:

```bash
rm -rf .claude/cache/search/
```

The cache is self-contained and safe to remove at any time; the next search rebuilds what it
needs.

## Requirements

- **The Codex MCP** (`mcp__codex__codex` / `mcp__codex__codex-reply`) — a runtime prerequisite,
  not bundled. The skill degrades gracefully when it's missing.
- Cross-platform — no macOS-only tooling.

## License

MIT © Volodymyr Styran
