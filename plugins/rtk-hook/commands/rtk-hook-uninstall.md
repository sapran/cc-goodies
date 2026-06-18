---
description: Remove rtk-hook — offers to restore the hand-wired `rtk hook claude` entry in settings.json that /rtk-hook-install removed, then guides full plugin removal (with confirmation).
allowed-tools: Bash(jq:*), Bash(cp:*), Bash(test:*), Bash(command -v jq), Read
---

You are removing **rtk-hook** for the current user. The hook itself lives inside the
plugin (declared in `plugin.json`), so it disappears the moment the plugin is
uninstalled — a command cannot uninstall its own plugin. Your job is to offer to undo
the one durable change `/rtk-hook-install` made (it removed the hand-wired
`rtk hook claude` entry from `~/.claude/settings.json`) and then point the user at the
plugin-removal step.

1. **Ask how they want RTK to behave after removal:**
   - **Restore** the hand-wired hook so RTK keeps working without this plugin, **or**
   - **Leave it off** entirely (RTK no longer rewrites Bash commands).

   If they choose *leave it off*, skip to step 4.

2. **If restoring**, check prerequisites (`command -v jq`; if missing, `brew install jq`
   and stop) and read `$HOME/.claude/settings.json` (treat missing as `{}`). First check
   whether a `hooks.PreToolUse` entry with command exactly `rtk hook claude` already
   exists — if so, report "already present" and skip to step 4 (don't add a duplicate).

3. **Show the entry you will add** and confirm. Then back up `settings.json` to
   `settings.json.bak`, merge it in with `jq` without disturbing other keys, verify it
   still parses (`jq empty`), and write it back:

   ```sh
   jq '
     .hooks = (.hooks // {})
     | .hooks.PreToolUse = ((.hooks.PreToolUse // []) +
         [{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}])
   ' "$HOME/.claude/settings.json" > "$HOME/.claude/settings.json.tmp"
   jq empty "$HOME/.claude/settings.json.tmp" && mv "$HOME/.claude/settings.json.tmp" "$HOME/.claude/settings.json"
   ```

4. **Guide full removal.** Tell the user to finish by running:
   - `/plugin uninstall rtk-hook@cc-goodies` — removes the plugin and its hook
   - `/hooks` or a restart so the PreToolUse hook stops firing

5. **Report** exactly what you did (restored the entry, or left RTK off) and what remains
   for the user to do.

If anything is ambiguous, ask before editing settings.json.
