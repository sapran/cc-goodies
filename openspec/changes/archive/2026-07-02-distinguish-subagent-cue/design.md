## Context

`voice-notify` (plugins/voice-notify) is a single bash script `notify.sh` dispatched by an
event arg from three inline hooks declared in `plugin.json`:

- `UserPromptSubmit` → `start` — stamps a turn-start epoch in `$TMPDIR/vn-<sid>.start` (no
  speech), so `Stop` can time the turn for the quiet-on-quick-turns gate.
- `Notification` → `notification` — classifies `.message` (permission / idle / neutral) and
  speaks a first-person reason.
- `Stop` → `stop` — reads+removes the start file, computes elapsed, applies the duration gate
  (silent under ~20s; standard sign-off; long-turn sign-off), and speaks "your turn".

The script already has reusable machinery this change leans on unchanged: global mute
(`CLAUDE_VOICE_NOTIFY=off`), non-macOS no-op (`command -v say`), lazy voice resolution,
`pick`/`want_garnish`/`compose` (small pools × optional garnish × `[[slnc 250]]` pause), and
the ephemeral-`$TMPDIR` state pattern keyed by sanitised `session_id`.

There is **no** cue for the subagent-working state. The phrasing behaviour is captured in the
existing `voice-notify-phrasing` spec; this change adds a new `voice-notify-subagent-cues`
capability that reuses that machinery without modifying its requirements.

Verified hook facts (Claude Code docs, via claude-code-guide):
- `Stop` fires once per turn at agent stop; `SubagentStop` fires per subagent completion;
  there is also a `SubagentStart`. `PreToolUse` can match the subagent-dispatch tool.
- `SubagentStop` stdin carries `session_id`, `cwd`, `hook_event_name`, `agent_id`,
  `agent_transcript_path`, `tool_use_id`, `stop_hook_active`.
- **Undocumented / must verify by spike**: (a) whether `Stop` ever fires mid-turn while the
  main agent is suspended on subagents; (b) whether `Stop` double-fires right after the last
  `SubagentStop`; (c) the exact dispatch tool name in this Claude Code build (`Task` vs
  `Agent`) and that `PreToolUse`/`SubagentStart` actually fire here.

User decisions (this proposal):
- **Dispatch cue only** — announce when subagents start; stay silent on each finish.
- **Debounce to one cue** — a burst collapses to a single spoken cue.

## Goals / Non-Goals

**Goals:**
- Give the subagent-working state its own debounced, distinct voice cue.
- Keep the `Stop` "your turn" cue honest — never spoken as a side effect of a subagent pause.
- Reuse existing machinery; no config file; ephemeral `$TMPDIR` state only; `/plugin
  uninstall` stays a complete revert.
- Preserve all existing event behaviour and defaults (no breaking change).

**Non-Goals:**
- Per-subagent progress cues or counts ("two of three done") — explicitly declined.
- A "subagent finished" cue — silent by design.
- Non-macOS speech, or any new runtime dependency beyond `say`/`jq`.
- Reworking the `voice-notify-phrasing` duration gate.

## Decisions

### D1 — Trigger the dispatch cue from `PreToolUse` on the dispatch tool (primary)

Fire the new `dispatch` arm from a `PreToolUse` hook matched to the subagent-dispatch tool.
Rationale: `PreToolUse` fires *before* the subagents run — the earliest, most accurate moment
to say "this'll be a while" — and gives access to `tool_input`. Matcher value is resolved by
the spike (`Task`, `Agent`, or `Task|Agent`).

- Alternative: `SubagentStart`. Also viable and semantically clean, but fires per-subagent at
  init (same debounce need) and is newer/less certain in this build. Kept as fallback if the
  spike shows `PreToolUse` does not match the dispatch tool. Either source feeds the same
  debounced `dispatch` arm, so the trigger choice is isolated to `plugin.json`.

### D2 — Debounce via an ephemeral `$TMPDIR` marker, mtime-based

Reuse the existing state pattern: `$TMPDIR/vn-<sid>.dispatch` holds the epoch of the last
dispatch cue. On a `dispatch` event: if the file exists and `now - mtime < window`, suppress;
else speak and (re)write the file. Default window ~10s (`CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE`).
Rationale: matches the proven `vn-<sid>.start` mechanism (sanitised session id, digit-validated
contents, `$TMPDIR` only), needs no daemon or counters, and collapses a same-message fan-out
(several near-simultaneous `PreToolUse` fires) to one cue. Stale/corrupt file → treat as
"speak" (fail-audible), consistent with the existing duration gate.

