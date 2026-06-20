#!/bin/bash
# cc-goodies / rtk-hook
# Run RTK (Rust Token Killer) as a managed PreToolUse hook on the Bash tool.
#
# RTK rewrites Bash commands into a token-cheaper proxy form (e.g. `git status`
# -> `rtk git status`). Upstream you wire `rtk hook claude` straight into
# settings.json; this plugin owns that wiring instead, so RTK installs and
# uninstalls like every other cc-goodies plugin.
#
# This wrapper hands the hook's stdin JSON to `rtk hook claude` and relays its
# stdout/exit. Two ways it stays out of the way, both fail OPEN:
#   - paused  (RTK_HOOK_DISABLE=1) -> no-op, the command runs unrewritten;
#   - rtk NOT on PATH              -> no-op, exit 0.
# So the plugin is harmless for anyone without rtk, and a missing/renamed binary
# never blocks a Bash command. We never invent a blocking exit code ourselves;
# exit codes are whatever rtk returns (normally 0 = allow).
#
# Config, lowest to highest precedence:
#   built-in default  ->  ~/.claude/rtk-hook.conf (KEY=VALUE)  ->  environment
#
#   RTK_HOOK_DISABLE=1   # pause RTK without uninstalling (see /rtk-hook)

set -u

# --- Effective configuration (env > conf file > default) --------------------
# The conf file is read with a safe KEY=VALUE parser, never `source`d, so a
# stray ~/.claude/rtk-hook.conf cannot execute arbitrary shell in the hook.
CONF="$HOME/.claude/rtk-hook.conf"
conf_get() {
  [ -f "$CONF" ] || return 0
  line=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$CONF" 2>/dev/null | tail -n1)
  [ -n "$line" ] || return 0
  val=${line#*=}
  val=${val#"${val%%[![:space:]]*}"}   # ltrim
  val=${val%"${val##*[![:space:]]}"}   # rtrim
  val=${val#\"}; val=${val%\"}          # strip surrounding double quotes
  val=${val#\'}; val=${val%\'}          # strip surrounding single quotes
  printf '%s' "$val"
}

DISABLE="${RTK_HOOK_DISABLE:-$(conf_get RTK_HOOK_DISABLE)}"

# Escape hatch: paused -> no-op, let the command run unrewritten.
[ -n "${DISABLE:-}" ] && [ "$DISABLE" != "0" ] && exit 0

# rtk absent -> no-op, let the command run unchanged.
command -v rtk >/dev/null 2>&1 || exit 0

# Hand stdin straight to rtk and become it (its stdout/exit are the hook's).
exec rtk hook claude
