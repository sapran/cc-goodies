# Design — waiting-on-subagents cue

## Context

`voice-notify` already distinguishes three states by ear: attention (`Notification`),
turn-end (`Stop`), and subagent-dispatch (`PreToolUse(Agent)`, a debounced "handing off"
cue). The gap is the **turn-boundary-with-work-outstanding** state: the main turn ends while
background subagents keep running, and the `Stop` arm speaks a turn-end sign-off — a false
"finished".

The prior change (`distinguish-subagent-cue`, archived 2026-07-02) deliberately shipped no
`Stop` guard because its spike found `Stop` fires only at true turn-end. That was correct for
**foreground/blocking** subagents. The **background-subagent** mode invalidates it: docs state
`Stop` fires without waiting for background subagents; `SubagentStop` fires per background
completion. The user observes the false sign-off directly.

## Verified facts (Claude Code hook model)

- `SubagentStop` exists, fires once per subagent completion, payload includes `session_id`
  and a unique `agent_id`.
- `Stop` fires at main-turn end and does **not** block on background subagents.
- Dispatch tool name is `Agent`; `PreToolUse(Agent)` fires once per spawn, including parallel
  spawns in one assistant message.
- `PreToolUse(Agent)` has **no** `agent_id` (the agent does not exist yet), so spawn markers
  cannot be paired one-to-one with `SubagentStop` done markers. We therefore count both sides
  independently and subtract.

## Decision D1 — in-flight accounting via two create-only marker dirs

Two per-session directories under `$TMPDIR`:

- `vn-<sid>.spawn.d/` — `dispatch` arm creates one file per spawn, uniquely named
  `<epoch>.<pid>.<rand>`. Distinct name per concurrent hook ⇒ no read-modify-write race.
- `vn-<sid>.done.d/` — `subagent-stop` arm creates one file named by the sanitized
  `agent_id`. Keying by `agent_id` makes it **idempotent**: a duplicate/retried `SubagentStop`
  for the same agent overwrites the same file and still counts once.

**in-flight = max(0, count(spawn.d) − count(done.d)).** Clamp at zero so a toggled mute or a
done-without-spawn edge can never go negative.

Rejected alternative: a single integer counter file incremented/decremented in place. Async
hooks fire concurrently; read-modify-write on one file races and loses updates. The marker-dir
scheme sidesteps it — every writer touches a distinct path, creation only.

## Decision D2 — Stop branches on in-flight, waiting cue bypasses the duration gate

Per the user's decision, **any** `Stop` with in-flight > 0 speaks the waiting cue, regardless
of `CLAUDE_VOICE_NOTIFY_QUIET_UNDER`. Rationale: the notable event is "I paused with work
outstanding", which is worth announcing even after a short turn; the duration gate exists to
avoid nagging on quick *finished* turns, which this is not. The start-timer file is still
consumed as today. When in-flight == 0, the arm is unchanged (duration gate, standard/long
sign-off pools).

Foreground agents: all `SubagentStop`s precede `Stop`, so spawn == done → in-flight 0 → normal
sign-off. **No regression** on the common path.

## Decision D3 — TTL prune for self-healing

A spawned agent that never emits `SubagentStop` (crash, or a `PreToolUse`-then-denied agent)
would leave an unmatched spawn marker and wedge in-flight > 0 for the rest of the session. At
`Stop`, before counting, prune entries in **both** dirs older than
`CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` seconds (default 3600) by mtime
(`find … -mmin +N -delete`). Pruning both keeps in-flight correct for currently-relevant
agents and bounds directory growth over a long session. Trade-off: an agent running longer
than the TTL is treated as finished (may miss its waiting cue). One hour is comfortably longer
than a typical background agent; the knob is configurable.

## Decision D4 — reuse the existing subagent mute; one new knob

`CLAUDE_VOICE_NOTIFY_SUBAGENT=off` already gates the dispatch cue; it now also gates the whole
accounting path (spawn write, done write, Stop in-flight check). Off ⇒ `Stop` behaves exactly
as before this change. Only one new env var: `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` (seconds,
digit-validated, default 3600). No config file — consistent with the plugin's precedence rule
(env var → built-in default).

## Decision D5 — the waiting cue is its own pool

`WAITING_CORES` is distinct from `STOP_CORES`/`STOP_LONG_CORES` (turn-end) and from
`SUBAGENT_CORES` (dispatch/"handing off"). Dispatch announces the *start* of the hand-off;
the waiting cue announces the *turn boundary with work still outstanding*. Different moments,
different words, so the four states stay audibly separable. Assembled through the existing
`compose()`/garnish/prosody like every other cue.

## Open questions / non-goals

- **Second `Stop` after background agents finish**: if the harness re-invokes the main agent
  on completion and that re-invocation ends in its own `Stop`, in-flight is then 0 and the
  normal sign-off speaks — the real "done". We do not add logic to force a sign-off from
  `SubagentStop` itself; `SubagentStop` stays silent. If no such second `Stop` occurs, the
  user has at least heard the waiting cue and not a false "done"; that is the fix's scope.
- **jq-missing**: as elsewhere in the plugin, session/agent id resolution needs `jq`; without
  it the arm falls back to a shared `nosess` key and a unique done-marker name, degrading to
  best-effort counting rather than erroring.
