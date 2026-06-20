#!/bin/bash
# cc-goodies / rtk-hook — hook test harness (no real rtk binary needed).
#
# Stubs `rtk` on a temp PATH (drains stdin, touches $RTK_MARKER, exits 0), so
# "did the hook invoke rtk?" reduces to "does the marker file exist?". Asserts
# the exit code and whether rtk ran across the wrapper's paths:
#
#   1. enabled + rtk present              -> rtk invoked, exit 0
#   2. paused via env RTK_HOOK_DISABLE=1   -> rtk skipped, exit 0
#   3. paused via ~/.claude/rtk-hook.conf  -> rtk skipped, exit 0
#   4. rtk absent                          -> no-op, exit 0
#
# Run: bash plugins/rtk-hook/tests/run.sh   (exit 0 = all pass)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../scripts/rtk-hook.sh"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"/tmp"}'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/.claude"

# Stub rtk: drain stdin like real `rtk hook claude`, record the call, allow.
cat > "$tmp/bin/rtk" <<'STUB'
#!/bin/bash
cat >/dev/null
echo ran >> "$RTK_MARKER"
exit 0
STUB
chmod +x "$tmp/bin/rtk"

WITH_RTK="$tmp/bin:/usr/bin:/bin"
NO_RTK="/usr/bin:/bin"

pass=0; fail=0
ran() { if [ -f "$1" ]; then echo 1; else echo 0; fi; }
assert() { # desc want_exit got_exit want_ran got_ran
  if [ "$3" = "$2" ] && [ "$5" = "$4" ]; then
    pass=$((pass + 1)); printf 'ok   — %s\n' "$1"
  else
    fail=$((fail + 1)); printf 'FAIL — %s (exit %s want %s; ran %s want %s)\n' "$1" "$3" "$2" "$5" "$4"
  fi
}

# 1) enabled + rtk present -> rtk invoked, exit 0
printf '%s' "$PAYLOAD" | env HOME="$tmp" PATH="$WITH_RTK" RTK_MARKER="$tmp/m1" bash "$HOOK"; e=$?
assert "enabled + rtk present -> rtk runs" 0 "$e" 1 "$(ran "$tmp/m1")"

# 2) paused via env -> rtk skipped, exit 0
printf '%s' "$PAYLOAD" | env HOME="$tmp" PATH="$WITH_RTK" RTK_MARKER="$tmp/m2" RTK_HOOK_DISABLE=1 bash "$HOOK"; e=$?
assert "paused via env RTK_HOOK_DISABLE=1 -> rtk skipped" 0 "$e" 0 "$(ran "$tmp/m2")"

# 3) paused via conf file -> rtk skipped, exit 0
printf 'RTK_HOOK_DISABLE=1\n' > "$tmp/.claude/rtk-hook.conf"
printf '%s' "$PAYLOAD" | env HOME="$tmp" PATH="$WITH_RTK" RTK_MARKER="$tmp/m3" bash "$HOOK"; e=$?
assert "paused via ~/.claude/rtk-hook.conf -> rtk skipped" 0 "$e" 0 "$(ran "$tmp/m3")"
rm -f "$tmp/.claude/rtk-hook.conf"

# 4) rtk absent -> no-op, exit 0
printf '%s' "$PAYLOAD" | env HOME="$tmp" PATH="$NO_RTK" RTK_MARKER="$tmp/m4" bash "$HOOK"; e=$?
assert "rtk absent -> no-op" 0 "$e" 0 "$(ran "$tmp/m4")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
