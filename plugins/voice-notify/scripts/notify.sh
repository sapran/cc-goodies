#!/bin/bash
# cc-goodies / voice-notify
# Speak a short, rotating, first-person cue when Claude Code needs attention.
#
# Usage (from hooks):  notify.sh <event>
#   event = "stop" | "notification" | "start" | "dispatch" | "agent-result" | "subagent-stop"
#         | "tool-result" | "cmd-start" | "stop-failure" | "perm-request" | "perm-denied"
# The hook's JSON arrives on stdin: "notification" reads .message and .notification_type;
# "dispatch" reads .tool_input.description; "agent-result" reads .tool_input.description and
# .tool_response; "subagent-stop" reads .agent_id, .agent_type, .last_assistant_message and
# .background_tasks; "stop" reads .background_tasks; "cmd-start" reads .tool_input and
# .tool_use_id; "tool-result" reads .tool_name and dispatches to the agent or command path;
# "stop-failure" reads .error and .error_type; "perm-request" reads .tool_name and .tool_use_id;
# every event reads .session_id to key its ephemeral state.
#
# "tool-result" is matched on every tool, not just Agent/Bash, because approving a permission
# prompt is signalled only by the tool actually running. It therefore decides and exits as early
# as possible for tools it has nothing to say about.
#
# Only "stop" and "subagent-stop" are given .background_tasks by the harness, so those two are
# the only events that can tell whether background work is still outstanding. They leave that
# answer in a marker file for "notification", whose payload carries no such list.
#
# Environment:
#   CLAUDE_VOICE="Name"                 override the voice (default: "Matilda (Premium)")
#   CLAUDE_VOICE_NOTIFY=off             mute without uninstalling
#   CLAUDE_VOICE_NOTIFY_QUIET_UNDER=N   skip the Stop cue when the turn ran < N seconds
#                                       (default 20; set 0 to speak after every turn)
#   CLAUDE_VOICE_NOTIFY_GARNISH_PCT=N   chance (0-100) of a leading interjection (default 40)
#   CLAUDE_VOICE_NOTIFY_SUBAGENT=off    disable the whole subagent path (dispatch cue,
#                                       completion cues, in-flight tracking, waiting cue)
#   CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE=N  collapse a dispatch burst within N s (default 10)
#   CLAUDE_VOICE_NOTIFY_SUBAGENT_COLLECT=N   seconds the first dispatch of a burst waits for its
#                                       siblings to register before speaking (default 2), so the
#                                       cue can announce the whole burst and not just agent one
#   CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL=N  prune in-flight markers older than N s (default 3600),
#                                       so a subagent that never reports done can't wedge count
#   CLAUDE_VOICE_NOTIFY_AGENT_NAMES=off speak the pre-0.6.0 anonymous cues: no purposes, no
#                                       completion cues, no roll-up
#   CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP=N  name individual completions only while at most N
#                                       subagents are in flight (default 3)
#   CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX=N  characters of an agent description to speak (default 60)
#   CLAUDE_VOICE_NOTIFY_CMD=off         disable the whole shell-command path (still-running cue,
#                                       completion cues, background completion, the watcher)
#   CLAUDE_VOICE_NOTIFY_CMD_QUIET_UNDER=N  skip a finished command that ran < N seconds (default 60)
#   CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER=N  announce a command still running after N s (default 45;
#                                       0 disables the still-running cue only)
#   CLAUDE_VOICE_NOTIFY_NAG_EVERY=N     re-announce an unanswered permission prompt every N s
#                                       (default 60; 0 disables reminders)
#   CLAUDE_VOICE_NOTIFY_NAG_MAX=N       stop reminding after N repeats (default 5), so an
#                                       unattended session never talks all night
#
# macOS only (uses `say`). No-ops cleanly anywhere `say` is absent.

set -u
event="${1:-}"

# Mute switch.
[ "${CLAUDE_VOICE_NOTIFY:-on}" = "off" ] && exit 0
# No TTS engine -> nothing to do (keeps the hook harmless off macOS). Applies to
# every event, including "start": there's no point timing turns we can't announce.
command -v say >/dev/null 2>&1 || exit 0

# Read the hook payload once; every field below comes from here.
input=$(cat 2>/dev/null)

# --- config (env var -> default), validated to digits so bad input can't break math ---
quiet_under="${CLAUDE_VOICE_NOTIFY_QUIET_UNDER:-20}"
case "$quiet_under" in ''|*[!0-9]*) quiet_under=20 ;; esac
garnish_pct="${CLAUDE_VOICE_NOTIFY_GARNISH_PCT:-40}"
case "$garnish_pct" in ''|*[!0-9]*) garnish_pct=40 ;; esac
debounce="${CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE:-10}"
case "$debounce" in ''|*[!0-9]*) debounce=10 ;; esac
collect="${CLAUDE_VOICE_NOTIFY_SUBAGENT_COLLECT:-2}"
case "$collect" in ''|*[!0-9]*) collect=2 ;; esac
name_cap="${CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP:-3}"
case "$name_cap" in ''|*[!0-9]*) name_cap=3 ;; esac
desc_max="${CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX:-60}"
case "$desc_max" in ''|*[!0-9]*) desc_max=60 ;; esac
ttl="${CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL:-3600}"
case "$ttl" in ''|*[!0-9]*) ttl=3600 ;; esac
ttl=$((10#$ttl))   # force base-10: a leading-zero value (e.g. 0900) must not parse as octal
                   # inside the later $(( ... - ttl )), which would error and, under set -u,
                   # kill the whole stop arm (silencing every turn).
cmd_quiet="${CLAUDE_VOICE_NOTIFY_CMD_QUIET_UNDER:-60}"
case "$cmd_quiet" in ''|*[!0-9]*) cmd_quiet=60 ;; esac
cmd_quiet=$((10#$cmd_quiet))
cmd_running="${CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER:-45}"
case "$cmd_running" in ''|*[!0-9]*) cmd_running=45 ;; esac
cmd_running=$((10#$cmd_running))
nag_every="${CLAUDE_VOICE_NOTIFY_NAG_EVERY:-60}"
case "$nag_every" in ''|*[!0-9]*) nag_every=60 ;; esac
nag_every=$((10#$nag_every))
nag_max="${CLAUDE_VOICE_NOTIFY_NAG_MAX:-5}"
case "$nag_max" in ''|*[!0-9]*) nag_max=5 ;; esac
nag_max=$((10#$nag_max))

# The command path is on by default; "off" leaves every other cue untouched. Reminders are
# deliberately NOT gated on this — the two features are independently useful.
cmds="on"
[ "${CLAUDE_VOICE_NOTIFY_CMD:-on}" = "off" ] && cmds="off"

# Naming is the 0.6.0 behaviour; "off" restores the anonymous cues of earlier versions.
naming="on"
[ "${CLAUDE_VOICE_NOTIFY_AGENT_NAMES:-on}" = "off" ] && naming="off"

# --- voice resolution, done lazily so "start" never pays for `say -v '?'` ---
voice_resolved=""
voice_val=""
resolve_voice() {
  [ -n "$voice_resolved" ] && return
  voice_resolved=1
  voice_val="${CLAUDE_VOICE:-Matilda (Premium)}"
  # Fall back to the system default if the configured voice isn't installed
  # (teammates won't necessarily have the premium download).
  say -v '?' 2>/dev/null | grep -qF "$voice_val" || voice_val=""
}
speak() {
  resolve_voice
  if [ -n "$voice_val" ]; then say -v "$voice_val" "$1"; else say "$1"; fi
}

# read_ts / read_kv: first and second line of a marker file, empty when absent.
read_ts() {
  local t=""
  [ -f "$1" ] || { printf ''; return 0; }
  IFS= read -r t < "$1" 2>/dev/null
  printf '%s' "$t"
}
read_kv() {
  [ -f "$1" ] || { printf ''; return 0; }
  sed -n '2p' "$1" 2>/dev/null
}
# read_line <file> <n>: nth line, empty when absent. Reminder records carry four.
read_line() {
  [ -f "$1" ] || { printf ''; return 0; }
  sed -n "${2}p" "$1" 2>/dev/null
}

# Cues can now originate from several agents finishing at once, so two `say` calls could
# overlap and render each other unintelligible. Serialise through a create-only lock dir:
# whoever creates it speaks, the rest wait briefly and then give up. A dropped cue beats a
# backlog of stale ones, and a lock left behind by a killed process is reclaimed by age so the
# plugin can never be wedged into permanent silence.
LOCK_WAIT=4     # seconds a cue will wait for its turn before giving up
LOCK_STALE=45   # a lock older than this belonged to a process that died holding it
speak_locked() {
  local ld waited ts now
  ld="${TMPDIR:-/tmp}/vn-speak.lock.d"
  waited=0
  while :; do
    if mkdir "$ld" 2>/dev/null; then
      date +%s > "$ld/ts" 2>/dev/null
      speak "$1"
      rm -rf "$ld" 2>/dev/null
      return 0
    fi
    ts=$(read_ts "$ld/ts")
    case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
    now=$(date +%s)
    if [ "$ts" -gt 0 ] && [ "$(( now - ts ))" -ge "$LOCK_STALE" ]; then
      rm -rf "$ld" 2>/dev/null
      continue
    fi
    waited=$((waited + 1))
    [ "$waited" -gt "$LOCK_WAIT" ] && return 0   # drop, never queue
    sleep 1
  done
}

# Shell-agnostic random line picker: awk does 1-based indexing identically in
# bash/zsh/sh; seeded per-process from $RANDOM so separate hook fires vary.
pick() { awk -v s="${RANDOM:-$$}" 'BEGIN{srand(s)} {a[NR]=$0} END{if(NR)print a[int(rand()*NR)+1]}'; }

# A brief silence between the garnish and the core so the cue sounds spoken, not
# read. `say` honours [[slnc N]] (ms) and never voices it as text.
PAUSE='[[slnc 250]]'

# Garnish fires only some of the time: a lead-in on every cue reads as a formula,
# an occasional one reads as a person. Probability is CLAUDE_VOICE_NOTIFY_GARNISH_PCT.
want_garnish() {
  awk -v s="${RANDOM:-$$}" -v p="$garnish_pct" 'BEGIN{srand(s); exit !(int(rand()*100) < p)}'
}

# compose <garnish-pool> <core>: always speak the core; sometimes prefix a garnish
# drawn from the pool, joined by a comma + pause. Multiplicative variety from small
# pools instead of one flat list.
compose() {
  local pool="$1" core="$2" g
  if [ -n "$pool" ] && want_garnish; then
    g=$(printf '%s\n' "$pool" | pick)
    printf '%s, %s %s' "$g" "$PAUSE" "$core"
  else
    printf '%s' "$core"
  fi
}

# Small numbers read better as words than as digits.
num_word() {
  case "$1" in
    1) printf 'one' ;;   2) printf 'two' ;;   3) printf 'three' ;;
    4) printf 'four' ;;  5) printf 'five' ;;  6) printf 'six' ;;
    7) printf 'seven' ;; 8) printf 'eight' ;; 9) printf 'nine' ;;
    10) printf 'ten' ;;  *) printf '%s' "$1" ;;
  esac
}

