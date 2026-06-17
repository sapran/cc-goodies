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
- *(optional)* a premium voice such as **Matilda (Premium)**: System Settings → Accessibility → Spoken Content → System Voice → Manage Voices. Without it, voice-notify falls back to your default system voice.

See each plugin's README for configuration.

## License

MIT © Volodymyr Styran
