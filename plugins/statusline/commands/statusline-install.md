---
description: Install the cc-goodies enriched statusline — copies the script and wires it into settings.json (with confirmation).
allowed-tools: Bash(mkdir:*), Bash(cp:*), Bash(chmod:*), Bash(jq:*), Bash(test:*), Bash(command -v jq), Read, Edit
disable-model-invocation: true
---

You are installing the **cc-goodies enriched statusline** for the current user. A plugin cannot set the `statusLine` setting itself, so do the wiring carefully and idempotently:

1. **Locate the bundled script** at `${CLAUDE_PLUGIN_ROOT}/statusline-command.sh`. Verify it exists; if not, stop and report the path you checked.

2. **Check prerequisites.** Confirm `jq` is available (`command -v jq`). The statusline requires it. If missing, tell the user to `brew install jq` and stop.

3. **Copy the script to a stable path.** The plugin's cache directory changes on every update, so copy it out:
   - `mkdir -p "$HOME/.claude"`
   - `cp "${CLAUDE_PLUGIN_ROOT}/statusline-command.sh" "$HOME/.claude/team-statusline.sh"`
   - `chmod +x "$HOME/.claude/team-statusline.sh"`

4. **Read** `$HOME/.claude/settings.json` (treat as `{}` if it does not exist).

5. **Show the user the exact change** before writing, and ask for confirmation. The change sets, using the *resolved absolute* home path (never a literal `~`):
   ```json
   "statusLine": { "type": "command", "command": "bash <ABSOLUTE_HOME>/.claude/team-statusline.sh" }
   ```
   If a `statusLine` key already exists, show its current value and ask whether to overwrite.

6. **On confirmation**, merge the `statusLine` key into settings.json with `jq` so every existing setting is preserved, then write it back and verify it still parses (`jq empty`). Never touch unrelated keys.

7. **Report success** and tell the user to run `/hooks` or restart for it to take effect. Mention they can revert by removing the `statusLine` key and deleting `~/.claude/team-statusline.sh`.

If anything is ambiguous, ask before writing.
