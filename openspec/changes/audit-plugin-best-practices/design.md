## Context

`cc-goodies` is a marketplace of seven independently-installable plugins, authored
incrementally. The repo already documents its own conventions (root `CLAUDE.md`,
`docs/shell-safety.md`) and ships a test harness per guard, but it has never been measured
against an external plugin-development standard. Two authoritative references are available
locally: the `plugin-dev` skill set and the `plugin-validator` agent
(`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/plugin-dev/`), plus
Anthropic's published plugin/marketplace docs online. This change builds the rubric from
those sources and applies it, producing a report — it changes no plugin.

## Goals / Non-Goals

**Goals:**
- A conformance rubric, cross-checked between `plugin-dev` (primary) and official docs
  (validation), with each item sourced and conflicts resolved explicitly.
- A complete, evidence-backed assessment of all seven plugins + `marketplace.json`.
- A single durable, triaged gap report that seeds prioritized follow-up changes.

**Non-Goals:**
- Modifying any plugin manifest, script, command, skill, README, or `marketplace.json`
  to close gaps. (Deferred to follow-up changes.)
- Re-deriving best practices from first principles — the rubric is sourced, not invented.
- Auditing plugins outside this marketplace.

## Decisions

### D1 — Rubric source precedence: `plugin-dev` primary, official docs validating
The bundled `plugin-dev` skills + `plugin-validator` agent are the primary rubric source
because they are the executable, version-matched standard the local toolchain enforces.
Official docs are the validation layer: they catch items the skills omit and flag where
the skills lag the published schema. Each rubric item cites its source; conflicts get a
recorded resolution + rationale (per spec). *Alternative considered:* docs-only — rejected
because the docs are prose and the `plugin-validator` encodes checks the prose doesn't.

### D2 — Read the `marketplaces/` copy, not the `cache/` copy, and pin versions
Two on-disk copies of `plugin-dev` exist (`plugins/marketplaces/.../plugin-dev` and
`plugins/cache/.../plugin-dev/unknown`). The audit reads the `marketplaces/` copy (the
managed source) and records the `plugin-dev` version it read, so the rubric is reproducible.
*Alternative considered:* invoking each skill via the Skill tool — rejected for the rubric
build because we need the verbatim rule text as a citation, not the activated behavior.

### D3 — Report lives at `docs/plugin-audit.md`, not in the change dir
The report is a durable backlog that must outlive this change (the change gets archived;
the gaps persist until fixed). It sits beside `docs/shell-safety.md`, discoverable from the
repo root. *Alternative considered:* keeping it inside
`openspec/changes/audit-plugin-best-practices/` — rejected because archiving the change
would bury the backlog.

### D4 — Verdict + severity vocabulary
Each (plugin, item) pair is `pass` | `gap` | `n/a`. Each `gap` carries a severity:
`blocker` (validation fails / install-uninstall asymmetry / breaks documented contract),
`major` (missing required manifest field, undocumented durable state), `minor` (convention
drift, doc omission), `nit` (cosmetic). `n/a` carries a one-line reason. Every non-`pass`
verdict carries file:line evidence — no unsupported assertions.

### D5 — Audit method: rubric build → per-plugin assessment → machine validation → triage
Build the rubric once. Assess each plugin against it (per-plugin assessment is independent
and parallelizable across read-only subagents). Run `claude plugins validate <plugin>` per
plugin and fold the result in as evidence. Synthesize into the matrix + per-plugin narrative
+ cross-cutting findings + triage. The marketplace manifest + root `README.md` are audited
as a "marketplace" pseudo-target.

### D6 — Report structure
(1) Rubric table (item · dimension · source · conflict-note). (2) Coverage matrix
(plugins × items → pass/gap/n-a). (3) Per-plugin narrative with evidence for each gap.
(4) Cross-cutting findings. (5) Triage: gaps grouped by severity, each cluster naming a
proposed follow-up change.

## Risks / Trade-offs

- **Installed `plugin-dev` lags or leads the official docs** → D1/D2 make divergence a
  first-class, recorded rubric output rather than a silent pick.
- **Official-docs fetch fails (offline / URL drift)** → degrade gracefully: mark affected
  items "validated against plugin-dev only" and note the gap; do not block the audit.
- **Verdict subjectivity** → every non-`pass` requires file:line evidence (D4); the spec
  makes "evidenced + severity-rated" a testable requirement.
- **Scope creep into fixing** → spec forbids mutating any `plugins/` file or
  `marketplace.json`; completion check asserts an empty `git diff` under `plugins/`.
- **Stale rubric over time** → the report records the `plugin-dev` version + audit date so a
  later re-audit knows what it's comparing against.

## Resolved Questions

- **Root `CLAUDE.md` "Install ⇄ uninstall symmetry" is a rubric *source*** (resolved): it is
  a local house rule layered on the standard, so its requirements (symmetric install/uninstall
  verbs, ownership-guarded reverts for durable external state, backup-before-edit) become rubric
  items in the `install⇄uninstall symmetry` dimension, cited as `CLAUDE.md` rather than treated
  as an audited artifact.
- **Follow-up "fix" changes are list-only** (resolved): the triage section names proposed
  follow-up changes but does not scaffold them as stub OpenSpec changes — this change stays a
  pure measurement.
