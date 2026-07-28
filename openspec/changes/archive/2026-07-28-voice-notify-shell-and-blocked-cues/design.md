## Context

voice-notify 0.7.0 gives the *subagent* lifecycle a voice: a dispatch cue that names the
delegated work, a completion cue per agent, a cap and a roll-up, a waiting cue when a turn ends
with work outstanding, and suppression of the idle notification while that is true. Nothing
covers the other two things that keep a user waiting — a shell command that runs for minutes, and
a session that has stopped and will never resume on its own.

The harness surface was verified against the Claude Code 2.1.220 binary rather than assumed:

- The hook event list contains `StopFailure` ("When the turn ends due to an API error") with a
  cause enum of `rate_limit`, `overloaded`, `authentication_failed`, `oauth_org_not_allowed`,
  `billing_error`, `invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`,
  `unknown`. voice-notify does not hook it, so a turn killed this way is completely silent.
- `PermissionRequest` fires when a permission dialog is displayed, carrying `tool_name`,
  `tool_input` and `tool_use_id`. `PermissionDenied` fires on refusal.
- `PostToolUseFailure` carries `error`, `error_type`, `is_interrupt` and `is_timeout`.
- The `Bash` tool response carries `backgroundTaskId` — documented in the binary as *"ID of the
  background task if command is running in background"* — and the same id appears in the
  `background_tasks` entries that `Stop` and `SubagentStop` already deliver.
- The complete `notification_type` enum is `permission_prompt`, `idle_prompt`, `auth_success`,
  `elicitation_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`,
  `agent_completed`. **There is no shell-command equivalent**, which is the single fact that
  shapes this design: a background command's completion is not an event, it is an absence.
- A hook process that exceeds its declared `timeout` is killed and its output discarded.

Constraints carried from the existing plugin: bash 3.2, `set -u`, degrade silently off macOS or
without `jq`, `$TMPDIR`-only state so `/plugin uninstall` stays a complete revert, no
read-modify-write on state that concurrent async hooks touch, and env-var-only configuration.

## Goals / Non-Goals

**Goals:**

- Announce a foreground command that ran long enough that the user probably walked away.
- Announce a command that is *still* running, so "busy" is distinguishable from "stuck".
- Announce a background command's completion, named rather than anonymous.
- Break the silence when a turn dies on an API error.
- Keep telling the user about a permission prompt they did not answer.
- Add all of it without changing a single existing cue's behaviour.

**Non-Goals:**

- Changing what counts as outstanding work. The 0.7.0 block-list — a running `shell` and a
  `monitor` do not gate the sign-off — stays exactly as it is.
- Speaking command output, exit codes, or the command string itself.
- Announcing every command. The default thresholds mean the overwhelming majority stay silent.
- Real-time background-command completion. It is reported at the next turn boundary or not at all.
- Any non-macOS speech path, any config file, any install command.

## Decisions

### Duration gate at `PostToolUse`, not prediction at `PreToolUse`

Nothing in a `Bash` payload says how long the command will take, so the decision to speak can
only be made once the answer is known. `PostToolUse` carries `duration_ms`, so the completion cue
needs no timer and no state at all in the common case. This mirrors the plugin's existing
quiet-on-quick-turns rule, applied per command instead of per turn — the same idea, the same
knob shape, so the feature is explainable in one sentence.

*Alternative rejected:* classify commands by name at dispatch (`npm test` is slow, `git status` is
fast). Brittle, endless, and wrong the moment a repo is large.

### One elected watcher per session, not one timer per command

The still-running cue is the only part that genuinely needs a process alive while nothing else
happens. The obvious implementation — an async `PreToolUse` hook that sleeps and then checks — is
one sleeping process per `Bash` call, which in a session with hundreds of commands is
unacceptable. Instead every dispatch writes a marker and then *attempts* a create-only election;
only the winner loops. It polls every few seconds, speaks for markers past the threshold, speaks
due permission reminders, and exits when nothing is outstanding. The next dispatch elects a fresh
watcher.

This reuses two idioms already in the script — the create-only burst claim and the age-reclaimed
speech lock — rather than introducing a new concurrency primitive. Because a hook killed at its
timeout would die holding the election, the claim is reclaimable by age, and the watcher bounds
its own lifetime below the declared hook timeout so it exits cleanly instead of being killed.

*Alternative rejected:* piggyback the check on the next hook event of any kind. It cannot work —
when one long command is running, no hook events fire at all, which is precisely the case the cue
exists for.

### Background completion by task id diff, not by polling

