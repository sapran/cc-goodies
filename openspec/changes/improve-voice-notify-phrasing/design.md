## Context

`voice-notify` is a three-file macOS plugin (`plugin.json`, `scripts/notify.sh`,
`README.md`). Two inline hooks fire `notify.sh`: `Notification` (speaks a first-person
attention reason, composed as `lead + reason`) and `Stop` (speaks one of 10 flat
sign-offs). The script already establishes the plugin's contract: fail-open mute switch,
non-macOS no-op, voice verification with system-default fallback, a shell-agnostic awk
`pick()` selector, and a `jq` first-person transform for the notification message.

Two weaknesses motivate this change. (1) The `Stop` branch is a flat, context-free list
that reads as robotic over a session and fires on *every* turn — including quick ones
where the user is present, which is pure noise. (2) The notification first-person
transform ends in a catch-all `gsub("Claude"; "I")` that can mangle unrecognised wording
(e.g. "Claude Code is…" → "I Code is…").

Constraints (from CLAUDE.md and the plugin's own contract): bash 3.2-compatible,
`#!/bin/bash` + `set -u`, must degrade gracefully and never hard-fail a workflow; config
precedence is env var → default with **no** sourced conf file; `jq` optional (fail open);
zero new dependencies; nothing written outside the plugin dir except exempt `$TMPDIR`
caches, preserving `/plugin uninstall` as the full revert.

## Goals / Non-Goals

**Goals:**
- More natural-sounding cues (cadence varies; tone fits the situation; spoken not read).
- More diversity from *fewer* maintained lines (multiplicative, not additive).
- Speak in the away-worthy moments and stay quiet when the user is plainly present.
- Harden the first-person transform against unrecognised messages.
- Keep the plugin simple: zero new deps, env-var-only config, clean no-ops everywhere.

**Non-Goals:**
- Bigger flat phrase lists (additive variety that stays robotic).
- Brand-new chatty hook events beyond the one `UserPromptSubmit` timestamp writer.
- LLM/Ollama-generated phrasing — breaks the instant/offline/zero-dependency contract.
- Cross-platform TTS (Linux `spd-say`/`espeak`); macOS-only no-op stays as-is.
- A debounce/idle daemon or transcript parsing.

## Decisions

### D1 — One `compose(garnish_pool, core_pool)` function for both branches

Replace the two ad-hoc paths with a single composer: draw a core (always), draw a garnish
with probability `p` (default ~0.4), join with a prosody pause. `Notification`'s core is
the reason; `Stop`'s core is a sign-off. This is *less* code than two bespoke branches and
yields ~5×8≈50 forms from ~13 lines per context.

*Alternatives:* keep two branches and just enlarge pools (rejected: additive, still
robotic, more lines); full templating grammar with multiple slots (rejected: combos go
ungrammatical — "Hey there, done and dusted, back to you"; over the simplicity budget).

*Why probabilistic garnish:* a garnish that fires every time becomes a formula. ~40%
keeps it human (sometimes "Done", sometimes "Okay, that's done"). Frequency is an env
knob.

### D2 — Context-subtype routing keyed off the existing message / duration

`Notification` routes on the `.message` text: a permission subtype, an idle/waiting
subtype, else neutral. `Stop` routes on turn length (D4). Routing picks *which* small
pool to compose from; D1 then varies within it. Naturalness comes from fit, so we spend
the pool budget on situational tone rather than raw count.

*Alternatives:* a single shared pool for all subtypes (rejected: a brisk "Quick one!" for
an idle wait feels wrong); regex-heavy classification (rejected: keep matching to a couple
of `case`/glob checks for bash-3.2 simplicity and fail to neutral).

### D3 — Rewrite the first-person transform to be allow-list, not catch-all

Match only known message shapes (permission, waiting) and emit a curated first-person
core; drop the final `gsub("Claude"; "I")` catch-all. Unrecognised → neutral fallback.
Keeps `jq` optional: no `jq` ⇒ neutral fallback, exactly as today.

*Alternatives:* keep the catch-all but order more rules first (rejected: still coupled to
Claude Code's exact wording, still mangles the unseen case). Treating unknown messages as
neutral is safer than best-effort rewriting.

### D4 — Duration gate via a `$TMPDIR` timestamp + one `UserPromptSubmit` hook

Add a `UserPromptSubmit` hook that writes `epoch_seconds` to
`$TMPDIR/vn-<session_id>.start`. On `Stop`, read it, compute elapsed, then `rm` it.
Below threshold (default ~20s) ⇒ stay silent. At/above ⇒ speak, choosing a duration-aware
core pool. Missing/unreadable start ⇒ speak with the default pool (fail-audible).
`session_id` comes from the hook JSON on stdin; `$TMPDIR` files are CLAUDE.md-exempt from
teardown.

This is the keystone: the same timestamp both **suppresses quick-turn noise** (the main
UX win) and **enables duration-relative phrasing** (the main naturalness win).

*Alternatives:* read the transcript to time the turn (rejected: heavy, fragile, over
budget); probabilistically speak Stop X% of the time (rejected: unreliable — you'd miss
the one cue you cared about); a persistent debounce daemon (rejected: state outside
`$TMPDIR`, breaks clean-uninstall). Time source is `date +%s` (epoch math is bash-3.2
safe).

### D5 — Prosody via macOS `say` inline silence

Join garnish and core with a short `[[slnc NNN]]` silence (≈250ms). `say` honours it;
it must never be spoken as literal text. Since the plugin is macOS-only at the `say`
gate, no portability shim is needed; the pause string lives next to the `speak()` helper.

*Alternative:* control rate with `-r` (rejected for now: changes the whole voice, more
intrusive than a single inter-clause pause; can revisit).

### D6 — Config surface stays env-var-only

New knobs join the existing pattern (env var → default), no conf file, no `source`:
- `CLAUDE_VOICE_NOTIFY_QUIET_UNDER` — Stop silence threshold in seconds (default ~20).
- `CLAUDE_VOICE_NOTIFY_GARNISH_PCT` — garnish probability 0–100 (default ~40).
Existing `CLAUDE_VOICE`, `CLAUDE_VOICE_NOTIFY=off` semantics unchanged. README documents
each. (Final names confirmed at implementation; keep the `CLAUDE_VOICE_NOTIFY_*` prefix.)

## Risks / Trade-offs

- **`UserPromptSubmit` hook fires on plain chat, not just tool work** → start file is
  written every prompt; that's fine — elapsed is still real wall-clock for the turn, and
  the gate is about presence, not tool activity.
- **Threshold defaults won't suit everyone** (fast typists vs long walk-aways) → it's an
  env knob; default chosen conservatively (~20s) and documented.
- **Stale `$TMPDIR` start files** if a `Stop` never fires (crash) → harmless: next `Stop`
  reads a stale-but-bounded elapsed or the file is absent → fail-audible path; OS clears
  `$TMPDIR` anyway.
- **`session_id` missing/garbled from stdin** → fall back to unknown-duration (speak);
  never key a path on an empty id (guard before building the filename).
- **Two near-simultaneous fires re-seed awk in the same second** → identical phrase
  possible (pre-existing `pick()` trait); acceptable, not worsened.
- **Adding a hook changes `plugin.json`** → only ships if the duration gate ships; the
  phrasing-only moves (D1–D3, D5) need no manifest change, so they can land first if we
  choose to stage.
- **Reduced Stop chatter is a behaviour change** users might notice → documented in
  README/CHANGELOG; recoverable by setting the threshold to 0 (speak every turn).

## Migration Plan

1. Land D1–D3 + D5 (phrasing + transform hardening + prosody) — script-only, no manifest
   change, no new state. Safe, immediately better, fully reverted by `/plugin uninstall`.
2. Land D4 + D6 (duration gate + knobs) — adds the `UserPromptSubmit` hook to
   `plugin.json` and the `$TMPDIR` read/write. Bump plugin version; update README,
   marketplace description, CHANGELOG.
3. Validate per CLAUDE.md: `bash -n` + `shellcheck` on the script; `jq empty` on
   `plugin.json` and `marketplace.json`; synthetic-stdin tests asserting exit codes and
   spoken/silent outcomes (dry-run with `say` stubbed) across subtypes, threshold
   boundaries, missing-`jq`, non-macOS, and mute.

Rollback: revert the commits or `/plugin uninstall` — no durable external state to undo.

## Open Questions

- Final default for the silence threshold — 20s, or shorter (e.g. 12–15s)?
- Should `Notification` also respect a (separate, shorter) duration/quiet rule, or always
  speak? Current plan: `Notification` always speaks (it's the "needs you" channel); only
  `Stop` is gated.
- Stage D1–D3/D5 and D4/D6 as two commits/PRs, or ship together? Tasks assume one change,
  two logical commits.
