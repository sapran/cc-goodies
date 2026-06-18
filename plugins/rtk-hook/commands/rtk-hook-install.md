---
description: Finish rtk-hook setup — remove the now-duplicate hand-wired `rtk hook claude` PreToolUse entry from settings.json (with confirmation), so only the plugin runs it.
allowed-tools: Bash(jq:*), Bash(cp:*), Bash(test:*), Bash(command -v rtk), Bash(command -v jq), Read
---

You are finishing the **rtk-hook** setup for the current user. Installing the plugin
already wired RTK via `plugin.json`, so RTK works the moment the plugin loads. This
command only cleans up a *redundant* hand-wired copy: many users have
`rtk hook claude` wired directly into `~/.claude/settings.json` under
`hooks.PreToolUse`. Leaving it there runs RTK twice per Bash call. RTK is idempotent
(an already-`rtk`-prefixed command passes through untouched), so it is harmless — but
removing the duplicate is tidier.

1. **Check prerequisites.** Confirm `jq` is available (`command -v jq`); it is needed
   to edit settings.json safely. If missing, tell the user to `brew install jq` and
   stop. Also check `command -v rtk`: if rtk is **not** installed, note that the plugin
   hook will no-op until they install rtk (and mention the name-collision warning —
   `reachingforthejack/rtk` is a different tool), but continue, since the cleanup below
   is still valid.

2. **Read** `$HOME/.claude/settings.json` (treat a missing file as nothing to do —
   report that and stop).

3. **Look for the hand-wired entry.** Search `hooks.PreToolUse` for a hook whose
   `command` is exactly `rtk hook claude`. If none exists, report "no hand-wired RTK
   hook to remove — the plugin already provides it" and stop. **Ownership guard:** only
   ever touch an entry whose command is *exactly* `rtk hook claude`. Never remove any
   other PreToolUse hook.

4. **Show the user the exact entry you will remove** and ask for confirmation.

5. **On confirmation**, back up `settings.json` to `settings.json.bak`, then remove
   only that entry with `jq`, pruning anything left empty, and verify the result still
   parses (`jq empty`) before writing it back:

   ```sh
   jq '
     (.hooks.PreToolUse) |= ( map(.hooks |= map(select(.command != "rtk hook claude")))
                              | map(select((.hooks | length) > 0)) )
     | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end
     | if (.hooks | length) == 0 then del(.hooks) else . end
   ' "$HOME/.claude/settings.json" > "$HOME/.claude/settings.json.tmp"
   jq empty "$HOME/.claude/settings.json.tmp" && mv "$HOME/.claude/settings.json.tmp" "$HOME/.claude/settings.json"
   ```

   Preserve every other setting — never touch unrelated keys.

6. **Report success** and tell the user to run `/hooks` or restart so the change takes
   effect. Note that `/rtk-hook-uninstall` will offer to put this entry back if they
   ever remove the plugin.
