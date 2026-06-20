# rtk-hook

Wires **RTK (Rust Token Killer)** — a token-optimizing CLI proxy — as a managed
`PreToolUse` hook on Claude's Bash tool, so RTK installs and uninstalls like every
other cc-goodies plugin instead of being hand-wired into `settings.json`.

RTK rewrites common Bash commands into a token-cheaper proxy form (e.g. `git status`
→ `rtk git status`), transparently saving output tokens on routine dev operations.

## How it works

The plugin declares a single `PreToolUse`/`Bash` hook that runs a tiny wrapper,
`scripts/rtk-hook.sh`:

- If `rtk` is on `PATH` and the hook isn't paused, the wrapper hands the hook's stdin
  straight to `rtk hook claude` and relays its output/exit — identical to wiring
  `rtk hook claude` directly, just managed by the plugin.
- If you've **paused** it (`RTK_HOOK_DISABLE=1`, see [Configuration](#configuration)), the
  wrapper no-ops and your command runs unrewritten.
- If `rtk` is **not** installed, the wrapper does nothing and exits 0 (**fails open**).
  So the plugin is safe to install even if you don't have RTK — it simply no-ops until
  you do, and a missing or renamed binary never blocks a Bash command.

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install rtk-hook@cc-goodies
```

The plugin hook activates on install (restart or `/hooks` to load it). There is no separate
install command — the inline hook is the whole install. RTK itself is a separate prerequisite —
install the `rtk` binary first (`brew install rtk`; homepage <https://www.rtk-ai.app/>). The
hook no-ops until `rtk` is on your `PATH`, so the order doesn't matter.

## Configuration

Optional. Run **`/rtk-hook`** to view state and pause/resume RTK, or to clean up a redundant
hand-wired copy of the hook. Settings live in `~/.claude/rtk-hook.conf` (a plain `KEY=VALUE`
file); precedence is **environment variable → `~/.claude/rtk-hook.conf` → built-in default**,
and changes take effect on the next Bash command.

| Key | Default | Meaning |
|-----|---------|---------|
| `RTK_HOOK_DISABLE` | unset | `1` pauses the hook (commands run unrewritten) without uninstalling; unset or `0` runs it. |

**Hand-wired duplicate.** If you previously wired `rtk hook claude` into
`~/.claude/settings.json` yourself, the plugin's hook now duplicates it (RTK runs twice per
Bash call). RTK is idempotent, so it's harmless — just untidy. `/rtk-hook` offers to remove the
hand-wired entry (after showing it and confirming), and `/rtk-hook-uninstall` offers to put it
back if you remove the plugin.

## Uninstall

```text
/rtk-hook-uninstall
/plugin uninstall rtk-hook@cc-goodies
```

`/rtk-hook-uninstall` deletes the `~/.claude/rtk-hook.conf` it created (after backup + confirm),
then **offers to restore** any hand-wired `rtk hook claude` entry that `/rtk-hook` removed (so
RTK can keep working without this plugin) — or leaves RTK off entirely, your choice. `/plugin
uninstall` then removes the plugin and its hook. To stop RTK *without* uninstalling, run
`/rtk-hook` and pause it instead.

## Notes

- **Name collision.** There is an unrelated tool also called `rtk`
  (`reachingforthejack/rtk`, "Rust Type Kit"). This plugin assumes the token-killer
  `rtk` — the one where `rtk gain` works. If the wrong binary is on `PATH`, the wrapper
  will hand stdin to it; remove it from `PATH` or the hook will misbehave.
- The wrapper adds no measurable overhead beyond RTK itself; it's a conf check, a
  `command -v` check and an `exec`.

## Requirements

- `bash`, and the `rtk` (Rust Token Killer) binary on `PATH` for any effect
  (`brew install rtk` — homepage <https://www.rtk-ai.app/>). `jq` is used only by the
  `/rtk-hook` and `/rtk-hook-uninstall` commands to edit `settings.json`.

## License

MIT © Volodymyr Styran
