# voice-notify

Spoken notifications for Claude Code on macOS. Claude tells you — in the first person — when it needs you or when it's finished, so you can step away from the terminal.

## What you'll hear

- **When Claude needs you** (`Notification` — a permission prompt, waiting on input after going idle, or a background agent reporting in): the actual reason in the first person, routed by context — a brisk lead-in for permission prompts (*"Quick one — I need your permission to use Bash"*), a gentler one when it's just waiting (*"Whenever you're ready — I'm waiting for your input"*), and the agent's own name when a background agent finishes or needs you.
- **When Claude hands work to subagents** (`PreToolUse` on the `Agent` tool): a cue that **names what was delegated**, so you know what's running without looking. One agent is named on its own (*"Handing off — review script changes."*), two are both named (*"Two helpers: review script changes, and map the hook payloads."*), and a bigger fan-out is counted rather than enumerated (*"Five helpers, starting with review script changes."*). It stays a distinct *still-working* cue, never a sign-off, and a burst of parallel dispatches is **debounced** to a single announcement.
- **When an agent's results come back** (`PostToolUse` for foreground agents, `SubagentStop` for background ones): the same purpose again, with the outcome — *"Review script changes — done."*, or the distinct failure phrasing when an agent came back with nothing. Each agent is voiced exactly once. On a large fan-out the individual cues are **capped** (see *Naming and the name cap*) so a sweep of ten agents doesn't become ten announcements.
- **When the batch drains**: a roll-up (*"All five helpers are back."*) — but only when something was left unsaid, i.e. you were told to wait, or the cap suppressed the individual cues. A small fan-out that was named all the way through has already told you everything, so it gets no roll-up.
- **When the turn ends but agents are still running** (`Stop` with **background** subagents in flight): a distinct *waiting* cue (*"Still going, the helpers aren't done yet."*) instead of a turn-end sign-off — so a main session that goes idle while its background subagents keep working never says "All done" prematurely. The real sign-off waits until nothing is in flight, and the roll-up closes the loop when the last agent lands. (Blocking/foreground subagents finish before the turn ends, so they never trigger it.)
- **When a long turn finishes** (`Stop`, nothing in flight): a sign-off, e.g. *"All done."*, *"Your turn."*, *"That's a wrap."* — and for a turn you clearly waited on, one that acknowledges it (*"Okay, that took a bit, but it's done."*). **Quick turns stay silent** (see *Quiet on quick turns* below), so you only hear "done" for the work you stepped away from.

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
| `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` | Disable the whole subagent path — the hand-off cue, the completion cues, the roll-up, the in-flight tracking, **and** the waiting cue — leaving the attention and turn-end cues. With it off, `Stop` signs off exactly as it did before in-flight tracking existed. |
| `CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE` | Seconds within which a burst of subagent dispatches collapses to one cue (default `10`). Raise it if a single task dispatches several waves and you only want one hand-off cue; lower it to hear each wave. |
| `CLAUDE_VOICE_NOTIFY_SUBAGENT_COLLECT` | Seconds the first dispatch of a burst waits for its siblings to register before speaking (default `2`), so the cue can describe the whole fan-out instead of only the agent that fired first. `0` speaks immediately and will usually announce just one agent. |
| `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` | Seconds after which an in-flight subagent marker is treated as stale and pruned (default `3600`), so a subagent that never reports completion (a crash, or a denied dispatch) can't wedge the count into a permanent *waiting* state. |
| `CLAUDE_VOICE_NOTIFY_AGENT_NAMES=off` | Turn off naming: anonymous hand-off cues, no completion cues, no roll-up — the pre-0.6.0 behaviour, with the waiting cue and sign-off unchanged. |
| `CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP` | Name individual completions only while at most this many subagents are in flight (default `3`). Above it, completions go quiet and the batch gets one roll-up instead. |
| `CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX` | Characters of an agent's description to speak (default `60`), truncated at a word boundary. |

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

### Subagent hand-off cue

When the main agent dispatches subagents (the `Agent` tool) it pauses while they run — a
different state from "finished, your turn". A `PreToolUse` hook on that tool speaks a distinct
*still-working* cue so you can tell the two apart by ear, and names what was handed off. A
fan-out fires the hook once per subagent, so the cue is **debounced**: the first fire speaks and
records an epoch in a single per-session `$TMPDIR` file (`vn-<session>.dispatch`); further fires
within `CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE` seconds (default 10) stay silent, so a parallel
dispatch is one cue, not one per subagent. Mute just this cue (and the completion and waiting
cues below) with `CLAUDE_VOICE_NOTIFY_SUBAGENT=off`. The marker is ephemeral `$TMPDIR` state,
like the turn timer, so `/plugin uninstall` remains a complete revert.

Because each agent's hook fires separately, the agent that speaks for the burst can't know how
many siblings are coming. It therefore claims the burst (a create-only `$TMPDIR` directory, so
exactly one speaks) and waits `CLAUDE_VOICE_NOTIFY_SUBAGENT_COLLECT` seconds (default 2) for the
others to register their descriptions before composing the cue. Set it to `0` for an immediate
cue that will usually name only the first agent.

