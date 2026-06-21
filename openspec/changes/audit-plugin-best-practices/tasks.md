## 1. Build the rubric (sources cross-checked)

- [x] 1.1 Read the `marketplaces/` copy of the `plugin-dev` skills (plugin-structure,
      hook-development, command-development, agent-development, skill-development,
      mcp-integration, plugin-settings) and the `plugin-validator` agent; record the
      `plugin-dev` version and audit date.
- [x] 1.2 Fetch Anthropic's official plugin & marketplace documentation; if the fetch
      fails, mark affected items "validated against plugin-dev only" and continue.
      (Docs retrieved 2026-06-21, Claude Code v2.1.x — validation layer live, not degraded.)
- [x] 1.3 Assemble the rubric table: each item with its dimension (marketplace, manifest,
      hooks, commands, skills, agents, MCP, docs/README, install⇄uninstall symmetry,
      naming/structure, validation), its source citation, and — where sources diverge or
      one is silent — the recorded resolution + rationale. (86 items, 12 dimensions;
      conflict notes on MAN-1, HOOK-1, HOOK-10, SET-1.)
- [x] 1.4 Confirm rubric coverage: every component type used by any plugin has ≥1 item.

## 2. Assess each target against the rubric

- [x] 2.1 Audit the `marketplace` pseudo-target (`marketplace.json` + root `README.md`):
      verdict per applicable item, file:line evidence for every non-pass, severity per gap.
- [x] 2.2 Audit `voice-notify` against every applicable item (verdict + evidence + severity).
- [x] 2.3 Audit `statusline`.
- [x] 2.4 Audit `git-guard`.
- [x] 2.5 Audit `shell-guard`.
- [x] 2.6 Audit `rtk-hook`.
- [x] 2.7 Audit `session-finalise`.
- [x] 2.8 Audit `project-scope`.
- [x] 2.9 Run `claude plugins validate <plugin>` for each of the seven plugins and capture
      pass/fail output as evidence alongside the manual verdicts.

## 3. Synthesize the gap report

- [x] 3.1 Build the coverage matrix (targets × rubric items → pass/gap/n-a); confirm every
      applicable pair has a verdict and every n/a has a reason.
- [x] 3.2 Write the per-target narrative: each gap with file:line evidence and severity.
- [x] 3.3 Capture cross-cutting findings (patterns shared across multiple plugins).
- [x] 3.4 Triage: group gaps by severity and name a proposed follow-up change for each
      cluster (list-only — do not scaffold the follow-up changes).
- [x] 3.5 Write the full report to `docs/plugin-audit.md` (rubric table → matrix →
      narratives → cross-cutting → triage), stamped with `plugin-dev` version + audit date.

## 4. Verify completion

- [x] 4.1 Assert no plugin files were mutated: `git diff --stat -- plugins/` is empty and no
      `marketplace.json` entry changed.
- [x] 4.2 Cross-check the report against every spec requirement (sourced items, full
      coverage, evidenced gaps, validator output captured, triage present, no mutation).
