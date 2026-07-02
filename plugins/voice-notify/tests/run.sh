#!/bin/bash
# voice-notify test harness.
# No test framework: pipe synthetic hook JSON to notify.sh with `say` stubbed and
# PATH isolated, then assert what was spoken (or that nothing was) and exit codes.
#
#   bash plugins/voice-notify/tests/run.sh
#
set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/notify.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Isolated tool dirs: one that looks like macOS (has `say`), one that doesn't.
bin_mac="$work/bin-mac"; bin_nomac="$work/bin-nomac"
mkdir -p "$bin_mac" "$bin_nomac"
for t in bash jq awk date grep tr cat rm sed mktemp; do
  p=$(command -v "$t" 2>/dev/null) || continue
  ln -sf "$p" "$bin_mac/$t"; ln -sf "$p" "$bin_nomac/$t"
done

# Fake `say`: answers the voice probe, logs whatever it's told to speak.
cat > "$bin_mac/say" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "-v" ] && [ "${2:-}" = "?" ]; then
  echo "Samantha            en_US    # Hello"; exit 0
fi
printf '%s\n' "${*: -1}" >> "$SAY_LOG"
STUB
chmod +x "$bin_mac/say"

pass=0; fail=0
spoke=""        # contents of the say log after a run
run() {          # run <event> <json> ; honours pre-exported env + PATH choice
  : > "$SAY_LOG"
  printf '%s' "$2" | PATH="$PATH_USE" TMPDIR="$work" bash "$script" "$1"
  rc=$?
  spoke=$(cat "$SAY_LOG" 2>/dev/null)
  return $rc
}
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no()   { fail=$((fail+1)); printf 'FAIL   %s\n     %s\n' "$1" "$2"; }

SAY_LOG="$work/say.log"; export SAY_LOG   # the `say` stub (a grandchild) reads this
PATH_USE="$bin_mac"
now() { date +%s; }
stamp() { echo "$1" > "$work/vn-sess.start"; }   # write a turn-start <epoch>
dstamp() { echo "$1" > "$work/vn-sess.dispatch"; }  # write a last-dispatch-cue <epoch>
J_PERM='{"message":"Claude needs your permission to use Bash","session_id":"sess"}'
J_IDLE='{"message":"Claude is waiting for your input","session_id":"sess"}'
J_WEIRD='{"message":"Claude Code is reticulating splines","session_id":"sess"}'
J_EMPTY='{"session_id":"sess"}'
J_SESS='{"session_id":"sess"}'
J_DISPATCH='{"session_id":"sess","tool_name":"Task"}'

# --- Notification: subtype routing + first-person + no mangling ---
export CLAUDE_VOICE_NOTIFY_GARNISH_PCT=0   # core-only -> deterministic assertions
run notification "$J_PERM"
case "$spoke" in *"I need your permission to use Bash"*) ok "permission -> first-person reason";; *) no "permission reason" "$spoke";; esac
run notification "$J_IDLE"
case "$spoke" in *"I'm waiting for your input"*) ok "idle -> first-person reason";; *) no "idle reason" "$spoke";; esac
run notification "$J_WEIRD"
case "$spoke" in "I need your attention.") ok "unknown wording -> neutral fallback (not mangled)";; *) no "weird not neutral" "$spoke";; esac
run notification "$J_EMPTY"
case "$spoke" in "I need your attention.") ok "empty message -> neutral fallback";; *) no "empty not neutral" "$spoke";; esac

# --- Garnish + prosody join ---
export CLAUDE_VOICE_NOTIFY_GARNISH_PCT=100
run notification "$J_PERM"
case "$spoke" in *", [[slnc 250]] "*"I need your permission"*) ok "garnish on -> prosody pause joins lead-in";; *) no "garnish/prosody" "$spoke";; esac
export CLAUDE_VOICE_NOTIFY_GARNISH_PCT=0

# --- Stop duration gate ---
export CLAUDE_VOICE_NOTIFY_QUIET_UNDER=20
stamp "$(( $(now) - 3 ))"        # 3s turn -> under threshold
run stop "$J_SESS"
[ -z "$spoke" ] && ok "quick turn (3s) -> silent" || no "quick turn should be silent" "$spoke"
[ -f "$work/vn-sess.start" ] && no "start file should be consumed" "exists" || ok "Stop consumes the start file"

stamp "$(( $(now) - 30 ))"       # 30s -> above quiet, below long(60)
run stop "$J_SESS"
member_std=0
while IFS= read -r line; do [ "$spoke" = "$line" ] && member_std=1; done <<'EOF'
All done.
Done.
Finished.
Ready when you are.
Your turn.
Back to you.
That's a wrap.
Over to you.
Done and dusted.
Wrapped up.
EOF
[ "$member_std" = 1 ] && ok "mid turn (30s) -> standard sign-off" || no "mid turn pool" "$spoke"