### Naming and the name cap

Each agent's purpose comes from the `description` on its `Agent` tool call — the same short
phrase Claude writes when dispatching it. It is spoken verbatim, sanitised first: control
characters stripped, whitespace collapsed, `say`'s own `[[…]]` directive syntax neutralised, and
truncated at a word boundary to `CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX` characters (default 60). A
description is always passed to `say` as a single quoted argument and never interpolated into a
command, so shell metacharacters in it are inert.

**Where the completion cue comes from** depends on how the agent ran, because Claude Code
reports the two cases through different events:

| Agent | Result reaches the parent at | Voiced by |
|-------|------------------------------|-----------|
| Foreground (`run_in_background: false`) | `PostToolUse` on the `Agent` tool, carrying both the description and the result | `PostToolUse` |
| Background (the default) | `SubagentStop`, where the agent still appears in the event's own `background_tasks` list with its description | `SubagentStop` |

A background agent's `PostToolUse` fires milliseconds after dispatch as a launch acknowledgement
— voicing it would be a false "finished", so it only records the agent's id and purpose for
later. The presence of that record (or of the `background_tasks` entry) is exactly what tells
the two cases apart, so **every agent is voiced once and only once**.

A foreground agent that errors or that you interrupt never reaches `PostToolUse` at all —
Claude Code fires `PostToolUseFailure` instead — so that event is hooked too, and routes to the
same failure phrasing (*"Count to three — that one didn't finish."*). A background agent that
fails surfaces the other way, as a `SubagentStop` with no final message.

Individual completion cues are spoken only while at most `CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP`
(default 3) subagents are in flight. Above the cap they go quiet — ten agents finishing should
not be ten announcements — and the batch is marked as owing you a summary.

### The drain roll-up

When the last in-flight subagent lands, voice-notify speaks a roll-up (*"All five helpers are
back."*) **only if something was left unsaid**: either the waiting cue promised you an all-clear,
or the name cap suppressed the individual completions. A fan-out that was named all the way
through needs no roll-up — the final agent's own cue already was the all-clear. The count comes
from a per-batch marker directory, and the two flags (`vn-<session>.waited`,
`vn-<session>.capped`) are cleared as soon as the roll-up fires, when a turn ends with nothing
outstanding, or at the next prompt if nothing is running.

### One cue at a time

Naming completions means several agents can finish together and try to speak at once, which on
macOS produces two overlapping voices. Cues are therefore serialised through a create-only lock
directory under `$TMPDIR`: one speaks, the others wait a few seconds and then **drop** their cue
rather than queueing it, so a burst never leaves a backlog of stale announcements playing after
the fact. A lock left behind by a killed process is reclaimed by age, so the plugin can't be
wedged into permanent silence.

### Waiting-on-subagents cue

With **background** subagents, the main turn can end while they keep running: Claude Code fires
`Stop` without waiting for them (a `SubagentStop` fires later, per agent, when each finishes).
Left alone, `Stop` would speak a turn-end sign-off — a false "All done" for work still in
progress. If any subagents are still in flight, voice-notify speaks a distinct **waiting** cue
(*"Not done yet, the agents are still working."*) instead of the sign-off — regardless of the
quiet-on-quick-turns gate, since a turn boundary with work outstanding is worth flagging — and
remembers that it owes you the all-clear when the batch drains. When nothing is in flight
(including every ordinary turn, and any turn whose subagents were blocking/foreground and so
finished first), `Stop` behaves exactly as before.

The in-flight number comes from `background_tasks`, the list of running work that Claude Code
puts on the `Stop` and `SubagentStop` payloads themselves — authoritative, and immune to the
stuck-count problem a tally can have. The agent whose completion is being handled is still
listed at its own stop, so it is excluded from its own count.

Claude Code versions that don't send that list fall back to the original tally: two create-only
marker directories under `$TMPDIR` (one for spawns, one for completions, the latter keyed by
`agent_id` so a duplicate stop counts once), so concurrent asynchronous hooks never race. A
subagent that never reports completion — a crash, or a dispatch you denied — would otherwise
leave that tally stuck, so markers older than `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` seconds
(default `3600`) are pruned. Nothing is written outside `$TMPDIR` and the plugin's own
directory, so `/plugin uninstall` remains a complete revert.

## Prerequisites

The voice hooks need:

- **macOS** — the hooks call the built-in `say` command. On any non-macOS machine the script no-ops cleanly (silent, no error), so it's safe to install team-wide.
- **A speech voice** — macOS ships with **Samantha** (en_US, female) out of the box, so the hooks work with **no download**. If the configured voice isn't installed, the hooks fall back to your system default voice. For higher quality, install an Enhanced/Premium voice (below).
- **`jq`** *(recommended)* — used to read the hook payload: the *specific* reason on a notification (e.g. "…to use Bash") and every agent description. Without it you still get a generic "I need your attention." and the anonymous pre-0.6.0 subagent cues, with no completion cues. Install with `brew install jq`.

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