# --- phrase pools (small on purpose; compose() multiplies them) ---
BRISK_GARNISH="Hey
Heads up
Quick one
Excuse me
Knock knock"

GENTLE_GARNISH="Whenever you're ready
No rush
When you get a sec
When you have a moment"

NEUTRAL_GARNISH="Hey
So
Right
Okay
Hey there"

STOP_CORES="All done.
Done.
Finished.
Ready when you are.
Your turn.
Back to you.
That's a wrap.
Over to you.
Done and dusted.
Wrapped up."

STOP_LONG_CORES="Okay, that took a bit, but it's done.
Phew, finally done.
That one took a while. All wrapped up.
Done at last.
Took some doing, but it's finished.
All done. Thanks for waiting."

# Dispatch cue: a distinct pool that signals work-still-going (the main agent handed
# off to subagents and paused), never a sign-off — keeps "your turn" and "still working"
# audibly different. Used when naming is off or no purpose could be resolved.
SUBAGENT_CORES="Spinning up some helpers, back in a bit.
Working with a few helpers now.
Handing some work off, give me a moment.
Got some sub-agents on it, hang tight.
Delegating this, back shortly."

# Lead-ins for a *named* single dispatch: "<lead> — review script changes."
DISPATCH_ONE_LEADS="Handing off
Off to a helper
Delegating
One helper on it
Someone's on it"

# Waiting cue: the turn ended but background subagents are still running, so a turn-end
# sign-off would be a false "finished". Distinct from the dispatch pool (which announces the
# hand-off) and the sign-off pools — this marks a turn boundary with work still outstanding.
WAITING_CORES="Still going, the helpers aren't done yet.
Not done yet, the agents are still working.
Paused here, but the sub-agents are still running.
Holding for the helpers to finish.
Agents still busy, not your turn just yet.
Work's still out with the helpers."

# Completion cues: spoken as "<purpose> <suffix>", so the purpose leads and the pool only
# varies the tail. Distinct pools for a clean finish and one that came back with nothing.
DONE_SUFFIXES="— done.
— finished.
— is back.
— wrapped up."

FAIL_SUFFIXES="— that one didn't finish.
— that one has failed.
— no result from that one."

# Used when a completion can't be attributed to any purpose or agent type.
DONE_ANON_CORES="A helper's done.
One of the helpers is back.
That's one helper finished."

FAIL_ANON_CORES="A helper didn't finish.
One of the helpers came back empty."

# Roll-up: the batch drained. Distinct from the sign-off pools so it never reads as turn-end.
ROLLUP_ONE_CORES="The helper's back.
That one's back now.
Helper's done."

# --- shell-command pools ---
# Still-running: spoken as "<lead> <purpose>." while a command is in flight. A separate pool from
# the subagent hand-off so "a command is slow" never sounds like "I delegated something".
CMD_RUNNING_LEADS="Still running
Still going
This one's taking a while
Still working on
Give it a moment"

CMD_RUNNING_ANON_CORES="A command's still running.
Something's still going here.
Still waiting on a command."

# Command completion, spoken as "<purpose> <suffix>" so the purpose leads.
CMD_DONE_SUFFIXES="— done.
— finished.
— that's finished.
— all done."

CMD_FAIL_SUFFIXES="— that one failed.
— that didn't work.
— came back with an error."

CMD_TIMEOUT_SUFFIXES="— that one timed out.
— timed out waiting on that."

CMD_INTERRUPT_SUFFIXES="— that one was interrupted.
— that got cut short."

CMD_DONE_ANON_CORES="That command's done.
The command finished.
That one's finished."

CMD_FAIL_ANON_CORES="A command failed.
That command came back with an error."

# Background completion. Phrased so it never implies immediacy: it is noticed at a turn
# boundary, which can be a while after the command actually exited.
BG_DONE_LEADS="That background job is done
The background one finished
Background job's finished"

BG_DONE_ANON_CORES="A background command has finished.
The background job is done."

# --- blocked-session pools ---
# Stalled: the turn died on an API error, so no sign-off will ever come. Distinct from every
# other pool — this is the one cue that means "nothing more is happening".
STALL_CORES="I've stalled — something went wrong with the API.
That turn didn't finish. The API errored out.
I've stopped — an API error ended the turn."

STALL_RATE_CORES="I've stalled — I'm being rate limited.
Hit a rate limit, so that turn stopped.
Rate limited. I've stopped for now."

STALL_BUSY_CORES="I've stalled — the servers are overloaded.
The API is overloaded, so that turn stopped."

STALL_AUTH_CORES="I've stopped — there's an authentication problem.
Authentication failed, so I can't carry on."

STALL_BILLING_CORES="I've stopped — there's a billing problem on the account.
Billing error. I can't carry on until that's sorted."

STALL_LIMIT_CORES="I've stopped — I hit the output limit for that response.
That response ran past its length limit and stopped."

# Permission reminder: audibly a repeat, never mistakable for the first request.
NAG_LEADS="Still waiting on you
I'm still blocked
Still need you here
Nothing's moving until you answer"

