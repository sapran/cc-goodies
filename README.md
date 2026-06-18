# cc-goodies

Developer-experience extras for [Claude Code](https://claude.com/claude-code), shared as a plugin marketplace. Two small, **independent, opt-in** plugins:

| Plugin | What it does |
|--------|--------------|
| **[voice-notify](plugins/voice-notify)** | Speaks a short, rotating, first-person cue (macOS `say`) when Claude needs your attention or finishes a turn. |
| **[statusline](plugins/statusline)** | An enriched two-line statusline: `user@host`, cwd, branch/worktree, task focus, model, effort, context % and rate-limit %. |

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install voice-notify@cc-goodies     # the talking one
/plugin install statusline@cc-goodies        # the statusline
/statusline-setup                             # one-time wiring (statusline only)
```

Install either, both, or neither — they don't depend on each other.

## Requirements

- **macOS** — voice-notify uses the built-in `say`; the statusline uses a few BSD tools.
- **`jq`** — `brew install jq` (statusline, and the notification message transform).
- **A voice (for voice-notify)** — macOS includes **Samantha** (en_US) out of the box, so it works with no download (`CLAUDE_VOICE="Samantha"`). For higher quality, install an Enhanced/Premium voice via System Settings → Accessibility → Spoken Content → Manage Voices. See [voice-notify's README](plugins/voice-notify#choosing--installing-a-voice) for the steps.

See each plugin's README for configuration.

## License

MIT © Volodymyr Styran
