# Cleanup (CONFIRM each)

Runs only once Commit / stash and Orient's scratch-file triage have already surfaced and
captured anything this phase might otherwise destroy.

- **Temp/scratch files** created this session → list them → confirm → remove.
- **Worktrees & branches** → `git worktree list`; identify merged/abandoned ones → confirm →
  remove the worktree, **and** remove its corresponding Claude Code project dir
  (`~/.claude/projects/<worktree-path-slug>/`, path with `/` → `-`).
