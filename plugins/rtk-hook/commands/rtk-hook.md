---
description: View or change rtk-hook settings (pause/resume, or remove a hand-wired settings.json duplicate). Writes ~/.claude/rtk-hook.conf with confirmation.
allowed-tools: Read, Write, Edit, Bash(test:*), Bash(grep:*), Bash(jq:*), Bash(cp:*), Bash(command -v rtk), Bash(command -v jq)
---

You are configuring **rtk-hook** for the current user. The hook is declared inline in the
plugin manifest, so installing the plugin is the whole install — it activates on load and
stays active across plugin updates; there is no separate hook to install. The hook script
reads its settings at runtime from `~/.claude/rtk-hook.conf` (a plain `KEY=VALUE` file), so a
pause/resume takes effect on the **next Bash command** — no restart needed.

RTK (Rust Token Killer) rewrites Bash commands into a token-cheaper proxy form (e.g.
`git status` → `rtk git status`). This command lets you pause that rewriting, resume it, or
clean up a redundant hand-wired copy of the hook.

1. **Read the current config.** Read `$HOME/.claude/rtk-hook.conf` (treat a missing file as
   "all defaults"). The only setting is:
   - `RTK_HOOK_DISABLE` — `1` pauses the hook (commands run unrewritten); unset or `0` means
     it's running (default unset).

2. **Lead with the hook's current state**, derived from `RTK_HOOK_DISABLE`:
   **`rtk-hook is: ON`** when unset or `0`, **`rtk-hook is: PAUSED`** when `1`. Then report the
   two facts that decide whether RTK actually does anything:
   - Whether `rtk` is on `PATH` (`command -v rtk`). If not, note the hook no-ops until the
     `rtk` binary is installed, and mention the name-collision warning —
     `reachingforthejack/rtk` ("Rust Type Kit") is a different tool; this plugin wants the
     token-killer `rtk` (the one where `rtk gain` works).
   - Whether a **hand-wired** `rtk hook claude` entry exists in `~/.claude/settings.json` under
     `hooks.PreToolUse`. If present, it duplicates the plugin's hook and runs RTK twice per
     Bash call (harmless — RTK is idempotent — but untidy); offer to remove it (option [3]).

3. **Offer an explicit menu** (skip the toggle that matches the current state):
   - **[1] Pause rtk-hook** — set `RTK_HOOK_DISABLE=1` (no-ops but stays installed)
   - **[2] Resume rtk-hook** — clear the pause (remove the `RTK_HOOK_DISABLE` line, or set it to `0`)
   - **[3] Remove hand-wired duplicate** — delete a redundant `rtk hook claude` entry you wired
     into `settings.json` yourself, so RTK isn't invoked twice (see step 5)

   If the user only wants to view, stop here.

4. **Pause/resume — write the conf.** Create/update `$HOME/.claude/rtk-hook.conf` with the
   `KEY=VALUE` line, **preserving every key you are not changing** — merge into the existing
   file, never clobber it. Only keys that differ from default need to be present. Show the exact
   resulting file contents and confirm before writing. Example:
   ```
   RTK_HOOK_DISABLE=1
   ```

5. **Remove hand-wired duplicate — edit settings.json.** Only if the user picked [3]. Requires
   `jq` (`command -v jq`; if missing, tell them to `brew install jq` and stop). Read
   `$HOME/.claude/settings.json` (a missing file means nothing to do — report and stop). Find a
   `hooks.PreToolUse` hook whose `command` is **exactly** `rtk hook claude`. If none exists,
   report "no hand-wired RTK hook to remove — the plugin already provides it" and stop.
   **Ownership guard:** only ever touch an entry whose command is *exactly* `rtk hook claude`;
   never remove any other PreToolUse hook. Show the user the exact entry you will remove and
   confirm. Then back up `settings.json` to `settings.json.bak`, remove only that entry —
   pruning anything left empty — and verify the result still parses (`jq empty`) before writing
   it back:

   ```sh
   jq '
     (.hooks.PreToolUse) |= ( map(.hooks |= map(select(.command != "rtk hook claude")))
                              | map(select((.hooks | length) > 0)) )
     | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end
     | if (.hooks | length) == 0 then del(.hooks) else . end
   ' "$HOME/.claude/settings.json" > "$HOME/.claude/settings.json.tmp"
   jq empty "$HOME/.claude/settings.json.tmp" && mv "$HOME/.claude/settings.json.tmp" "$HOME/.claude/settings.json"
   ```

   Preserve every other setting. Note that `/rtk-hook-uninstall` will offer to put this entry
   back if they ever remove the plugin.

6. **Confirm** the new effective state back to the user (e.g. "rtk-hook is now PAUSED" /
   "rtk-hook is now ON", or "removed the hand-wired duplicate"), and remind them the hook only
   affects Claude's Bash tool — they can pause it any time with `RTK_HOOK_DISABLE=1`, or run a
   raw command themselves.
