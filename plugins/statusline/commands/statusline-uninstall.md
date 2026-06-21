---
description: Remove the cc-goodies statusline — deletes the installed script and removes the statusLine entry it added (with confirmation). Won't touch a statusline you set up yourself.
allowed-tools: Bash(jq:*), Bash(rm:*), Bash(cp:*), Bash(test:*), Bash(command -v jq), Read, Edit
disable-model-invocation: true
---

You are reverting what `/statusline-install` did for the current user. Be careful and idempotent, and **never remove a statusline the user configured themselves**.

1. **Read** `$HOME/.claude/settings.json`. If it has no `statusLine` key, report "no statusLine configured — nothing to remove" and jump to step 4.

2. **Check ownership — this is the critical guard.** Inspect `.statusLine.command`. Proceed to remove it **only if it references `team-statusline.sh`** (the script this plugin installs). If it points anywhere else (for example a hand-written `statusline-command.sh`), **do not modify it**: show the user the current value, explain that it was not installed by this plugin, and stop. Ask before touching any statusLine you did not install.

3. **Remove the key, with confirmation.** Show the `statusLine` block you will delete and confirm. Then back up `settings.json` to `settings.json.bak`, remove just that key with `jq 'del(.statusLine)'` into a temp file, verify it still parses (`jq empty`), and replace `settings.json`. Preserve every other setting — never touch unrelated keys.

4. **Delete the installed script.** Remove `$HOME/.claude/team-statusline.sh` if it exists (`rm -f`). Never delete any other statusline script (e.g. `statusline-command.sh`).

5. **Report** what was removed and remind the user to:
   - finish removing the plugin: `/plugin uninstall statusline@cc-goodies`
   - run `/hooks` or restart so the statusline disappears.

If anything is ambiguous, ask before writing or deleting.
