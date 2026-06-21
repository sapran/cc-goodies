---
name: gpt-search
version: 0.1.0
description: Deep web search via ChatGPT/Codex with smart caching. Use for /gpt-search, web research, or finding recent information.
---

# ChatGPT Web Search

Deep web research using OpenAI Codex MCP with intelligent caching.

## Usage

```
/gpt-search <query>
```

## Prerequisite: the Codex MCP

This skill drives the **Codex MCP** (`mcp__codex__codex` and `mcp__codex__codex-reply`). The
plugin ships **no** `.mcp.json` — you supply your own Codex MCP server.

**If `mcp__codex__codex` is unavailable**, do not hard-fail or attempt a workaround. Tell the
user that the Codex MCP is required and how to add it (their `codex` plugin / MCP server
provides it), then stop. A cached result may still be returned from Step 1, but a fresh
search cannot run without the Codex MCP.

## Process

### Step 1: Check Cache

1. Glob `.claude/cache/search/*.md`
2. For each file, read first 10 lines and parse YAML frontmatter:
   ```yaml
   ---
   query: "original search query"
   date: 2026-01-18
   keywords: ["oscp", "exam", "format"]
   ---
   ```
3. Extract keywords from new query (lowercase, split by spaces)
4. Compare with cached keywords:
   ```
   relevance = shared_keywords / max(query_keywords, cached_keywords)
   ```
5. If relevance > 50%, ask user with AskUserQuestion:
   - **Use cache** — return cached result immediately
   - **Re-search** — delete cached file, perform new search
   - **Not relevant** — treat as new query

### Step 2: Call Codex MCP

If no relevant cache or user chose re-search:

```json
{
  "prompt": "Research: $ARGUMENTS\n\nRequirements:\n- Find 3+ authoritative sources\n- Include publication dates\n- Provide source URLs\n- Note any conflicting information",
  "approval-policy": "on-failure",
  "sandbox": "read-only"
}
```

### Step 3: Format & Cache

1. Format response:
   - **Summary** — 2-3 sentences
   - **Key Facts** — bullet points
   - **Sources** — markdown links with dates

2. Create file with YAML frontmatter:
   ```markdown
   ---
   query: "<original query>"
   date: YYYY-MM-DD
   keywords: ["word1", "word2", ...]
   ---

   # <Topic>

   ## Summary
   ...
   ```

3. Save to `.claude/cache/search/YYYY-MM-DD_<topic>.md`

### Step 4: Return Result

Return summary to user with path to cached file.

## Cache Structure

```
.claude/cache/search/
├── 2026-01-18_oscp-exam.md       # With YAML frontmatter
└── 2026-01-15_react-19-ssr.md    # Each file self-contained
```

No index.json needed — metadata is in each file's frontmatter.

The cache is created **on use**, project-local under `.claude/cache/search/`. It is not
created on install and is not removed on uninstall. To clear it, delete the directory:

```bash
rm -rf .claude/cache/search/
```

That is an optional, user-driven cleanup — the cache is self-contained and safe to remove
at any time; the next search simply rebuilds what it needs.

## Follow-up Research

Use `mcp__codex__codex-reply` for deeper investigation:
```json
{
  "conversationId": "<id from initial search>",
  "prompt": "Expand on <specific aspect>"
}
```

## Best Practices

- Specific queries: "OSCP exam format 2026" > "OSCP"
- Add context: "React 19 SSR features" > "React features"
- Comparisons: "Next.js vs Remix performance 2026"
