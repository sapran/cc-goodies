# Orient (read-only)

Snapshot the session, then summarize in one screen and propose which phases apply:

```bash
git status --short --branch
git worktree list
git log --oneline -5
```

Also note: files created/touched this session, and any tracker IDs (GitHub issue/PR numbers,
Asana task GIDs, Linear/Jira keys) mentioned in the conversation. Nothing here mutates state.

Don't trust memory alone for "what I created" — after a long or compacted session it's
unreliable. Derive candidate scratch files from `git status` untracked entries and **confirm
with the user** which are throwaway versus keep before Cleanup deletes anything.

## Delegable to a subagent

This is a noisy, read-only survey. Running it in a subagent keeps that noise out of the main
context — the subagent returns a small structured summary instead. Whether to actually delegate
is a judgment call (session size, how noisy the read would be), not a fixed rule to always or
never delegate it.
