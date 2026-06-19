# cc-goodies

Developer-experience extras for [Claude Code](https://claude.com/claude-code), shared as a plugin marketplace. Small, **independent, opt-in** plugins:

| Plugin | What it does |
|--------|--------------|
| **[voice-notify](plugins/voice-notify)** | Speaks a short, rotating, first-person cue (macOS `say`) when Claude needs your attention or finishes a turn. |
| **[statusline](plugins/statusline)** | An enriched two-line statusline: `user@host`, cwd, branch/worktree, task focus, model, effort, context % and rate-limit %. |
| **[git-guard](plugins/git-guard)** | Blocks accidental commits/merges/pushes to protected branches (`main`/`master`) before they run. Selectable policies, configurable branches. Cross-platform. |
| **[shell-guard](plugins/shell-guard)** | Blocks a curated set of catastrophic shell commands (`rm -rf /` or `~`, `dd` to a disk, `mkfs`, fork bombs, `curl\|sh`) before they run. Defence in depth over the deny list; configurable. Cross-platform. |
| **[rtk-hook](plugins/rtk-hook)** | Wires RTK (Rust Token Killer) as a managed `PreToolUse` hook to cut output tokens on routine Bash commands. No-ops without the `rtk` binary. Cross-platform. |

> **Shell safety.** `git-guard` and `shell-guard`, together with your `settings.json`
> deny list and plan mode, form a layered defense against dangerous shell commands. The
> **[shell-safety manual](docs/shell-safety.md)** is the map: threat model, what each
> layer catches and misses, and how to set it all up. It also ships an **advisory
> companion** ([`rules/shell-safety.md`](rules/shell-safety.md)) you symlink into
> `~/.claude/rules/` — the judgment calls (obfuscation, piping remote → shell, prompt
> injection) a hook can't enforce.

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install voice-notify@cc-goodies
/plugin install statusline@cc-goodies
/plugin install git-guard@cc-goodies
/plugin install shell-guard@cc-goodies
/plugin install rtk-hook@cc-goodies
/statusline-install
/rtk-hook-install
```

Install any subset — they don't depend on each other. `/statusline-install` and `/rtk-hook-install` are one-time wiring steps: the first is needed only if you installed the statusline; the second is an optional cleanup most people skip — it only removes a `rtk hook claude` entry you hand-wired into `settings.json` yourself (RTK itself is a separate prerequisite: `brew install rtk`).

## Uninstall

Reverse of install — undo any wiring or config first, then remove the plugins and the marketplace:

```text
/statusline-uninstall
/git-guard-uninstall
/shell-guard-uninstall
/rtk-hook-uninstall
/plugin uninstall statusline@cc-goodies
/plugin uninstall git-guard@cc-goodies
/plugin uninstall shell-guard@cc-goodies
/plugin uninstall rtk-hook@cc-goodies
/plugin uninstall voice-notify@cc-goodies
/plugin marketplace remove cc-goodies
```

Each plugin's dedicated uninstall only undoes what its install added and refuses to touch anything you configured yourself. voice-notify writes nothing outside its plugin directory, so `/plugin uninstall` removes it completely. Run `/hooks` or restart afterwards.

## Requirements

- **macOS** — voice-notify uses the built-in `say`; the statusline uses a few BSD tools.
- **`jq`** — `brew install jq` (statusline, and the notification message transform).
- **A voice (for voice-notify)** — macOS includes **Samantha** (en_US) out of the box, so it works with no download (`CLAUDE_VOICE="Samantha"`). For higher quality, install an Enhanced/Premium voice via System Settings → Accessibility → Spoken Content → Manage Voices. See [voice-notify's README](plugins/voice-notify#choosing--installing-a-voice) for the steps.

See each plugin's README for configuration.

## Design principles

Every plugin here is independent and opt-in, and ships a **symmetric, documented install ⇄ uninstall path**:

- Each plugin README has both an **Install** and an **Uninstall** section; this README mirrors both.
- Every install verb has a written inverse: `marketplace add` ⇄ `marketplace remove`, `/plugin install` ⇄ `/plugin uninstall`, `/<name>-install` ⇄ `/<name>-uninstall`.
- Anything that writes **durable** state outside the plugin directory (e.g. `settings.json`, `~/.claude/<plugin>.conf`) ships a dedicated, ownership-guarded revert command that never removes what you set up yourself. Pure-hook plugins (no external writes) rely on `/plugin uninstall` — and say so. Ephemeral `$TMPDIR` caches are exempt.

Contributors follow this rule — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT © Volodymyr Styran
