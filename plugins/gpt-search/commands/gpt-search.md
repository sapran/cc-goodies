---
description: Deep web research via the Codex MCP with project-local cache reuse — alias for the gpt-search skill.
argument-hint: [query — e.g. "OSCP exam format 2026"]
---

# /gpt-search

Use the **gpt-search** skill to run deep web research through the Codex MCP. Follow that skill's process exactly: check the project-local cache first (offer reuse / re-search / new-query on a relevant hit), call the Codex MCP on a miss, then format and cache the result. If the Codex MCP (`mcp__codex__codex`) is unavailable, tell the user it is required and how to add it — do not hard-fail.

The user's search query for this run (may be empty): **$ARGUMENTS**

If it's empty, ask once for a query before proceeding.
