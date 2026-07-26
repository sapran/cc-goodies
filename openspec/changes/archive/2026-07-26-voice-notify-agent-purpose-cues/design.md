## Context

voice-notify 0.5.0 treats subagents as an anonymous mass: `PreToolUse`/`Agent` speaks one
debounced "helpers are working" cue, `SubagentStop` deliberately speaks nothing and only
increments a marker count, and `Stop` uses that count to choose between a waiting cue and a
sign-off. Nothing the user hears identifies *which* work was delegated or *when it landed*.

The payload shapes below were established by running a probe session (Claude Code 2.1.220,
`claude -p` with dump-everything hooks on `PreToolUse`, `PostToolUse`, `SubagentStart`,
`SubagentStop`, `Stop`, `Notification`) that dispatched one foreground and one background agent.
They are observed, not inferred from documentation:

| Event | Fires | Carries |
|---|---|---|
| `PreToolUse(Agent)` | at dispatch, in parent | `tool_input.{description, subagent_type, model, run_in_background}`, `tool_use_id`; **no** `agent_id` |
| `SubagentStart` | just after dispatch, per agent | `agent_id`, `agent_type`; **no** description |
| `PostToolUse(Agent)` background | ~2 ms after dispatch | `tool_input.description` + `tool_response.{isAsync:true, status:"async_launched", agentId, outputFile}` |
| `PostToolUse(Agent)` foreground | at completion | `tool_response.{status:"completed", agentId, agentType, content[].text, totalDurationMs}`, `duration_ms` |
| `SubagentStop` | per agent, on finish | `agent_id`, `agent_type`, `last_assistant_message`, `agent_transcript_path`, `background_tasks[]` |
| `Stop` | turn end | `last_assistant_message`, `background_tasks[]` (empty when idle) |

The decisive observation: at a **background** agent's own `SubagentStop`, that agent is *still
listed* in its own `background_tasks` as
`{id, type:"subagent", status:"running", description, agent_type}`. A **foreground** agent never
appears in `background_tasks` at all — its entry was `[]`.

Constraints inherited from the marketplace: bash 3.2, `set -u`, no `source` of config, `jq`
recommended but never required, non-macOS must no-op, and every byte of state confined to
`$TMPDIR` so `/plugin uninstall` stays a complete revert.

## Goals / Non-Goals

**Goals:**

- Every dispatch cue names the delegated work; every completion that is voiced names it too.
- A completion is voiced at the moment the result reaches the parent session.
- A fan-out that goes quiet under the name cap still gets one summary when it drains.
- Retire the TTL-wedge failure mode in in-flight accounting by using the harness's own list.
- Degrade to exactly today's behaviour when `jq`, `background_tasks`, or `say` is unavailable.

**Non-Goals:**

- Summarising or speaking an agent's *result*. `last_assistant_message` is available but
  speaking it is unbounded, model-authored prose; only the purpose is spoken.
- Duration-based phrasing for agents (explicitly declined; `Stop` keeps its own duration gate).
- Any new dependency, config file, or state outside `$TMPDIR`.
- Reacting to `SubagentStart`. It carries no description, and every state transition it could
  mark is already covered by `PreToolUse` (purpose) and `PostToolUse` (identity).

## Decisions

### Voice foreground agents at `PostToolUse`, background agents at `SubagentStop`

A foreground agent's `PostToolUse` fires at completion with both `tool_input.description` and
`tool_response.status == "completed"` — one event carrying purpose and outcome, and semantically
exactly "the result returned to the parent". Its `SubagentStop` fires *earlier* and lacks the
description, so it cannot name the agent.

A background agent is the mirror image: `PostToolUse` fires ~2 ms after dispatch as an
`async_launched` acknowledgement (voicing it as a finish would be flatly wrong), while
`SubagentStop` is the first event carrying both identity and — via the self-entry in
`background_tasks` — the description.

Double-speak is prevented by the same field that supplies the description: at `SubagentStop`, a
self-entry present in `background_tasks` means background (speak here); absent means foreground
(stay silent, `PostToolUse` will speak). *Alternative considered:* branching on
`tool_input.run_in_background`. Rejected — it is absent when the model omits the parameter, so
it cannot distinguish "foreground" from "defaulted to background".

