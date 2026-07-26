# Phase 3 — present, then ask (full spec)

## 3A. Proposal print template

Print this before any `AskUserQuestion` call — the user must see the whole proposal before the
menu loads. Per-item natural-language overrides are supported between print and apply (e.g.
"looks good but skip X").

```
Proposed scoping for theme: <theme>

UNINSTALL — plugins, project scope (claude plugins uninstall <id> --scope project):
  Plugins: <list>     # removed from THIS project only; user/global scope untouched

DISABLE — user-level / Desktop tools (denylist & override, save context tokens):
  Skills:  <list>     # skillOverrides → user-invocable-only — still callable via /<name>
  MCPs (CC-native + Desktop): <list>     # deniedMcpServers
  MCPs (claude.ai integrations): <itemize each; e.g. "claude.ai Asana", "claude.ai Gmail", ...>
    # Each gets its own granular toggle in Qci below (up to 4 shown as tickboxes;
    # overflow goes through the Customize text path).

INSTALL — already downloaded, scope into project (claude plugins install <id> --scope project):
  <list of plugins — one-line description + always_on token cost, disclosed per mechanism.md's
   three-step resolution (bare number = exact match; "via <key>, not <model>" = family match;
   "unavailable" = no match, excluded from the budget sum below) (+ "bundles MCP" flag if any)>

INSTALL — from marketplace, downloads + scopes into project (claude plugins install <id> --scope project):
  <list of plugins — one-line description + unique_installs + always_on token cost, same
   disclosure convention as above (+ "bundles MCP" flag if any)>
  ⚠ Each install executes plugin code locally — explicit consent required.

CONTEXT BUDGET (skillListingBudgetFraction):
  Current: <current value or "default 1%">
  Proposed: <value> — state the trade-off (lower = leaner per-turn cost; higher = fuller skill
    descriptions and better matching) and why this value fits the theme. The user can override
    with any fraction >0, ≤1.
  Per-turn context note: sum of always_on (exact + family-match figures only) across the proposed
    enabled set ≈ <N> tokens/turn. Name any plugin excluded as unavailable/unmeasured — never
    count it as zero. If the sum includes any family-match figures, say so explicitly (e.g. "≈ N
    tokens/turn, includes M plugins' figures from a different model generation") — it is not a
    precise measurement of this session's own cost when it does.
```

## 3B. AskUserQuestion call

Construct **one** call with up to 4 questions, skipping any whose bucket is empty:

| # | Question | Type | Options (max 4 each) |
|---|---|---|---|
| Q1 | "Apply the proposed removals?" *(plugin uninstalls + skill/non-claude.ai-MCP disables — claude.ai handled in Qci below)* | single-select | "Apply all", "Customize (specify in next reply)", "Skip — remove nothing" |
| Qci | "Which claude.ai integrations to KEEP allowed?" *(only if Pass A contains ≥1 claude.ai MCP)* | **multiSelect** | one option per proposed-for-denial claude.ai server, label "Keep `<serverName>` allowed" (max 4 servers shown as tickboxes) |
| Q2 | "Apply the proposed INSTALLS (already-downloaded plugins)?" | single-select | "Install all", "Customize", "Skip — install nothing" |
| Q3 | "Apply the proposed INSTALLS (from marketplace — downloads + executes code)?" (only if Pass C non-empty) | single-select | "Install all (downloads code)", "Customize", "Skip — install nothing" |
| Q4 | "Skill listing context budget for this project?" | single-select | the proposed value (from 3A) plus 2–3 neighboring options sized to the theme (e.g. leaner / as-proposed / fuller) |

**Always include Q4.** "Other" is auto-provided by `AskUserQuestion` for free-text entry (e.g. a
precise percentage) — convert to a fraction and validate against the schema range (>0, ≤1).

If the user picks "Customize" for any bucket, accept their natural-language follow-up in the
next turn (e.g. "skip optimize-image and fade-audio from disable list, keep the rest") and apply
selectively. If they don't follow up, re-prompt once, then default to "Skip" for that bucket.

## Qci semantics (claude.ai multiSelect)

Give claude.ai servers individual tickboxes (not one bundled yes/no) whenever the Qci slot is
available — users keep heterogeneous subsets (deny Ahrefs, keep Gmail).

- Default-deny semantics: **unticked = denied**, **ticked = kept allowed**. Default checked
  state should be `false` for every option (model proposes denial; user opts back in).
- Skip Qci entirely if Pass A contains no `mcp__claude_ai_*` servers.
- If Pass A proposes ≤4 claude.ai servers for denial, list them all as options.
- If Pass A proposes >4: list the **top 4 most theme-ambiguous** (the ones the user is most
  likely to want to override) as tickboxes; bundle the rest into Q1's Customize fallback and
  say so explicitly in the 3A print: *"<N> additional claude.ai servers (<list>) bundled into
  Q1 (removals) Customize — name them in your reply if you want to keep any."*

## Menu overflow (Q1 + Qci + Q2 + Q3 + Q4 all fire)

Five questions in one call is over budget. Decide what to ask now versus fold into 3A's
print with an implicit-apply note, based on each bucket's own risk and reversibility for
*this* run — not a fixed drop order. Installing already-downloaded plugins (Q2) is usually the
lowest-friction, lowest-risk class (no marketplace fetch, no remote code execution), so it's
often the first reasonable candidate to fold into 3A as "applying all unless you object in your
next reply" — but check the actual run: if this time Q2 bundles a plugin with real `always_on`
cost or a bundled MCP, keep it as a question instead. **Never** fold Qci — that discards
per-server granularity users rely on. **Never** fold Q4 — the consent invariant requires the
budget fraction to always be confirmed, not implicitly applied.
