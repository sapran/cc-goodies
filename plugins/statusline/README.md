# statusline

An enriched, fast two-line statusline for Claude Code.

```text
user@host  ~/cab/claude.ai  [main]  "first task" → "latest ask"
Opus 4.8 (xhigh)  c:42%  s:18%  w:5%
```

- **Line 1:** `user@host`, compressed cwd, git branch (or worktree), and the session's first task → latest request.
- **Line 2:** model, effort level, context-window %, and 5-hour / 7-day rate-limit usage.

Tuned for speed: a single `jq` parse, bounded transcript reads, and short-lived caches for the git branch and "latest message" lookups.

## Install

```text
/plugin install statusline@cc-goodies
/statusline-setup
```

`/statusline-setup` copies the script to `~/.claude/team-statusline.sh`, then — after showing you the change and confirming — adds the `statusLine` entry to your `~/.claude/settings.json` (existing settings preserved). A plugin can't set `statusLine` automatically, hence the one-time command.

Run `/hooks` or restart for it to take effect.

## Requirements

- **macOS** — uses BSD `stat -f`, `tail -r`, and `md5` (degrades gracefully elsewhere, but tuned for macOS).
- **`jq`** — required. `brew install jq`.
- **`git`** — for the branch/worktree segment.

## Uninstall

```text
/statusline-uninstall                       # reverts the statusLine entry + deletes the installed script (with confirmation)
/plugin uninstall statusline@cc-goodies     # removes the plugin itself
```

`/statusline-uninstall` only undoes what `/statusline-setup` added — it **refuses to touch a statusline you configured yourself**. (To revert by hand instead: remove the `statusLine` key from `~/.claude/settings.json` and delete `~/.claude/team-statusline.sh`.)