### `background_tasks` as the in-flight source, markers as fallback

In-flight becomes `background_tasks | select(.type == "subagent") | select(.id != agent_id)` —
authoritative, self-healing, and free of the stale-marker problem the TTL knob exists to paper
over. The existing `spawn.d`/`done.d` counting is retained verbatim for payloads without the
field, and a new `agents.d/<agent_id>` marker (content: the description), written at the
background `PostToolUse`, covers the residual race where the registry reaps an agent before its
`SubagentStop` arrives. `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` keeps governing the fallback markers.

*Alternative considered:* deleting the markers outright. Rejected — it would silently degrade
the subagent cues on any Claude Code that predates the field, with no signal to the user.

### Name cap of 3, with the roll-up covering what the cap suppressed

Individual completions are named while at most `CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP` (default 3)
agents are in flight. Above it, cues are suppressed and a per-turn flag records that naming was
withheld. The roll-up fires when in-flight reaches zero **and** either that flag is set or a
waiting cue was spoken this turn. When every agent in a batch was named individually, the last
name *is* the all-clear and no roll-up is spoken.

*Alternative considered:* rolling up on every drain. Rejected as an extra utterance on small
fan-outs the user was watching anyway.

### Serialise cues through a create-only lock

Per-agent completion cues make simultaneous `say` invocations likely for the first time; macOS
speaks them concurrently and unintelligibly. A cue acquires a create-only `$TMPDIR` lock dir,
speaks, and releases. A cue that cannot acquire within a short bounded wait is **dropped, not
queued** — a backlog of stale cues is worse than a missing one. The lock carries its own epoch
so a crashed holder is reclaimed rather than deadlocking the plugin into permanent silence.

### Sanitise descriptions before speaking

Descriptions are model-authored free text (capped at 1000 chars by the harness). Before
reaching `say` they are stripped of control characters, collapsed on whitespace, and truncated
at `CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX` (default 60) on a word boundary. They are always passed
as a single quoted argument to `say`, never interpolated into a command string, and `say`'s
`[[...]]` command syntax is neutralised so a description cannot inject prosody directives.

## Risks / Trade-offs

- **More talking.** Naming every completion is strictly more speech than silence → the name cap
  bounds it, `CLAUDE_VOICE_NOTIFY_AGENT_NAMES=off` restores the 0.5.0 anonymous cues verbatim,
  and `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` still disables the whole path.
- **Payload shapes are version-specific.** `background_tasks` and the `async_launched` response
  were verified on 2.1.220 and are not part of a stable contract → every read is optional with a
  fallback chain (self-entry → `agents.d` marker → `agent_type` → generic cue), so a shape change
  degrades to today's behaviour rather than breaking.
- **`agent_completed` notifications could not be verified.** They are emitted by the interactive
  background-agent view, and the headless probe produced no `Notification` event → the
  classifier extension is additive allow-list matching; unmatched wording still falls through to
  the existing neutral cue, so a wrong guess costs nothing.
- **A dropped cue under lock contention.** A tight fan-out may lose a name → the drain roll-up
  still reports the batch, so the user is never left with nothing.
- **Descriptions can be poor.** A vague description ("Investigate") makes a vague cue → out of
  scope; the plugin speaks what the caller wrote and never invents a name.

## Migration Plan

Additive within one plugin. Installing the new version replaces the manifest's hook set (adding
`PostToolUse`/`Agent`); `/plugin uninstall` remains the complete revert since no state leaves
`$TMPDIR`. Rollback is reinstalling the prior version, or setting
`CLAUDE_VOICE_NOTIFY_AGENT_NAMES=off` to get 0.5.0 phrasing from the new code. The change alters
one spec-mandated behaviour (silence on completion), so `voice-notify-subagent-cues` is updated
in the same PR rather than left contradicting the implementation.

## Open Questions

None outstanding. The foreground/background split, the cap value, the roll-up trigger, the
tracking source, and the overlap policy were each decided against the probe results and
confirmed with the user before this document was written.
