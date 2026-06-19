#!/bin/bash
# cc-goodies / shell-guard
# Block a small, curated set of *catastrophic* shell commands before they run.
#
# Wired as a PreToolUse hook on the Bash tool. The tool call's JSON arrives on
# stdin; we read .tool_input.command and .cwd, split the command into segments,
# and block (exit 2) when a segment matches a high-confidence dangerous pattern:
# wiping `/` or `$HOME`, recursively deleting a top-level system dir, writing
# onto a raw disk device, mkfs/wipefs, a fork bomb, piping a network download
# into a shell, truncating a file to empty (`: >`/`truncate -s0`), `chmod 777`,
# `eval`, `sudo`, and system halt/reboot. Everything else passes straight through.
#
# Designed to fully cover — and improve on — a typical settings.json shell
# deny list: by normalising flags/spacing and resolving the target it catches
# obfuscated variants (`rm -fr /`, `rm --recursive --force ~`) that exact-string
# matching misses. It is a convenience guard, not a sandbox — keep real OS-level
# protections too. It deliberately does NOT block ordinary work like
# `rm -rf ./build` or `rm -rf node_modules`.
#
# Config, lowest to highest precedence:
#   built-in defaults -> ~/.claude/shell-guard.conf (KEY=VALUE) -> environment
#
#   SHELL_GUARD_DISABLE=1            # turn the guard off without uninstalling
#   SHELL_GUARD_ALLOW_SUDO=1        # permit `sudo` (blocked by default)
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
# `sudo` is blocked by default (privilege escalation); opt out to permit it.
ALLOW_SUDO="${SHELL_GUARD_ALLOW_SUDO:-$(conf_get SHELL_GUARD_ALLOW_SUDO)}"

# Regexes kept in variables so the `>` / `(` inside them never confuse the [[ ]]
# parser, and so they read as plain ERE.
# A download whose output reaches an interpreter — through any number of pipe
# stages, an optional env/var/sudo prefix before the shell, and a wider set of
# interpreters (sh/bash/zsh/dash/ksh + python/perl/ruby/node/php).
NET_RE='(curl|wget|fetch)([^|]*\|)+[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|env[[:space:]]+|sudo[[:space:]]+)*(sh|bash|zsh|dash|ksh|python[0-9.]*|perl|ruby|node|php)([[:space:]]|-|$)'
# Process substitution fed to an interpreter incl. source/. — `bash <(curl …)`.
NETSUB_RE='(sh|bash|zsh|dash|ksh|source|\.)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*<\((curl|wget|fetch)'
# Command substitution fed to an interpreter — `bash -c "$(curl …)"`.
NETCMDSUB_RE='(sh|bash|zsh|dash|ksh)[[:space:]][^=]*\$\([[:space:]]*(curl|wget|fetch)'
DEV_RE='>[[:space:]]*/dev/(disk|rdisk|sd|hd|nvme|vd)'
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
  t="$1"
  t="${t#\"}"; t="${t%\"}"; t="${t#\'}"; t="${t%\'}"   # strip surrounding quotes
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
  if [ -n "${CWD:-}" ] && [ "$CWD" = "$HOME" ]; then
    case "$t" in '.'|'./'|'*'|'.*'|'./*') return 0 ;; esac
  fi
  return 1
}

