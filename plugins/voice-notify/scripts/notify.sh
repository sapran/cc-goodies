#!/bin/bash
# cc-goodies / voice-notify
# Speak a short, rotating, first-person cue when Claude Code needs attention.
#
# Usage (from hooks):  notify.sh <event>
#   event = "stop" | "notification" | "start" | "dispatch" | "subagent-stop"
# The hook's JSON arrives on stdin: "notification" reads .message; "stop"/"start"/"dispatch"/
# "subagent-stop" read .session_id (to time the turn, debounce the dispatch cue, and track
# in-flight subagents); "subagent-stop" also reads .agent_id.
#
# Environment:
#   CLAUDE_VOICE="Name"                 override the voice (default: "Matilda (Premium)")
#   CLAUDE_VOICE_NOTIFY=off             mute without uninstalling
#   CLAUDE_VOICE_NOTIFY_QUIET_UNDER=N   skip the Stop cue when the turn ran < N seconds
#                                       (default 20; set 0 to speak after every turn)
#   CLAUDE_VOICE_NOTIFY_GARNISH_PCT=N   chance (0-100) of a leading interjection (default 40)
#   CLAUDE_VOICE_NOTIFY_SUBAGENT=off    disable the whole subagent path (dispatch cue,
#                                       in-flight tracking, and the waiting-at-turn-end cue)
#   CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE=N  collapse a dispatch burst within N s (default 10)
#   CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL=N  prune in-flight markers older than N s (default 3600),
#                                       so a subagent that never reports done can't wedge count
#
# macOS only (uses `say`). No-ops cleanly anywhere `say` is absent.

set -u
event="${1:-}"

# Mute switch.
[ "${CLAUDE_VOICE_NOTIFY:-on}" = "off" ] && exit 0
# No TTS engine -> nothing to do (keeps the hook harmless off macOS). Applies to
# every event, including "start": there's no point timing turns we can't announce.
command -v say >/dev/null 2>&1 || exit 0

# Read the hook payload once; both .message and .session_id come from here.
input=$(cat 2>/dev/null)

# --- config (env var -> default), validated to digits so bad input can't break math ---
quiet_under="${CLAUDE_VOICE_NOTIFY_QUIET_UNDER:-20}"
case "$quiet_under" in ''|*[!0-9]*) quiet_under=20 ;; esac
garnish_pct="${CLAUDE_VOICE_NOTIFY_GARNISH_PCT:-40}"
case "$garnish_pct" in ''|*[!0-9]*) garnish_pct=40 ;; esac
debounce="${CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE:-10}"
case "$debounce" in ''|*[!0-9]*) debounce=10 ;; esac
ttl="${CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL:-3600}"
case "$ttl" in ''|*[!0-9]*) ttl=3600 ;; esac
ttl=$((10#$ttl))   # force base-10: a leading-zero value (e.g. 0900) must not parse as octal
                   # inside the later $(( ... - ttl )), which would error and, under set -u,
                   # kill the whole stop arm (silencing every turn).

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
# audibly different. Routed through compose() with the neutral lead-ins, like the others.
SUBAGENT_CORES="Spinning up some helpers, back in a bit.
Working with a few helpers now.
Handing some work off, give me a moment.
Got some sub-agents on it, hang tight.
Delegating this, back shortly."

# Waiting cue: the turn ended but background subagents are still running, so a turn-end
# sign-off would be a false "finished". Distinct from the dispatch pool (which announces the
# hand-off) and the sign-off pools — this marks a turn boundary with work still outstanding.
WAITING_CORES="Still going, the helpers aren't done yet.
Not done yet, the agents are still working.
Paused here, but the sub-agents are still running.
Holding for the helpers to finish.
Agents still busy, not your turn just yet.
Work's still out with the helpers."

# --- duration state (ephemeral, $TMPDIR only; OS clears it, /plugin uninstall is enough) ---
session_id() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null \
    | tr -cd 'A-Za-z0-9._-'   # UUIDs only; never let a stray char escape the path
}
state_file() { printf '%s/vn-%s.start' "${TMPDIR:-/tmp}" "$1"; }
dispatch_file() { printf '%s/vn-%s.dispatch' "${TMPDIR:-/tmp}" "$1"; }

# --- in-flight subagent accounting (two create-only marker dirs per session) ---
# Spawn markers (one per dispatch, uniquely named) and done markers (one per completion, named
# by agent_id so a duplicate SubagentStop overwrites instead of double-counting). Each marker's
# content is its creation epoch, so prune_dir can age out stale ones without stat(1). Writers
# only ever create distinct paths, so concurrent async hooks never race a read-modify-write.
spawn_dir() { printf '%s/vn-%s.spawn.d' "${TMPDIR:-/tmp}" "$1"; }
done_dir()  { printf '%s/vn-%s.done.d'  "${TMPDIR:-/tmp}" "$1"; }

# Read .agent_id, sanitised so it is safe as a filename. Empty without jq or the field.
agent_id() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$input" | jq -r '.agent_id // ""' 2>/dev/null \
    | tr -cd 'A-Za-z0-9._-'
}

# mark <dir> <name>: create/overwrite a marker whose content is the current epoch.
mark() {
  mkdir -p "$1" 2>/dev/null || return 0
  printf '%s' "$(date +%s)" > "$1/$2" 2>/dev/null
}

