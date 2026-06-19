#!/bin/bash
# cc-goodies / shell-guard
# Block a small, curated set of *catastrophic* shell commands before they run.
#
# Wired as a PreToolUse hook on the Bash tool. The tool call's JSON arrives on
# stdin; we read .tool_input.command and .cwd, split the command into segments,
# and block (exit 2) when a segment matches a high-confidence dangerous pattern:
# wiping `/` or `$HOME`, recursively deleting a top-level system dir, writing
# onto a raw disk device, mkfs/wipefs/destructive diskutil, a fork bomb, piping
# a network download into a shell, truncating a file to empty (`: >`), `chmod 777`,
# `eval`, privilege escalation (`sudo`/`doas`/…), and system halt/reboot.
# Everything else passes straight through.
#
# Threat model: an *aligned* agent that emits a catastrophic command BY ACCIDENT
# in plain form (`rm -rf /`). This is a convenience guard, not a sandbox — it does
# not try to defeat *deliberate* evasion (deep wrapping, encoding, `bash -c`,
# `eval` indirection, a target supplied at runtime via stdin). Plan mode is the
# backstop for that. It deliberately allows ordinary work like `rm -rf ./build`.
#
# Config, lowest to highest precedence:
#   built-in defaults -> ~/.claude/shell-guard.conf (KEY=VALUE) -> environment
#
#   SHELL_GUARD_DISABLE=1            # turn the guard off without uninstalling
#   SHELL_GUARD_EXTRA_PATTERNS="..." # extra ERE block patterns, ;- or newline-separated
#
# Requires jq to parse the hook JSON. If jq is missing the guard cannot read the
# command, so it no-ops with a one-line warning rather than blocking every Bash
# call (fails OPEN — a guard that blocks everything when a dependency is missing
# is worse than no guard).
#
# Exit codes: 0 = allow, 2 = block (stderr is fed back to Claude). Any other
# code is a non-blocking error in the hooks API, so we never use one to deny.

set -u
set -f   # never glob while tokenising — keep `*` / `.*` literal in the command

input=$(cat)

# Without jq we cannot read the command -> fail OPEN. Documented above.
if ! command -v jq >/dev/null 2>&1; then
  echo "shell-guard: jq not found; guard disabled (brew install jq to enable)." >&2
  exit 0
fi

# Defence in depth: only act on the Bash tool.
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
[ "$tool" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
CWD=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -n "$cmd" ] || exit 0

# --- Effective configuration (env > conf file > default) --------------------
# The conf file is read with a safe KEY=VALUE parser, never `source`d, so a
# stray ~/.claude/shell-guard.conf cannot execute arbitrary shell in the hook.
CONF="$HOME/.claude/shell-guard.conf"
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

DISABLE="${SHELL_GUARD_DISABLE:-$(conf_get SHELL_GUARD_DISABLE)}"
[ -n "${DISABLE:-}" ] && [ "$DISABLE" != "0" ] && exit 0   # escape hatch
EXTRA="${SHELL_GUARD_EXTRA_PATTERNS:-$(conf_get SHELL_GUARD_EXTRA_PATTERNS)}"

# Regexes kept in variables so the `>` / `(` inside them never confuse the [[ ]]
# parser, and so they read as plain ERE.
# Redirect onto a raw disk device — `> /dev/disk0`, `>| /dev/disk0`, quoted target.
# KEEP IN SYNC with the `dd` arm's of= glob below — these two are the single
# source of the catastrophic disk-device class.
DEV_RE='>[|]?[[:space:]]*["'"'"']?/dev/(disk|rdisk|sd|hd|nvme|vd)'
# Fork bomb: a function that pipes & backgrounds a call to itself.
FORK_RE='([A-Za-z_:][A-Za-z0-9_:]*)\(\)[[:space:]]*\{(.*)\}'
# The `: >` truncate-to-empty idiom: a segment that starts with `:` then a
# single `>` redirect. (A bare `> file` is an ordinary redirect — not matched.)
TRUNC_RE='^[[:space:]]*:[[:space:]]*>([^>]|$)'

# --- Helpers ----------------------------------------------------------------
deny() {
  # $1 = human reason
  printf '%s\n' "⛔ shell-guard: blocked a dangerous command — $1." >&2
  printf '%s\n' "   If you really mean it, run it yourself in a terminal, set" >&2
  printf '%s\n' "   SHELL_GUARD_DISABLE=1, or see /shell-guard." >&2
  return 2
}

