# statusline

An enriched, fast two-line statusline for Claude Code.

```text
user@host  ~/cab/claude.ai  [main]  "first task" → "latest ask"
Opus 4.8 (xhigh)  c:42% ⧗1h23m  s:18% ⟲2h45m  w:5% ⟲3d4h
```

- **Line 1:** `user@host`, compressed cwd, git branch (or worktree), and the session's first task → latest request.
- **Line 2:** model, effort level, then three usage gauges — `c:` context window used, `s:` 5-hour session rate-limit, `w:` 7-day (weekly) rate-limit. Each gauge can carry a dim time suffix: `c:` adds session elapsed time marked with an hourglass `⧗` (counts up), while `s:`/`w:` add a countdown to when that window resets, marked with `⟲` (counts down). The `s:`/`w:` gauges appear only once Claude Code reports rate-limit data; each `⧗`/`⟲` suffix appears only when Claude Code reports its source field (`cost.total_duration_ms`, or the window's `resets_at`), and the reset countdowns stay live across renders that omit rate-limit data via the same short-lived cache the gauges use.

Tuned for speed: a single `jq` parse, bounded transcript reads, and short-lived caches for the git branch and "latest message" lookups.

## Install

```text
/plugin install statusline@cc-goodies
/statusline-install
```

`/statusline-install` copies the script to `~/.claude/team-statusline.sh`, then — after showing you the change and confirming — adds the `statusLine` entry to your `~/.claude/settings.json` (existing settings preserved). A plugin can't set `statusLine` automatically, hence the one-time command.

Run `/hooks` or restart for it to take effect.

## Requirements

- **macOS** — uses BSD `stat -f`, `tail -r`, and `md5`. It still renders elsewhere, but
  degrades: `md5` falls back to `md5sum`, while `stat -f` and `tail -r` have no fallback —
  so on Linux the cache is bypassed (recomputed each render) and the "latest request" half
  of the task segment may stay blank.
- **`jq`** — required. `brew install jq`.
- **`git`** — for the branch/worktree segment.

## Uninstall

```text
/statusline-uninstall
/plugin uninstall statusline@cc-goodies
```

`/statusline-uninstall` only undoes what `/statusline-install` added — it **refuses to touch a statusline you configured yourself**. (To revert by hand instead: remove the `statusLine` key from `~/.claude/settings.json` and delete `~/.claude/team-statusline.sh`.)
