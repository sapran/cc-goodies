---
description: View or change shell-guard settings (pause it, or add extra block patterns). Writes ~/.claude/shell-guard.conf with confirmation.
allowed-tools: Read, Write, Edit, Bash(test:*), Bash(grep:*), Bash(command -v jq)
---

You are configuring **shell-guard** for the current user. The hook is declared inline in
the plugin manifest, so installing the plugin is the whole install — it activates on load
and stays active across plugin updates; there is no separate hook to install. The hook
script reads its settings at runtime from `~/.claude/shell-guard.conf` (a plain `KEY=VALUE`
file), so config changes take effect on the **next Bash command** — no restart needed.

shell-guard hard-blocks (exit 2) a small set of catastrophic commands: recursive deletes
of `/`, `$HOME`/`~`, or a top-level system directory; `dd` or a redirect onto a raw disk
device; `mkfs`/`wipefs`/destructive `diskutil`; fork bombs; piping a network download
into a shell; truncating a file to empty (`: >`); `chmod 777`; `eval`; `sudo`; and system
halt/reboot (`reboot`/`shutdown`/`halt`/`poweroff`). It targets plain-form accidents and
deliberately allows ordinary work like `rm -rf ./build`, `chmod 755 x`, or a plain
`> file` redirect.

1. **Read the current config.** Read `$HOME/.claude/shell-guard.conf` (treat a missing
   file as "all defaults"). The effective settings and their defaults are:
   - `SHELL_GUARD_DISABLE` — `1` pauses the guard; unset or `0` means it's running (default unset)
   - `SHELL_GUARD_EXTRA_PATTERNS` — extra ERE block patterns, `;`- or newline-separated
     (default unset). Each is matched against every command segment; a match blocks it.

2. **Lead with the guard's current state**, derived from `SHELL_GUARD_DISABLE`
   (**`Guard is: ON`** when unset or `0`, **`Guard is: PAUSED`** when `1`), then show what
   shell-guard blocks by default (the list above) so they understand the baseline before
   changing anything.

3. **Offer an explicit menu** (skip the toggle that matches the current state):
   - **[1] Pause guard** — set `SHELL_GUARD_DISABLE=1` (no-ops but stays installed)
   - **[2] Resume guard** — clear the pause (remove the `SHELL_GUARD_DISABLE` line, or set it to `0`)
   - **[3] Edit extra patterns** — add/remove `SHELL_GUARD_EXTRA_PATTERNS`

   If the user only wants to view, stop here. Warn that `SHELL_GUARD_EXTRA_PATTERNS` are raw
   regular expressions: a broad pattern can block a lot of legitimate commands, so keep them
   specific.

4. **Write the change.** Create/update `$HOME/.claude/shell-guard.conf` with the `KEY=VALUE`
   lines, **preserving every key you are not changing** — merge into the existing file,
   never clobber it (e.g. pausing must keep an existing `SHELL_GUARD_EXTRA_PATTERNS`). Only
   keys that differ from default need to be present. Show the exact resulting file contents
   and confirm before writing. Example:
   ```
   SHELL_GUARD_EXTRA_PATTERNS="git clean -fdx;>[[:space:]]*~/.ssh"
   ```

5. **Confirm** the new effective state back to the user (e.g. "Guard is now PAUSED" /
   "Guard is now ON"), and remind them the guard only gates Claude's Bash tool — they can
   always run a blocked command themselves in a terminal, or set `SHELL_GUARD_DISABLE=1` to
   pause it.
