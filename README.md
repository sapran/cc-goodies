# cc-goodies

Developer-experience extras for [Claude Code](https://claude.com/claude-code), shared as a plugin marketplace. Small, **independent, opt-in** plugins:

| Plugin | What it does |
|--------|--------------|
| **[voice-notify](plugins/voice-notify)** | Speaks a short, rotating, first-person cue (macOS `say`) when Claude needs your attention or finishes a turn. |
| **[statusline](plugins/statusline)** | An enriched two-line statusline: `user@host`, cwd, branch/worktree, task focus, model, effort, context % and rate-limit %. |
| **[git-guard](plugins/git-guard)** | Blocks accidental commits/merges/pushes to protected branches (`main`/`master`) before they run. Selectable policies, configurable branches. Cross-platform. |

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install voice-notify@cc-goodies     # the talking one
/plugin install statusline@cc-goodies        # the statusline
/plugin install git-guard@cc-goodies         # the branch guard
/statusline-install                             # one-time wiring (statusline only)
```

Install any subset — they don't depend on each other.

## Uninstall

Reverse of install — undo any wiring or config first, then remove the plugins and the marketplace:

```text
/statusline-uninstall                          # revert the statusLine entry + delete the installed script (statusline)
/git-guard-uninstall                           # remove ~/.claude/git-guard.conf (git-guard) — /git-guard just pauses it
/plugin uninstall statusline@cc-goodies
/plugin uninstall git-guard@cc-goodies
/plugin uninstall voice-notify@cc-goodies
/plugin marketplace remove cc-goodies          # drop the marketplace entry
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
