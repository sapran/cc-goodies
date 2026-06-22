---
description: Toggle the cc-goodies statusline between enriched and lean mode
allowed-tools: Bash(mkdir:*), Bash(grep:*), Bash(cut:*), Bash(mv:*), Bash(test:*), Bash(printf:*), Read
disable-model-invocation: true
---

You are switching the **cc-goodies statusline render mode** for the current user. The mode is a
single `STATUSLINE_MODE` key in `$HOME/.claude/statusline.conf`; the statusline script re-reads
it on **every** render, so a change takes effect on the next prompt — no restart, no re-install.
This is a local, display-only, trivially reversible flag, so do **not** prompt for confirmation.

The argument to this command (if any) is `$ARGUMENTS`.

1. **Determine the target mode.**
   - If `$ARGUMENTS` is exactly `enriched` or `lean`, that is the target mode — set it explicitly.
   - If `$ARGUMENTS` is empty, read the current mode and flip it. Read the current value safely —
     **never `source` the conf** (a stray line in it must not execute):
     ```bash
     test -f "$HOME/.claude/statusline.conf" \
       && grep '^STATUSLINE_MODE=' "$HOME/.claude/statusline.conf" | tail -n1 | cut -d= -f2-
     ```
     Treat an absent file, an absent key, or any value other than `enriched`/`lean` as the default
     `enriched`. Then the target is the opposite: `enriched` → `lean`, otherwise → `enriched`.
   - If `$ARGUMENTS` is anything else (a non-empty value that is not `enriched` or `lean`), do not
     write — report that the argument is invalid and that valid values are `enriched`, `lean`, or
     none (to flip), and stop.

2. **Persist the target mode, updating only the `STATUSLINE_MODE` key** while preserving every
   other line in the conf. The conf is a plain, plugin-managed file, so refuse to write through a
   symlink. Strip any existing `STATUSLINE_MODE=` line into a temp file **in the conf's own
   directory**, append the new line, then rename it into place:
   ```bash
   conf="$HOME/.claude/statusline.conf"
   test -L "$conf" && { printf 'refusing: %s is a symlink\n' "$conf" >&2; exit 1; }
   mkdir -p "$HOME/.claude"
   tmp="$conf.tmp.$$"
   printf '' > "$tmp"   # empty temp file (a bare colon-redirect truncate would trip shell-guard)
   test -f "$conf" && grep -v '^STATUSLINE_MODE=' "$conf" >> "$tmp" 2>/dev/null
   printf 'STATUSLINE_MODE=%s\n' "<TARGET>" >> "$tmp"
   mv "$tmp" "$conf"
   ```
   Substitute the resolved target mode for `<TARGET>`. The temp file lives in the conf's own
   directory, so the `mv` is an atomic same-filesystem rename — a concurrent render never sees a
   half-written file.

3. **Report the result.** Tell the user the resulting mode (`enriched` or `lean`) and that it takes
   effect on the **next render** — no restart and no re-install. Do not ask for confirmation.
