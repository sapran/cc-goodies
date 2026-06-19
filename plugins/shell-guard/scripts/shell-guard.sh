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
NET_RE='(curl|wget|fetch)([^|]*\|)+[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|env[[:space:]]+|sudo[[:space:]]+|xargs([[:space:]]+-[^[:space:]]+)*[[:space:]]+)*(sh|bash|zsh|dash|ksh|pwsh|python[0-9.]*|perl|ruby|node|php|osascript|deno|bun|Rscript|tclsh|lua)([[:space:]]|-|$|[);&|}])'
# Process substitution fed to an interpreter incl. source/. and a `< <(curl …)` stdin redirect.
NETSUB_RE='(sh|bash|zsh|dash|ksh|source|\.)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(<[[:space:]]*)?<\((curl|wget|fetch)'
# Command substitution fed to an interpreter — `bash -c "$(curl …)"`, `python -c "$(curl …)"`.
NETCMDSUB_RE='(sh|bash|zsh|dash|ksh|pwsh|python[0-9.]*|perl|ruby|node|php)[[:space:]][^=]*\$\([[:space:]]*(curl|wget|fetch)'
# Redirect onto a raw disk device — `> /dev/disk0`, `>| /dev/disk0`, quoted target.
DEV_RE='>[|]?[[:space:]]*["'"'"']?/dev/(disk|rdisk|sd|hd|nvme|vd)'
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

# Does this argument name a raw disk device? Quotes are stripped first so a
# quoted target (`"/dev/disk0"`) is still caught. Keep the device list in sync
# with DEV_RE (the `>`-redirect variant) above.
is_raw_disk() {
  dev="${1//\"/}"; dev="${dev//\'/}"
  case "$dev" in
    /dev/disk*|/dev/rdisk*|/dev/sd*|/dev/hd*|/dev/nvme*|/dev/vd*) return 0 ;;
  esac
  return 1
}

