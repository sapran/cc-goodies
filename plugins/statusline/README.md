# statusline

An enriched, fast two-line statusline for Claude Code.

```text
user@host  ~/cab/claude.ai  [main]  "first task" → "latest ask"
Opus 4.8 (xhigh)  c:42% ⧗1h23m  s:18% ⟲2h45m  w:5% ⟲3d4h
```

- **Line 1:** `user@host`, compressed cwd, git branch (or worktree), and the session's first task → latest request.
- **Line 2:** model, effort level, then three usage gauges — `c:` context window used, `s:` 5-hour session rate-limit, `w:` 7-day (weekly) rate-limit. Each gauge is **coloured by its own fill level** so severity reads at a glance: green → amber → red as it climbs, with the context gauge interposing a yellow step (green → yellow → amber → red) and the critical red tier bolded. Thresholds are tuned per gauge — `c:` green below 25%, yellow at 25, amber at 50, red at 75; `s:` amber at 50, red at 80; `w:` amber at 50, red at 75. (Colours use 256-colour indices so amber/red stay legible on a light background; the static example above shows them uncoloured.) Each gauge can carry a dim time suffix: `c:` adds session elapsed time marked with an hourglass `⧗` (counts up), while `s:`/`w:` add a countdown to when that window resets, marked with `⟲` (counts down). The `s:`/`w:` gauges appear only once Claude Code reports rate-limit data; each `⧗`/`⟲` suffix appears only when Claude Code reports its source field (`cost.total_duration_ms`, or the window's `resets_at`), and the reset countdowns stay live across renders that omit rate-limit data via the same short-lived cache the gauges use.

Tuned for speed: a single `jq` parse, bounded transcript reads, and short-lived caches for the git branch and "latest message" lookups.

## Modes

The statusline renders in one of two modes, switchable while Claude Code is running:

- **`enriched`** (the default) — the full two-line output shown above. Unchanged.
- **`lean`** — a single compact line: compressed cwd, git branch (or `wt:` worktree token), model display name, and the `c:` context gauge.

```text
~/cab/claude.ai  [main]  Opus 4.8  c:42%
```

Lean keeps where you are, the branch/worktree, the model, and how full the context window is — the `c:` gauge keeps its value-driven severity colour. It **drops** the `user@host` segment, the `task → latest` prompt snippet, the `(effort)` suffix, the `s:` (5-hour) and `w:` (7-day) rate-limit gauges, and every `⧗` elapsed and `⟲` reset time suffix. Lean is also genuinely lighter, not just visually trimmed: it skips the work behind the dropped segments — both transcript reads, the rate-limit gauge/reset bookkeeping, the duration humanising, and the effort-from-settings fallback — so it does strictly less I/O per render than enriched.

### Toggling the mode

```text
/statusline-toggle          # flip enriched ⇄ lean
/statusline-toggle lean     # set lean explicitly
/statusline-toggle enriched # set enriched explicitly
```

A bare `/statusline-toggle` flips the current mode; an optional `enriched`/`lean` argument sets one explicitly. The change applies on the **next render** — no restart, no re-install — and the command reports the resulting mode.

The mode is persisted as a `STATUSLINE_MODE=enriched|lean` line in `~/.claude/statusline.conf`, which the statusline **re-reads on every render** (that is how a flip reaches the already-running session). The conf is *read, never `source`d*, so a stray line in it can't execute. Any value outside `{enriched, lean}` — or an absent key or file — fails soft to `enriched`, which is why an install with no conf renders exactly as before. `/statusline-toggle` creates the conf lazily on first use; `/statusline-install` is unchanged and writes no conf.

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

`/statusline-uninstall` only undoes what `/statusline-install` added — it **refuses to touch a statusline you configured yourself** — and also removes `~/.claude/statusline.conf` (the mode-toggle state `/statusline-toggle` creates), no-op-clean when that conf is absent. (To revert by hand instead: remove the `statusLine` key from `~/.claude/settings.json`, delete `~/.claude/team-statusline.sh`, and delete `~/.claude/statusline.conf`.)