# --- duration state (ephemeral, $TMPDIR only; OS clears it, /plugin uninstall is enough) ---
session_id() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null \
    | tr -cd 'A-Za-z0-9._-'   # UUIDs only; never let a stray char escape the path
}
state_file() { printf '%s/vn-%s.start' "${TMPDIR:-/tmp}" "$1"; }
dispatch_file() { printf '%s/vn-%s.dispatch' "${TMPDIR:-/tmp}" "$1"; }

# --- in-flight subagent accounting (create-only marker dirs per session) ---
# Spawn markers (one per dispatch, uniquely named) and done markers (one per completion, named
# by agent_id so a duplicate SubagentStop overwrites instead of double-counting). Each marker's
# first line is its creation epoch, so prune_dir can age out stale ones without stat(1). Writers
# only ever create distinct paths, so concurrent async hooks never race a read-modify-write.
# These are the *fallback* count: when the payload carries `background_tasks`, that list wins.
spawn_dir() { printf '%s/vn-%s.spawn.d' "${TMPDIR:-/tmp}" "$1"; }
done_dir()  { printf '%s/vn-%s.done.d'  "${TMPDIR:-/tmp}" "$1"; }
# agent_id -> description, recorded when a background agent is launched, so its completion can
# still be named if the harness has already dropped it from `background_tasks`.
agents_dir()  { printf '%s/vn-%s.agents.d'  "${TMPDIR:-/tmp}" "$1"; }
# Descriptions dispatched in the current burst, awaiting the burst's single spoken cue.
pending_dir() { printf '%s/vn-%s.pending.d' "${TMPDIR:-/tmp}" "$1"; }
# One marker per agent dispatched in the current batch, so the roll-up can say how many.
batch_dir()   { printf '%s/vn-%s.batch.d'   "${TMPDIR:-/tmp}" "$1"; }
# Create-only claim on a dispatch burst: the winner waits for siblings, then speaks.
burst_dir()   { printf '%s/vn-%s.burst.d'   "${TMPDIR:-/tmp}" "$1"; }
# Per-turn flags: a waiting cue was spoken / the name cap suppressed a completion cue. Either
# means the batch owes the user a roll-up when it finally drains.
waited_file() { printf '%s/vn-%s.waited' "${TMPDIR:-/tmp}" "$1"; }
capped_file() { printf '%s/vn-%s.capped' "${TMPDIR:-/tmp}" "$1"; }
# Busy marker: "the harness reported outstanding work the last time we could see it". Only Stop
# and SubagentStop carry the task list; a Notification carries none, so the idle cue reads this
# instead of guessing. First line is the epoch, so the in-flight TTL ages it out and a marker
# orphaned by a killed process can never mute the idle cue for good.
busy_file() { printf '%s/vn-%s.busy' "${TMPDIR:-/tmp}" "$1"; }

# --- shell-command state ---
# A running foreground command, keyed by tool_use_id: epoch on line 1, purpose on line 2. Its
# presence is what the watcher polls; its absence is what lets the watcher exit.
cmd_dir()     { printf '%s/vn-%s.cmd.d'     "${TMPDIR:-/tmp}" "$1"; }
# "The still-running cue for this command has been spoken." Separate create-only marker rather
# than a third line, so the watcher never rewrites a record another hook may be reading.
cmdsaid_dir() { printf '%s/vn-%s.cmdsaid.d' "${TMPDIR:-/tmp}" "$1"; }
# backgroundTaskId -> purpose, recorded at the launch acknowledgement. The harness fires no
# completion event for a background command, so its finish is detected as the id's *absence*
# from a later payload's background_tasks.
bg_dir()      { printf '%s/vn-%s.bg.d'      "${TMPDIR:-/tmp}" "$1"; }
# An unanswered permission prompt, keyed by tool_use_id: creation epoch (line 1, so the TTL
# prunes from when the prompt appeared), tool name (2), repeats so far (3), last-spoken epoch (4).
perm_dir()    { printf '%s/vn-%s.perm.d'    "${TMPDIR:-/tmp}" "$1"; }
# Create-only election: exactly one watcher polls per session. Its ts is refreshed every poll,
# so a live watcher is never displaced and a dead one is reclaimed promptly.
watch_dir()   { printf '%s/vn-%s.watch.d'   "${TMPDIR:-/tmp}" "$1"; }

# Seconds between polls. Configurable mainly so the test suite can drive the watcher
# quickly; there is little reason to change it in normal use.
WATCH_POLL="${CLAUDE_VOICE_NOTIFY_WATCH_POLL:-5}"
case "$WATCH_POLL" in ''|*[!0-9]*) WATCH_POLL=5 ;; esac
WATCH_POLL=$((10#$WATCH_POLL))
[ "$WATCH_POLL" -lt 1 ] && WATCH_POLL=1
WATCH_MAX_LIFE=900  # hard stop, so a watcher can never outlive its usefulness unboundedly
WATCH_STALE=45      # an election whose heartbeat stopped this long ago is reclaimable

# set_busy <sid> <count>: record outstanding work, or clear the record when nothing is left.
# A non-numeric count means we never resolved one — leave the record untouched rather than
# inventing an all-clear.
set_busy() {
  case "$2" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$2" -gt 0 ]; then
    date +%s > "$(busy_file "$1")" 2>/dev/null
  else
    rm -f "$(busy_file "$1")" 2>/dev/null
  fi
}

# is_busy <sid>: true only when the record exists and is younger than the in-flight TTL.
is_busy() {
  local ts
  ts=$(read_ts "$(busy_file "$1")")
  case "$ts" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(( $(date +%s) - ts ))" -lt "$ttl" ]
}

# Read .agent_id / .agent_type, with the id sanitised so it is safe as a filename.
agent_id() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$input" | jq -r '.agent_id // ""' 2>/dev/null \
    | tr -cd 'A-Za-z0-9._-'
}
agent_type() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$input" | jq -r '.agent_type // ""' 2>/dev/null
}

# mark <dir> <name>: create/overwrite a marker whose first line is the current epoch.
mark() {
  mkdir -p "$1" 2>/dev/null || return 0
  date +%s > "$1/$2" 2>/dev/null
}

# mark_kv <dir> <name> <value>: epoch on line 1, free text on line 2.
mark_kv() {
  mkdir -p "$1" 2>/dev/null || return 0
  printf '%s\n%s\n' "$(date +%s)" "$3" > "$1/$2" 2>/dev/null
}

