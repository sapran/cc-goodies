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
all_reset()     { spawn_reset; agents_reset; pending_reset; batch_reset; flags_reset; rm -f "$work/vn-sess.dispatch"; }
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
hasnt "didn't finish" "a completed agent uses the success pool"

all_reset
run agent-result "$J_FG_FAIL"
has_any "a failed agent uses the failure pool" "didn't finish" "came back empty" "no result from that one"

# PostToolUseFailure carries tool_input but no tool_response at all (an interrupted or errored
# agent tool call). The same arm must still name it and route it to the failure pool.
all_reset
run agent-result '{"session_id":"sess","tool_name":"Agent","tool_input":{"description":"Count to three"},"tool_use_id":"t1","error":"interrupted","is_interrupt":true}'
has "Count to three" "an interrupted agent is still named"
has_any "an interrupted agent uses the failure pool" "didn't finish" "came back empty" "no result from that one"

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
has_any "an empty result uses the failure pool" "didn't finish" "came back empty" "no result from that one"

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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
