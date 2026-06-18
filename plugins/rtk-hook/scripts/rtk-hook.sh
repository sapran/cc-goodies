#!/bin/bash
# cc-goodies / rtk-hook
# Run RTK (Rust Token Killer) as a managed PreToolUse hook on the Bash tool.
#
# RTK rewrites Bash commands into a token-cheaper proxy form (e.g. `git status`
# -> `rtk git status`). Upstream you wire `rtk hook claude` straight into
# settings.json; this plugin owns that wiring instead, so RTK installs and
# uninstalls like every other cc-goodies plugin.
#
# This wrapper just hands the hook's stdin JSON to `rtk hook claude` and relays
# its stdout/exit. If rtk is NOT on PATH it does nothing and exits 0 (fails
# OPEN) — so the plugin is harmless for anyone who hasn't installed rtk, and a
# missing/renamed binary never blocks a Bash command.
#
# Exit codes are whatever rtk returns (normally 0 = allow, possibly with a
# rewritten command on stdout). We never invent a blocking exit code ourselves.

set -u

# rtk absent -> no-op, let the command run unchanged.
command -v rtk >/dev/null 2>&1 || exit 0

# Hand stdin straight to rtk and become it (its stdout/exit are the hook's).
exec rtk hook claude