# Evaluate the tokenised command word of ONE pipeline stage. Returns 2 to block.
eval_tokens() {
  # shellcheck disable=SC2086
  set -- $1
  [ $# -gt 0 ] || return 0

  # Walk past leading redirections, command wrappers, and shell keywords to the real
  # command word. `sudo` is blocked outright by default (privilege escalation); with
  # SHELL_GUARD_ALLOW_SUDO set it's treated as a prefix so the wrapped command is still
  # inspected. Wrappers (timeout/setsid/env/xargs/…) are matched by basename so
  # `/usr/bin/env rm -rf /` is handled; sw=1 once we are past a prefix lets a wrapper's
  # own options (`env -i`, `nice -n 5`) be skipped without swallowing a bare command.
  sw=0
  while [ $# -gt 0 ]; do
    [ "${#1}" -lt 4096 ] || break   # an oversized token is the command word — no prefix to skip
    case "$1" in
      '>'|'>>'|'<'|'<<'|'<<<'|'>|'|'&>'|'&>>'|[0-9]'>'|[0-9]'>>'|[0-9]'<')
        sw=1; shift; [ $# -gt 0 ] && shift; continue ;;   # redirect op + its target token
      [0-9]*'>'*|[0-9]*'<'*|'>'*|'<'*|'&>'*)
        sw=1; shift; continue ;;                          # redirect glued to target: >/tmp/x
    esac
    # basename, but only for slashed tokens under 4 KB — `${##*/}` is O(n^2) and a
    # 4 KB+ "command word" is never a real program name, so skip the strip there.
    case "$1" in */*) [ "${#1}" -lt 4096 ] && w="${1##*/}" || w="$1" ;; *) w="$1" ;; esac
    w="${w#\\}"; w="${w//\"/}"; w="${w//\'/}"
    case "$w" in
      sudo|doas|su|runuser|pkexec|gosu|sudoedit|setpriv)   # privilege escalation — blocked by default
        if [ -z "${ALLOW_SUDO:-}" ] || [ "$ALLOW_SUDO" = "0" ]; then
          deny "$w — privilege escalation (set SHELL_GUARD_ALLOW_SUDO=1 to permit)"; return 2
        fi
        sw=1; shift; continue ;;
      command|exec|builtin|nohup|time|env|setsid|stdbuf|then|do|else)
        sw=1; shift; continue ;;
      timeout|nice|chrt|taskset|ionice)   # resource wrappers: skip their opts, opt
        sw=1; shift                        # values, AND numeric positionals to the real cmd
        while [ $# -gt 0 ]; do
          case "$1" in
            -s|--signal|-k|--kill-after) shift; [ $# -gt 0 ] && shift ;;   # timeout SIG/DUR value
            -*) shift ;;
            [0-9]*) shift ;;               # duration/priority/mask
            *) break ;;
          esac
        done
        continue ;;
      xargs)     # xargs [opts] cmd — skip opts AND their values to reach the command
        sw=1; shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -I|--replace|-d|--delimiter|-E|--eof|-n|--max-args|-P|--max-procs|-L|--max-lines|-l|-s)
              shift; [ $# -gt 0 ] && shift ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        continue ;;
    esac
    case "$1" in
      *=*) sw=1; shift; continue ;;                       # VAR=val prefix
      -*)  if [ "$sw" = 1 ]; then shift; continue; else break; fi ;;  # a wrapper's option
      *)   break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  c="$1"; shift
  [ "${#c}" -lt 4096 ] || return 0   # an oversized command word is no known dangerous command
  case "$c" in */*) c="${c##*/}" ;; esac   # basename (length-guarded above: avoid O(n^2))
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
      for a in "$@"; do
        na="${a//\"/}"; na="${na//\'/}"
        case "$na" in of=/dev/*) deny "dd onto a device node"; return 2 ;; esac
      done
      ;;
    mkfs|mkfs.*|wipefs|newfs|newfs_*)
      deny "filesystem creation/wipe ($c)"; return 2
      ;;
    find)
      # `find <protected path> … -delete`, or `-exec`/`-ok` running a *mutating*
      # command, recursively destroys like `rm -rf`. A read-only `-exec grep/cat/…`
      # over a system dir is ordinary recon, so the executed command is inspected.
      fdestroy=0; fcata=0; inexec=0; xskip=0
      for a in "$@"; do
        if [ "$inexec" = 1 ]; then   # walk past wrappers to the command -exec actually runs
          if [ "$xskip" = 1 ]; then xskip=0; else
          case "${a##*/}" in
            env|nohup|setsid|stdbuf|ionice|nice|chrt|taskset|timeout|xargs|command|exec|sudo|doas|su|runuser|pkexec|gosu) : ;;
            -s|--signal|-k|--kill-after|-u|--user|-g|--group|-I|--replace|-d|--delimiter|-E|--eof|-n|--max-args|-P|--max-procs|-C|-S|--split-string|-a|-o|-L|-l)
              xskip=1 ;;              # wrapper option that takes a value — skip its value too
            *=*|-*|[0-9]*) : ;;      # VAR=val, a wrapper option, or a numeric positional
            rm|rmdir|mv|chmod|chown|shred|dd|truncate|tee|unlink) fdestroy=1; inexec=0 ;;
            *) inexec=0 ;;           # a read-only command (grep/cat/…): stop, not destructive
          esac
          fi
        fi
        case "$a" in
          -exec|-execdir|-ok|-okdir) inexec=1 ;;
          -delete) fdestroy=1 ;;
          -*) : ;;
          *) is_cata_target "$a" && fcata=1 ;;
        esac
      done
      [ "$fdestroy" = 1 ] && [ "$fcata" = 1 ] && { deny "destructive find over a protected path"; return 2; }
      ;;
    shred)
      for a in "$@"; do
        is_raw_disk "$a" && { deny "shred a raw disk device"; return 2; }
        is_cata_target "$a" && { deny "shred of a protected path"; return 2; }
      done
      ;;
    cp|tee)
      # Overwriting a raw disk device via cp/tee (not just dd/redirect).
      for a in "$@"; do
        is_raw_disk "$a" && { deny "$c onto a raw disk device"; return 2; }
      done
      ;;
    diskutil)
      case "${1:-}" in
        eraseDisk|eraseVolume|reformat|zeroDisk|secureErase|partitionDisk|eraseall)
          deny "destructive diskutil ($1)"; return 2 ;;
        apfs) case "${2:-}" in delete*|erase*) deny "destructive diskutil (apfs $2)"; return 2 ;; esac ;;
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
  # An interpreter running an inline script string — recurse into the -c argument so
  # `bash -c "rm -rf /"` (or `timeout 5 bash -c "…"`) is judged like a normal command.
  # The option group accepts long options (`--norc`, `--rcfile /dev/null`) before -c.
  # A depth bound stops a deeply nested `bash -c bash -c …` from stalling the hook.
  if [ "${SG_CDEPTH:-0}" -lt 8 ] && [[ "$seg" =~ (^|[^[:alnum:]_])(sh|bash|zsh|dash|ksh)[[:space:]]+([-A-Za-z0-9_/.=]+[[:space:]]+)*-[A-Za-z]*c[[:space:]]+(.*)$ ]]; then
    inner="${BASH_REMATCH[4]}"
    inner="${inner%\"}"; inner="${inner#\"}"; inner="${inner%\'}"; inner="${inner#\'}"
    if [ -n "$inner" ] && [ "$inner" != "$seg" ]; then
      SG_CDEPTH=$(( ${SG_CDEPTH:-0} + 1 ))
      evaluate_segment "$inner"; rc=$?
      SG_CDEPTH=$(( SG_CDEPTH - 1 ))
      [ "$rc" = 2 ] && return 2
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
