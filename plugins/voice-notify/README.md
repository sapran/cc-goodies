# voice-notify

Spoken notifications for Claude Code on macOS. Claude tells you — in the first person — when it needs you or when it's finished, so you can step away from the terminal.

## What you'll hear

- **When Claude needs you** (`Notification` — a permission prompt, or waiting on input after going idle): the actual reason in the first person, routed by context — a brisk lead-in for permission prompts (*"Quick one — I need your permission to use Bash"*), a gentler one when it's just waiting (*"Whenever you're ready — I'm waiting for your input"*).
- **When a long turn finishes** (`Stop`): a sign-off, e.g. *"All done."*, *"Your turn."*, *"That's a wrap."* — and for a turn you clearly waited on, one that acknowledges it (*"Okay, that took a bit, but it's done."*). **Quick turns stay silent** (see *Quiet on quick turns* below), so you only hear "done" for the work you stepped away from.

Each cue is composed from small phrase pools and *sometimes* gets a lead-in (about 40% of the time, joined by a brief spoken pause) — so it varies in both wording and cadence and never settles into a formula.

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
| `CLAUDE_VOICE_NOTIFY_QUIET_UNDER` | Seconds below which a finished turn is *not* announced (default `20`). Set `0` to speak after every turn (the pre-0.3.0 behaviour); raise it to only hear about genuinely long tasks. |
| `CLAUDE_VOICE_NOTIFY_GARNISH_PCT` | Chance (0–100) that a cue gets a leading interjection (default `40`). `0` = always the bare phrase; `100` = always a lead-in. |

### Pause / mute

To silence the notifications without uninstalling, set `CLAUDE_VOICE_NOTIFY=off` (as an
environment variable in your shell profile, or Claude Code's `env` setting). Unset it — or
set it to `on` — to resume. This is voice-notify's pause path: there's no config file or
command, because the plugin is env-var only.

### Quiet on quick turns

A voice cue is only useful when you've stepped away — after a 3-second turn you're still
looking at the screen, so announcing it is noise. To time each turn, a `UserPromptSubmit`
hook writes a start timestamp to a single per-session file under your system temp directory
(`$TMPDIR`); the `Stop` hook reads it, measures how long the turn ran, and removes it. Turns
shorter than `CLAUDE_VOICE_NOTIFY_QUIET_UNDER` seconds (default 20) are skipped; longer ones
speak, and clearly long ones get a wait-acknowledging sign-off.

The timestamp file is ephemeral — the OS clears `$TMPDIR`, and nothing is ever written
outside it and the plugin's own directory, so `/plugin uninstall` remains a complete revert.
If the timing can't be determined (first turn, missing file), the cue is spoken rather than
swallowed. To restore the old "speak after every turn" behaviour, set
`CLAUDE_VOICE_NOTIFY_QUIET_UNDER=0`.

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

The phrase pools are plain newline-separated lists near the top of [`scripts/notify.sh`](scripts/notify.sh) (cores, plus brisk/gentle/neutral lead-ins) — fork and tweak.

## Uninstall

```text
/plugin uninstall voice-notify@cc-goodies
```
