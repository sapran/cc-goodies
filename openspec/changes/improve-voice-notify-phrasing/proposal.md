## Why

voice-notify's spoken cues are functional but feel robotic over a long session: the
`Stop` branch picks from a flat pool of 10 fixed phrases disconnected from what just
happened, and it fires after **every** turn — including 3-second ones where the user is
sitting right at the terminal. A voice cue's value is inverse to how likely the user is
already looking; talking on every quick turn is noise, not help. We want phrasing that is
more natural and more varied, and that speaks in more of the genuinely away-worthy
moments — without growing the plugin's complexity or adding dependencies.

## What Changes

- **Unify both event branches under one `garnish? + core` composition.** A single
  compose function joins an optional short interjection ("garnish", fired ~40% of the
  time) with an always-present core phrase. Multiplicative variety from small pools
  (e.g. ~5 garnishes × ~8 cores ≈ 50 outputs from 13 lines) instead of one flat list.
  The probabilistic garnish is the naturalness lever — a person sometimes just says
  "Done" and sometimes "Okay, that's done."
- **Route phrase pools by context subtype** so tone fits the situation:
  - `Notification`: distinguish "needs permission" (brisk) from "waiting for input"
    (gentle), falling back to a neutral pool.
  - `Stop`: distinguish short vs long turns (see duration gate).
- **Add a near-free macOS `say` prosody pause** (`[[slnc …]]`) between garnish and core
  for human cadence — zero new phrases, zero dependency.
- **Duration gate for `Stop` (optional, flagged).** A `$TMPDIR` timestamp file written on
  `UserPromptSubmit` and read on `Stop` lets the hook stay **silent on quick turns**
  (under a configurable threshold ≈ 20s, when the user is present) and speak only when the
  user likely stepped away — which simultaneously unlocks duration-relative phrasing
  ("phew, finally" vs "done"). One mechanism, two wins (UX + naturalness).
- **Config stays env-var only**, preserving the existing precedence and zero-config-file
  contract. New optional knobs (threshold, garnish frequency) follow the same pattern.

Non-goals (explicitly out of scope): growing flat phrase lists, adding brand-new chatty
hook events, and LLM/Ollama-generated phrasing (breaks the instant/offline/zero-dependency
contract).

## Capabilities

### New Capabilities
- `voice-notify-phrasing`: how voice-notify composes, varies, and times its spoken cues —
  the garnish+core composition model, context-subtype routing, prosody, the duration gate
  and silence-on-quick-turns behaviour, and the configuration surface governing them.

### Modified Capabilities
<!-- None: voice-notify has no existing spec; this is the first one. -->

## Impact

- **Plugin**: `plugins/voice-notify/` — `scripts/notify.sh` (rewritten phrase logic,
  prosody, optional duration read), `.claude-plugin/plugin.json` (add a `UserPromptSubmit`
  hook only if the duration gate ships), `README.md` (document new env knobs + duration
  behaviour).
- **Marketplace**: `.claude-plugin/marketplace.json` description and root `README.md` /
  `CHANGELOG.md` if user-visible behaviour changes; `plugin.json` version bump.
- **Dependencies**: none added. macOS `say` + optional `jq` unchanged. Non-macOS and
  muted paths remain clean no-ops.
- **State**: at most one ephemeral `$TMPDIR/vn-<session>.start` file per session
  (CLAUDE.md exempts `$TMPDIR` caches from teardown); nothing written outside the plugin
  dir, so `/plugin uninstall` remains the full revert.
