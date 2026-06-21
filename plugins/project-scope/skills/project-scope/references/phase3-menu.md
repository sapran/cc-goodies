# Phase 3B — AskUserQuestion menu (full spec)

Construct **one** AskUserQuestion call with up to 4 questions. Skip any question whose bucket is empty.

| # | Question | Type | Options (max 4 each) |
|---|---|---|---|
| Q1 | "Apply the proposed removals?" *(plugin uninstalls + skill/non-claude.ai-MCP disables — claude.ai handled in Qci below)* | single-select | "Apply all", "Customize (specify in next reply)", "Skip — remove nothing" |
| Qci | "Which claude.ai integrations to KEEP allowed?" *(only if Pass A contains ≥1 claude.ai MCP)* | **multiSelect** | one option per proposed-for-denial claude.ai server, label "Keep `<serverName>` allowed" (max 4 servers shown as tickboxes) |
| Q2 | "Apply the proposed INSTALLS (already-downloaded plugins)?" | single-select | "Install all", "Customize", "Skip — install nothing" |
| Q3 | "Apply the proposed INSTALLS (from marketplace — downloads + executes code)?" (only if Pass C non-empty) | single-select | "Install all (downloads code)", "Customize", "Skip — install nothing" |
| Q4 | "Skill listing context budget for this project?" | single-select | "1% — leanest (default)", "2% — balanced", "3% — generous", "5% — maximum" |

**Always include Q4** even if all other buckets are empty.

For Q4, "Other" is auto-provided by AskUserQuestion — the user can supply a custom value like 4% via free text. Convert to fraction (1% → 0.01, 5% → 0.05). Validate against the schema range (>0, ≤1).

If a user picks "Customize" for any bucket, accept their natural-language follow-up in the next turn (e.g. "skip optimize-image and fade-audio from disable list, keep the rest"). Apply selectively. If they don't follow up, re-prompt once, then default to "Skip" for that bucket.

## Qci semantics (claude.ai multiSelect)

Give claude.ai servers individual tickboxes (not one bundled yes/no) whenever the Qci slot is available — users keep heterogeneous subsets (deny Ahrefs, keep Gmail). Only bundle when the 5-question overflow rule below forces it.

- Default-deny semantics: **unticked = denied**, **ticked = kept allowed**. Default checked state should be `false` for every option (model proposes denial; user opts back in).
- Skip Qci entirely if Pass A contains no `mcp__claude_ai_*` servers.
- If Pass A proposes ≤4 claude.ai servers for denial, list them all as options.
- If Pass A proposes >4 claude.ai servers for denial: list the **top 4 most theme-ambiguous** (i.e. the ones the user is most likely to want to override) as tickboxes; bundle the rest into Q1's Customize fallback and explicitly note in Phase 3A: *"<N> additional claude.ai servers (<list>) bundled into Q1 (removals) Customize — name them in your reply if you want to keep any."*
- If Q1, Q2, Q3, Q4, and Qci would all fire (5 questions, over budget): drop Q2 from the menu and surface Pass B candidates in Phase 3A only — apply them with implicit "Apply all" unless the user objects in their next reply. Rationale: installing already-downloaded plugins at project scope is the lowest-friction, lowest-risk class of change (no marketplace fetch, no remote code execution). **Never** drop Qci to make room — that defeats the granularity feature. **Never** drop Q4 — budget fraction must always be confirmed.