# count_dir <dir>: number of marker files, via globbing only (no ls/find needed off-PATH).
count_dir() {
  local d="$1" n=0 f
  [ -d "$d" ] || { printf 0; return; }
  for f in "$d"/*; do [ -e "$f" ] && n=$((n+1)); done
  printf '%s' "$n"
}

# prune_dir <dir> <cutoff-epoch>: drop markers older than the cutoff (or with an empty first
# line from a failed write). Non-numeric content is kept — fail toward "still in-flight", never
# a false all-clear that would let a premature sign-off through.
prune_dir() {
  local d="$1" cutoff="$2" f ts
  [ -d "$d" ] || return 0
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    ts=$(read_ts "$f")
    case "$ts" in
      '')       rm -f "$f" 2>/dev/null ;;
      *[!0-9]*) : ;;
      *)        [ "$ts" -lt "$cutoff" ] && rm -f "$f" 2>/dev/null ;;
    esac
  done
}

# inflight_markers <sid>: the fallback count — spawns minus completions, clamped at zero,
# after pruning anything stale. Fed only by the Agent-matched hooks, so it sees subagents and
# nothing else: a workflow is not an Agent call and leaves no marker. That gap is deliberate.
# This path exists for Claude Code versions whose Stop payload carries no task list; on versions
# that do carry one, inflight_payload wins and already covers every kind of work. Closing the gap
# here would mean new hook matchers and per-kind completion tracking for no gain.
inflight_markers() {
  local sid="$1" cutoff n
  cutoff=$(( $(date +%s) - ttl ))
  prune_dir "$(spawn_dir "$sid")" "$cutoff"
  prune_dir "$(done_dir "$sid")" "$cutoff"
  prune_dir "$(agents_dir "$sid")" "$cutoff"
  n=$(( $(count_dir "$(spawn_dir "$sid")") - $(count_dir "$(done_dir "$sid")") ))
  [ "$n" -lt 0 ] && n=0
  printf '%s' "$n"
}

# inflight_payload <exclude-agent-id>: background work still registered with the harness,
# excluding the one whose completion is being handled (it is still listed, as "running", at its
# own stop). Returns non-zero when the payload carries no task list, so callers fall back to the
# markers.
#
# The harness reports several kinds of work here — subagent, workflow, shell, monitor, MCP task,
# teammate, dream, auto-mode scan, cloud session. This counts everything *except* shell and
# monitor: a background command is often a long-lived server and a monitor is a standing watch,
# so counting either would mute the turn-end sign-off for the rest of the session. Deliberately a
# block-list, not an allow-list — a task type added by a future Claude Code counts as outstanding
# by default, which errs toward "still working" the way prune_dir errs on unreadable markers. A
# spurious waiting cue is a nuisance; a sign-off spoken over running work is a lie.
inflight_payload() {
  local n
  command -v jq >/dev/null 2>&1 || return 1
  n=$(printf '%s' "$input" | jq -r --arg me "$1" '
        if (.background_tasks | type) == "array" then
          [ .background_tasks[]
            | select(.type != "shell" and .type != "monitor")
            | select(.id != $me) ] | length
        else "" end' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$n"
}

# bt_self <agent-id>: "yes|<description>" when the agent is listed in the payload's task list
# (i.e. it is a background agent), "no" otherwise. A foreground agent never appears there.
bt_self() {
  command -v jq >/dev/null 2>&1 || { printf 'no'; return 0; }
  printf '%s' "$input" | jq -r --arg me "$1" '
      ((.background_tasks // []) | map(select(.id == $me))) as $m
      | if ($m | length) > 0 then "yes|" + (($m[0].description // "") | tostring) else "no" end' \
      2>/dev/null
}

# Descriptions are model-authored free text. Strip control characters, fold whitespace,
# neutralise `say`'s [[...]] directive syntax so a description can't inject prosody commands,
# and truncate on a word boundary. Always passed to `say` as one quoted argument — never
# interpolated into a command — so shell metacharacters inside it stay inert.
sanitise_desc() {
  local s
  s=$(printf '%s' "$1" \
      | tr -d '\000-\010\013\014\016-\037\177' \
      | tr '\011\012' '  ' \
      | sed 's/\[\[/ /g; s/\]\]/ /g; s/  */ /g; s/^ //; s/ *$//')
  if [ "${#s}" -gt "$desc_max" ]; then
    s=${s:0:$desc_max}
    case "$s" in *' '*) s=${s% *} ;; esac
  fi
  printf '%s' "$s"
}

# Read a description out of the tool call being dispatched / reported on. Note this is the
# model-authored *description* only — .tool_input.command is never read for speech, because a
# command line routinely carries tokens and paths that must not be read aloud.
tool_desc() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$input" | jq -r '.tool_input.description // ""' 2>/dev/null
}

tool_name() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null
}
# Sanitised for use as a filename: tool_use_id is harness-generated, but it keys a path.
tool_use_id() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$input" | jq -r '.tool_use_id // ""' 2>/dev/null | tr -cd 'A-Za-z0-9._-'
}
hook_event() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null
}

# speak_cmd_running <purpose>: the still-running cue.
speak_cmd_running() {
  local purpose="$1" core lead
  if [ -n "$purpose" ]; then
    lead=$(printf '%s\n' "$CMD_RUNNING_LEADS" | pick)
    core="$lead: $purpose."
  else
    core=$(printf '%s\n' "$CMD_RUNNING_ANON_CORES" | pick)
  fi
  speak_locked "$(compose "$NEUTRAL_GARNISH" "$core")"
}

# speak_cmd_done <purpose> <outcome>: outcome is ok | fail | timeout | interrupt.
speak_cmd_done() {
  local purpose="$1" outcome="$2" core suffix
  if [ -n "$purpose" ]; then
    case "$outcome" in
      ok)        suffix=$(printf '%s\n' "$CMD_DONE_SUFFIXES" | pick) ;;
      timeout)   suffix=$(printf '%s\n' "$CMD_TIMEOUT_SUFFIXES" | pick) ;;
      interrupt) suffix=$(printf '%s\n' "$CMD_INTERRUPT_SUFFIXES" | pick) ;;
      *)         suffix=$(printf '%s\n' "$CMD_FAIL_SUFFIXES" | pick) ;;
    esac
    core="$purpose $suffix"
  else
    case "$outcome" in
      ok) core=$(printf '%s\n' "$CMD_DONE_ANON_CORES" | pick) ;;
      *)  core=$(printf '%s\n' "$CMD_FAIL_ANON_CORES" | pick) ;;
    esac
  fi
  speak_locked "$(compose "$NEUTRAL_GARNISH" "$core")"
}

# speak_bg_done <purpose>: a background command noticed as finished at a turn boundary.
speak_bg_done() {
  local purpose="$1" core lead
  if [ -n "$purpose" ]; then
    lead=$(printf '%s\n' "$BG_DONE_LEADS" | pick)
    core="$lead: $purpose."
  else
    core=$(printf '%s\n' "$BG_DONE_ANON_CORES" | pick)
  fi
  speak_locked "$(compose "$NEUTRAL_GARNISH" "$core")"
}

# drain_bg <sid>: announce every recorded background command whose id has left the payload's
# task list. Silent — and non-destructive — when the payload carries no list at all, so a
# version or event without one can never be read as "everything finished".
drain_bg() {
  local sid="$1" d have ids f id desc
  [ "$cmds" = "off" ] && return 0
  command -v jq >/dev/null 2>&1 || return 0
  d=$(bg_dir "$sid")
  [ -d "$d" ] || return 0
  # Aged out like every other marker dir, so a command whose id never leaves the list cannot
  # leave a record behind indefinitely.
  prune_dir "$d" "$(( $(date +%s) - ttl ))"
  # "Is there a list at all?" is asked separately from "what is in it", so an empty list (every
  # background command has finished) stays distinguishable from no list (nothing to conclude).
  have=$(printf '%s' "$input" \
         | jq -r 'if (.background_tasks | type) == "array" then "yes" else "no" end' 2>/dev/null)
  [ "$have" = "yes" ] || return 0
  ids=$(printf '%s' "$input" | jq -r '.background_tasks[].id // empty' 2>/dev/null)
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    id=${f##*/}
    # Still listed as running -> nothing to say yet.
    printf '%s\n' "$ids" | grep -qxF "$id" && continue
    desc=$(read_kv "$f")
    rm -f "$f" 2>/dev/null
    speak_bg_done "$desc"
  done
}

# nag_due <file> <now>: true when this reminder is due to speak again and still under its cap.
nag_due() {
  local f="$1" now="$2" count last
  [ "$nag_every" -gt 0 ] || return 1
  count=$(read_line "$f" 3); case "$count" in ''|*[!0-9]*) count=0 ;; esac
  [ "$((10#$count))" -ge "$nag_max" ] && return 1
  last=$(read_line "$f" 4); case "$last" in ''|*[!0-9]*) last=0 ;; esac
  [ "$last" -eq 0 ] && last=$(read_ts "$f")
  case "$last" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(( now - last ))" -ge "$nag_every" ]
}