- Alternative: count active subagents (increment on start, decrement on stop, speak only on
  0→1). More precise but needs reliable paired start/stop events and concurrency-safe counter
  writes from parallel hook processes — fragile in bash. Declined for the debounce window,
  which is simpler and good enough for "one cue per burst".

### D3 — Keep `Stop` honest, conditional on the spike

Desired end state (spec): "your turn" speaks only at true turn-end. Two cases:
- If the spike shows `Stop` fires **only** at genuine turn-end (expected), no code is needed —
  the requirement holds for free, and `SubagentStop` stays unwired (silent finishes).
- If the spike shows `Stop` (or a wired `SubagentStop`) would emit a premature "your turn"
  mid-turn, add a guard: the `stop` arm checks an "active subagents" marker (set on dispatch,
  cleared at genuine turn-end) and suppresses the sign-off while subagents are in flight.
This keeps the change minimal when the platform already behaves, and corrective only when it
does not — avoiding speculative complexity.

### D4 — Distinct phrase pool, reuse `compose()`

Add `SUBAGENT_CORES` (e.g. "Spinning up some helpers, back in a bit.", "Working with a few
helpers now.", "Handing some work off, give me a moment.") and route through the existing
`compose()` with a fitting garnish pool (likely the gentle/neutral lead-ins). No new prosody
or composition logic. Rationale: keeps the three states audibly distinct with zero new
phrasing code and inherits variety + the `[[slnc 250]]` pause automatically.

### D5 — Config: env-var only, two new knobs

`CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE` (seconds, default 10, digit-validated like the others)
and `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` (independent mute, defaults on). Global
`CLAUDE_VOICE_NOTIFY=off`, non-macOS no-op, and missing-`jq` fallback apply to the new arm by
construction (they are checked before the event switch / share the `session_id` helper). No
config file — honours the marketplace env-var-only rule and keeps `/plugin uninstall` total.

## Risks / Trade-offs

- **Dispatch tool name unknown (`Task` vs `Agent`)** → Spike confirms the live tool name and
  that `PreToolUse` matches it before any wiring; matcher is a one-line edit in `plugin.json`.
- **`Stop` may fire mid-turn on subagent pause (undocumented)** → Spike with a logging hook
  over a real 3-subagent fan-out; if confirmed, D3's guard suppresses the premature cue.
  This is likely the actual root of the user's "no difference" complaint, so the spike is
  load-bearing, not optional.
- **Possible `Stop` double-fire after last `SubagentStop`** → We leave `SubagentStop` unwired
  (silent finishes), so only `Stop` can speak the sign-off; the double-fire concern is moot
  for cues. Spike still notes the observed sequence.
- **Debounce window too short/long** → Tunable via env; default 10s collapses a same-message
  fan-out while still allowing a genuinely later second wave to re-announce.
- **Parallel hook processes writing the debounce file** → Same single-file, last-writer-wins
  pattern as `vn-<sid>.start`; a lost update at worst speaks one extra/one fewer cue —
  harmless. No locking needed.
- **Non-macOS / no `jq`** → New arm inherits the existing no-op and fallback paths; covered by
  tests mirroring the current non-macOS and mute cases.

## Migration Plan

Additive and default-safe. Ship behind the existing install path (inline hooks activate on
`/plugin install`/update). Rollback = `/plugin uninstall` or `CLAUDE_VOICE_NOTIFY_SUBAGENT=off`
(subagent cue only) / `CLAUDE_VOICE_NOTIFY=off` (everything). No state migration; the new
`$TMPDIR` marker self-clears. Version bumps: `voice-notify` `plugin.json` and the marketplace
`metadata.version`, per the release flow.

## Open Questions

- **Resolved by spike** (Claude Code 2.1.197, logging hook over a real 3-subagent fan-out):
  - Dispatch tool name is **`Agent`**, not `Task`; `PreToolUse` matcher `Agent` fires once per
    dispatch — this is the wired trigger (D1 confirmed, matcher = `Agent`).
  - **`Stop` fires exactly once, at true turn-end**, after all three `SubagentStop` — never
    mid-pause. So **D3's guard is not needed and is not shipped**; "your turn" is already honest
    on this build, and `SubagentStop` stays unwired (finishes silent).
  - Observed order: `PreToolUse:Agent ×3` (interleaved with `SubagentStart ×3`) → the subagents'
    own `PreToolUse:Bash ×3` → `SubagentStop ×3` → `Stop ×1`. The three dispatches land close
    together, so the 10s debounce collapses them to one cue as designed (D2 confirmed).
  - `PreToolUse:Agent` fires *before* `SubagentStart`, so it is the earliest signal and the
    chosen trigger over `SubagentStart`.
- Phrase-pool wording and the default debounce window (10s) are first guesses — easy to tune
  after listening in real use.
