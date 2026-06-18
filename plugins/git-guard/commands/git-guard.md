---
description: View or change the git-guard policy (which branches Claude may commit/push to). Writes ~/.claude/git-guard.conf with confirmation.
allowed-tools: Read, Write, Edit, Bash(test:*), Bash(grep:*), Bash(command -v jq)
---

You are configuring **git-guard** for the current user. The hook script reads its
settings at runtime from `~/.claude/git-guard.conf` (a plain `KEY=VALUE` file), so
config changes take effect on the **next Bash command** — no restart needed.

1. **Read the current config.** Read `$HOME/.claude/git-guard.conf` (treat a missing
   file as "all defaults"). The effective settings and their defaults are:
   - `GIT_GUARD_POLICY` — `1`, `2`, or `3` (default `2`)
   - `GIT_GUARD_MAIN_BRANCHES` — space-separated, default `main master`
   - `GIT_GUARD_DEV_BRANCHES` — space-separated, default `develop`
   - `GIT_GUARD_DISABLE` — `1` to turn the guard off (default unset)

2. **Show the user the current state and the policy table** so they can choose:

   | Policy | Push → main | Commit → main | Push → develop | Commit → develop |
   |:------:|:-----------:|:-------------:|:--------------:|:----------------:|
   | **1** | ⛔ block | ✅ allow | ✅ allow | ✅ allow |
   | **2** (default) | ⛔ block | ⛔ block | ✅ allow | ✅ allow |
   | **3** | ⛔ block | ⛔ block | ⛔ block *(all pushes)* | ✅ allow |

   Policy 3 blocks **every** push and any commit to a protected branch; commits to
   `develop` and feature branches are still allowed.

3. **Ask what to change** — policy number, the protected-branch list, the dev-branch
   list, or enable/disable. If the user only wants to view, stop here.

4. **Write the change.** Create/update `$HOME/.claude/git-guard.conf` with the
   `KEY=VALUE` lines (only the keys that differ from default need to be present).
   Show the exact file contents and confirm before writing. Example:
   ```
   GIT_GUARD_POLICY=3
   GIT_GUARD_MAIN_BRANCHES="main master release"
   ```

5. **Confirm** the new effective policy back to the user, and remind them the guard
   only gates Claude's Bash tool — they can always run a blocked command themselves
   in a terminal, or set `GIT_GUARD_DISABLE=1` to pause it.
