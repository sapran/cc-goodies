# Implementation notes

Out-of-scope findings noticed while working on something else. Nothing here is a
commitment — each is a candidate for its own change, to be queued or dismissed
deliberately rather than folded silently into unrelated work.

## Stale `policy 2` reference in `CLAUDE.md`

**Found:** 2026-07-28, while adding `GIT_GUARD_LOCAL_WRITE_CHANNEL`.

`CLAUDE.md` (Git workflow) says:

> This repo eats its own dog food — `git-guard` (policy 2) blocks commits/pushes to
> `main` from a Claude session.

`git-guard` has no numbered policies. `GIT_GUARD_POLICY` was removed in commit `f58284e`
("refactor(git-guard): collapse to one default + block-all-push toggle"); the script now
carries a single policy (`git-guard.sh`, "Resolve the target branch and apply the single
policy"), and `plugins/git-guard/README.md` does not mention policies at all.

The statement's *substance* is still correct — the guard does block commits and pushes to
`main` from a session — so this is a wording fix, not a behaviour gap. Suggested
replacement: drop the parenthetical, or say "by default".

Not fixed in the `add-git-guard-local-write-channel` change: that change's `CLAUDE.md`
edit was scoped to the plugin-table row, and this line predates it.
