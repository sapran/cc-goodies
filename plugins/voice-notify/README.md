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

Installing the plugin is the whole install — the hooks are declared inline in the plugin
manifest, so they activate on install (you may need `/hooks` or a restart to load them the
first time) and stay active across plugin updates. There is no separate hook-install step
and nothing is written to `settings.json`.

## Configuration

Set these as environment variables (shell profile, or Claude Code's `env` setting):

| Variable | Effect |
|----------|--------|
| `CLAUDE_VOICE` | Voice to use. Default `Matilda (Premium)`; falls back to the system default if not installed. List options with `say -v '?'`. |
| `CLAUDE_VOICE_NOTIFY=off` | Mute without uninstalling. |

### Pause / mute

To silence the notifications without uninstalling, set `CLAUDE_VOICE_NOTIFY=off` (as an
environment variable in your shell profile, or Claude Code's `env` setting). Unset it — or
set it to `on` — to resume. This is voice-notify's pause path: there's no config file or
command, because the plugin is env-var only and writes nothing outside its own directory.

## Prerequisites

The voice hooks need:

- **macOS** — the hooks call the built-in `say` command. On any non-macOS machine the script no-ops cleanly (silent, no error), so it's safe to install team-wide.
- **A speech voice** — macOS ships with **Samantha** (en_US, female) out of the box, so the hooks work with **no download**. If the configured voice isn't installed, the hooks fall back to your system default voice. For higher quality, install an Enhanced/Premium voice (below).
- **`jq`** *(recommended)* — used to speak the *specific* reason on a notification (e.g. "…to use Bash"). Without it you still get a generic "I need your attention." Install with `brew install jq`.

`say` itself needs no installation.

## Choosing / installing a voice

**Samantha** — built into macOS, no download. Confirm it's there, test it, and point voice-notify at it:

```bash
say -v '?' | grep Samantha       # confirm it's installed (it is, on stock macOS)
say -v Samantha "Hello"          # hear it
export CLAUDE_VOICE="Samantha"   # use it (put in your shell profile or Claude Code `env`)
```

**Higher-quality voices** (Enhanced / Premium — larger downloads):

1. **System Settings → Accessibility → Spoken Content**
2. Open the **System Voice** dropdown → **Manage Voices…**
3. Expand **English**, tick a voice (e.g. *Samantha (Enhanced)*, *Matilda (Premium)*) — macOS downloads it.
4. Set `CLAUDE_VOICE` to the **exact** name from `say -v '?'`, parentheses included — e.g. `export CLAUDE_VOICE="Samantha (Enhanced)"`.

## Editing the phrases

The phrase pools are plain bash arrays in [`scripts/notify.sh`](scripts/notify.sh) — fork and tweak.

## Uninstall

```text
/plugin uninstall voice-notify@cc-goodies
```