# Evaluate the tokenised command word of ONE pipeline stage. Returns 2 to block.
eval_tokens() {
  # shellcheck disable=SC2086
  set -- $1
  [ $# -gt 0 ] || return 0

  # Walk past benign prefixes / shell keywords to the real command word.
  # `sudo` is blocked outright by default (privilege escalation); with
  # SHELL_GUARD_ALLOW_SUDO set it's treated as a prefix so the wrapped command
  # is still inspected (e.g. `sudo rm -rf /` is caught by the rm check below).
  while [ $# -gt 0 ]; do
    case "$1" in
      sudo)
        if [ -z "${ALLOW_SUDO:-}" ] || [ "$ALLOW_SUDO" = "0" ]; then
          deny "sudo — privilege escalation (set SHELL_GUARD_ALLOW_SUDO=1 to permit)"; return 2
        fi
        shift ;;
      *=*|command|exec|builtin|nice|nohup|time|env|then|do|else) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  c="$1"; shift

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
      for a in "$@"; do
        case "$a" in of=/dev/*) deny "dd onto a device node"; return 2 ;; esac
      done
      ;;
    mkfs|mkfs.*|wipefs|newfs|newfs_*)
      deny "filesystem creation/wipe ($c)"; return 2
      ;;
    diskutil)
      case "${1:-}" in
        eraseDisk|eraseVolume|reformat|zeroDisk|secureErase|partitionDisk|eraseall)
          deny "destructive diskutil ($1)"; return 2 ;;
      esac
      ;;
    chmod|chown)
      has_R=0; cata=0; perm777=0
      for a in "$@"; do
        case "$a" in
          777|0777)    perm777=1 ;;
          --recursive) has_R=1 ;;
          --*) : ;;
          -*) case "$a" in *R*) has_R=1 ;; esac ;;
          *)  is_cata_target "$a" && cata=1 ;;
        esac
      done
      [ "$c" = chmod ] && [ "$perm777" = 1 ] && { deny "chmod 777 — world-writable permissions"; return 2; }
      [ "$has_R" = 1 ] && [ "$cata" = 1 ] && { deny "recursive $c of a protected path"; return 2; }
      ;;
    reboot|shutdown|halt|poweroff)
      deny "system halt/reboot ($c)"; return 2
      ;;
    init|telinit)
      case "${1:-}" in 0|6) deny "system halt/reboot ($c $1)"; return 2 ;; esac
      ;;
    eval)
      deny "eval — arbitrary code execution"; return 2
      ;;
    truncate)
      # `truncate -s 0` / `-s0` / `--size=0` zeroes a file.
      sflag=""
      for a in "$@"; do
        case "$a" in
          -s0|-s0K|-s0M|--size=0|--size=0K|--size=0M) deny "truncate a file to zero"; return 2 ;;
          -s|--size) sflag=1 ;;
          0|0K|0M|0KB) [ -n "$sflag" ] && { deny "truncate a file to zero"; return 2; }; sflag="" ;;
          *) sflag="" ;;
        esac
      done
      ;;
  esac
  return 0
}

# Evaluate ONE command segment. Returns 2 (and prints) to block, 0 to allow.
evaluate_segment() {
  seg="$1"

  # -- raw-text checks (these don't survive tokenising) ----------------------
  if [[ "$seg" =~ $NET_RE ]] || [[ "$seg" =~ $NETSUB_RE ]] || [[ "$seg" =~ $NETCMDSUB_RE ]]; then
    deny "network download piped into a shell"; return 2
  fi
  if [[ "$seg" =~ $DEV_RE ]]; then
    deny "redirect onto a raw disk device"; return 2
  fi
  if [[ "$seg" =~ $TRUNC_RE ]]; then
    deny "truncate a file to empty (\`: >\`)"; return 2
  fi
  # Fork bomb: a function that pipes & backgrounds a call to itself.
  if [[ "$seg" =~ $FORK_RE ]]; then
    fn="${BASH_REMATCH[1]}"; body="${BASH_REMATCH[2]}"
    if [[ "$body" == *"|"* && "$body" == *"&"* && "$body" == *"$fn"* ]]; then
      deny "fork bomb"; return 2
    fi
  fi
  # User-supplied extra patterns (ERE), ;- or newline-separated.
  if [ -n "${EXTRA:-}" ]; then
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      [[ "$seg" =~ $pat ]] && { deny "matches a configured block pattern"; return 2; }
    done <<EOF2
$(printf '%s\n' "$EXTRA" | awk '{gsub(/;/,"\n")}1')
EOF2
  fi

  # -- tokenised checks ------------------------------------------------------
  # The pipe/redirect-aware regexes above already ran on the whole segment.
  # Now split it into pipeline stages and subshell/brace bodies (on | & ( ) { })
  # and run the per-command checks on each, so a dangerous command behind a pipe,
  # a background &, a subshell or a brace group is still inspected. set -f (top of
  # file) keeps globs literal across the split.
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    eval_tokens "$stage" || return 2
  done <<EOF_STAGE
$(printf '%s\n' "$seg" | awk '{gsub(/[|&(){}]/,"\n")}1')
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