# Is this argument a catastrophic target — `/`, `$HOME`/`~`, a top-level system
# directory, or a glob-all while the session sits in $HOME?
is_cata_target() {
  [ "${#1}" -lt 256 ] || return 1   # no catastrophic top-level target is this long — skip the O(n) work
  t="$1"
  t="${t//\"/}"; t="${t//\'/}"; t="${t#\\}"   # drop all quotes + a leading backslash (/"" \/ ''/ "$HOME")
  # The `~` / `$HOME` patterns are literal text as typed in the command, matched
  # verbatim — not meant to expand here. (Silences SC2088/SC2016.)
  # shellcheck disable=SC2088,SC2016
  case "$t" in
    /|'/*') return 0 ;;
    '~'|'~/'|'~/*') return 0 ;;
    '$HOME'|'${HOME}'|'$HOME/'|'${HOME}/'|'$HOME/*'|'${HOME}/*') return 0 ;;
  esac
  d="${t%/}"; [ -n "$d" ] || d="/"   # trailing-slash insensitive (keep bare /)
  case "$d" in
    /usr|/etc|/bin|/sbin|/lib|/lib64|/var|/boot|/sys|/proc|/dev|/opt|/root|/run|/home|/Users|/System|/Library|/Applications|/Volumes)
      return 0 ;;
  esac
  # A glob-all of a top-level system dir's contents — `/usr/*`, `/etc/*` — is just as fatal.
  case "$t" in
    */\*) case "${d%/\*}" in
            /usr|/etc|/bin|/sbin|/lib|/lib64|/var|/boot|/sys|/proc|/dev|/opt|/root|/run|/home|/Users|/System|/Library|/Applications|/Volumes)
              return 0 ;;
          esac ;;
  esac
  if [ -n "${CWD:-}" ] && [ "$CWD" = "$HOME" ]; then
    case "$t" in '.'|'./'|'*'|'.*'|'./*') return 0 ;; esac
  fi
  return 1
}

# Strip a leading run of wrappers (`env`, `timeout`, `nice`, a `VAR=val` prefix…)
# from a tokenised pipeline stage and echo the real command word + its args. This
# is a *flat* skip: no per-wrapper option-value tables. `sw=1` once we are past a
# wrapper lets that wrapper's own `-flags` and a bare numeric arg (`timeout 5`,
# `nice 10`) be skipped without swallowing a bare command. A misparse fails OPEN
# (echoes nothing -> the arms below allow), the correct bias for accident guard.
skip_wrappers() {
  # shellcheck disable=SC2086
  set -- $1
  sw=0
  while [ $# -gt 0 ]; do
    case "$1" in */*) w="${1##*/}" ;; *) w="$1" ;; esac
    w="${w#\\}"; w="${w//\"/}"; w="${w//\'/}"
    case "$w" in
      env|nohup|nice|timeout|setsid|stdbuf|ionice|xargs|time) sw=1; shift; continue ;;
    esac
    case "$1" in
      *=*) sw=1; shift; continue ;;                                  # VAR=val prefix
      -*)     if [ "$sw" = 1 ]; then shift; continue; else break; fi ;; # a wrapper's own flag
      [0-9]*) if [ "$sw" = 1 ]; then shift; continue; else break; fi ;; # a wrapper's numeric arg (timeout 5, nice 10)
      *)   break ;;
    esac
  done
  printf '%s' "$*"
}

# Evaluate ONE pipeline stage: skip wrappers, then judge the command word. 2 = block.
eval_stage() {
  # shellcheck disable=SC2046,SC2086
  set -- $(skip_wrappers "$1")
  [ $# -gt 0 ] || return 0
  c="$1"; shift
  case "$c" in */*) c="${c##*/}" ;; esac   # basename
  c="${c#\\}"; c="${c//\\/}"; c="${c//\"/}"; c="${c//\'/}"   # de-quote + de-backslash

  case "$c" in
    rm)
      # Recursive removal of a catastrophic target is blocked with or without -f
      # (`rm -r /` is just as fatal); --no-preserve-root is always a red flag.
      has_r=0; nopreserve=0; cata=0
      for a in "$@"; do
        case "$a" in
          --no-preserve-root) nopreserve=1 ;;
          --recursive)        has_r=1 ;;
          --*) : ;;
          -*) case "$a" in *[rR]*) has_r=1 ;; esac ;;
          *)  is_cata_target "$a" && cata=1 ;;
        esac
      done
      if [ "$nopreserve" = 1 ] || { [ "$has_r" = 1 ] && [ "$cata" = 1 ]; }; then
        deny "recursive delete of a protected path"; return 2
      fi
      ;;
    dd)
      # Only `of=` to a raw DISK device class (KEEP IN SYNC with DEV_RE above) —
      # NOT all of /dev, so `dd of=/dev/null` and `dd of=file` are allowed.
      for a in "$@"; do
        na="${a//\"/}"; na="${na//\'/}"
        case "$na" in
          of=/dev/disk*|of=/dev/rdisk*|of=/dev/sd*|of=/dev/hd*|of=/dev/nvme*|of=/dev/vd*)
            deny "dd onto a raw disk device"; return 2 ;;
        esac
      done
      ;;
    mkfs|mkfs.*|wipefs|newfs|newfs_*)
      deny "filesystem creation/wipe ($c)"; return 2
      ;;
    diskutil)
      case "${1:-}" in
        eraseDisk|eraseVolume|reformat|zeroDisk|secureErase|partitionDisk|eraseall)
          deny "destructive diskutil ($1)"; return 2 ;;
        apfs) case "${2:-}" in delete*|erase*) deny "destructive diskutil (apfs $2)"; return 2 ;; esac ;;
      esac
      ;;
    reboot|shutdown|halt|poweroff)
      deny "system halt/reboot ($c)"; return 2
      ;;
    sudo|doas|su|runuser|pkexec|gosu|sudoedit|setpriv)
      deny "$c — privilege escalation"; return 2
      ;;
    eval)
      deny "eval — arbitrary code execution"; return 2
      ;;
    chmod)
      for a in "$@"; do
        case "$a" in 777|0777) deny "chmod 777 — world-writable permissions"; return 2 ;; esac
      done
      ;;
  esac
  return 0
}

