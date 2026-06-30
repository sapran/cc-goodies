## Context

This marketplace's `statusline` plugin and the separate `caveman` plugin both want the
Claude Code `statusLine` slot, of which there is exactly one. The caveman plugin ships
`caveman-statusline.sh`, which reads `~/.claude/.caveman-active` (a whitelisted mode flag)
and `~/.claude/.caveman-statusline-suffix` (a pre-rendered token-savings string) and prints
an orange `[CAVEMAN]` / `[CAVEMAN:MODE]` badge with an optional savings suffix. A user who
wires this marketplace's richer `statusline-command.sh` loses that badge entirely.

`statusline-command.sh` is performance-tuned around a one-`jq`-parse budget, renders in two
modes (`enriched` two-line, `lean` single-line) resolved each render from
`~/.claude/statusline.conf`, and is written to fail soft on every external read. The caveman
state files already carry careful hardening because they are echoed to the terminal each
render. This change folds the badge into the enriched render path, reusing the caveman state
files by fixed path, so both plugins coexist under one command.

## Goals / Non-Goals

**Goals:**
- Render the caveman badge (and its savings suffix) at the end of the enriched L2 line when
  the caveman flag is active, matching the caveman plugin's badge appearance.
- Zero behavioural change when the caveman flag is absent — the overwhelmingly common case,
  since caveman is a separate, non-bundled marketplace.
- Preserve the one-`jq`-parse budget: the badge path uses plain-bash file reads only.
- Reuse the caveman plugin's exact hardening (symlink refusal, read cap, charset strip, mode
  whitelist) so the new read introduces no terminal-escape-injection surface.
- Keep the opt-out ergonomic and consistent with the caveman plugin's own env knob.

**Non-Goals:**
- Rendering the badge in `lean` mode. Lean is the deliberately minimal mode and its spec
  enumerates its single line's contents; adding the badge there would modify the
  `statusline-mode-toggle` capability. Out of scope here.
- Taking a hard dependency on, installing, or version-coupling to the caveman plugin. The
  coupling is a soft, one-directional read of two files by conventional path.
- Re-deriving or recomputing the savings number. The statusline only renders the token the
  caveman plugin already wrote; it never shells out to `node` or runs `/caveman-stats`.
- Changing how the mode flag is written. The caveman plugin owns `.caveman-active`; this
  change is read-only against it.

## Decisions

### Read the caveman state files by fixed path rather than coupling the plugins

The badge reads `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active` and `…/.caveman-statusline-suffix`
directly. *Alternative considered:* a formal hand-off (the caveman plugin writes a
statusline-agnostic file, or exposes a shared contract). Rejected as over-engineering for two
files whose format and location are already stable and already consumed by the caveman
plugin's own statusline. The fixed-path read keeps the dependency one-directional and lets the
feature work the instant both plugins are installed, with no wiring step. The cost is a
documented coupling to two caveman path/format conventions — recorded in
`docs/shell-safety.md` and both READMEs so a future caveman change knows this consumer exists.

### Replicate the caveman hardening verbatim, do not weaken it

The flag/suffix reads carry the same controls the caveman script uses: refuse symlinks
(`[ -L ]`), cap the read (`head -c 64`), lower-case and strip the flag to `[a-z0-9-]`, strip
control bytes from the suffix, and validate the mode against the whitelist before emitting
anything. *Alternative considered:* trust the files because the caveman plugin wrote them.
Rejected — the statusline cannot assume the writer; a local attacker (or a corrupted file)
could plant escape sequences that the statusline would otherwise paint to the terminal every
keystroke. The statusline already applies exactly this discipline to `statusline.conf` and its
cache files, so this is consistent with the script's existing posture, not new ceremony.

### Always-on when the flag is present, with an env-var opt-out

The badge renders whenever `.caveman-active` is present and valid; `STATUSLINE_CAVEMAN=0`
suppresses the whole segment and `CAVEMAN_STATUSLINE_SAVINGS=0` suppresses only the savings
suffix. *Alternatives considered:* (a) opt-in via a `STATUSLINE_CAVEMAN=1` key in
`statusline.conf`. Rejected — it forces configuration for the obvious case (you installed
caveman; you want its badge) and the absent-flag fail-soft already means non-caveman users see
nothing. (b) A new conf key instead of an env var. Rejected for the savings knob specifically:
reusing the caveman plugin's existing `CAVEMAN_STATUSLINE_SAVINGS` name means a user who
already set it keeps the same behaviour after switching to this statusline. The whole-segment
opt-out is a sibling env var (`STATUSLINE_CAVEMAN`) for symmetry; an env var (not a conf key)
keeps the badge path free of any extra file parse.

### Enriched-only placement at the very end of L2

The badge is appended after the rate-limit gauges on the second line, inside the existing
enriched render block. *Alternative considered:* L1 (after the task snippet) or L2 start
(before the model). The end-of-L2 position keeps the mode indicator with the "how this session
runs" information (model, effort, gauges) and places it where it cannot push apart the more
frequently scanned cwd/branch/task segments. Confining it to the enriched block means the lean
path does strictly less work, honouring the lean-mode guarantee untouched.

## Risks / Trade-offs

- **Path/format coupling to the caveman plugin** → If caveman renames `.caveman-active`, its
  value whitelist, or the suffix file, the badge silently stops rendering (fail-soft, no
  error). Mitigation: document the coupling in `docs/shell-safety.md` and both READMEs; keep
  the read fail-soft so a drift degrades to "no badge", never to a broken statusline.
- **Whitelist drift** → A future caveman mode not in the replicated whitelist renders no badge
  until the statusline's list is updated. Mitigation: mirror the exact list and add a test that
  pins it; the failure mode is a missing badge, not a security hole or crash.
- **Per-render file reads** → Two extra `stat`/`head` reads per enriched render. Mitigation:
  they are plain-bash, no `jq`, and gated so they short-circuit immediately when the flag file
  is absent (the common case) — negligible against the transcript reads enriched already does.
- **Terminal-escape injection via planted files** → A hostile `.caveman-active`/suffix could
  carry escape sequences. Mitigation: the replicated hardening (symlink refusal, read cap,
  charset/control strip, mode whitelist) neutralises this before any byte is emitted; covered
  by dedicated tests.
