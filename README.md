# cc-goodies

Developer-experience extras for [Claude Code](https://claude.com/claude-code), shared as a plugin marketplace. Small, **independent, opt-in** plugins:

| Plugin | What it does |
|--------|--------------|
| **[voice-notify](plugins/voice-notify)** | Speaks a short, rotating, first-person cue (macOS `say`) when Claude needs your attention or finishes a turn. |
| **[statusline](plugins/statusline)** | An enriched two-line statusline: `user@host`, cwd, branch/worktree, task focus, model, effort, context % and rate-limit %. |
| **[git-guard](plugins/git-guard)** | Blocks accidental commits/merges/pushes to protected branches (`main`/`master`) before they run. One default behaviour plus an optional block-all-push mode; configurable branches. Cross-platform. |
| **[shell-guard](plugins/shell-guard)** | Blocks a curated set of catastrophic shell commands (`rm -rf /` or `~`, `dd` to a disk, `mkfs`, fork bombs, `curl\|sh`) before they run. Defence in depth over the deny list; configurable. Cross-platform. |
| **[rtk-hook](plugins/rtk-hook)** | Wires RTK (Rust Token Killer) as a managed `PreToolUse` hook to cut output tokens on routine Bash commands. No-ops without the `rtk` binary. Cross-platform. |
| **[session-finalise](plugins/session-finalise)** | An end-of-session checklist that preserves work, then cleans up: commit/stash, durable memory, handoff, tracker updates, scratch-file and worktree removal — confirming every irreversible step. Auto-activates on wrap-up, or run `/session-finalise`. Cross-platform. |
| **[project-scope](plugins/project-scope)** | Scopes a project's plugins, MCP servers and skills to a stated theme — uninstalls off-theme plugins at project scope, disables user-level skills/MCPs, installs relevant ones, sets the context budget. Every change is consent-gated; project scope only. Auto-activates, or run `/project-scope <theme>`. Cross-platform. |

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
/plugin install session-finalise@cc-goodies
/plugin install project-scope@cc-goodies
/statusline-install
/rtk-hook-install
```

Install any subset — they don't depend on each other. The hook plugins (`voice-notify`, `git-guard`, `shell-guard`, `rtk-hook`) need no wiring: their hooks are declared inline in `plugin.json`, so `/plugin install` is the whole install and the hook stays active across updates. Pause the guards any time without uninstalling via `/git-guard` / `/shell-guard` (or `CLAUDE_VOICE_NOTIFY=off` for voice-notify). `/statusline-install` and `/rtk-hook-install` are one-time wiring steps: the first is needed only if you installed the statusline; the second is an optional cleanup most people skip — it only removes a `rtk hook claude` entry you hand-wired into `settings.json` yourself (RTK itself is a separate prerequisite: `brew install rtk`).

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
/plugin uninstall session-finalise@cc-goodies
/plugin uninstall project-scope@cc-goodies
/plugin uninstall voice-notify@cc-goodies
/plugin marketplace remove cc-goodies
```

Each plugin's dedicated uninstall only undoes what its install added and refuses to touch anything you configured yourself. voice-notify, session-finalise and project-scope write nothing outside their plugin directories, so `/plugin uninstall` removes them completely. Run `/hooks` or restart afterwards.

## Install / uninstall everything (shell)

Prefer the terminal? These do the same as the per-plugin steps above, in one shot — plain `claude plugins` CLI, one line each.

**Install everything:**

```bash
claude plugins marketplace add sapran/cc-goodies
claude plugins install voice-notify@cc-goodies
claude plugins install statusline@cc-goodies
claude plugins install git-guard@cc-goodies
claude plugins install shell-guard@cc-goodies
claude plugins install rtk-hook@cc-goodies
claude plugins install session-finalise@cc-goodies
claude plugins install project-scope@cc-goodies
```

Then, inside Claude, wire the statusline (the CLI can't set the `statusLine` key): `/statusline-install`. RTK is a separate prerequisite (`brew install rtk`); `/rtk-hook-install` is an optional cleanup.

**Remove everything:**

> **Wired the statusline? Run `/statusline-uninstall` inside Claude _before_ the commands
> below.** The CLI can't edit the `statusLine` key, and the bar runs from a standalone copy
> at `~/.claude/team-statusline.sh` — so removing the plugin alone leaves it rendering.
> `/statusline-uninstall` drops the key (backing up `settings.json` first, and only if it
> still points at this plugin's script) and deletes the copy.

```bash
claude plugins uninstall statusline@cc-goodies
claude plugins uninstall git-guard@cc-goodies
claude plugins uninstall shell-guard@cc-goodies
claude plugins uninstall rtk-hook@cc-goodies
claude plugins uninstall session-finalise@cc-goodies
claude plugins uninstall project-scope@cc-goodies
claude plugins uninstall voice-notify@cc-goodies
claude plugins marketplace remove cc-goodies
rm -f ~/.claude/git-guard.conf ~/.claude/shell-guard.conf
```

Uninstalling the plugins removes their hooks too (hooks are declared inline in each `plugin.json`). The `rm -f` clears the two guard config files, which exist only if you customised those guards.

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