# count_dir <dir>: number of marker files, via globbing only (no ls/find needed off-PATH).
count_dir() {
  local d="$1" n=0 f
  [ -d "$d" ] || { printf 0; return; }
  for f in "$d"/*; do [ -e "$f" ] && n=$((n+1)); done
  printf '%s' "$n"
}

# prune_dir <dir> <cutoff-epoch>: drop markers older than the cutoff (or with an empty content
# from a failed write). Non-numeric content is kept — fail toward "still in-flight", never a
# false all-clear that would let a premature sign-off through.
prune_dir() {
  local d="$1" cutoff="$2" f ts
  [ -d "$d" ] || return 0
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    ts=$(cat "$f" 2>/dev/null)
    case "$ts" in
      '')       rm -f "$f" 2>/dev/null ;;
      *[!0-9]*) : ;;
      *)        [ "$ts" -lt "$cutoff" ] && rm -f "$f" 2>/dev/null ;;
    esac
  done
}

# Map a Notification message to (subtype, first-person reason). Allow-list only:
# unrecognised wording falls through to a neutral cue rather than being mangled.
sub=""
reason=""
classify() {
  local m="$1" im="I'm"
  case "$m" in
    *"permission"*)
      sub="permission"
      reason="${m/Claude needs/I need}"
      reason="${reason/Claude is/$im}"
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

case "$event" in
  start)
    # Stamp the turn start so Stop can measure how long it ran.
    sid=$(session_id)
    [ -n "$sid" ] || exit 0
    date +%s > "$(state_file "$sid")" 2>/dev/null
    exit 0
    ;;

  stop)
    elapsed=""
    sid=$(session_id)
    if [ -n "$sid" ]; then
      sf=$(state_file "$sid")
      if [ -f "$sf" ]; then
        start_ts=$(cat "$sf" 2>/dev/null)
        rm -f "$sf" 2>/dev/null
        case "$start_ts" in
          ''|*[!0-9]*) elapsed="" ;;
          *) elapsed=$(( $(date +%s) - start_ts )) ;;
        esac
      fi
    fi

    # Subagents still running? The main turn ended but background agents keep working, so a
    # sign-off would be a false "finished". Announce the waiting state instead — and, since a
    # turn boundary with work outstanding is worth flagging even after a short turn, bypass the
    # quiet-under gate. Foreground agents report every SubagentStop before Stop (spawn == done),
    # so they resolve to zero in-flight and fall through to the normal sign-off.
    if [ "${CLAUDE_VOICE_NOTIFY_SUBAGENT:-on}" != "off" ]; then
      sub_sid="$sid"; [ -n "$sub_sid" ] || sub_sid="nosess"
      cutoff=$(( $(date +%s) - ttl ))
      prune_dir "$(spawn_dir "$sub_sid")" "$cutoff"
      prune_dir "$(done_dir "$sub_sid")" "$cutoff"
      inflight=$(( $(count_dir "$(spawn_dir "$sub_sid")") - $(count_dir "$(done_dir "$sub_sid")") ))
      if [ "$inflight" -gt 0 ]; then
        core=$(printf '%s\n' "$WAITING_CORES" | pick)
        speak "$(compose "$NEUTRAL_GARNISH" "$core")"
        exit 0
      fi
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
    speak "$(compose "$NEUTRAL_GARNISH" "$core")"
    ;;

  notification)
    msg=""
    if command -v jq >/dev/null 2>&1; then
      msg=$(printf '%s' "$input" | jq -r '.message // ""' 2>/dev/null)
    fi
    classify "$msg"
    case "$sub" in
      permission) garnish="$BRISK_GARNISH" ;;
      idle)       garnish="$GENTLE_GARNISH" ;;
      *)          garnish="$NEUTRAL_GARNISH" ;;
    esac
    speak "$(compose "$garnish" "$reason")"
    ;;

  dispatch)
    # Subagent(s) just dispatched and the main agent paused: announce the
    # working-state once per burst, then stay quiet (finishes are silent by design).
    [ "${CLAUDE_VOICE_NOTIFY_SUBAGENT:-on}" = "off" ] && exit 0
    # The cue doesn't read .message, so it works without jq; fall back to a fixed key
    # so debounce still dedupes a burst when no session id is available.
    sid=$(session_id)
    [ -n "$sid" ] || sid="nosess"

    # Record this spawn for in-flight accounting BEFORE the debounce: every dispatched subagent
    # must count, even when its cue is debounced into silence.
    mark "$(spawn_dir "$sid")" "$(date +%s).$$.${RANDOM:-0}"

    df=$(dispatch_file "$sid")
    last=""
    [ -f "$df" ] && last=$(cat "$df" 2>/dev/null)
    case "$last" in ''|*[!0-9]*) last="" ;; esac   # missing/corrupt -> speak
    nowts=$(date +%s)
    # Within the debounce window of the last cue -> this is the same burst, stay quiet.
    if [ -n "$last" ] && [ "$(( nowts - last ))" -lt "$debounce" ]; then
      exit 0
    fi
    printf '%s' "$nowts" > "$df" 2>/dev/null

    core=$(printf '%s\n' "$SUBAGENT_CORES" | pick)
    speak "$(compose "$NEUTRAL_GARNISH" "$core")"
    ;;

  subagent-stop)
    # A subagent finished: record the completion so a later Stop can tell whether work is still
    # outstanding. Speak nothing — per-completion cues would be chatter on a large fan-out.
    [ "${CLAUDE_VOICE_NOTIFY_SUBAGENT:-on}" = "off" ] && exit 0
    sid=$(session_id)
    [ -n "$sid" ] || sid="nosess"
    aid=$(agent_id)
    # Key by agent_id so a duplicate SubagentStop overwrites (counts once); fall back to a
    # unique name when the id is unavailable (jq missing) so the completion still registers.
    [ -n "$aid" ] || aid="a$(date +%s).$$.${RANDOM:-0}"
    mark "$(done_dir "$sid")" "$aid"
    exit 0
    ;;

  *)
    exit 0
    ;;
esac
