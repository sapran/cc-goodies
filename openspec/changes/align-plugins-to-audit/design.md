## Context

The audit deferred all fixes to follow-up changes. This is that change. The 15 findings map
to specific files; some files attract two findings (the statusline commands → CMD-6 + CMD-2;
`session-finalise.md` → CMD-2), and three findings resolve in the shared `CLAUDE.md`. A naïve
per-finding branch split would therefore conflict on shared files.

## Goals / Non-Goals

**Goals:**
- Close every confirmed finding (mechanical + judgment + documented-exception) in one
  coherent change, implemented as parallel per-plugin branches merged to `develop`.
- Encode the resolutions as ongoing `plugin-conformance` requirements.

**Non-Goals:**
- Re-auditing or changing the rubric. No new plugin capabilities. No push to a remote.

## Decisions

### D1 — Slice by plugin, not by finding (conflict-free)
Each branch `align/<plugin>` owns exactly one plugin's files; file sets are disjoint, so the
seven branches merge into `develop` without conflict. *Alternative:* per-finding branches —
rejected because CMD-6/CMD-2 share the statusline command files and would collide.

### D2 — Shared-file edits stay central on `develop`
`CLAUDE.md` (the three documented exceptions) and the `openspec/` artifacts are edited only
in the main session on `develop`, never inside a plugin branch — the one shared mutable file
is touched in exactly one place. *Alternative:* assign `CLAUDE.md` to one plugin branch —
rejected as arbitrary and conflict-prone if revisited.

### D3 — Worktree-isolated parallel implementation
Seven named worktrees (`align/<plugin>` branches off `develop`) are created up front
(sequentially, to avoid concurrent `.git/worktrees` races), then one subagent per worktree
implements its slice, runs `claude plugins validate`, and commits on its branch. The main
session reviews each branch and merges with `--no-ff`. *Alternative:* opaque
workflow-managed worktrees — rejected because this change needs named branches to merge back.

### D4 — Judgment items follow the audit's recommendation
CMD-3 and the nits (VAL-6, CMD-12) are resolved as *documented conventions* rather than code
changes, per the audit's reasoning (e.g. adding `allowed-tools` to an alias command would not
actually constrain the delegated skill). SKILL-5 is the one structural refactor (split to
`references/`).

## Risks / Trade-offs

- **Concurrent commits across worktrees** → safe: worktrees have per-tree indexes and write
  distinct refs; creation is serialized to avoid the one shared-metadata race.
- **Over-trimming a description loses triggering signal (CMD-2)** → keep descriptions
  specific and verb-first, not just short; skills carry their own triggering text.
- **SKILL-5 split breaks a reference** → the agent must create `references/` files and verify
  each pointer resolves; `claude plugins validate` + a file-existence check gate the branch.
- **`disable-model-invocation` blocks a needed auto-invocation** → only control commands get
  it; they are user-initiated by design, so no workflow regression.

## Migration Plan

Create umbrella change + `CLAUDE.md` edits on `develop` → create 7 worktrees → parallel
implement + validate + commit per branch → review → merge each `--no-ff` to `develop` →
remove worktrees and delete merged branches. No remote push (local only).