stamp "$(( $(now) - 300 ))"      # 5min -> long pool
run stop "$J_SESS"
member_long=0
while IFS= read -r line; do [ "$spoke" = "$line" ] && member_long=1; done <<'EOF'
Okay, that took a bit, but it's done.
Phew, finally done.
That one took a while. All wrapped up.
Done at last.
Took some doing, but it's finished.
All done. Thanks for waiting.
EOF
[ "$member_long" = 1 ] && ok "long turn (5min) -> wait-acknowledging sign-off" || no "long turn pool" "$spoke"

rm -f "$work/vn-sess.start"      # no start file -> unknown duration
run stop "$J_SESS"
[ -n "$spoke" ] && ok "unknown duration -> speaks (fail audible)" || no "unknown duration silent" "(nothing)"

# --- start event stamps state ---
rm -f "$work/vn-sess.start"
run start "$J_SESS"
[ -f "$work/vn-sess.start" ] && ok "start -> writes \$TMPDIR timestamp" || no "start no state file" "missing"
ts=$(cat "$work/vn-sess.start" 2>/dev/null)
case "$ts" in ''|*[!0-9]*) no "start timestamp not numeric" "$ts";; *) ok "start timestamp is epoch seconds";; esac

# --- Subagent dispatch cue: distinct pool, debounce, silent finishes ---
export CLAUDE_VOICE_NOTIFY_GARNISH_PCT=0          # core-only -> deterministic membership
export CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE=30
rm -f "$work/vn-sess.dispatch"
run dispatch "$J_DISPATCH"
member_sub=0
while IFS= read -r line; do [ "$spoke" = "$line" ] && member_sub=1; done <<'EOF'
Spinning up some helpers, back in a bit.
Working with a few helpers now.
Handing some work off, give me a moment.
Got some sub-agents on it, hang tight.
Delegating this, back shortly.
EOF
[ "$member_sub" = 1 ] && ok "dispatch -> distinct subagent cue (not a sign-off)" || no "dispatch pool" "$spoke"
# the same phrase must NOT be a turn-end sign-off (states stay audibly distinct)
member_stop=0
while IFS= read -r line; do [ "$spoke" = "$line" ] && member_stop=1; done <<'EOF'
All done.
Done.
Finished.
Ready when you are.
Your turn.
Back to you.
That's a wrap.
Over to you.
Done and dusted.
Wrapped up.
EOF
[ "$member_stop" = 0 ] && ok "dispatch cue is not in the Stop sign-off pool" || no "dispatch overlaps stop" "$spoke"
[ -f "$work/vn-sess.dispatch" ] && ok "dispatch writes \$TMPDIR debounce marker" || no "no debounce marker" "missing"

run dispatch "$J_DISPATCH"        # marker fresh -> same burst
[ -z "$spoke" ] && ok "dispatch within window -> debounced silent" || no "debounce not silent" "$spoke"

dstamp "$(( $(now) - 60 ))"       # marker older than the 30s window -> new burst
run dispatch "$J_DISPATCH"
[ -n "$spoke" ] && ok "dispatch after window -> speaks again" || no "post-window silent" "(nothing)"
unset CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE

run subagent-stop "$J_SESS"       # no finish arm -> any such event no-ops
[ -z "$spoke" ] && ok "subagent finish -> silent (no finish cue)" || no "subagent finish spoke" "$spoke"

# --- mute wins everywhere ---
export CLAUDE_VOICE_NOTIFY=off
run notification "$J_PERM"; [ -z "$spoke" ] && ok "mute -> notification silent" || no "mute notif" "$spoke"
stamp "$(( $(now) - 300 ))"; run stop "$J_SESS"; [ -z "$spoke" ] && ok "mute -> stop silent" || no "mute stop" "$spoke"
rm -f "$work/vn-sess.dispatch"; run dispatch "$J_DISPATCH"; [ -z "$spoke" ] && ok "mute -> dispatch silent" || no "mute dispatch" "$spoke"
unset CLAUDE_VOICE_NOTIFY

# --- subagent-only mute: gags the dispatch cue, leaves stop/notification speaking ---
export CLAUDE_VOICE_NOTIFY_SUBAGENT=off
rm -f "$work/vn-sess.dispatch"; run dispatch "$J_DISPATCH"; [ -z "$spoke" ] && ok "subagent mute -> dispatch silent" || no "subagent mute dispatch" "$spoke"
stamp "$(( $(now) - 300 ))"; run stop "$J_SESS"; [ -n "$spoke" ] && ok "subagent mute -> stop still speaks" || no "subagent mute gagged stop" "(nothing)"
unset CLAUDE_VOICE_NOTIFY_SUBAGENT

# --- non-macOS (no `say`) -> clean no-op ---
PATH_USE="$bin_nomac"
run notification "$J_PERM"; rc=$?
{ [ -z "$spoke" ] && [ "$rc" = 0 ]; } && ok "no say -> silent, exit 0" || no "non-macos no-op" "rc=$rc spoke=$spoke"
rm -f "$work/vn-sess.dispatch"; run dispatch "$J_DISPATCH"; rc=$?
{ [ -z "$spoke" ] && [ "$rc" = 0 ]; } && ok "no say -> dispatch silent, exit 0" || no "non-macos dispatch no-op" "rc=$rc spoke=$spoke"
PATH_USE="$bin_mac"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
