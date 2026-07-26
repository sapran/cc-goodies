---
name: project-scope
version: 0.3.1
description: >-
  This skill should be used when the user wants to scope or trim THIS project's plugins, MCP
  servers, and skills to only those relevant for a stated theme — "scope this project to
  security work", "trim my plugins for this theme", "reduce per-turn token cost here", "which
  tools should this project have?".
---

# Project Scope

Investigate the Claude Code resources available to **this project** — active,
installed-but-disabled, and available-in-marketplace — judge each one's relevance to a stated
theme, and apply only what the user explicitly approves: plugin install/uninstall at project
scope, skill/MCP disable via `.claude/settings.json`, and the project's skill-listing context
budget.

**Theme & starting point.** Invoked via `/project-scope <theme>`, the theme is the command
argument; auto-activated from a natural request, it's whatever the user asked to scope for. If
the theme's meaning or the user's starting point (what's already in place, add vs. remove) is
ambiguous, ask one direct question at a time before inventory — a theme and starting point
that are already clear skip straight to Phase 1.

**Mechanics** (commands, `.claude/settings.json` keys, the catalog-cache data source, the
Phase 1 subagent contract): **[references/mechanism.md](references/mechanism.md)** — read it
before Phase 1 or Phase 4.

## Workflow

### Phase 0 — Refresh

`claude plugins marketplace update` before inventorying anything. If a specific marketplace
fails (network, auth, gone), continue with the others and surface which slice is stale in
Phase 3 — don't abort; partial freshness beats none.

### Phase 1 — Inventory

Dispatch a subagent per mechanism.md's Phase 1 section (pass it that file's path, the theme,
and the refreshed catalog-cache path). It returns one row per active/installed-disabled/
marketplace candidate — no raw CLI dump, `--json` stream, or unfiltered catalog rows reach you.
Read `./CLAUDE.md` and `./.claude/settings.json` yourself — Phase 2 and Phase 4 need them
directly.

### Phase 2 — Evaluate

Classify each returned candidate: keep/remove (active), install/skip (installed-disabled),
propose/skip (marketplace) — sized to the theme's actual relevance, not a fixed count. Weigh
`always_on` token cost per mechanism.md's disclosure convention; never present a family-match or
unavailable figure as this session's own exact cost. Anything mandated by global
`~/.claude/CLAUDE.md` or `~/.claude/rules/*.md` is kept, never silently removed — flag it
instead. Never propose removing `superpowers:using-superpowers`, `update-config`, or
`project-scope` itself.

### Phase 3 — Present, then ask

Print the full proposal before asking anything, then one `AskUserQuestion` call covering only
the non-empty buckets. The print template and question/option tables are canonical in
**[references/phase3-menu.md](references/phase3-menu.md)** — decide what to ask now versus
confirm implicitly by each bucket's risk and reversibility, not a fixed drop order.

### Phase 4 — Apply

Plugin ops first — uninstalls, then installs; abort and report on failure rather than
half-applying. Then merge `.claude/settings.json` (never replace, never hand-edit
`enabledPlugins`) using mechanism.md's keys and commands.

### Phase 5 — Verify

- [ ] `.claude/settings.json` is valid JSON.
- [ ] Each approved plugin's project-scope state matches the proposal (installed/uninstalled).
- [ ] `deniedMcpServers` / `skillOverrides` reflect the approved buckets; live MCP connections
      match.
- [ ] `skillListingBudgetFraction` matches what the user chose.
- [ ] Report any mismatch, and which changes need a session restart vs. are already live.

### Phase 6 — Hand off

End with a ≤3-sentence summary: counts per bucket, what needs a restart, and that disabled
skills stay callable via `/<name>`.

## Invariant

Every plugin install, plugin uninstall, and `.claude/settings.json` write is confirmed by the
user before it's applied — project scope only (`--scope project`, `./.claude/settings.json`),
never global. On any edge case not covered above, pick the conservative option: fewer removals,
fewer installs, ask rather than assume.
