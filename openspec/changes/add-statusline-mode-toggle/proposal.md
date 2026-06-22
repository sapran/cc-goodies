## Why

The statusline is deliberately "enriched" — two lines carrying `user@host`, cwd, git
branch, the session's first task → latest request, model, effort, and three
severity-coloured usage gauges with elapsed/reset time suffixes. That density is the right
default, but there are moments it is noise: screen-sharing or pairing, a narrow terminal, a
recording, or simply wanting a quieter line while heads-down. Today the only way to slim it
is to edit and re-wire the script — there is no way to dial the detail down **while Claude
Code is running** and back up a minute later. This change adds that runtime switch.

## What Changes

- **Add two render modes — `enriched` (today's full two-line output) and `lean` (a single
  compact line).** Lean renders exactly: compressed cwd, git branch (or worktree), model
  display name, and the `c:` context gauge — `~/cab/claude.ai  [main]  Opus 4.8  c:42%`. It
  drops `user@host`, the `task → latest` prompt snippet, the effort suffix, the `s:`/`w:`
  rate-limit gauges, and every `⧗`/`⟲` time suffix. The `c:` gauge keeps its value-driven
  severity colour; the surviving segments keep their existing colours.
- **Lean is genuinely lighter, not just visually trimmed.** In lean mode the script skips
  the transcript reads that derive `task`/`latest`, the rate-limit gauge/reset bookkeeping,
  the duration humanising, and the effort-from-settings fallback — none of their output is
  shown, so none of the work runs. Lean does less I/O per render than enriched.
- **Toggle at runtime via `/statusline-toggle`.** The command flips a `STATUSLINE_MODE`
  value persisted in `~/.claude/statusline.conf`; bare invocation flips enriched⇄lean, and
  an optional `enriched`/`lean` argument sets a mode explicitly. The statusline script
  re-reads the conf on **every** render, so the next prompt reflects the new mode with no
  restart and no re-install.
- **Mode resolution: `~/.claude/statusline.conf` → built-in default `enriched`.** The conf
  is parsed safely (a `grep`/parameter-expansion read of `STATUSLINE_MODE=…`, never
  `source`d) and validated to the set `{enriched, lean}`; any other or absent value
  fails soft to `enriched`. No new render path runs when the conf is absent — existing
  installs behave exactly as before until the user toggles. (An environment-variable
  override was considered and intentionally left out — see design.)
- **Extend `/statusline-uninstall` to remove `~/.claude/statusline.conf`.** The conf is the
  one piece of durable external state this change introduces; the toggle command creates it
  and uninstall now removes it, preserving the marketplace's install ⇄ uninstall symmetry.
  As before, uninstall refuses to touch a statusline the user configured by hand.

No new dependency and no new data source: lean reads strictly fewer of the fields the script
already parses, and the only new external write is the user-owned, user-clearable
`~/.claude/statusline.conf` that the toggle command manages and uninstall reverts.

## Capabilities

### New Capabilities

- `statusline-mode-toggle`: The statusline renders in one of two modes — `enriched` (the
  existing full two-line output, unchanged) or `lean` (a single compact line of cwd, git
  branch/worktree, model, and the `c:` context gauge). The active mode is read each render
  from `~/.claude/statusline.conf` (`STATUSLINE_MODE`), defaulting to `enriched` when the
  file or key is absent or invalid; a `/statusline-toggle` command flips or sets the value so
  the switch takes effect on the next render with no restart. Lean mode additionally skips the
  enriched-only computations (transcript reads, rate-limit/reset bookkeeping, duration,
  effort fallback) so it does strictly less work. `/statusline-uninstall` removes the conf.

### Modified Capabilities

<!-- None. `enriched` mode is bit-for-bit today's output, so the two existing statusline
     specs — `statusline-severity-colours` and `statusline-time-readouts` — remain accurate
     descriptions of enriched-mode rendering and no REQUIREMENT in them changes. The new
     `statusline-mode-toggle` spec owns the mode concept and explicitly defers to those specs
     for enriched-mode behaviour, scoping lean mode as a subset that omits (not redefines)
     their elements. This mirrors how `add-statusline-severity-colours` recorded "Modified
     Capabilities: None" when it only added behaviour atop an unspec'd baseline. -->

## Impact

- **Code:** `plugins/statusline/statusline-command.sh` — resolve `mode` from the conf near the
  top (safe `grep` read, validated to `{enriched, lean}`, default `enriched`); gate the
  enriched-only work (task/latest transcript reads, rate-limit gauge + reset cache, duration,
  effort fallback, the second-line `printf` block) behind `mode = enriched`; add a lean
  single-line `printf` (cwd, branch/worktree, model, severity-coloured `c:`). cwd compression,
  branch lookup/cache, worktree shortening, and `gauge_sgr`/`used_int` stay shared.
- **Commands:** new `plugins/statusline/commands/statusline-toggle.md` (reads current mode,
  flips or sets it, updates only the `STATUSLINE_MODE=` line in `~/.claude/statusline.conf`
  while preserving any other lines, reports the new mode and that it applies next render);
  edit `plugins/statusline/commands/statusline-uninstall.md` to also delete the conf.
- **Docs:** `plugins/statusline/README.md` — document the two modes, the lean layout, the
  `/statusline-toggle` command, the `~/.claude/statusline.conf` / `STATUSLINE_MODE` mechanism
  and `enriched` default, and the conf's removal on uninstall; the marketplace root
  `README.md` mirrors the statusline entry; `plugin.json` keywords unchanged.
- **Dependencies:** none added. Still `jq` + `git`; mode resolution is a pure-bash file read.
- **Compatibility:** backward-compatible. With no conf present every install renders exactly
  as today; lean is strictly opt-in. Re-reading a tiny conf per render is one bounded file
  read alongside the caches the script already stats.
- **Install/uninstall:** `/statusline-install` is unchanged (the conf is created lazily on
  first toggle, not at install). The new durable state (`~/.claude/statusline.conf`) is
  introduced by `/statusline-toggle` and reverted by the extended `/statusline-uninstall`, so
  the symmetry holds: `/plugin uninstall` plus `/statusline-uninstall` is the full revert.
- **Out of scope:** an environment-variable mode override (deferred — it cannot change an
  already-running session, so it would not be the "runtime" toggle asked for); per-project
  (vs global) mode; more than two modes or a user-defined custom layout; changing the
  enriched output itself; and a statusline-wide config file beyond the single mode key.