`PostToolUse` on a backgrounded `Bash` call is a launch acknowledgement carrying
`backgroundTaskId` — structurally identical to a background *agent's* acknowledgement, which the
plugin already handles by recording rather than speaking. Recording `id → description` and then
noticing at a later `Stop` that the id has left `background_tasks` names the finished command
exactly, and reuses the list the `Stop` arm already parses. The cost is latency: the cue arrives
at the next turn boundary, which may be minutes after the command actually exited. That is
accepted and documented rather than engineered around, because the alternative — watching an
output file or polling the process — buys a few minutes of timeliness for a permanent background
poller.

### Announcing a command must not make it "outstanding work"

There is a tempting-looking simplification here that would be a regression: now that background
commands are tracked, count them in the in-flight tally. 0.7.0 deliberately excluded `shell` from
that tally because a dev server started once would mute the turn-end sign-off for the rest of the
session. The two concerns are separate — *what is worth announcing* is not *what should hold back
the sign-off* — and the spec states the exclusion as a requirement with scenarios so a later
change cannot quietly undo it.

### The command text is never spoken

Only the model-authored `description` reaches the speech engine. A command line routinely
contains tokens, hostnames and paths; reading it aloud would be both unintelligible and a
credential-disclosure path. The existing agent-description sanitiser is reused unchanged, which
is why `voice-notify-agent-identity` is modified rather than duplicated: one sanitising path, not
two.

### Reminders ride the same watcher, but do not depend on the command path

The permission reminder needs exactly what the still-running cue needs — something alive while
nothing happens — so it uses the same election. But the two features are independently useful, so
arming a reminder elects a watcher on its own, and `CLAUDE_VOICE_NOTIFY_CMD=off` silences command
cues without disabling reminders.

Disarming is the awkward part: approval is signalled only by the tool actually running, so the
disarm must see *any* tool's completion. That forces the `PostToolUse`/`PostToolUseFailure`
matcher from `Agent` to `*`. This is the change's one real cost and is handled by making the
script decide in its first few lines: unless the tool is `Agent` or `Bash`, or a permission marker
directory exists, it exits immediately.

### Reminders are bounded

An unanswered prompt at 02:00 must not talk until morning. Reminders stop after
`CLAUDE_VOICE_NOTIFY_NAG_MAX` repeats (default ~5) and the record ages out with the existing TTL
regardless. This knob is an addition to the four in the proposal discussion, added because
"repeats forever" is not a defensible default.

### `StopFailure` mirrors `Stop`

The stalled arm is deliberately shaped like the existing `stop` arm: same lock, same composition,
same per-turn cleanup (consume the turn-start timestamp, clear bookkeeping) — differing only in
the pool it draws from and in ignoring the duration gate. A turn that died is worth reporting at
any length, exactly as the waiting cue already ignores the gate.

## Risks / Trade-offs

- **`PostToolUse` widens to every tool** → the script must exit on its first decision when the
  tool is uninteresting and no permission marker exists. This path is measured in a test, not
  assumed.
- **A watcher process outlives its usefulness** → bounded self-lifetime below the hook timeout,
  exit when nothing is outstanding, election reclaimable by age, and marker TTL pruning. Three
  independent stops, because a stuck watcher is the one failure that could produce speech at
  random later.
- **Two watchers elected at once under a race** → the election is a create-only directory, the
  same primitive the burst claim already relies on; a duplicate would only produce duplicate cues,
  and the speech lock drops rather than queues contended cues.
- **Background completion cue arrives long after the fact** → phrased so it does not imply
  immediacy, and documented as turn-boundary-reported.
- **Chatty on a command-heavy session** → the defaults (45s still-running, 60s completion) mean a
  normal session speaks about commands almost never; the whole path is one env var away from off.
- **A description is missing** → anonymous fallback; never the command string.
- **Threshold interaction is confusing** (still-running at 45s, completion at 60s, so an announced
  command finishing at 50s would otherwise be silent) → the "an announced command always reports
  its completion" requirement removes the surprise.

## Migration Plan

Additive only. Every new cue is off-by-threshold or on-by-default with conservative values, no
existing cue changes, and no state format changes. Rollback is `CLAUDE_VOICE_NOTIFY_CMD=off` plus
`CLAUDE_VOICE_NOTIFY_NAG_EVERY=0`, or `/plugin uninstall`. No install or uninstall command is
introduced because nothing is written outside `$TMPDIR`.

## Open Questions

None blocking. Two to settle during implementation by testing rather than by argument: the
watcher's poll interval (a few seconds, traded against wake-ups), and whether the stalled cue
should distinguish all nine API error causes or collapse the rarer ones into a generic phrase.
