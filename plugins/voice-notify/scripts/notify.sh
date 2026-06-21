#!/bin/bash
# cc-goodies / voice-notify
# Speak a short, rotating, first-person cue when Claude Code needs attention.
#
# Usage (from hooks):  notify.sh <event>   event = "stop" | "notification" | "start"
# The hook's JSON arrives on stdin: "notification" reads .message; "stop"/"start"
# read .session_id to time the turn for the quiet-on-quick-turns gate.
#
# Environment:
#   CLAUDE_VOICE="Name"                 override the voice (default: "Matilda (Premium)")
#   CLAUDE_VOICE_NOTIFY=off             mute without uninstalling
#   CLAUDE_VOICE_NOTIFY_QUIET_UNDER=N   skip the Stop cue when the turn ran < N seconds
#                                       (default 20; set 0 to speak after every turn)
#   CLAUDE_VOICE_NOTIFY_GARNISH_PCT=N   chance (0-100) of a leading interjection (default 40)
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

# --- duration state (ephemeral, $TMPDIR only; OS clears it, /plugin uninstall is enough) ---
session_id() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null \
    | tr -cd 'A-Za-z0-9._-'   # UUIDs only; never let a stray char escape the path
}
state_file() { printf '%s/vn-%s.start' "${TMPDIR:-/tmp}" "$1"; }

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

  *)
    exit 0
    ;;
esac