# Split a segment into pipeline stages and detect a download piped into an
# interpreter, command-word-anchored (NOT a raw-text regex). We flag the segment
# only when a stage whose command word is curl/wget/fetch is *followed* by a stage
# whose command word is an interpreter — so `echo "curl x | bash"` (one stage,
# command word `echo`) is NOT a false positive, while a real `curl x | bash` is.
detect_net_pipe() {
  saw_dl=0
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    # shellcheck disable=SC2046,SC2086
    set -- $(skip_wrappers "$stage")
    [ $# -gt 0 ] || continue
    sc="$1"
    case "$sc" in */*) sc="${sc##*/}" ;; esac
    sc="${sc#\\}"; sc="${sc//\"/}"; sc="${sc//\'/}"
    if [ "$saw_dl" = 1 ]; then
      case "$sc" in
        sh|bash|zsh|dash|ksh|python|python[0-9]*|perl|ruby|node|php)
          return 2 ;;
      esac
    fi
    case "$sc" in curl|wget|fetch) saw_dl=1 ;; esac
  done <<EOF_NET
$(printf '%s\n' "$1" | awk '{gsub(/\|/,"\n")}1')
EOF_NET
  return 0
}

# Evaluate ONE command segment. Returns 2 (and prints) to block, 0 to allow.
evaluate_segment() {
  seg="$1"

  # -- structural checks (these only survive on the raw segment text) --------
  if [[ "$seg" =~ $DEV_RE ]]; then
    deny "redirect onto a raw disk device"; return 2
  fi
  if [[ "$seg" =~ $TRUNC_RE ]]; then
    deny "truncate a file to empty (\`: >\`)"; return 2
  fi
  if [[ "$seg" =~ $FORK_RE ]]; then
    fn="${BASH_REMATCH[1]}"; body="${BASH_REMATCH[2]}"
    if [[ "$body" == *"|"* && "$body" == *"&"* && "$body" == *"$fn"* ]]; then
      deny "fork bomb"; return 2
    fi
  fi
  # curl|sh — command-word-anchored (see detect_net_pipe).
  detect_net_pipe "$seg" || { deny "network download piped into a shell"; return 2; }

  # User-supplied extra patterns (ERE), ;- or newline-separated.
  if [ -n "${EXTRA:-}" ]; then
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      [[ "$seg" =~ $pat ]] && { deny "matches a configured block pattern"; return 2; }
    done <<EOF2
$(printf '%s\n' "$EXTRA" | awk '{gsub(/;/,"\n")}1')
EOF2
  fi

  # -- per-stage command-word checks -----------------------------------------
  # Split the segment into pipeline stages and subshell/brace bodies (on
  # | & ( ) { } and backtick) so a dangerous command behind a pipe, a background
  # &, a subshell or a brace group is still inspected. set -f keeps globs literal.
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    eval_stage "$stage" || return 2
  done <<EOF_STAGE
$(printf '%s\n' "$seg" | awk '{gsub(/[|&(){}]/,"\n"); gsub(/\140/,"\n")}1')
EOF_STAGE
  return 0
}

# Split the command on shell separators (&&, ||, ;) and physical newlines, then
# judge each piece independently. Best-effort: exotic quoting can hide an op,
# which fails open — acceptable for a convenience guard.
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  evaluate_segment "$seg" || exit 2
done <<EOF
$(printf '%s\n' "$cmd" | awk '{gsub(/&&|\|\||;/,"\n")}1')
EOF

exit 0
