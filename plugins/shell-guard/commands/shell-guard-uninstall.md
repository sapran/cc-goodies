---
description: Remove shell-guard — deletes the ~/.claude/shell-guard.conf it created and guides full plugin removal (with confirmation). Use /shell-guard to just pause it instead.
allowed-tools: Bash(rm:*), Bash(cp:*), Bash(test:*), Bash(cat:*), Read
disable-model-invocation: true
---

You are removing **shell-guard** for the current user. The hook itself lives inside
the plugin (declared in `plugin.json`), so it disappears the moment the plugin is
uninstalled — a command cannot uninstall its own plugin. Your job here is to clean
up the only thing shell-guard writes outside the plugin (`~/.claude/shell-guard.conf`)
and then point the user at the plugin-removal step.

1. **Decide if uninstall is even what they want.** If the user only wants to stop the
   guard temporarily, they should NOT uninstall — tell them to run `/shell-guard` and
   set `SHELL_GUARD_DISABLE=1` (or add that line to `~/.claude/shell-guard.conf`). The
   guard then no-ops but stays installed. Only continue below for a real removal.

2. **Check for the config file.** Look for `$HOME/.claude/shell-guard.conf`. If it does
   not exist, report "no shell-guard config to remove" and skip to step 4.

3. **Remove the config, with confirmation.** Show the user the current contents of
   `~/.claude/shell-guard.conf`, confirm, then back it up to `shell-guard.conf.bak` and
   `rm -f` the original. This only removes shell-guard's own settings file — it touches
   nothing else.

4. **Guide full removal.** Tell the user to finish by running:
   - `/plugin uninstall shell-guard@cc-goodies` — removes the plugin and its hook
   - `/hooks` or a restart so the PreToolUse hook stops firing

5. **Report** exactly what was removed (the conf file, if any) and what remains for the
   user to do. After uninstall, only the static `permissions.deny` list guards dangerous
   commands — remind them of that so it is a deliberate choice, not a silent gap.

If anything is ambiguous, ask before deleting.
