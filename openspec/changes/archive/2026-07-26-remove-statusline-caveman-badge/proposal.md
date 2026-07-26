## Why

The `statusline-caveman-badge` capability exists solely to co-render the separate
[`caveman`](https://github.com/juliusbrussee/caveman) plugin's mode badge inside this
marketplace's statusline, because Claude Code allows exactly one `statusLine` command.
The maintainer has uninstalled caveman entirely — plugin, marketplace registration,
skills, agents, and its state files are gone — so the badge can never render again:
`caveman_badge()` short-circuits on the first `[ -f "$flag" ]` test on every single
render, forever.

What remains is a dead segment that still costs something. It carries a cross-plugin
coupling to two file paths and a value format this repo does not own, ~43 lines of
hardening written to defend against terminal-escape injection through those files, 8
of the statusline harness's 19 cases, a documented capability, and a `render()` helper
that word-splits an unquoted `$EXTRA_ENV` into the test environment (a shellcheck
suppression that exists only to set the two caveman opt-out variables). Removing the
feature deletes the coupling, the attack surface, and the maintenance claim in one
step.

## What Changes

- **BREAKING**: `statusline-command.sh` drops the `caveman_badge()` helper and its call
  site at the end of the enriched second line. The `STATUSLINE_CAVEMAN` and
  `CAVEMAN_STATUSLINE_SAVINGS` environment variables are no longer read; setting them
  has no effect. Users who still run caveman lose the badge from this statusline and
  must wire the caveman plugin's own `caveman-statusline.sh` into the `statusLine` slot
  instead.
- The enriched second line now ends with the `c:`/`s:`/`w:` gauges and their time
  suffixes. For every install without an active caveman flag — the case for all
  installs, since the flag file is what gated the segment — the rendered output is
  **byte-identical to today**.
- The `statusline` harness drops the 8 badge cases (`l`..`s`), the `CAVEMAN_MODES`
  whitelist pin, and the `cm_stdin` helper, along with the now-unused `EXTRA_ENV`
  splice in `render()` and its `shellcheck disable=SC2086`.
- Docs drop the badge: the plugin README's "Caveman badge" section, the root README's
  statusline row, and the CHANGELOG gains a `Removed` entry under `[Unreleased]`.

## Capabilities

### Removed Capabilities
- `statusline-caveman-badge`: all seven requirements — badge rendering at the end of
  the enriched line, sourcing from the caveman state files, the mode-specific label,
  the escape-injection hardening, the savings suffix, the environment opt-outs, and the
  fail-soft-when-absent guarantee. Nothing replaces it; the statusline no longer reads
  any external plugin's state.

### Modified Capabilities
<!-- None. The badge was enriched-mode-only and always the final segment, so
     statusline-mode-toggle, statusline-severity-colours, and statusline-time-readouts
     keep their requirements verbatim: lean was already byte-identical, and no other
     segment's position was defined relative to the badge. -->

## Impact

- **Code**: `plugins/statusline/statusline-command.sh` (helper + call site removed);
  `plugins/statusline/tests/run.sh` (8 cases, 2 helpers, and the `EXTRA_ENV` splice
  removed — 19 cases become 11).
- **Cross-plugin coupling**: eliminated. This repo no longer reads
  `.caveman-active`, `.caveman-statusline-suffix`, or any file another plugin owns.
- **Docs**: `plugins/statusline/README.md`, root `README.md`, `CHANGELOG.md`.
- **Versioning**: `statusline` `plugin.json` `0.6.0` → `0.7.0` (the badge arrived in
  `0.6.0`; its removal is the mirror bump). Marketplace `metadata.version` is bumped at
  release time, not here — the CHANGELOG entry lands under `[Unreleased]`.
- **Behavioural risk**: none for anyone without an active caveman flag. Users still
  running caveman see the badge disappear from this statusline — that is the intent,
  and the caveman plugin's own statusline script remains available to them.
