---
description: Scope this project's plugins, MCP servers and skills to a stated theme — alias for the project-scope skill. Proposes per-bucket install/uninstall (project scope) plus settings.json disables, confirming every change before it applies.
argument-hint: [theme — e.g. "analyze and improve Claude Code performance"]
---

# /project-scope

Use the **project-scope** skill to scope this project's plugins, MCP servers and skills to a stated theme. Follow that skill's phased workflow exactly, including its consent gates: print the full proposal first, then ask per-bucket via AskUserQuestion; never install/uninstall a plugin or edit `.claude/settings.json` without approval; project scope only — never touch global `~/.claude/settings.json`.

The user's stated theme for this run (may be empty): **$ARGUMENTS**

If it's empty, the skill asks once for a theme before proceeding.
