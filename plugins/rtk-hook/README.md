# rtk-hook

Wires **RTK (Rust Token Killer)** — a token-optimizing CLI proxy — as a managed
`PreToolUse` hook on Claude's Bash tool, so RTK installs and uninstalls like every
other cc-goodies plugin instead of being hand-wired into `settings.json`.

RTK rewrites common Bash commands into a token-cheaper proxy form (e.g. `git status`
→ `rtk git status`), transparently saving output tokens on routine dev operations.

## How it works

The plugin declares a single `PreToolUse`/`Bash` hook that runs a tiny wrapper,
`scripts/rtk-hook.sh`:

- If `rtk` is on `PATH`, the wrapper hands the hook's stdin straight to
  `rtk hook claude` and relays its output/exit — identical to wiring `rtk hook claude`
  directly, just managed by the plugin.
- If `rtk` is **not** installed, the wrapper does nothing and exits 0 (**fails open**).
  So the plugin is safe to install even if you don't have RTK — it simply no-ops until
  you do, and a missing or renamed binary never blocks a Bash command.

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install rtk-hook@cc-goodies
/rtk-hook-install                       # optional cleanup — most people skip it (see below)
```

The plugin hook activates on install (restart or `/hooks` to load it). RTK itself is a
separate prerequisite — install the `rtk` binary first (`brew install rtk`; homepage
<https://www.rtk-ai.app/>). The hook no-ops until `rtk` is on your `PATH`, so the order
doesn't matter.

`/rtk-hook-install` is an **optional** one-time cleanup — **skip it unless you previously
hand-wired `rtk hook claude` into `~/.claude/settings.json` yourself** (most people never
did; the plugin's own hook is all you need). If you *did* wire it by hand, this command
removes that now-duplicate entry (after showing it and confirming) so RTK isn't invoked
twice per Bash call. RTK is idempotent, so the duplicate is harmless if you skip this —
just untidy.

## Uninstall

```text
/rtk-hook-uninstall
/plugin uninstall rtk-hook@cc-goodies
```

`/rtk-hook-uninstall` **offers to restore** the hand-wired `rtk hook claude` entry in
`settings.json` that `/rtk-hook-install` removed (so RTK can keep working without this
plugin) — or leaves RTK off entirely, your choice. `/plugin uninstall` then removes the
plugin and its hook.

## Notes

- **Name collision.** There is an unrelated tool also called `rtk`
  (`reachingforthejack/rtk`, "Rust Type Kit"). This plugin assumes the token-killer
  `rtk` — the one where `rtk gain` works. If the wrong binary is on `PATH`, the wrapper
  will hand stdin to it; remove it from `PATH` or the hook will misbehave.
- The wrapper adds no measurable overhead beyond RTK itself; it's a `command -v` check
  and an `exec`.

## Requirements

- `bash`, and the `rtk` (Rust Token Killer) binary on `PATH` for any effect
  (`brew install rtk` — homepage <https://www.rtk-ai.app/>). `jq` is used only by the
  install/uninstall commands to edit `settings.json`.

## License

MIT © Volodymyr Styran
