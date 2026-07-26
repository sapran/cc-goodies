# Durable memory — reconciliation

The harness saves memories automatically now; this phase reconciles rather than authors from a
schema. Read the project's `MEMORY.md`, then judge two things:

- **What this session established that no file records** — decisions, gotchas, non-obvious
  config, user preferences worth persisting across sessions. Propose saving it.
- **What recorded memory is now stale** given what's observed on disk this session. Flag it and
  propose an update — don't leave reconciliation implicit.

**Fallback for authoring a new file:** read an existing file elsewhere in the project's memory
store first and copy its exact frontmatter shape — don't assume a schema. If the store has no
existing file anywhere to copy from, use the harness's own standard memory frontmatter (it
already knows the shape) rather than fabricating an undocumented format or refusing to save the
fact.

**Skip** anything already authoritative in code or git history — don't restate the repo.
