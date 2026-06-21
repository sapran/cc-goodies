---
description: Remove git-guard — deletes the ~/.claude/git-guard.conf it created and guides full plugin removal (with confirmation). Use /git-guard to just pause it instead.
allowed-tools: Bash(rm:*), Bash(cp:*), Bash(test:*), Bash(cat:*), Read
disable-model-invocation: true
---

You are removing **git-guard** for the current user. The hook itself lives inside
the plugin (declared in `plugin.json`), so it disappears the moment the plugin is
uninstalled — a command cannot uninstall its own plugin. Your job here is to clean
up the only thing git-guard writes outside the plugin (`~/.claude/git-guard.conf`)
and then point the user at the plugin-removal step.

1. **Decide if uninstall is even what they want.** If the user only wants to stop
   the guard temporarily, they should NOT uninstall — tell them to run `/git-guard`
   and set `GIT_GUARD_DISABLE=1` (or add that line to `~/.claude/git-guard.conf`).
   The guard then no-ops but stays installed. Only continue below for a real removal.

2. **Check for the config file.** Look for `$HOME/.claude/git-guard.conf`. If it does
   not exist, report "no git-guard config to remove" and skip to step 4.

3. **Remove the config, with confirmation.** Show the user the current contents of
   `~/.claude/git-guard.conf`, confirm, then back it up to `git-guard.conf.bak` and
   `rm -f` the original. This only removes git-guard's own settings file — it touches
   nothing else.

4. **Guide full removal.** Tell the user to finish by running:
   - `/plugin uninstall git-guard@cc-goodies` — removes the plugin and its hook
   - `/hooks` or a restart so the PreToolUse hook stops firing

5. **Report** exactly what was removed (the conf file, if any) and what remains for
   the user to do. After uninstall, nothing guards their branches — remind them of
   that so it is a deliberate choice, not a silent gap.

If anything is ambiguous, ask before deleting.
