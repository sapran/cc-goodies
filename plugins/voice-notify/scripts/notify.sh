#!/bin/bash
# cc-goodies / voice-notify
# Speak a short, rotating, first-person cue when Claude Code needs attention.
#
# Usage (from hooks):  notify.sh <event>     event = "stop" | "notification"
# The hook's JSON arrives on stdin; the "notification" event reads its .message.
#
# Environment:
#   CLAUDE_VOICE="Name"      override the voice (default: "Matilda (Premium)")
#   CLAUDE_VOICE_NOTIFY=off  mute without uninstalling
#
# macOS only (uses `say`). No-ops cleanly anywhere `say` is absent.

set -u
event="${1:-}"

# Mute switch.
[ "${CLAUDE_VOICE_NOTIFY:-on}" = "off" ] && exit 0
# No TTS engine -> nothing to do (keeps the hook harmless off macOS).
command -v say >/dev/null 2>&1 || exit 0

# Resolve the voice; fall back to the system default if it isn't installed
# (teammates won't necessarily have the premium download).
voice="${CLAUDE_VOICE:-Matilda (Premium)}"
if ! say -v '?' 2>/dev/null | grep -qF "$voice"; then
  voice=""
fi

speak() {
  if [ -n "$voice" ]; then say -v "$voice" "$1"; else say "$1"; fi
}

# Shell-agnostic random line picker: awk does 1-based indexing identically in
# bash/zsh/sh; seeded per-process from $RANDOM so separate hook fires vary.
pick() { awk -v s="${RANDOM:-$$}" 'BEGIN{srand(s)} {a[NR]=$0} END{if(NR)print a[int(rand()*NR)+1]}'; }

case "$event" in
  stop)
    phrase=$(printf '%s\n' \
      "I'm done." "All done." "Finished." "Ready when you are." "Your turn." \
      "Task complete." "Back to you." "Done and dusted." "That's a wrap." "Over to you." | pick)
    speak "$phrase"
    ;;
  notification)
    # Flip Claude Code's third-person message into first person; fall back if jq
    # is missing or the message is empty.
    reason=$(jq -r '(.message // "I need your attention.")
      | gsub("Claude needs"; "I need")
      | gsub("Claude is"; "I am")
      | gsub("Claude"; "I")' 2>/dev/null)
    [ -z "$reason" ] && reason="I need your attention."
    lead=$(printf '%s\n' \
      "Hey" "Heads up" "Hey there" "Excuse me" "When you get a sec" "Quick one" "Knock knock" | pick)
    speak "$lead, $reason"
    ;;
  *)
    exit 0
    ;;
esac
