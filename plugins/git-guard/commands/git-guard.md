---
description: View or change git-guard settings (protected branches, block-all-push, pause/resume). Writes ~/.claude/git-guard.conf with confirmation.
allowed-tools: Read, Write, Edit, Bash(test:*), Bash(grep:*), Bash(command -v jq)
---

You are configuring **git-guard** for the current user. The hook is declared inline in the
plugin manifest, so installing the plugin is the whole install — it activates on load and
stays active across plugin updates; there is no separate hook to install. The hook script
reads its settings at runtime from `~/.claude/git-guard.conf` (a plain `KEY=VALUE` file), so
config changes take effect on the **next Bash command** — no restart needed.

1. **Read the current config.** Read `$HOME/.claude/git-guard.conf` (treat a missing file
   as "all defaults"). The effective settings and their defaults are:
   - `GIT_GUARD_DISABLE` — `1` pauses the guard; unset or `0` means it's running (default unset)
   - `GIT_GUARD_MAIN_BRANCHES` — space-separated protected branches, default `main master`
   - `GIT_GUARD_BLOCK_ALL_PUSH` — `1` to block **every** push, not just pushes to a
     protected branch (default unset)

2. **Lead with the guard's current state**, derived from `GIT_GUARD_DISABLE`:
   **`Guard is: ON`** when it is unset or `0`, **`Guard is: PAUSED`** when it is `1`. Then
   summarise the active behaviour so they can choose:

   - **Default** — block a local write (`commit`/`merge`/`pull`/`rebase`/`cherry-pick`/
     `revert`/history-moving `reset`) while **on** a protected branch, and block any
     **push** whose resolved target is a protected branch. `develop` and feature
     branches are unrestricted.
   - **`GIT_GUARD_BLOCK_ALL_PUSH=1`** — additionally block **every** push regardless of
     target (strictly local-only workflow).

3. **Offer an explicit menu** (skip the toggle that matches the current state):
   - **[1] Pause guard** — set `GIT_GUARD_DISABLE=1` (no-ops but stays installed)
   - **[2] Resume guard** — clear the pause (remove the `GIT_GUARD_DISABLE` line, or set it to `0`)
   - **[3] Edit protected branches** — change `GIT_GUARD_MAIN_BRANCHES`
   - **[4] Block-all-push on/off** — toggle `GIT_GUARD_BLOCK_ALL_PUSH`

   If the user only wants to view, stop here.

4. **Write the change.** Create/update `$HOME/.claude/git-guard.conf` with the `KEY=VALUE`
   lines, **preserving every key you are not changing** — merge into the existing file,
   never clobber it (e.g. pausing must keep an existing `GIT_GUARD_MAIN_BRANCHES`). Only the
   keys that differ from default need to be present. Show the exact resulting file contents
   and confirm before writing. Example:
   ```
   GIT_GUARD_MAIN_BRANCHES="main master release"
   GIT_GUARD_BLOCK_ALL_PUSH=1
   ```

5. **Confirm** the new effective state back to the user (e.g. "Guard is now PAUSED" /
   "Guard is now ON"), and remind them the guard only gates Claude's Bash tool — they can
   always run a blocked command themselves in a terminal, or set `GIT_GUARD_DISABLE=1` to
   pause it.
