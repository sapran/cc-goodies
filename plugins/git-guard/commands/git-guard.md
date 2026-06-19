---
description: View or change git-guard settings (protected branches, block-all-push, disable). Writes ~/.claude/git-guard.conf with confirmation.
allowed-tools: Read, Write, Edit, Bash(test:*), Bash(grep:*), Bash(command -v jq)
---

You are configuring **git-guard** for the current user. The hook script reads its
settings at runtime from `~/.claude/git-guard.conf` (a plain `KEY=VALUE` file), so
config changes take effect on the **next Bash command** — no restart needed.

1. **Read the current config.** Read `$HOME/.claude/git-guard.conf` (treat a missing
   file as "all defaults"). The effective settings and their defaults are:
   - `GIT_GUARD_MAIN_BRANCHES` — space-separated protected branches, default `main master`
   - `GIT_GUARD_BLOCK_ALL_PUSH` — `1` to block **every** push, not just pushes to a
     protected branch (default unset)
   - `GIT_GUARD_DISABLE` — `1` to turn the guard off (default unset)

2. **Show the user the current state and the behaviour** so they can choose:

   - **Default** — block a local write (`commit`/`merge`/`pull`/`rebase`/`cherry-pick`/
     `revert`/history-moving `reset`) while **on** a protected branch, and block any
     **push** whose resolved target is a protected branch. `develop` and feature
     branches are unrestricted.
   - **`GIT_GUARD_BLOCK_ALL_PUSH=1`** — additionally block **every** push regardless of
     target (strictly local-only workflow).

3. **Ask what to change** — the protected-branch list, block-all-push on/off, or
   enable/disable. If the user only wants to view, stop here.

4. **Write the change.** Create/update `$HOME/.claude/git-guard.conf` with the
   `KEY=VALUE` lines (only the keys that differ from default need to be present).
   Show the exact file contents and confirm before writing. Example:
   ```
   GIT_GUARD_MAIN_BRANCHES="main master release"
   GIT_GUARD_BLOCK_ALL_PUSH=1
   ```

5. **Confirm** the new effective behaviour back to the user, and remind them the guard
   only gates Claude's Bash tool — they can always run a blocked command themselves
   in a terminal, or set `GIT_GUARD_DISABLE=1` to pause it.
