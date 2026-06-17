# voice-notify

Spoken notifications for Claude Code on macOS. Claude tells you — in the first person — when it needs you or when it's finished, so you can step away from the terminal.

## What you'll hear

- **When Claude needs you** (`Notification` — a permission prompt, or waiting on input after going idle): a random lead-in plus the actual reason, e.g. *"Heads up, I need your permission to use Bash"* or *"When you get a sec, I am waiting for your input."*
- **When a turn finishes** (`Stop`): a random sign-off, e.g. *"All done."*, *"Your turn."*, *"That's a wrap."*

Phrases rotate randomly so it never feels robotic.

## Install

```text
/plugin install voice-notify@cc-goodies
```

The hooks activate on install (you may need `/hooks` or a restart to load them the first time).

## Configuration

Set these as environment variables (shell profile, or Claude Code's `env` setting):

| Variable | Effect |
|----------|--------|
| `CLAUDE_VOICE` | Voice to use. Default `Matilda (Premium)`; falls back to the system default if not installed. List options with `say -v '?'`. |
| `CLAUDE_VOICE_NOTIFY=off` | Mute without uninstalling. |

## Requirements

- **macOS** — `say` is built in.
- **`jq`** *(recommended)* — used to speak the *specific* reason on notifications. Without it you'll still hear a generic "I need your attention." `brew install jq`.
- *(optional)* a premium voice such as **Matilda (Premium)**: System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.

## Editing the phrases

The phrase pools are plain bash arrays in [`scripts/notify.sh`](scripts/notify.sh) — fork and tweak.

## Uninstall

```text
/plugin uninstall voice-notify@cc-goodies
```
