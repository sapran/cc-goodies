---
description: Remove rtk-hook — deletes the ~/.claude/rtk-hook.conf it created, offers to restore a hand-wired `rtk hook claude` entry in settings.json, then guides full plugin removal (with confirmation). Use /rtk-hook to just pause it instead.
allowed-tools: Bash(jq:*), Bash(cp:*), Bash(rm:*), Bash(cat:*), Bash(test:*), Bash(command -v jq), Read
---

You are removing **rtk-hook** for the current user. The hook itself lives inside the plugin
(declared in `plugin.json`), so it disappears the moment the plugin is uninstalled — a command
cannot uninstall its own plugin. Your job is to clean up what rtk-hook wrote outside the plugin
and point the user at the plugin-removal step.

rtk-hook can leave two durable traces: its own `~/.claude/rtk-hook.conf` (pause state), and — if
you ever used `/rtk-hook` to remove a hand-wired `rtk hook claude` entry from
`~/.claude/settings.json` — that now-missing entry.

1. **Decide if uninstall is even what they want.** If the user only wants to stop RTK
   temporarily, they should NOT uninstall — tell them to run `/rtk-hook` and set
   `RTK_HOOK_DISABLE=1` (the hook then no-ops but stays installed). Only continue below for a
   real removal.

2. **Remove the config, with confirmation.** Look for `$HOME/.claude/rtk-hook.conf`. If it does
   not exist, note "no rtk-hook config to remove" and continue. Otherwise show the user its
   current contents, confirm, back it up to `rtk-hook.conf.bak`, then `rm -f` the original. This
   only removes rtk-hook's own settings file — it touches nothing else.

3. **Ask how they want RTK to behave after removal:**
   - **Restore** a hand-wired `rtk hook claude` hook so RTK keeps working without this plugin, **or**
   - **Leave it off** entirely (RTK no longer rewrites Bash commands).

   If they choose *leave it off*, skip to step 5.

4. **If restoring**, check prerequisites (`command -v jq`; if missing, `brew install jq` and
   stop) and read `$HOME/.claude/settings.json` (treat missing as `{}`). First check whether a
   `hooks.PreToolUse` entry with command exactly `rtk hook claude` already exists — if so, report
   "already present" and skip to step 5 (don't add a duplicate). Otherwise show the entry you
   will add, confirm, back up `settings.json` to `settings.json.bak`, merge it in with `jq`
   without disturbing other keys, verify it still parses (`jq empty`), and write it back:

   ```sh
   jq '
     .hooks = (.hooks // {})
     | .hooks.PreToolUse = ((.hooks.PreToolUse // []) +
         [{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}])
   ' "$HOME/.claude/settings.json" > "$HOME/.claude/settings.json.tmp"
   jq empty "$HOME/.claude/settings.json.tmp" && mv "$HOME/.claude/settings.json.tmp" "$HOME/.claude/settings.json"
   ```

5. **Guide full removal.** Tell the user to finish by running:
   - `/plugin uninstall rtk-hook@cc-goodies` — removes the plugin and its hook
   - `/hooks` or a restart so the PreToolUse hook stops firing

6. **Report** exactly what you did (removed the conf; restored or left off the hand-wired entry)
   and what remains for the user to do.

If anything is ambiguous, ask before editing settings.json or deleting files.
