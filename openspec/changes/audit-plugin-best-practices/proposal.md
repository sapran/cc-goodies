## Why

The `cc-goodies` marketplace has grown to seven plugins authored incrementally over
time, and no one has yet measured them against a canonical plugin-development standard.
Structural, manifest, and documentation drift accumulates silently when there is no
rubric to check against. Before committing to any "fix" work, we need a grounded,
repeatable measurement — a rubric derived from authoritative sources and a per-plugin
gap report that says exactly where each plugin stands and why.

## What Changes

- **Derive a conformance rubric** from two cross-checked sources: the bundled
  `plugin-dev` skill set as the primary authority (plugin-structure, hook-development,
  command-development, agent-development, skill-development, mcp-integration,
  plugin-settings) and the `plugin-validator` agent's checks, validated against
  Anthropic's published plugin & marketplace documentation. Where the two diverge or one
  is silent, the rubric records which source won and why.
- **Audit all seven plugins** — `voice-notify`, `statusline`, `git-guard`,
  `shell-guard`, `rtk-hook`, `session-finalise`, `project-scope` — plus the
  top-level `marketplace.json`, against every rubric item.
- **Produce a per-plugin gap report**: for each plugin, every rubric item gets a verdict
  (pass / gap / not-applicable), file:line evidence, and a severity. Cross-cutting
  findings (e.g. patterns shared across plugins) are called out separately.
- **Triage gaps into prioritized follow-up work** so the report directly seeds future
  alignment changes.
- **Explicitly deferred (non-goals):** no plugin code, manifest, script, or documentation
  is modified to close gaps in this change. This change *measures*; later changes *fix*.

## Capabilities

### New Capabilities

- `plugin-best-practice-audit`: the rubric (its sources, dimensions, and conflict-resolution
  rule), the per-plugin conformance assessment, and the triaged gap report that the audit
  produces. Defines what a complete, evidence-backed audit of this marketplace requires.

### Modified Capabilities

<!-- None. openspec/specs/ is empty; this is the first spec in the repo and changes no existing requirements. -->

## Impact

- **Artifacts only.** Adds OpenSpec artifacts under
  `openspec/changes/audit-plugin-best-practices/` and a durable gap-report document in the
  repo. No plugin code, manifest, script, README, or `marketplace.json` entry is touched.
- **Inputs / dependencies.** Reads the locally installed `plugin-dev` skills and
  `plugin-validator` agent; fetches Anthropic's official plugin/marketplace docs for
  cross-checking; runs `claude plugins validate` against each plugin. No new dependencies.
- **Downstream.** The triaged report becomes the backlog for one or more follow-up
  "align plugin X" changes — none of which are in scope here.
