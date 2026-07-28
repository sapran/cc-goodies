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
for t in bash jq awk date grep tr cat rm sed sleep mktemp mkdir; do
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

# A third tool dir that looks like macOS but has no `jq`: the new agent events read every
# description through jq, so their degradation path needs its own PATH.
bin_nojq="$work/bin-nojq"; mkdir -p "$bin_nojq"
for t in bash awk date grep tr cat rm sed sleep mktemp mkdir; do
  p=$(command -v "$t" 2>/dev/null) || continue
  ln -sf "$p" "$bin_nojq/$t"
done
cp "$bin_mac/say" "$bin_nojq/say"

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
# In-flight marker helpers (mirror the script's spawn.d/done.d dirs under $TMPDIR=$work).
count_files() { local n=0 f; for f in "$1"/*; do [ -e "$f" ] && n=$((n+1)); done; printf '%s' "$n"; }
spawn_reset() { rm -rf "$work/vn-sess.spawn.d" "$work/vn-sess.done.d"; }
spawn_add() { mkdir -p "$work/vn-sess.spawn.d"; printf '%s' "${1:-$(now)}" > "$work/vn-sess.spawn.d/m$RANDOM$RANDOM"; }
done_add() { mkdir -p "$work/vn-sess.done.d"; printf '%s' "${1:-$(now)}" > "$work/vn-sess.done.d/${2:-a$RANDOM}"; }
spawn_n() { count_files "$work/vn-sess.spawn.d"; }
done_n()  { count_files "$work/vn-sess.done.d"; }
# 0.6.0 state: launch records (agent_id -> purpose), the per-burst pending list, the per-batch
# dispatch tally, and the two roll-up flags. All mirror notify.sh's $TMPDIR layout.
agents_reset()  { rm -rf "$work/vn-sess.agents.d"; }
agents_add()    { mkdir -p "$work/vn-sess.agents.d"; printf '%s\n%s\n' "$(now)" "$2" > "$work/vn-sess.agents.d/$1"; }
pending_reset() { rm -rf "$work/vn-sess.pending.d"; }
pending_add()   { mkdir -p "$work/vn-sess.pending.d"; printf '%s\n%s\n' "$(now)" "$2" > "$work/vn-sess.pending.d/$1"; }
batch_reset()   { rm -rf "$work/vn-sess.batch.d"; }
batch_add()     { mkdir -p "$work/vn-sess.batch.d"; printf '%s' "$(now)" > "$work/vn-sess.batch.d/$1"; }
flags_reset()   { rm -f "$work/vn-sess.waited" "$work/vn-sess.capped"; }
# 0.7.0 state: the busy marker the idle Notification consults, since its payload carries no
# in-flight task list of its own.
busy_reset()    { rm -f "$work/vn-sess.busy"; }
busy_set()      { printf '%s' "${1:-$(now)}" > "$work/vn-sess.busy"; }
busy_is_set()   { [ -f "$work/vn-sess.busy" ]; }
all_reset()     { spawn_reset; agents_reset; pending_reset; batch_reset; flags_reset; busy_reset; rm -f "$work/vn-sess.dispatch"; }
# One in-flight task of a given type, as the harness reports it.
bg_task()       { printf '{"session_id":"sess","background_tasks":[{"id":"t1","type":"%s","status":"running","description":"some work"}]}' "$1"; }
# Substring assertions: `has <needle> <label>` / `has_any <label> <needle>...`.
has() { case "$spoke" in *"$1"*) ok "$2" ;; *) no "$2" "$spoke" ;; esac; }
hasnt() { case "$spoke" in *"$1"*) no "$2" "$spoke" ;; *) ok "$2" ;; esac; }
has_any() {
  local label="$1" n
  shift
  for n in "$@"; do case "$spoke" in *"$n"*) ok "$label"; return ;; esac; done
  no "$label" "$spoke"
}
# The collect window makes the first dispatch of a burst wait for its siblings; tests drive
# state directly, so waiting only slows them down.
export CLAUDE_VOICE_NOTIFY_SUBAGENT_COLLECT=0
# Permission reminders ride the permission Notification, so leaving them on would make every
# permission test sit through a watcher. Off by default here; the reminder tests opt in.
export CLAUDE_VOICE_NOTIFY_NAG_EVERY=0
# The watcher polls every 5s in production; at that rate the watcher tests dominate the
# suite runtime. One second keeps them honest and makes a full run quick.
export CLAUDE_VOICE_NOTIFY_WATCH_POLL=1
J_PERM='{"message":"Claude needs your permission to use Bash","session_id":"sess"}'
J_IDLE='{"message":"Claude is waiting for your input","session_id":"sess"}'
J_WEIRD='{"message":"Claude Code is reticulating splines","session_id":"sess"}'
J_EMPTY='{"session_id":"sess"}'
J_SESS='{"session_id":"sess"}'
J_DISPATCH='{"session_id":"sess","tool_name":"Task"}'
J_SUBSTOP='{"session_id":"sess","agent_id":"agent-abc-123"}'

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

# --- Subagent finish: records a done marker (idempotent per agent_id). This payload has no
# --- task list and no launch record, so the agent reads as foreground: agent-result owns its
# --- cue and subagent-stop stays silent. ---
spawn_reset; agents_reset
run subagent-stop "$J_SUBSTOP"
[ -z "$spoke" ] && ok "foreground finish -> silent here (agent-result speaks)" || no "subagent finish spoke" "$spoke"
[ "$(done_n)" = 1 ] && ok "subagent finish -> writes a done marker" || no "no done marker" "$(done_n)"
run subagent-stop "$J_SUBSTOP"        # same agent_id -> must not double-count
[ "$(done_n)" = 1 ] && ok "duplicate SubagentStop for same agent_id counts once" || no "dup counted" "$(done_n)"

# --- In-flight at Stop: waiting cue in place of a sign-off ---
export CLAUDE_VOICE_NOTIFY_QUIET_UNDER=20
spawn_reset
rm -f "$work/vn-sess.dispatch"
run dispatch "$J_DISPATCH"            # dispatch also records a spawn marker
[ "$(spawn_n)" = 1 ] && ok "dispatch -> writes a spawn marker" || no "no spawn marker" "$(spawn_n)"
WAIT_POOL='Still going, the helpers aren'\''t done yet.
Not done yet, the agents are still working.
Paused here, but the sub-agents are still running.
Holding for the helpers to finish.
Agents still busy, not your turn just yet.
Work'\''s still out with the helpers.'
stamp "$(( $(now) - 30 ))"           # long enough that a no-work turn would sign off
run stop "$J_SESS"
member_wait=0
while IFS= read -r line; do [ "$spoke" = "$line" ] && member_wait=1; done <<EOF
$WAIT_POOL
EOF
[ "$member_wait" = 1 ] && ok "stop with subagent in-flight -> waiting cue" || no "waiting cue" "$spoke"
# waiting cue must not collide with the sign-off pools or the dispatch pool
member_notwait=0
while IFS= read -r line; do [ "$spoke" = "$line" ] && member_notwait=1; done <<'EOF'
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
Spinning up some helpers, back in a bit.
Working with a few helpers now.
Handing some work off, give me a moment.
Got some sub-agents on it, hang tight.
Delegating this, back shortly.
EOF
[ "$member_notwait" = 0 ] && ok "waiting cue is distinct from sign-off/dispatch pools" || no "waiting overlaps" "$spoke"

stamp "$(( $(now) - 3 ))"             # quick turn, but work still outstanding
run stop "$J_SESS"
[ -n "$spoke" ] && ok "waiting cue bypasses the quiet-under gate" || no "waiting gated by quiet" "(silent)"

done_add "$(now)" "agent-abc-123"    # completion balances the spawn -> normal sign-off
stamp "$(( $(now) - 30 ))"
run stop "$J_SESS"
member_bal=0
while IFS= read -r line; do [ "$spoke" = "$line" ] && member_bal=1; done <<'EOF'
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
[ "$member_bal" = 1 ] && ok "spawn balanced by completion -> normal sign-off (no regression)" || no "balanced not sign-off" "$spoke"

spawn_reset                          # stale spawn marker (older than the 3600s TTL) is pruned
spawn_add "$(( $(now) - 7200 ))"
stamp "$(( $(now) - 30 ))"
run stop "$J_SESS"
member_stale=0
while IFS= read -r line; do [ "$spoke" = "$line" ] && member_stale=1; done <<'EOF'
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
[ "$member_stale" = 1 ] && ok "stale spawn marker pruned -> normal sign-off" || no "stale not pruned" "$spoke"
[ "$(spawn_n)" = 0 ] && ok "stale spawn marker removed from dir" || no "stale marker remains" "$(spawn_n)"

# a custom TTL is honoured: a marker older than the configured window is pruned -> sign-off
export CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL=60
spawn_reset
spawn_add "$(( $(now) - 120 ))"      # 2min old, older than the 60s TTL
stamp "$(( $(now) - 30 ))"
run stop "$J_SESS"
[ "$(spawn_n)" = 0 ] && ok "custom TTL prunes an older marker" || no "custom TTL not applied" "$(spawn_n)"
unset CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL

# a leading-zero TTL must NOT be parsed as octal: $(( ... - ttl )) would error, leave cutoff
# unset, and under set -u kill the whole stop arm (silencing every turn). Guard: base-10 forced.
export CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL=0900
spawn_reset
spawn_add "$(now)"                   # fresh marker -> in-flight
stamp "$(( $(now) - 30 ))"
run stop "$J_SESS"; rc=$?
member_lz=0
while IFS= read -r line; do [ "$spoke" = "$line" ] && member_lz=1; done <<EOF
$WAIT_POOL
EOF
{ [ "$rc" = 0 ] && [ "$member_lz" = 1 ]; } && ok "leading-zero TTL -> no crash, speaks waiting cue" || no "leading-zero TTL crashed stop arm" "rc=$rc spoke=$spoke"
unset CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL

spawn_reset
unset CLAUDE_VOICE_NOTIFY_QUIET_UNDER

# --- mute wins everywhere ---
export CLAUDE_VOICE_NOTIFY=off
run notification "$J_PERM"; [ -z "$spoke" ] && ok "mute -> notification silent" || no "mute notif" "$spoke"
stamp "$(( $(now) - 300 ))"; run stop "$J_SESS"; [ -z "$spoke" ] && ok "mute -> stop silent" || no "mute stop" "$spoke"
rm -f "$work/vn-sess.dispatch"; run dispatch "$J_DISPATCH"; [ -z "$spoke" ] && ok "mute -> dispatch silent" || no "mute dispatch" "$spoke"
spawn_reset; run subagent-stop "$J_SUBSTOP"; { [ -z "$spoke" ] && [ "$(done_n)" = 0 ]; } && ok "mute -> subagent-stop silent, no marker" || no "mute subagent-stop" "spoke=$spoke done=$(done_n)"
unset CLAUDE_VOICE_NOTIFY

# --- subagent-only mute: disables the whole subagent path, leaves stop/notification speaking ---
export CLAUDE_VOICE_NOTIFY_SUBAGENT=off
spawn_reset
rm -f "$work/vn-sess.dispatch"; run dispatch "$J_DISPATCH"
[ -z "$spoke" ] && ok "subagent mute -> dispatch silent" || no "subagent mute dispatch" "$spoke"
[ "$(spawn_n)" = 0 ] && ok "subagent mute -> no spawn marker written" || no "muted spawn written" "$(spawn_n)"
run subagent-stop "$J_SUBSTOP"
[ "$(done_n)" = 0 ] && ok "subagent mute -> no done marker written" || no "muted done written" "$(done_n)"
spawn_add "$(now)"                    # even with an in-flight marker present...
stamp "$(( $(now) - 300 ))"; run stop "$J_SESS"
[ -n "$spoke" ] && ok "subagent mute -> stop signs off despite in-flight marker" || no "subagent mute gagged stop" "(nothing)"
spawn_reset
unset CLAUDE_VOICE_NOTIFY_SUBAGENT

# --- non-macOS (no `say`) -> clean no-op ---
PATH_USE="$bin_nomac"
run notification "$J_PERM"; rc=$?
{ [ -z "$spoke" ] && [ "$rc" = 0 ]; } && ok "no say -> silent, exit 0" || no "non-macos no-op" "rc=$rc spoke=$spoke"
rm -f "$work/vn-sess.dispatch"; run dispatch "$J_DISPATCH"; rc=$?
{ [ -z "$spoke" ] && [ "$rc" = 0 ]; } && ok "no say -> dispatch silent, exit 0" || no "non-macos dispatch no-op" "rc=$rc spoke=$spoke"
spawn_reset; run subagent-stop "$J_SUBSTOP"; rc=$?
{ [ "$(done_n)" = 0 ] && [ "$rc" = 0 ]; } && ok "no say -> subagent-stop no-op, exit 0" || no "non-macos subagent-stop no-op" "rc=$rc done=$(done_n)"
PATH_USE="$bin_mac"

# =====================================================================================
# 0.6.0: naming the agent's purpose, completion cues, the drain roll-up
# =====================================================================================
export CLAUDE_VOICE_NOTIFY_GARNISH_PCT=0      # core-only -> deterministic assertions

SUB_POOL='Spinning up some helpers, back in a bit.
Working with a few helpers now.
Handing some work off, give me a moment.
Got some sub-agents on it, hang tight.
Delegating this, back shortly.'
in_sub_pool() {   # membership against the anonymous dispatch pool
  local m=0 line
  while IFS= read -r line; do [ "$spoke" = "$line" ] && m=1; done <<EOF
$SUB_POOL
EOF
  [ "$m" = 1 ] && ok "$1" || no "$1" "$spoke"
}
lines_spoken() { printf '%s\n' "$spoke" | grep -c . ; }

J_DISP_D='{"session_id":"sess","tool_name":"Agent","tool_input":{"description":"Review script changes","subagent_type":"general-purpose","run_in_background":true}}'
J_LAUNCH='{"session_id":"sess","tool_name":"Agent","tool_input":{"description":"Name three colours"},"tool_response":{"isAsync":true,"status":"async_launched","agentId":"bg1"}}'
J_FG_DONE='{"session_id":"sess","tool_name":"Agent","tool_input":{"description":"Count to three"},"tool_response":{"status":"completed","agentId":"fg1","agentType":"general-purpose"}}'
J_FG_FAIL='{"session_id":"sess","tool_name":"Agent","tool_input":{"description":"Count to three"},"tool_response":{"status":"error","agentId":"fg1","agentType":"general-purpose"}}'
J_BG_STOP='{"session_id":"sess","agent_id":"bg1","agent_type":"general-purpose","last_assistant_message":"red green blue","background_tasks":[{"id":"bg1","type":"subagent","status":"running","description":"Name three colours"}]}'
J_BG_EMPTY='{"session_id":"sess","agent_id":"bg1","agent_type":"general-purpose","last_assistant_message":"","background_tasks":[{"id":"bg1","type":"subagent","status":"running","description":"Name three colours"}]}'
J_FG_STOP='{"session_id":"sess","agent_id":"fg1","agent_type":"general-purpose","last_assistant_message":"1 2 3","background_tasks":[]}'
J_BG_NOBT='{"session_id":"sess","agent_id":"bg1","agent_type":"general-purpose","last_assistant_message":"ok"}'
J_BG_BUSY='{"session_id":"sess","agent_id":"bg1","agent_type":"general-purpose","last_assistant_message":"ok","background_tasks":[{"id":"bg1","type":"subagent","description":"Name three colours"},{"id":"o1","type":"subagent","description":"one"},{"id":"o2","type":"subagent","description":"two"},{"id":"o3","type":"subagent","description":"three"},{"id":"o4","type":"subagent","description":"four"}]}'

# --- dispatch cue names the delegated work ---
all_reset
run dispatch "$J_DISP_D"
has "— Review script changes." "dispatch names a single agent"
[ ! -d "$work/vn-sess.pending.d" ] && ok "burst clears the pending list" || no "pending kept" "still there"

all_reset
pending_add z1 "Map the hook payloads"
run dispatch "$J_DISP_D"
has "Two helpers: Review script changes, and Map the hook payloads." "dispatch names both of two agents"

all_reset
pending_add z1 "Map the hook payloads"
pending_add z2 "Check the tests"
run dispatch "$J_DISP_D"
has "three helpers, starting with Review script changes." "large burst is counted, not enumerated"
hasnt "Check the tests" "large burst does not enumerate every purpose"

# --- agent-result: async launch is an acknowledgement, not a completion ---
all_reset
run agent-result "$J_LAUNCH"
[ -z "$spoke" ] && ok "async launch ack is silent" || no "launch ack spoke" "$spoke"
[ -f "$work/vn-sess.agents.d/bg1" ] && ok "async launch records the purpose" || no "no launch record" "missing"
rec=$(sed -n '2p' "$work/vn-sess.agents.d/bg1" 2>/dev/null)
[ "$rec" = "Name three colours" ] && ok "launch record holds the description" || no "bad launch record" "$rec"

# --- agent-result: a foreground agent is voiced when its result returns ---
all_reset
run agent-result "$J_FG_DONE"
has "Count to three —" "foreground completion is named when the result returns"
has_any "a completed agent uses the success pool" "— done." "— finished." "— is back." "— wrapped up."

all_reset
run agent-result "$J_FG_FAIL"
has_any "a failed agent uses the failure pool" "didn't finish" "has failed" "no result from that one"

# PostToolUseFailure carries tool_input but no tool_response at all (an interrupted or errored
# agent tool call). The same arm must still name it and route it to the failure pool.
all_reset
run agent-result '{"session_id":"sess","tool_name":"Agent","tool_input":{"description":"Count to three"},"tool_use_id":"t1","error":"interrupted","is_interrupt":true}'
has "Count to three" "an interrupted agent is still named"
has_any "an interrupted agent uses the failure pool" "didn't finish" "has failed" "no result from that one"

# --- subagent-stop: background agents are voiced here, foreground ones are not ---
all_reset
run subagent-stop "$J_BG_STOP"
has "Name three colours —" "background finish is named from the payload task list"
[ "$(done_n)" = 1 ] && ok "background finish still records a done marker" || no "no done marker" "$(done_n)"

all_reset
run subagent-stop "$J_FG_STOP"
[ -z "$spoke" ] && ok "foreground finish silent even with an empty task list" || no "fg stop spoke" "$spoke"

all_reset
spawn_add "$(now)"
agents_add bg1 "Name three colours"
run subagent-stop "$J_BG_NOBT"
has "Name three colours —" "falls back to the launch record when no task list is sent"
[ ! -f "$work/vn-sess.agents.d/bg1" ] && ok "launch record is consumed on completion" || no "record kept" "still there"

all_reset
run subagent-stop '{"session_id":"sess","agent_id":"bg1","agent_type":"Explore","last_assistant_message":"ok","background_tasks":[{"id":"bg1","type":"subagent","description":""}]}'
has "the Explore helper" "falls back to the agent type when no purpose is known"

all_reset
run subagent-stop '{"session_id":"sess","agent_id":"bg1","agent_type":"","last_assistant_message":"ok","background_tasks":[{"id":"bg1","type":"subagent","description":""}]}'
has_any "anonymous cue when nothing identifies the agent" "A helper's done." "One of the helpers is back." "That's one helper finished."

all_reset
run subagent-stop "$J_BG_EMPTY"
has_any "an empty result uses the failure pool" "didn't finish" "has failed" "no result from that one"

# --- name cap and the drain roll-up ---
all_reset
run subagent-stop "$J_BG_BUSY"
[ -z "$spoke" ] && ok "completion above the name cap is suppressed" || no "cap not applied" "$spoke"
[ -f "$work/vn-sess.capped" ] && ok "a suppressed completion records the capped flag" || no "no capped flag" "missing"

batch_add a1; batch_add a2; batch_add a3; batch_add a4; batch_add a5
run subagent-stop "$J_BG_STOP"           # nothing else in flight -> the batch drains
has_any "a capped batch gets a roll-up naming the count" "All five helpers are back." \
  "That's all five helpers back." "five helpers, all done." "All five are back now."
[ ! -f "$work/vn-sess.capped" ] && ok "the roll-up clears the batch flags" || no "flag kept" "still there"

all_reset
printf '%s' "$(now)" > "$work/vn-sess.waited"
batch_add a1; batch_add a2
run subagent-stop "$J_BG_STOP"
has_any "a batch that was told to wait gets a roll-up" "All two helpers are back." \
  "That's all two helpers back." "two helpers, all done." "All two are back now."

all_reset
batch_add a1
run subagent-stop "$J_BG_STOP"
[ "$(lines_spoken)" = 1 ] && ok "a fully named batch gets no roll-up" || no "unexpected roll-up" "$spoke"

# --- Stop: the waiting cue arms the roll-up; an empty task list overrides the markers ---
all_reset
spawn_add "$(now)"
stamp "$(( $(now) - 30 ))"
run stop "$J_SESS"
[ -f "$work/vn-sess.waited" ] && ok "the waiting cue records that the user was told to wait" || no "no waited flag" "missing"

all_reset
spawn_add "$(now)"                        # markers claim work is in flight...
stamp "$(( $(now) - 300 ))"
run stop '{"session_id":"sess","background_tasks":[]}'
hasnt "helpers aren't done" "an empty task list overrides a stale marker count"
has_any "empty task list -> a real sign-off" "Okay, that took a bit, but it's done." \
  "Phew, finally done." "That one took a while. All wrapped up." "Done at last." \
  "Took some doing, but it's finished." "All done. Thanks for waiting."

# --- Which kinds of background work hold off the sign-off ---
# The harness reports nine types in background_tasks. Everything except a background shell and a
# monitor is work the session is genuinely waiting on.
wait_cue() {   # wait_cue <label> : the spoken line came from the waiting pool
  has_any "$1" "the helpers aren't done yet" "the agents are still working" \
    "the sub-agents are still running" "Holding for the helpers to finish" \
    "Agents still busy" "Work's still out with the helpers"
}
long_signoff() {   # long_signoff <label> : the spoken line came from the long turn-end pool
  has_any "$1" "Okay, that took a bit, but it's done." "Phew, finally done." \
    "That one took a while. All wrapped up." "Done at last." \
    "Took some doing, but it's finished." "All done. Thanks for waiting."
}

for t in workflow teammate "cloud session" "MCP task" dream "auto-mode scan" "some-future-type"; do
  all_reset
  stamp "$(( $(now) - 300 ))"
  run stop "$(bg_task "$t")"
  wait_cue "stop with a '$t' in flight -> waiting cue"
done

for t in shell monitor; do
  all_reset
  stamp "$(( $(now) - 300 ))"
  run stop "$(bg_task "$t")"
  long_signoff "stop with only a '$t' in flight -> real sign-off"
  busy_is_set && no "'$t' wrote a busy marker" "present" || ok "a '$t' leaves no busy marker"
done

# --- The busy marker and the idle notification ---
all_reset
stamp "$(( $(now) - 300 ))"
run stop "$(bg_task workflow)"
busy_is_set && ok "stop with work outstanding writes the busy marker" || no "no busy marker" "missing"
run notification "$J_IDLE"
[ -z "$spoke" ] && ok "idle notification is silent while work is outstanding" || no "idle spoke while busy" "$spoke"

# ...and every other notification subtype still speaks, because each is still true.
run notification "$J_PERM"
has "I need your permission" "a permission request still speaks while work is outstanding"
run notification '{"session_id":"sess","notification_type":"agent_needs_input","message":"Explore agent needs your input: which branch?"}'
has "needs your input" "an agent asking for input still speaks while work is outstanding"
run notification '{"session_id":"sess","notification_type":"agent_completed","message":"Review script changes finished"}'
has "Review script changes finished" "an agent completion still speaks while work is outstanding"
run notification "$J_WEIRD"
has "I need your attention" "the neutral fallback still speaks while work is outstanding"

stamp "$(( $(now) - 300 ))"
run stop '{"session_id":"sess","background_tasks":[]}'
busy_is_set && no "empty task list left the busy marker" "present" || ok "an empty task list clears the busy marker"
run notification "$J_IDLE"
has "I'm waiting for your input" "idle notification speaks once the work has drained"

# The last background agent draining is what turns "still working" back into "idle" — Stop has
# already happened by then, so SubagentStop has to clear the marker itself.
all_reset
busy_set
run subagent-stop '{"session_id":"sess","agent_id":"a1","last_assistant_message":"done","background_tasks":[{"id":"a1","type":"subagent","status":"running","description":"review the diff"}]}'
busy_is_set && no "last agent left the busy marker" "present" || ok "the last background agent draining clears the busy marker"

all_reset
busy_reset
run subagent-stop '{"session_id":"sess","agent_id":"a1","last_assistant_message":"done","background_tasks":[{"id":"a1","type":"subagent","status":"running","description":"review the diff"},{"id":"w1","type":"workflow","status":"running","description":"migrate"}]}'
busy_is_set && ok "work still outstanding at SubagentStop keeps the busy marker" || no "marker cleared too early" "missing"

# Naming off must not skip the refresh: the idle gate has to stay accurate either way.
export CLAUDE_VOICE_NOTIFY_AGENT_NAMES=off
all_reset
busy_set
run subagent-stop '{"session_id":"sess","agent_id":"a1","last_assistant_message":"done","background_tasks":[{"id":"a1","type":"subagent","status":"running","description":"review the diff"}]}'
busy_is_set && no "naming off skipped the refresh" "present" || ok "naming off still refreshes the busy marker"
unset CLAUDE_VOICE_NOTIFY_AGENT_NAMES

all_reset
busy_set
run start "$J_SESS"
busy_is_set && no "start left the busy marker" "present" || ok "a new user prompt clears the busy marker"

all_reset
busy_set "$(( $(now) - 7200 ))"       # older than the 3600s in-flight TTL
run notification "$J_IDLE"
has "I'm waiting for your input" "a stale busy marker does not mute the idle cue"

export CLAUDE_VOICE_NOTIFY_SUBAGENT=off
all_reset
busy_set
run notification "$J_IDLE"
has "I'm waiting for your input" "subagent path off -> the idle cue is never gated"
all_reset
stamp "$(( $(now) - 300 ))"
run stop "$(bg_task workflow)"
busy_is_set && no "subagent path off wrote a busy marker" "present" || ok "subagent path off -> no busy marker is written"
unset CLAUDE_VOICE_NOTIFY_SUBAGENT
all_reset

# --- description sanitisation ---
all_reset
export CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX=20
run dispatch '{"session_id":"sess","tool_name":"Agent","tool_input":{"description":"Review the script changes and the hook payload wiring"}}'
has "— Review the script." "a long description is truncated at a word boundary"
hasnt "payload" "truncation drops the tail"
unset CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX

all_reset
run dispatch '{"session_id":"sess","tool_name":"Agent","tool_input":{"description":"Review\nscript\tchanges"}}'
has "Review script changes" "newlines and tabs collapse to single spaces"
[ "$(lines_spoken)" = 1 ] && ok "a multiline description stays one utterance" || no "split utterance" "$spoke"

all_reset
run dispatch '{"session_id":"sess","tool_name":"Agent","tool_input":{"description":"Review [[slnc 5000]] changes"}}'
hasnt "[[" "speech directives inside a description are neutralised"

all_reset
run dispatch '{"session_id":"sess","tool_name":"Agent","tool_input":{"description":"Fix $(id) and | ls"}}'
has '$(id)' "shell metacharacters are spoken as text"
hasnt "uid=" "a description is never expanded by the shell"

# --- Notification: background-agent types no longer collapse into the generic cue ---
all_reset
run notification '{"session_id":"sess","notification_type":"agent_completed","message":"Review script changes finished"}'
has "Review script changes finished" "agent_completed notification names the agent"
hasnt "I need your attention" "agent_completed does not fall through to the generic cue"

run notification '{"session_id":"sess","notification_type":"agent_needs_input","message":"Explore agent needs your input: which branch?"}'
has "needs your input" "agent_needs_input notification is routed"
hasnt "I need your attention" "agent_needs_input does not fall through to the generic cue"

run notification '{"session_id":"sess","message":"Explore agent finished"}'
has "Explore agent finished" "wording routes a completion notification with no type field"

# --- mutes and configuration ---
export CLAUDE_VOICE_NOTIFY_AGENT_NAMES=off
all_reset
run dispatch "$J_DISP_D"
in_sub_pool "names off -> the anonymous dispatch cue"
run agent-result "$J_FG_DONE"; [ -z "$spoke" ] && ok "names off -> no foreground completion cue" || no "names off spoke" "$spoke"
all_reset
run subagent-stop "$J_BG_STOP"; [ -z "$spoke" ] && ok "names off -> no background completion cue" || no "names off spoke" "$spoke"
unset CLAUDE_VOICE_NOTIFY_AGENT_NAMES

export CLAUDE_VOICE_NOTIFY_SUBAGENT=off
all_reset
run agent-result "$J_LAUNCH"; rc=$?
{ [ -z "$spoke" ] && [ ! -d "$work/vn-sess.agents.d" ] && [ "$rc" = 0 ]; } \
  && ok "subagent mute -> agent-result records nothing" || no "muted agent-result" "rc=$rc spoke=$spoke"
unset CLAUDE_VOICE_NOTIFY_SUBAGENT

export CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP=abc
all_reset
run subagent-stop "$J_BG_BUSY"
[ -z "$spoke" ] && ok "an invalid name cap falls back to the default" || no "bad cap parsed" "$spoke"
unset CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP

# --- degradation: no say, no jq ---
PATH_USE="$bin_nomac"
all_reset
run agent-result "$J_FG_DONE"; rc=$?
{ [ -z "$spoke" ] && [ "$rc" = 0 ]; } && ok "no say -> agent-result no-op, exit 0" || no "non-macos agent-result" "rc=$rc"
PATH_USE="$bin_nojq"
all_reset
rm -f "$work/vn-nosess.dispatch"; rm -rf "$work/vn-nosess.pending.d"
run agent-result "$J_FG_DONE"; rc=$?
{ [ -z "$spoke" ] && [ "$rc" = 0 ]; } && ok "no jq -> agent-result silent, exit 0" || no "no-jq agent-result" "rc=$rc spoke=$spoke"
run dispatch "$J_DISP_D"
in_sub_pool "no jq -> the anonymous dispatch cue"
PATH_USE="$bin_mac"

# --- speech serialisation ---
all_reset
mkdir -p "$work/vn-speak.lock.d"; printf '%s' "$(now)" > "$work/vn-speak.lock.d/ts"
run notification "$J_PERM"
[ -z "$spoke" ] && ok "a contended cue is dropped, not queued" || no "contended cue spoke" "$spoke"
rm -rf "$work/vn-speak.lock.d"

mkdir -p "$work/vn-speak.lock.d"; printf '%s' "$(( $(now) - 600 ))" > "$work/vn-speak.lock.d/ts"
run notification "$J_PERM"
[ -n "$spoke" ] && ok "an abandoned lock is reclaimed" || no "abandoned lock wedged the cue" "(nothing)"
rm -rf "$work/vn-speak.lock.d"

# ======================================================================================
# 0.8.0: shell-command cues and blocked-session cues
# ======================================================================================
export CLAUDE_VOICE_NOTIFY_GARNISH_PCT=0    # core-only -> deterministic assertions
export CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=45
export CLAUDE_VOICE_NOTIFY_CMD_QUIET_UNDER=60
export CLAUDE_VOICE_NOTIFY_NAG_EVERY=60
export CLAUDE_VOICE_NOTIFY_NAG_MAX=5
unset CLAUDE_VOICE_NOTIFY_CMD 2>/dev/null || true

cmd_reset()   { rm -rf "$work/vn-sess.cmd.d" "$work/vn-sess.cmdsaid.d" "$work/vn-sess.bg.d" \
                       "$work/vn-sess.perm.d" "$work/vn-sess.watch.d"; }
cmd_add()     { mkdir -p "$work/vn-sess.cmd.d"; printf '%s\n%s\n' "${2:-$(now)}" "$3" > "$work/vn-sess.cmd.d/$1"; }
cmd_said()    { mkdir -p "$work/vn-sess.cmdsaid.d"; printf '%s' "$(now)" > "$work/vn-sess.cmdsaid.d/$1"; }
bg_add()      { mkdir -p "$work/vn-sess.bg.d"; printf '%s\n%s\n' "$(now)" "$2" > "$work/vn-sess.bg.d/$1"; }
bg_has()      { [ -f "$work/vn-sess.bg.d/$1" ]; }
perm_add()    { mkdir -p "$work/vn-sess.perm.d"; printf '%s\n%s\n%s\n%s\n' "${2:-$(now)}" "$3" "${4:-0}" "${5:-0}" > "$work/vn-sess.perm.d/$1"; }
perm_has()    { [ -f "$work/vn-sess.perm.d/$1" ]; }
cmd_has()     { [ -f "$work/vn-sess.cmd.d/$1" ]; }

# Payload builders. duration_ms is what the harness actually sends (verified against 2.1.220).
j_post()  { printf '{"session_id":"sess","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"%s","tool_input":{"command":"make test","description":"%s"},"tool_response":{"stdout":"","stderr":"","interrupted":false},"duration_ms":%s}' "$1" "$2" "$3"; }
j_postbg() { printf '{"session_id":"sess","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"%s","tool_input":{"command":"npm run dev","description":"%s","run_in_background":true},"tool_response":{"stdout":"","stderr":"","interrupted":false,"backgroundTaskId":"%s"},"duration_ms":420}' "$1" "$2" "$3"; }
j_fail()  { printf '{"session_id":"sess","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_use_id":"%s","tool_input":{"command":"make test","description":"%s"},"error":"boom","is_timeout":%s,"is_interrupt":%s}' "$1" "$2" "$3" "$4"; }
j_pre()   { printf '{"session_id":"sess","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"%s","tool_input":{"command":"make test","description":"%s"%s}}' "$1" "$2" "$3"; }
j_stopf() { printf '{"session_id":"sess","hook_event_name":"StopFailure","error":"upstream said no","error_type":"%s"}' "$1"; }
j_permreq() { printf '{"session_id":"sess","hook_event_name":"PermissionRequest","tool_name":"%s","tool_use_id":"%s"}' "$1" "$2"; }
# background_tasks carrying an explicit list of shell ids (or an empty list).
j_stop_bt() { printf '{"session_id":"sess","hook_event_name":"Stop","background_tasks":[%s]}' "$1"; }
bt_shell()  { printf '{"id":"%s","type":"shell","status":"running","description":"a job","command":"sleep 5"}' "$1"; }

# --- 8.1 duration gate -----------------------------------------------------------------
cmd_reset; all_reset
run tool-result "$(j_post t1 'Run the test suite' 90000)"
has "Run the test suite" "a long command speaks on completion"

cmd_reset
run tool-result "$(j_post t2 'Print the branch' 700)"
[ -z "$spoke" ] && ok "a quick command stays silent" || no "quick command spoke" "$spoke"

cmd_reset
CLAUDE_VOICE_NOTIFY_CMD_QUIET_UNDER=0 run tool-result "$(j_post t3 'Print the branch' 700)"
has "Print the branch" "threshold 0 speaks for every command"

# No duration_ms in the payload -> fall back to the start record we wrote at dispatch.
cmd_reset
cmd_add t4 "$(( $(now) - 300 ))" 'Build the image'
run tool-result '{"session_id":"sess","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"t4","tool_input":{"command":"docker build .","description":"Build the image"},"tool_response":{"stdout":""}}'
has "Build the image" "missing duration falls back to the start record"

# --- 8.2 outcomes ----------------------------------------------------------------------
cmd_reset
cmd_add t5 "$(( $(now) - 300 ))" 'Run the test suite'
run tool-result "$(j_fail t5 'Run the test suite' false false)"
has_any "a failure is announced as a failure" "failed" "didn't work" "error"

cmd_reset
cmd_add t6 "$(( $(now) - 300 ))" 'Run the test suite'
run tool-result "$(j_fail t6 'Run the test suite' true false)"
has "timed out" "a timeout has its own phrasing"

cmd_reset
cmd_add t7 "$(( $(now) - 300 ))" 'Run the test suite'
run tool-result "$(j_fail t7 'Run the test suite' false true)"
has_any "an interruption has its own phrasing" "interrupted" "cut short"

cmd_reset
run tool-result "$(j_post t8 'Run the test suite' 90000)"
hasnt "failed" "success is not phrased as a failure"

# --- 8.3 / 8.4 still-running + the announced-always-reports rule ------------------------
# A command announced as running reports its completion even below the quiet threshold.
cmd_reset
cmd_add t9 "$(now)" 'Run the test suite'
cmd_said t9
run tool-result "$(j_post t9 'Run the test suite' 700)"
has "Run the test suite" "an announced command reports completion below the threshold"

cmd_reset
cmd_add t10 "$(now)" 'Run the test suite'
cmd_said t10
run tool-result "$(j_fail t10 'Run the test suite' false false)"
has_any "an announced command that fails still reports" "failed" "didn't work" "error"

# The still-running cue itself: drive the watcher with a tiny threshold and an already-old marker.
cmd_reset
cmd_add t11 "$(( $(now) - 100 ))" 'Run the test suite'
CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=1 run cmd-start "$(j_pre t12 'Another command' '')"
has "Run the test suite" "a command past the interval is announced as still running"
[ -f "$work/vn-sess.cmdsaid.d/t11" ] && ok "the still-running cue is marked as spoken" || no "no announced marker" "(missing)"

# Announced once only: a second watcher pass says nothing more about the same command.
cmd_reset
cmd_add t13 "$(( $(now) - 100 ))" 'Run the test suite'
cmd_said t13
CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=1 run cmd-start "$(j_pre t14 'Another command' '')"
hasnt "Run the test suite" "an already-announced command is not announced again"

# Interval 0 disables the running cue but leaves completion intact.
cmd_reset
cmd_add t15 "$(( $(now) - 100 ))" 'Run the test suite'
CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=0 run cmd-start "$(j_pre t16 'Another command' '')"
[ -z "$spoke" ] && ok "interval 0 disables the still-running cue" || no "spoke with interval 0" "$spoke"
cmd_reset
CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=0 run tool-result "$(j_post t17 'Run the test suite' 90000)"
has "Run the test suite" "interval 0 leaves completion cues working"

# --- 8.5 watcher election ---------------------------------------------------------------
cmd_reset
mkdir -p "$work/vn-sess.watch.d"; printf '%s' "$(now)" > "$work/vn-sess.watch.d/ts"
cmd_add t18 "$(( $(now) - 100 ))" 'Run the test suite'
CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=1 run cmd-start "$(j_pre t19 'Another command' '')"
[ -z "$spoke" ] && ok "a live election is not displaced (one watcher per session)" || no "second watcher ran" "$spoke"

# An election whose heartbeat stopped is reclaimed.
cmd_reset
mkdir -p "$work/vn-sess.watch.d"; printf '%s' "$(( $(now) - 600 ))" > "$work/vn-sess.watch.d/ts"
cmd_add t20 "$(( $(now) - 100 ))" 'Run the test suite'
CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=1 run cmd-start "$(j_pre t21 'Another command' '')"
has "Run the test suite" "an abandoned election is reclaimed"

# The watcher exits (rather than hanging) once nothing is outstanding: with no markers at all
# the run returns promptly and releases the claim.
cmd_reset
CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=1 run cmd-start "$(j_pre t22 'Another command' '')"
[ -d "$work/vn-sess.watch.d" ] && no "watcher left its election behind" "(claim still present)" \
  || ok "the watcher releases its election on exit"

# --- 8.6 background completion -----------------------------------------------------------
cmd_reset
run tool-result "$(j_postbg t23 'Start the dev server' btabc)"
[ -z "$spoke" ] && ok "a launch acknowledgement is silent" || no "launch ack spoke" "$spoke"
bg_has btabc && ok "a launch acknowledgement records the task id" || no "no bg record" "(missing)"

# Still listed -> nothing to say.
run stop "$(j_stop_bt "$(bt_shell btabc)")"
hasnt "Start the dev server" "a still-running background command is not announced"
bg_has btabc && ok "a still-running background record is kept" || no "record dropped early" "(missing)"

# Gone from the list -> announced once, then forgotten.
run stop "$(j_stop_bt '')"
has "Start the dev server" "a finished background command is announced by name"
bg_has btabc && no "background record survived its announcement" "(still present)" \
  || ok "an announced background command is forgotten"
run stop "$(j_stop_bt '')"
hasnt "Start the dev server" "a background command is announced only once"

# No task list at all -> conclude nothing, keep the record.
cmd_reset
bg_add btxyz 'Start the dev server'
run stop '{"session_id":"sess","hook_event_name":"Stop"}'
hasnt "Start the dev server" "no task list means no background completion is inferred"
bg_has btxyz && ok "no task list leaves background records intact" || no "record dropped" "(missing)"

# --- 8.7 the command string is never spoken -----------------------------------------------
cmd_reset
run tool-result '{"session_id":"sess","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"t24","tool_input":{"command":"curl -H token-sk-supersecret-value https://example.invalid","description":"Call the API"},"tool_response":{"stdout":""},"duration_ms":90000}'
hasnt "supersecret" "a secret on the command line is never voiced"
hasnt "curl" "the command string itself is never voiced"
has "Call the API" "the description is voiced instead"

# No description -> anonymous, still never the command.
cmd_reset
run tool-result '{"session_id":"sess","hook_event_name":"PostToolUse","tool_name":"Bash","tool_use_id":"t25","tool_input":{"command":"make release"},"tool_response":{"stdout":""},"duration_ms":90000}'
hasnt "make release" "a command with no description still never voices the command"
[ -n "$spoke" ] && ok "a command with no description falls back to an anonymous cue" || no "silent" "(nothing)"

# --- 8.8 in-flight accounting is unchanged -------------------------------------------------
cmd_reset; all_reset
# Stamp a long turn so the assertion targets the six-phrase long pool rather than trying to
# enumerate the ten-phrase standard one — the same trick the 0.7.0 in-flight tests use.
stamp "$(( $(now) - 300 ))"
run stop "$(j_stop_bt "$(bt_shell btq)")"
long_signoff "a running background command still lets the sign-off speak"
busy_is_set && no "a shell task wrote a busy marker" "(marker present)" || ok "a shell task writes no busy marker"

# --- 8.9 StopFailure ------------------------------------------------------------------------
cmd_reset; all_reset
run stop-failure "$(j_stopf rate_limit)"
has_any "a rate-limited turn is named" "rate limit" "Rate limited"
run stop-failure "$(j_stopf overloaded)"
has "overloaded" "an overloaded turn is named"
run stop-failure "$(j_stopf authentication_failed)"
has_any "an authentication failure is named" "authentication" "Authentication"
run stop-failure "$(j_stopf billing_error)"
has "illing" "a billing failure is named"
run stop-failure "$(j_stopf max_output_tokens)"
has_any "an output-limit failure is named" "output limit" "length limit"
run stop-failure "$(j_stopf something_new)"
has_any "an unknown cause falls back to a generic stalled cue" "stalled" "didn't finish" "stopped"
hasnt "All done" "a stalled turn never speaks a sign-off"

# The duration gate is bypassed: a turn that died 1 second in still speaks.
all_reset
stamp "$(now)"
export CLAUDE_VOICE_NOTIFY_QUIET_UNDER=3600
run stop-failure "$(j_stopf rate_limit)"
[ -n "$spoke" ] && ok "the stalled cue ignores the duration gate" || no "gate silenced the stalled cue" "(nothing)"
[ -f "$work/vn-sess.start" ] && no "turn-start state survived a stalled turn" "(still present)" \
  || ok "a stalled turn clears its turn-start state"
export CLAUDE_VOICE_NOTIFY_QUIET_UNDER=20

# Without jq the cause can't be read, but the generic cue must still speak.
PATH_USE="$bin_nojq"
run stop-failure "$(j_stopf rate_limit)"
[ -n "$spoke" ] && ok "no jq -> a generic stalled cue still speaks" || no "silent without jq" "(nothing)"
PATH_USE="$bin_mac"

# --- 8.10 permission reminders ---------------------------------------------------------------
# Arm through the real event and let the elected watcher speak. NAG_MAX=1 makes the reminder hit
# its cap after one repeat, so the watcher runs out of actionable work and exits promptly.
cmd_reset
CLAUDE_VOICE_NOTIFY_NAG_EVERY=1 CLAUDE_VOICE_NOTIFY_NAG_MAX=1 CLAUDE_VOICE_NOTIFY_CMD=off \
  run notification "$J_PERM"
has_any "an unanswered prompt is re-announced" "still need" "Still waiting" "still blocked" "Nothing's moving"
has "Bash" "the reminder names the tool"
ok "reminders work with the command path muted"

# A reminder already at its cap never speaks again. The second prompt (Write) is what gives the
# watcher something to do and then lets it exit.
cmd_reset
perm_add p3 "$(( $(now) - 600 ))" 'Bash' 5 "$(( $(now) - 600 ))"
CLAUDE_VOICE_NOTIFY_NAG_EVERY=1 CLAUDE_VOICE_NOTIFY_NAG_MAX=1 run perm-request "$(j_permreq Write p4)"
hasnt "Bash" "a reminder at its cap stops repeating"

# nag_every=0 disables reminders entirely (nothing is even armed).
cmd_reset
CLAUDE_VOICE_NOTIFY_NAG_EVERY=0 run perm-request "$(j_permreq Bash p7)"
perm_has p7 && no "a reminder was armed with nag_every=0" "(armed)" || ok "nag interval 0 arms no reminder"

# Disarm: the tool running (i.e. the prompt was approved), a denial, and a new prompt. The
# approval case is also what makes a prompt answered quickly never get re-announced.
cmd_reset
perm_add p8 "$(now)" 'Bash' 0 "$(now)"
run tool-result '{"session_id":"sess","hook_event_name":"PostToolUse","tool_name":"Write","tool_use_id":"p8","tool_input":{},"tool_response":{}}'
perm_has p8 && no "approval did not disarm the reminder" "(still armed)" \
  || ok "approval disarms the reminder, so a prompt answered quickly is never re-announced"

cmd_reset
perm_add p9 "$(now)" 'Bash' 0 "$(now)"
run perm-denied '{"session_id":"sess","hook_event_name":"PermissionDenied","tool_name":"Bash","tool_use_id":"p9"}'
perm_has p9 && no "denial did not disarm the reminder" "(still armed)" || ok "denial disarms the reminder"

cmd_reset
perm_add p10 "$(now)" 'Bash' 0 "$(now)"
perm_add p11 "$(now)" 'Write' 0 "$(now)"
run start "$J_SESS"
{ perm_has p10 || perm_has p11; } && no "a new prompt left reminders armed" "(still armed)" \
  || ok "a new prompt disarms every reminder"

# Reminders are per prompt: disarming one leaves the other.
cmd_reset
perm_add p12 "$(now)" 'Bash' 0 "$(now)"
perm_add p13 "$(now)" 'Write' 0 "$(now)"
run perm-denied '{"session_id":"sess","hook_event_name":"PermissionDenied","tool_name":"Bash","tool_use_id":"p12"}'
{ ! perm_has p12 && perm_has p13; } && ok "reminders are independent per prompt" \
  || no "disarming one reminder affected the other" "(wrong set)"

# A stale reminder record is pruned rather than speaking forever.
cmd_reset
perm_add p15 "$(( $(now) - 99999 ))" 'Bash' 0 "$(( $(now) - 99999 ))"
CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL=60 CLAUDE_VOICE_NOTIFY_NAG_EVERY=1 CLAUDE_VOICE_NOTIFY_NAG_MAX=1 \
  run cmd-start "$(j_pre t35 'Another command' '')"
perm_has p15 && no "a stale reminder record survived" "(still present)" || ok "a stale reminder record is pruned"

# --- 8.11 mutes and degradation ---------------------------------------------------------------
cmd_reset
CLAUDE_VOICE_NOTIFY=off run tool-result "$(j_post t26 'Run the test suite' 90000)"
[ -z "$spoke" ] && ok "the global mute silences command cues" || no "spoke while globally muted" "$spoke"

cmd_reset
CLAUDE_VOICE_NOTIFY_CMD=off run tool-result "$(j_post t27 'Run the test suite' 90000)"
[ -z "$spoke" ] && ok "the command mute silences the completion cue" || no "spoke while command-muted" "$spoke"

cmd_reset
CLAUDE_VOICE_NOTIFY_CMD=off run cmd-start "$(j_pre t28 'Run the test suite' '')"
cmd_has t28 && no "the command mute still wrote command state" "(state written)" \
  || ok "the command mute writes no command state"

cmd_reset
PATH_USE="$bin_nomac"
run tool-result "$(j_post t29 'Run the test suite' 90000)"
rc=$?
{ [ -z "$spoke" ] && [ "$rc" = 0 ]; } && ok "no say -> command cue no-op, exit 0" || no "non-macOS path" "$spoke/$rc"
run cmd-start "$(j_pre t30 'Run the test suite' '')"
rc=$?
[ "$rc" = 0 ] && ok "no say -> cmd-start no-op, exit 0" || no "cmd-start exit code" "$rc"
PATH_USE="$bin_mac"

cmd_reset
PATH_USE="$bin_nojq"
run tool-result "$(j_post t31 'Run the test suite' 90000)"
rc=$?
{ [ -z "$spoke" ] && [ "$rc" = 0 ]; } && ok "no jq -> command cue silent, exit 0" || no "no-jq path" "$spoke/$rc"
PATH_USE="$bin_mac"

# Malformed knobs fall back to their defaults rather than breaking the hook.
cmd_reset
CLAUDE_VOICE_NOTIFY_CMD_QUIET_UNDER=abc run tool-result "$(j_post t32 'Run the test suite' 90000)"
has "Run the test suite" "a malformed quiet-under falls back to the default"
cmd_reset
CLAUDE_VOICE_NOTIFY_NAG_MAX=xyz run perm-request "$(j_permreq Bash p14)"
rc=$?
[ "$rc" = 0 ] && ok "a malformed nag cap falls back to the default" || no "malformed nag cap" "$rc"
# A leading-zero value must parse base-10, not octal (the 0900 class of bug).
cmd_reset
CLAUDE_VOICE_NOTIFY_CMD_QUIET_UNDER=0090 run tool-result "$(j_post t33 'Run the test suite' 90000)"
has "Run the test suite" "a leading-zero threshold parses base-10"

# --- 8.12 early exit for uninteresting tools -----------------------------------------------
cmd_reset
run tool-result '{"session_id":"sess","hook_event_name":"PostToolUse","tool_name":"Read","tool_use_id":"t34","tool_input":{"file_path":"/tmp/x"},"tool_response":{},"duration_ms":90000}'
rc=$?
{ [ -z "$spoke" ] && [ "$rc" = 0 ]; } && ok "an uninteresting tool speaks nothing and exits 0" || no "early exit" "$spoke/$rc"
[ -d "$work/vn-sess.cmd.d" ] && no "an uninteresting tool wrote command state" "(state written)" \
  || ok "an uninteresting tool writes no command state"
cmd_reset; all_reset

# --- review fixes: reminders armed from Notification, bg records pruned ------------------------
# The permission Notification is the event known to fire (it speaks the first request), so it is
# what arms the reminder and takes up the watch. NAG_MAX=1 lets the watcher finish promptly.
cmd_reset
CLAUDE_VOICE_NOTIFY_NAG_EVERY=1 CLAUDE_VOICE_NOTIFY_NAG_MAX=1 run notification "$J_PERM"
has "I need your permission to use Bash" "the permission notification still speaks first"
has_any "the permission notification arms and drives the reminder" "still need" "Still waiting" "still blocked" "Nothing's moving"

# It names the tool it parsed out of the message.
cmd_reset
CLAUDE_VOICE_NOTIFY_NAG_EVERY=1 CLAUDE_VOICE_NOTIFY_NAG_MAX=1 run notification "$J_PERM"
has "permission to use Bash" "the reminder names the tool from the notification"

# A prompt already armed by PermissionRequest must not be armed a second time.
cmd_reset
perm_add tuid9 "$(now)" 'Bash' 0 "$(now)"
CLAUDE_VOICE_NOTIFY_NAG_EVERY=60 CLAUDE_VOICE_NOTIFY_NAG_MAX=0 run notification "$J_PERM"
[ -f "$work/vn-sess.perm.d/pending" ] && no "the notification double-armed an armed prompt" "(two records)" \
  || ok "an already-armed prompt is not armed twice"

# PermissionRequest supersedes the anonymous record rather than adding to it.
cmd_reset
perm_add pending "$(now)" '' 0 "$(now)"
CLAUDE_VOICE_NOTIFY_NAG_EVERY=60 run perm-request "$(j_permreq Bash tuid10)"
{ perm_has tuid10 && ! perm_has pending; } && ok "PermissionRequest supersedes the anonymous record" \
  || no "anonymous record not superseded" "(wrong set)"

# PermissionRequest must return immediately: it can carry an allow/deny decision, so it never
# runs the watcher. With a due record present it would otherwise have spoken.
cmd_reset
perm_add pending "$(( $(now) - 600 ))" 'Bash' 0 "$(( $(now) - 600 ))"
CLAUDE_VOICE_NOTIFY_NAG_EVERY=1 CLAUDE_VOICE_NOTIFY_NAG_MAX=1 run perm-request "$(j_permreq Write tuid11)"
[ -z "$spoke" ] && ok "PermissionRequest never runs the watcher" || no "PermissionRequest ran the loop" "$spoke"

# Any tool completing answers a pending prompt, so it clears the anonymous record too.
cmd_reset
perm_add pending "$(now)" 'Bash' 0 "$(now)"
run tool-result '{"session_id":"sess","hook_event_name":"PostToolUse","tool_name":"Read","tool_use_id":"zz","tool_input":{},"tool_response":{}}'
[ -f "$work/vn-sess.perm.d/pending" ] && no "an anonymous reminder survived the tool running" "(still armed)" \
  || ok "any tool completing clears the anonymous reminder"

# A stale background record is pruned rather than kept forever.
cmd_reset
bg_add btold 'Start the dev server'
printf '%s\n%s\n' "$(( $(now) - 99999 ))" 'Start the dev server' > "$work/vn-sess.bg.d/btold"
CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL=60 run stop "$(j_stop_bt "$(bt_shell other)")"
bg_has btold && no "a stale background record survived" "(still present)" || ok "a stale background record is pruned"
cmd_reset; all_reset

# --- PreToolUse precedes the permission dialog ------------------------------------------------
# Verified against 2.1.220: a denied tool fires PreToolUse and nothing else — no PostToolUse, no
# PostToolUseFailure, not even PermissionDenied. So a command marker exists from the moment a call
# is proposed, not from when it starts running.

# A command waiting on an unanswered prompt must not be called "still running".
cmd_reset
cmd_add w1 "$(( $(now) - 100 ))" 'Run the test suite'
perm_add pending "$(now)" 'Bash' 0 "$(now)"
CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=1 CLAUDE_VOICE_NOTIFY_NAG_EVERY=1 CLAUDE_VOICE_NOTIFY_NAG_MAX=1 \
  run cmd-start "$(j_pre w2 'Another command' '')"
hasnt "Run the test suite" "a command blocked on a permission prompt is not called still running"

# With no prompt outstanding the same command is announced normally.
cmd_reset
cmd_add w3 "$(( $(now) - 100 ))" 'Run the test suite'
CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=1 run cmd-start "$(j_pre w4 'Another command' '')"
has "Run the test suite" "the same command is announced once nothing is blocked"

# A refused call leaves no marker to surface later as a phantom cue.
cmd_reset
cmd_add w5 "$(now)" 'Write a file'
cmd_said w5
run perm-denied '{"session_id":"sess","hook_event_name":"PermissionDenied","tool_name":"Write","tool_use_id":"w5"}'
cmd_has w5 && no "a refused call left its marker behind" "(still present)" || ok "a refused call drops its command marker"
[ -f "$work/vn-sess.cmdsaid.d/w5" ] && no "a refused call left its announced marker" "(still present)" \
  || ok "a refused call drops its announced marker"
cmd_reset; all_reset

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