# watch_pending <sid>: work this watcher can still act on — commands not yet announced, and
# reminders that have not hit their repeat cap. Everything else has already been said, so the
# watcher exits instead of spinning until a command it can no longer speak about finishes. A
# later command or prompt elects a fresh watcher, so exiting early costs nothing.
watch_pending() {
  local sid="$1" n=0 f id count blocked=""
  # Mirrors the watch loop: while a prompt is outstanding, commands are not announceable, so they
  # are not work this watcher can act on. The reminders themselves keep it alive.
  [ "$(count_dir "$(perm_dir "$sid")")" -gt 0 ] && blocked=1
  if [ "$cmds" = "on" ] && [ "$cmd_running" -gt 0 ] && [ -z "$blocked" ]; then
    for f in "$(cmd_dir "$sid")"/*; do
      [ -e "$f" ] || continue
      id=${f##*/}
      [ -e "$(cmdsaid_dir "$sid")/$id" ] && continue
      n=$((n+1))
    done
  fi
  if [ "$nag_every" -gt 0 ]; then
    for f in "$(perm_dir "$sid")"/*; do
      [ -e "$f" ] || continue
      count=$(read_line "$f" 3)
      case "$count" in ''|*[!0-9]*) count=0 ;; esac
      [ "$((10#$count))" -ge "$nag_max" ] && continue
      n=$((n+1))
    done
  fi
  printf '%s' "$n"
}

# watch_loop <sid>: the single elected poller. Speaks the still-running cue for commands that
# outlived the threshold and re-announces unanswered permission prompts, then exits as soon as
# neither remains. The harness kills hook processes when the session ends, so this is bounded in
# practice by the session; WATCH_MAX_LIFE is the belt-and-braces stop.
watch_loop() {
  local sid="$1" started now f id ts desc count tool cutoff
  started=$(date +%s)
  while :; do
    now=$(date +%s)
    [ "$(( now - started ))" -ge "$WATCH_MAX_LIFE" ] && break
    # Heartbeat: proves to a would-be challenger that this watcher is alive.
    date +%s > "$(watch_dir "$sid")/ts" 2>/dev/null

    cutoff=$(( now - ttl ))
    prune_dir "$(cmd_dir "$sid")" "$cutoff"
    prune_dir "$(cmdsaid_dir "$sid")" "$cutoff"
    prune_dir "$(perm_dir "$sid")" "$cutoff"

    # PreToolUse fires *before* the permission dialog, so a command marker exists from the moment
    # a call is proposed — not from when it starts running. While a prompt is outstanding the
    # session is blocked and nothing is executing, so announcing "still running" would be false.
    # Verified against 2.1.220: a denied tool produces PreToolUse and nothing else at all.
    blocked=""
    [ "$(count_dir "$(perm_dir "$sid")")" -gt 0 ] && blocked=1
    if [ "$cmds" = "on" ] && [ "$cmd_running" -gt 0 ] && [ -z "$blocked" ]; then
      for f in "$(cmd_dir "$sid")"/*; do
        [ -e "$f" ] || continue
        id=${f##*/}
        [ -e "$(cmdsaid_dir "$sid")/$id" ] && continue
        ts=$(read_ts "$f")
        case "$ts" in ''|*[!0-9]*) continue ;; esac
        if [ "$(( now - ts ))" -ge "$cmd_running" ]; then
          desc=$(read_kv "$f")
          # Mark before speaking: speak_locked can block for seconds, and a second pass must
          # never re-announce the same command.
          mark "$(cmdsaid_dir "$sid")" "$id"
          speak_cmd_running "$desc"
        fi
      done
    fi

    for f in "$(perm_dir "$sid")"/*; do
      [ -e "$f" ] || continue
      nag_due "$f" "$now" || continue
      tool=$(read_line "$f" 2)
      count=$(read_line "$f" 3); case "$count" in ''|*[!0-9]*) count=0 ;; esac
      count=$(( 10#$count + 1 ))
      ts=$(read_ts "$f"); case "$ts" in ''|*[!0-9]*) ts="$now" ;; esac
      # Rewrite in place: the watcher is the only writer of lines 3 and 4.
      printf '%s\n%s\n%s\n%s\n' "$ts" "$tool" "$count" "$now" > "$f" 2>/dev/null
      speak_nag "$tool"
    done

    # Nothing left this watcher can act on.
    [ "$(watch_pending "$sid")" -eq 0 ] && break
    sleep "$WATCH_POLL"
  done
  rm -rf "$(watch_dir "$sid")" 2>/dev/null
}

# speak_nag <tool>: the repeat-request reminder.
speak_nag() {
  local tool="$1" lead core
  lead=$(printf '%s\n' "$NAG_LEADS" | pick)
  if [ -n "$tool" ]; then
    core="$lead — I still need your permission to use $tool."
  else
    core="$lead — that permission request is still sitting there."
  fi
  speak_locked "$(compose "$BRISK_GARNISH" "$core")"
}

# elect_watcher <sid>: become the session's watcher, or return without doing anything. The claim
# is create-only so a race can only ever produce one winner; a claim whose heartbeat has stopped
# is reclaimed so a killed watcher cannot silence the feature for the rest of the session.
elect_watcher() {
  local sid="$1" wd ts now
  wd=$(watch_dir "$sid")
  if mkdir "$wd" 2>/dev/null; then
    date +%s > "$wd/ts" 2>/dev/null
    watch_loop "$sid"
    return 0
  fi
  ts=$(read_ts "$wd/ts")
  case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
  now=$(date +%s)
  if [ "$ts" -gt 0 ] && [ "$(( now - ts ))" -ge "$WATCH_STALE" ]; then
    rm -rf "$wd" 2>/dev/null
    if mkdir "$wd" 2>/dev/null; then
      date +%s > "$wd/ts" 2>/dev/null
      watch_loop "$sid"
      return 0
    fi
  fi
  return 1
}

# disarm_perm <sid> <tool_use_id>: the prompt was answered (the tool ran, or was denied).
disarm_perm() {
  # A pending permission prompt blocks the session, so *any* tool completing means it was
  # answered. That clears the anonymous record as well as the id-keyed one.
  rm -f "$(perm_dir "$1")/pending" 2>/dev/null
  [ -n "$2" ] || return 0
  rm -f "$(perm_dir "$1")/$2" 2>/dev/null
}

# drop_cmd <sid> <tool_use_id>: forget a proposed command. A call that is refused never reaches
# PostToolUse — the harness fires PreToolUse and nothing else — so without this its marker would
# survive to the TTL and then be announced as a command that never ran.
drop_cmd() {
  [ -n "$2" ] || return 0
  rm -f "$(cmd_dir "$1")/$2" "$(cmdsaid_dir "$1")/$2" 2>/dev/null
}

# Map a Notification message to (subtype, first-person reason). Allow-list only:
# unrecognised wording falls through to a neutral cue rather than being mangled.
sub=""
reason=""
classify() {
  local m="$1" ntype="$2" im="I'm" clean
  clean=$(sanitise_desc "$m")
  # The payload's own type is authoritative when present; wording matching is the fallback for
  # payloads (and Claude Code versions) that don't carry one.
  case "$ntype" in
    agent_completed)
      sub="agent_done"
      reason="${clean:-A helper has finished.}"
      return
      ;;
    agent_needs_input)
      sub="agent_input"
      reason="${clean:-A helper needs your input.}"
      return
      ;;
  esac
  case "$m" in
    *"permission"*)
      sub="permission"
      reason="${m/Claude needs/I need}"
      reason="${reason/Claude is/$im}"
      ;;
    *"needs your input"*)
      sub="agent_input"
      reason="${clean:-A helper needs your input.}"
      ;;
    *" finished"*|*" failed"*)
      sub="agent_done"
      reason="${clean:-A helper has finished.}"
      ;;
    *"waiting for"*|*"is waiting"*|*"idle"*)
      sub="idle"
      reason="${m/Claude is/$im}"
      reason="${reason/Claude needs/I need}"
      ;;
    *)
      sub="neutral"
      reason="I need your attention."
      ;;
  esac
}

# speak_completion <purpose> <agent-type> <ok?>: one named completion cue, or an anonymous one
# when nothing identifies the agent.
speak_completion() {
  local purpose="$1" atype="$2" ok="$3" core suffix
  if [ -z "$purpose" ] && [ -n "$atype" ]; then
    purpose="the $atype helper"
  fi
  if [ -n "$purpose" ]; then
    if [ "$ok" = "yes" ]; then
      suffix=$(printf '%s\n' "$DONE_SUFFIXES" | pick)
    else
      suffix=$(printf '%s\n' "$FAIL_SUFFIXES" | pick)
    fi
    core="$purpose $suffix"
  else
    if [ "$ok" = "yes" ]; then
      core=$(printf '%s\n' "$DONE_ANON_CORES" | pick)
    else
      core=$(printf '%s\n' "$FAIL_ANON_CORES" | pick)
    fi
  fi
  speak_locked "$(compose "$NEUTRAL_GARNISH" "$core")"
}

# speak_rollup <sid>: the batch drained and owed the user a summary. Counts the agents
# dispatched this batch so the cue can say how many came back.
speak_rollup() {
  local sid="$1" n core w
  n=$(count_dir "$(batch_dir "$sid")")
  if [ "$n" -le 1 ]; then
    core=$(printf '%s\n' "$ROLLUP_ONE_CORES" | pick)
  else
    w=$(num_word "$n")
    core=$(printf '%s\n' "All $w helpers are back.
That's all $w helpers back.
$w helpers, all done.
All $w are back now." | pick)
  fi
  speak_locked "$(compose "$NEUTRAL_GARNISH" "$core")"
}

# clear_batch <sid>: forget the per-turn roll-up bookkeeping.
clear_batch() {
  rm -f "$(waited_file "$1")" "$(capped_file "$1")" 2>/dev/null
  rm -rf "$(batch_dir "$1")" "$(pending_dir "$1")" 2>/dev/null
}

# settle <sid> <inflight>: after a completion, decide whether the batch just drained and owes
# the user a roll-up — it does when a waiting cue promised one, or the name cap suppressed the
# individual cues. A batch that was named all the way through has already said everything.
settle() {
  local sid="$1" n="$2" owed=""
  [ "$n" -gt 0 ] && return 0
  [ -f "$(waited_file "$sid")" ] && owed=1
  [ -f "$(capped_file "$sid")" ] && owed=1
  [ -n "$owed" ] && speak_rollup "$sid"
  clear_batch "$sid"
}

# handle_agent_result: PostToolUse / PostToolUseFailure for the Agent tool.
handle_agent_result() {
  # The Agent tool returned to the parent. For a foreground agent that is its completion —
  # the payload carries both the description and the result. For a background agent it is a
  # launch acknowledgement fired milliseconds after dispatch: record the id-to-purpose join
  # for its later SubagentStop, and say nothing.
  [ "${CLAUDE_VOICE_NOTIFY_SUBAGENT:-on}" = "off" ] && exit 0
  [ "$naming" = "on" ] || exit 0
  command -v jq >/dev/null 2>&1 || exit 0
  sid=$(session_id)
  [ -n "$sid" ] || sid="nosess"

  status=$(printf '%s' "$input" | jq -r '.tool_response.status // ""' 2>/dev/null)
  is_async=$(printf '%s' "$input" | jq -r '.tool_response.isAsync // false' 2>/dev/null)
  aid=$(printf '%s' "$input" | jq -r '.tool_response.agentId // ""' 2>/dev/null \
        | tr -cd 'A-Za-z0-9._-')
  desc=$(sanitise_desc "$(tool_desc)")

  if [ "$status" = "async_launched" ] || [ "$is_async" = "true" ]; then
    [ -n "$aid" ] && mark_kv "$(agents_dir "$sid")" "$aid" "$desc"
    exit 0
  fi

  ok="no"
  [ "$status" = "completed" ] && ok="yes"
  atype=$(printf '%s' "$input" | jq -r '.tool_response.agentType // ""' 2>/dev/null)

  # The foreground agent's own SubagentStop has already recorded its completion, so this
  # count excludes it. No set_busy here on purpose: a PostToolUse payload carries no task list,
  # so this count is the marker fallback, and the Stop that follows will record the real one.
  inflight=$(inflight_markers "$sid")
  if [ "$inflight" -gt "$name_cap" ]; then
    date +%s > "$(capped_file "$sid")" 2>/dev/null
  else
    speak_completion "$desc" "$atype" "$ok"
  fi
  [ -n "$aid" ] && rm -f "$(agents_dir "$sid")/$aid" 2>/dev/null
  settle "$sid" "$inflight"
  exit 0
}

# handle_cmd_result: PostToolUse / PostToolUseFailure for the Bash tool. A backgrounded
# command's PostToolUse is only a launch acknowledgement — it carries backgroundTaskId and a
# duration of a few hundred ms — so it is recorded for drain_bg and says nothing. A foreground
# one is a real completion, gated on how long it actually ran.
handle_cmd_result() {
  local sid tuid btid desc evt dur ms ts announced outcome interrupted
  [ "$cmds" = "off" ] && exit 0
  command -v jq >/dev/null 2>&1 || exit 0
  sid=$(session_id); [ -n "$sid" ] || sid="nosess"
  tuid=$(tool_use_id)
  desc=$(sanitise_desc "$(tool_desc)")

  btid=$(printf '%s' "$input" | jq -r '.tool_response.backgroundTaskId // ""' 2>/dev/null \
         | tr -cd 'A-Za-z0-9._-')
  if [ -n "$btid" ]; then
    mark_kv "$(bg_dir "$sid")" "$btid" "$desc"
    [ -n "$tuid" ] && rm -f "$(cmd_dir "$sid")/$tuid" "$(cmdsaid_dir "$sid")/$tuid" 2>/dev/null
    exit 0
  fi

  announced=""
  [ -n "$tuid" ] && [ -e "$(cmdsaid_dir "$sid")/$tuid" ] && announced=1

  # Elapsed: the harness's own duration first, our start record as the fallback.
  dur=""
  ms=$(printf '%s' "$input" | jq -r '.duration_ms // ""' 2>/dev/null)
  case "$ms" in ''|*[!0-9]*) ms="" ;; esac
  if [ -n "$ms" ]; then
    dur=$(( 10#$ms / 1000 ))
  elif [ -n "$tuid" ]; then
    ts=$(read_ts "$(cmd_dir "$sid")/$tuid")
    case "$ts" in ''|*[!0-9]*) ts="" ;; esac
    [ -n "$ts" ] && dur=$(( $(date +%s) - 10#$ts ))
  fi

  # A failure event carries no tool_input, so fall back to the purpose recorded at dispatch.
  if [ -z "$desc" ] && [ -n "$tuid" ]; then
    desc=$(sanitise_desc "$(read_kv "$(cmd_dir "$sid")/$tuid")")
  fi

  [ -n "$tuid" ] && rm -f "$(cmd_dir "$sid")/$tuid" "$(cmdsaid_dir "$sid")/$tuid" 2>/dev/null

  evt=$(hook_event)
  outcome="ok"
  if [ "$evt" = "PostToolUseFailure" ]; then
    outcome="fail"
    [ "$(printf '%s' "$input" | jq -r '.is_timeout // false' 2>/dev/null)" = "true" ] \
      && outcome="timeout"
    [ "$(printf '%s' "$input" | jq -r '.is_interrupt // false' 2>/dev/null)" = "true" ] \
      && outcome="interrupt"
  else
    interrupted=$(printf '%s' "$input" | jq -r '.tool_response.interrupted // false' 2>/dev/null)
    [ "$interrupted" = "true" ] && outcome="interrupt"
  fi

  # Having been told a command was running, the user always gets the matching all-clear —
  # whatever the gate would otherwise have said.
  if [ -z "$announced" ] && [ "$cmd_quiet" -gt 0 ]; then
    [ -n "$dur" ] || exit 0
    [ "$dur" -lt "$cmd_quiet" ] && exit 0
  fi
  speak_cmd_done "$desc" "$outcome"
  exit 0
}

case "$event" in
  start)
    # Stamp the turn start so Stop can measure how long it ran.
    sid=$(session_id)
    [ -n "$sid" ] || exit 0
    date +%s > "$(state_file "$sid")" 2>/dev/null
    # A new prompt proves the user is back at the keyboard, so the idle cue has nothing left to
    # protect them from. Always clear it, even with the subagent path muted, so toggling the mute
    # can't strand a marker.
    rm -f "$(busy_file "$sid")" 2>/dev/null
    # The user is demonstrably back at the keyboard, so nothing is owed a reminder.
    rm -rf "$(perm_dir "$sid")" 2>/dev/null
    # Reset the roll-up bookkeeping only when nothing is outstanding: a turn submitted while
    # background agents still run must not lose the all-clear it was promised.
    [ "$(inflight_markers "$sid")" -eq 0 ] && clear_batch "$sid"
    exit 0
    ;;

  stop)
    elapsed=""
    sid=$(session_id)
    if [ -n "$sid" ]; then
      sf=$(state_file "$sid")
      if [ -f "$sf" ]; then
        start_ts=$(read_ts "$sf")
        rm -f "$sf" 2>/dev/null
        case "$start_ts" in
          ''|*[!0-9]*) elapsed="" ;;
          *) elapsed=$(( $(date +%s) - start_ts )) ;;
        esac
      fi
    fi

    # A background command that has left the harness's task list has finished. Announce that
    # before any waiting/sign-off cue, so the order matches what actually happened.
    bsid="$sid"; [ -n "$bsid" ] || bsid="nosess"
    drain_bg "$bsid"

    # Subagents still running? The main turn ended but background agents keep working, so a
    # sign-off would be a false "finished". Announce the waiting state instead — and, since a
    # turn boundary with work outstanding is worth flagging even after a short turn, bypass the
    # quiet-under gate. Foreground agents report every SubagentStop before Stop, so they resolve
    # to zero in-flight and fall through to the normal sign-off.
    if [ "${CLAUDE_VOICE_NOTIFY_SUBAGENT:-on}" != "off" ]; then
      sub_sid="$sid"; [ -n "$sub_sid" ] || sub_sid="nosess"
      # Record the state for the idle Notification that may follow a minute from now. Only the
      # harness's own list is trustworthy enough to record: the marker fallback can't see a
      # workflow, so a zero from it would be a guess, not an all-clear.
      if inflight=$(inflight_payload ""); then
        set_busy "$sub_sid" "$inflight"
      else
        inflight=$(inflight_markers "$sub_sid")
      fi
      if [ "$inflight" -gt 0 ]; then
        # Remember that the user was told to wait, so the drain can close the loop.
        [ "$naming" = "on" ] && date +%s > "$(waited_file "$sub_sid")" 2>/dev/null
        core=$(printf '%s\n' "$WAITING_CORES" | pick)
        speak_locked "$(compose "$NEUTRAL_GARNISH" "$core")"
        exit 0
      fi
      # Nothing outstanding: a sign-off subsumes any pending roll-up bookkeeping.
      clear_batch "$sub_sid"
    fi

    # Quiet on quick turns: if it finished fast, the user is probably still here.
    if [ -n "$elapsed" ] && [ "$elapsed" -lt "$quiet_under" ]; then
      exit 0
    fi

    # A clearly long turn earns a wait-acknowledging sign-off; otherwise the
    # standard pool (also used when duration is unknown -> fail audible).
    if [ -n "$elapsed" ] && [ "$elapsed" -ge "$(( quiet_under * 3 ))" ]; then
      core=$(printf '%s\n' "$STOP_LONG_CORES" | pick)
    else
      core=$(printf '%s\n' "$STOP_CORES" | pick)
    fi
    speak_locked "$(compose "$NEUTRAL_GARNISH" "$core")"
    ;;

  notification)
    msg=""
    ntype=""
    if command -v jq >/dev/null 2>&1; then
      msg=$(printf '%s' "$input" | jq -r '.message // ""' 2>/dev/null)
      ntype=$(printf '%s' "$input" | jq -r '.notification_type // ""' 2>/dev/null)
    fi
    classify "$msg" "$ntype"
    # "Waiting for your input" is the one cue that becomes false when work is outstanding — Stop
    # already said the helpers are still running, and this would contradict it a minute later.
    # Stay silent instead of re-routing: repeating the waiting cue adds noise, not information.
    # Every other subtype (permission, an agent asking for input, an agent reporting a result)
    # stays audible, because each is still true and still worth interrupting for.
    if [ "$sub" = "idle" ] && [ "${CLAUDE_VOICE_NOTIFY_SUBAGENT:-on}" != "off" ]; then
      nsid=$(session_id)
      [ -n "$nsid" ] || nsid="nosess"
      is_busy "$nsid" && exit 0
    fi
    case "$sub" in
      permission|agent_input) garnish="$BRISK_GARNISH" ;;
      idle)                   garnish="$GENTLE_GARNISH" ;;
      *)                      garnish="$NEUTRAL_GARNISH" ;;
    esac
    speak_locked "$(compose "$garnish" "$reason")"

    # A permission prompt blocks the session until it is answered, so it is the one cue worth
    # repeating. Arm the reminder from *this* event rather than from PermissionRequest alone:
    # this notification is known to fire (it is what speaks the first request), while
    # PermissionRequest could not be shown to fire at all — a headless probe never produces a
    # dialog. PermissionRequest still refines the record with the exact tool_use_id when it does
    # arrive. Speaking happens first above, so the reminder never delays the first announcement.
    if [ "$sub" = "permission" ] && [ "$nag_every" -gt 0 ]; then
      psid=$(session_id)
      [ -n "$psid" ] || psid="nosess"
      # Only one permission prompt can be pending at a time, so a record already armed by
      # PermissionRequest (keyed by its tool_use_id) is this same prompt — don't double-arm.
      if [ "$(count_dir "$(perm_dir "$psid")")" -eq 0 ] && mkdir -p "$(perm_dir "$psid")" 2>/dev/null; then
        ptool=""
        case "$msg" in *"to use "*) ptool="${msg##*to use }" ;; esac
        ptool=$(sanitise_desc "$ptool")
        nowts=$(date +%s)
        printf '%s\n%s\n0\n%s\n' "$nowts" "$ptool" "$nowts" \
          > "$(perm_dir "$psid")/pending" 2>/dev/null
      fi
      # The watcher runs here, in a plain notification hook, rather than inside
      # PermissionRequest — that event can return an allow/deny decision, and a long-running
      # loop has no business inside it.
      elect_watcher "$psid"
    fi
    ;;

  dispatch)
    # Subagent(s) just dispatched and the main agent paused: announce the working state once
    # per burst, naming what was handed off.
    [ "${CLAUDE_VOICE_NOTIFY_SUBAGENT:-on}" = "off" ] && exit 0
    # Fall back to a fixed key so debounce still dedupes a burst when no session id is available.
    sid=$(session_id)
    [ -n "$sid" ] || sid="nosess"

    # Record this spawn for in-flight accounting BEFORE the debounce: every dispatched subagent
    # must count, even when its cue is debounced into silence.
    uniq="$(date +%s).$$.${RANDOM:-0}"
    mark "$(spawn_dir "$sid")" "$uniq"

    if [ "$naming" = "on" ]; then
      desc=$(sanitise_desc "$(tool_desc)")
      mark "$(batch_dir "$sid")" "$uniq"
      [ -n "$desc" ] && mark_kv "$(pending_dir "$sid")" "$uniq" "$desc"
    fi

    df=$(dispatch_file "$sid")
    last=$(read_ts "$df")
    case "$last" in ''|*[!0-9]*) last="" ;; esac   # missing/corrupt -> speak
    nowts=$(date +%s)
    # Within the debounce window of the last cue -> this is the same burst, stay quiet.
    if [ -n "$last" ] && [ "$(( nowts - last ))" -lt "$debounce" ]; then
      exit 0
    fi

    # Exactly one dispatch of a burst speaks. Claim it create-only; the losers have already
    # registered their descriptions above and simply exit.
    bd=$(burst_dir "$sid")
    if ! mkdir "$bd" 2>/dev/null; then
      # A claim left behind by a killed process would otherwise silence every later burst.
      bts=$(read_ts "$bd/ts")
      case "$bts" in ''|*[!0-9]*) bts=0 ;; esac
      if [ "$bts" -gt 0 ] && [ "$(( nowts - bts ))" -ge "$(( collect + LOCK_STALE ))" ]; then
        rm -rf "$bd" 2>/dev/null
      fi
      exit 0
    fi
    printf '%s' "$nowts" > "$bd/ts" 2>/dev/null

    # Give the siblings of a parallel fan-out a moment to register, so the cue can describe the
    # whole burst rather than only the agent that happened to fire first.
    if [ "$naming" = "on" ] && [ "$collect" -gt 0 ]; then
      sleep "$collect"
    fi

    date +%s > "$df" 2>/dev/null

    core=""
    if [ "$naming" = "on" ]; then
      pd=$(pending_dir "$sid")
      n=0; first=""; second=""
      for f in "$pd"/*; do
        [ -e "$f" ] || continue
        d=$(read_kv "$f")
        [ -n "$d" ] || continue
        n=$((n+1))
        [ "$n" -eq 1 ] && first="$d"
        [ "$n" -eq 2 ] && second="$d"
      done
      rm -rf "$pd" 2>/dev/null
      if [ "$n" -eq 1 ]; then
        lead=$(printf '%s\n' "$DISPATCH_ONE_LEADS" | pick)
        core="$lead — $first."
      elif [ "$n" -eq 2 ]; then
        core="Two helpers: $first, and $second."
      elif [ "$n" -ge 3 ]; then
        core="$(num_word "$n") helpers, starting with $first."
      fi
    fi
    # No naming, or nothing resolvable: the anonymous hand-off cue.
    [ -n "$core" ] || core=$(printf '%s\n' "$SUBAGENT_CORES" | pick)

    rm -rf "$bd" 2>/dev/null
    speak_locked "$(compose "$NEUTRAL_GARNISH" "$core")"
    ;;

  agent-result)
    handle_agent_result
    ;;

  subagent-stop)
    # A subagent finished. Record the completion for the in-flight accounting, then decide
    # whether this event owns the spoken cue: a *background* agent is still listed in the
    # payload's task list (or has a launch record), while a foreground agent appears in neither
    # and is voiced by agent-result instead. That split keeps every agent voiced exactly once.
    [ "${CLAUDE_VOICE_NOTIFY_SUBAGENT:-on}" = "off" ] && exit 0
    sid=$(session_id)
    [ -n "$sid" ] || sid="nosess"
    aid=$(agent_id)
    # Key by agent_id so a duplicate SubagentStop overwrites (counts once); fall back to a
    # unique name when the id is unavailable (jq missing) so the completion still registers.
    [ -n "$aid" ] || aid="a$(date +%s).$$.${RANDOM:-0}"
    mark "$(done_dir "$sid")" "$aid"

    drain_bg "$sid"

    # Refresh the idle-cue marker first, before any naming-dependent exit below: this is the
    # event that turns "still working" back into "actually idle", and it has to do so even with
    # naming switched off. Reused further down so the list is parsed once.
    if inflight=$(inflight_payload "$aid"); then
      set_busy "$sid" "$inflight"
      have_payload=1
    else
      have_payload=""
    fi

    [ "$naming" = "on" ] || exit 0
    command -v jq >/dev/null 2>&1 || exit 0

    self=$(bt_self "$aid")
    purpose=""
    mine=""
    case "$self" in
      yes*) mine=1; purpose=$(sanitise_desc "${self#yes|}") ;;
    esac
    rec="$(agents_dir "$sid")/$aid"
    if [ -f "$rec" ]; then
      mine=1
      [ -n "$purpose" ] || purpose=$(sanitise_desc "$(read_kv "$rec")")
      rm -f "$rec" 2>/dev/null
    fi
    # Foreground agent: agent-result speaks for it.
    [ -n "$mine" ] || exit 0

    # An agent that produced no final message didn't really deliver a result.
    last_msg=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null)
    ok="yes"
    [ -n "$last_msg" ] || ok="no"

    [ -n "$have_payload" ] || inflight=$(inflight_markers "$sid")

    if [ "$inflight" -gt "$name_cap" ]; then
      date +%s > "$(capped_file "$sid")" 2>/dev/null
    else
      speak_completion "$purpose" "$(agent_type)" "$ok"
    fi
    settle "$sid" "$inflight"
    exit 0
    ;;

  cmd-start)
    # A shell command is starting. Record it so the watcher can announce it if it turns out to
    # be slow, then try to become that watcher.
    [ "$cmds" = "off" ] && exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    sid=$(session_id)
    [ -n "$sid" ] || sid="nosess"
    # A backgrounded command returns immediately and reports through drain_bg instead, so it is
    # never a "still running" candidate.
    bgflag=$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)
    [ "$bgflag" = "true" ] && exit 0
    tuid=$(tool_use_id)
    [ -n "$tuid" ] || exit 0
    mark_kv "$(cmd_dir "$sid")" "$tuid" "$(sanitise_desc "$(tool_desc)")"
    [ "$cmd_running" -gt 0 ] && elect_watcher "$sid"
    exit 0
    ;;

  tool-result)
    # PostToolUse / PostToolUseFailure, matched on every tool because approving a permission
    # prompt is signalled only by the tool actually running. Decide in one jq call and leave
    # immediately for the tools this plugin has nothing to say about.
    command -v jq >/dev/null 2>&1 || exit 0
    IFS=$'\t' read -r sid tname tuid <<EOF
$(printf '%s' "$input" | jq -r '[(.session_id//""),(.tool_name//""),(.tool_use_id//"")]|@tsv' 2>/dev/null)
EOF
    sid=$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9._-')
    tuid=$(printf '%s' "$tuid" | tr -cd 'A-Za-z0-9._-')
    [ -n "$sid" ] || sid="nosess"
    # The tool ran, so any permission prompt for it has been answered.
    [ -d "$(perm_dir "$sid")" ] && disarm_perm "$sid" "$tuid"
    case "$tname" in
      Agent) handle_agent_result ;;
      Bash)  handle_cmd_result ;;
    esac
    exit 0
    ;;

  stop-failure)
    # The turn died on an API error, so no Stop will ever fire and nothing else would speak.
    # Worth saying however short the turn was: the duration gate is deliberately bypassed.
    sid=$(session_id)
    if [ -n "$sid" ]; then
      rm -f "$(state_file "$sid")" 2>/dev/null
      [ "$(inflight_markers "$sid")" -eq 0 ] && clear_batch "$sid"
    fi
    etype=""
    if command -v jq >/dev/null 2>&1; then
      etype=$(printf '%s' "$input" | jq -r '.error_type // ""' 2>/dev/null)
    fi
    case "$etype" in
      rate_limit)            core=$(printf '%s\n' "$STALL_RATE_CORES" | pick) ;;
      overloaded|server_error) core=$(printf '%s\n' "$STALL_BUSY_CORES" | pick) ;;
      authentication_failed|oauth_org_not_allowed)
                             core=$(printf '%s\n' "$STALL_AUTH_CORES" | pick) ;;
      billing_error)         core=$(printf '%s\n' "$STALL_BILLING_CORES" | pick) ;;
      max_output_tokens)     core=$(printf '%s\n' "$STALL_LIMIT_CORES" | pick) ;;
      *)                     core=$(printf '%s\n' "$STALL_CORES" | pick) ;;
    esac
    speak_locked "$(compose "$BRISK_GARNISH" "$core")"
    ;;

  perm-request)
    # A permission dialog is on screen. The Notification arm speaks the first announcement; this
    # arms the reminder that follows if it goes unanswered. Deliberately independent of
    # CLAUDE_VOICE_NOTIFY_CMD: a blocked session is worth reporting even with command cues off.
    [ "$nag_every" -gt 0 ] || exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    sid=$(session_id)
    [ -n "$sid" ] || sid="nosess"
    tuid=$(tool_use_id)
    [ -n "$tuid" ] || exit 0
    mkdir -p "$(perm_dir "$sid")" 2>/dev/null || exit 0
    nowts=$(date +%s)
    printf '%s\n%s\n0\n%s\n' "$nowts" "$(sanitise_desc "$(tool_name)")" "$nowts" \
      > "$(perm_dir "$sid")/$tuid" 2>/dev/null
    # This record supersedes the anonymous one the Notification arm may have armed for the same
    # prompt, so the user is reminded once, not twice.
    rm -f "$(perm_dir "$sid")/pending" 2>/dev/null
    # Deliberately does NOT elect the watcher: this event can return an allow/deny decision, so
    # it must return immediately. The accompanying Notification takes up the watch.
    exit 0
    ;;

  perm-denied)
    command -v jq >/dev/null 2>&1 || exit 0
    sid=$(session_id)
    [ -n "$sid" ] || sid="nosess"
    ptuid=$(tool_use_id)
    disarm_perm "$sid" "$ptuid"
    drop_cmd "$sid" "$ptuid"
    exit 0
    ;;

  *)
    exit 0
    ;;
esac
