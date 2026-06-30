## Why

Claude Code allows only one `statusLine` command, so a user who runs both the
`statusline` plugin and the separate `caveman` plugin cannot see both — the caveman
plugin's own `caveman-statusline.sh` and this marketplace's `statusline-command.sh`
compete for the single slot, and whichever is wired wins. Users who want the rich
two-line statusline therefore lose the `[CAVEMAN]` mode indicator (and its
token-savings readout) the moment they pick this plugin. Folding the badge into this
statusline lets the two coexist in one command, with zero cost when caveman is not
installed.

## What Changes

- `statusline-command.sh` gains a caveman-badge segment rendered at the **end of the
  enriched L2 line**, after the `c:`/`s:`/`w:` gauges — e.g.
  `Opus 4.8 (high)  c:42% s:10% w:5%  [CAVEMAN] ~38% saved`.
- The badge is read from the caveman plugin's existing state files —
  `~/.claude/.caveman-active` (the mode flag) and `~/.claude/.caveman-statusline-suffix`
  (the pre-rendered savings token) — using the **same hardening** the caveman script
  already applies: refuse symlinks, cap the read length, lower-case and strip to a
  safe character set, and whitelist the mode value so nothing outside the known set is
  ever echoed to the terminal.
- Rendering is **always-on when the flag is present** and opt-out via a
  `STATUSLINE_CAVEMAN=0` environment variable, mirroring the caveman plugin's
  `CAVEMAN_STATUSLINE_SAVINGS` opt-out. When the flag file is absent (caveman not
  installed or mode off) the statusline renders exactly as it does today.
- The badge segment uses **no `jq`** — plain-bash file reads only — preserving the
  script's one-jq-parse performance budget.
- **Lean mode is unchanged**: the badge is an enriched-mode-only addition, so the
  `statusline-mode-toggle` capability and its "lean does strictly less work" guarantee
  are not touched.
- README (plugin + root) and `docs/shell-safety.md` cross-reference updated to document
  the badge, its opt-out, and the cross-plugin coupling; CHANGELOG entry added.

## Capabilities

### New Capabilities
- `statusline-caveman-badge`: rendering of the caveman mode badge and optional
  savings suffix at the end of the enriched statusline's second line, sourced from the
  caveman plugin's state files, hardened against terminal-escape injection, opt-out via
  environment variable, and fully fail-soft (no badge, no error) when caveman is absent.

### Modified Capabilities
<!-- None. The badge renders only in enriched mode, leaving statusline-mode-toggle,
     statusline-severity-colours, and statusline-time-readouts requirements unchanged. -->

## Impact

- **Code**: `plugins/statusline/statusline-command.sh` (new badge segment, enriched
  path only); `plugins/statusline/tests/run.sh` (badge render / hardening / opt-out /
  fail-soft cases).
- **Cross-plugin coupling**: a soft, one-directional read of two caveman state files by
  fixed path. No hard dependency — the caveman plugin is in a separate marketplace and
  is neither required nor installed by this one; absence is the common case and renders
  nothing.
- **Docs**: `plugins/statusline/README.md`, root `README.md`, `docs/shell-safety.md`,
  `CHANGELOG.md`.
- **Versioning**: `statusline` `plugin.json` minor bump and marketplace
  `metadata.version` bump per the repo release flow.
- **No breaking changes**: existing installs with no caveman flag render byte-identically
  to today.
