#!/bin/bash
# cc-goodies / shell-guard
# Block or ask before a small, curated set of *catastrophic* shell commands run.
#
# Wired as a PreToolUse hook on the Bash tool. The tool call's JSON arrives on
# stdin; we read .tool_input.command and .cwd, split the command into segments,
# and act when a segment matches a high-confidence dangerous pattern. Every
# matched arm resolves to one of two AXIS 2 channels (design.md, guard-ask-
# escalation): DENY (exit 2, stderr) for harm that is irreversible or that a
# human at a prompt could not actually judge — wiping `/` or `$HOME`, a top-
# level system dir, writing onto a raw disk device, mkfs/wipefs/destructive
# diskutil, a fork bomb, a network download piped into a shell (including via
# `eval "$(curl …)"`), and system halt/reboot; or ASK (permissionDecision:
# "ask" JSON on stdout, exit 0) for harm that is reversible and disclosed in
# the command text itself — truncating a file to empty (`: >`), `chmod 777`,
# `eval` (without a fetched payload), and privilege escalation (`sudo`/`doas`/
# …). Everything else passes straight through. A compound command (`;`/`&&`/
# `||`/pipes/newlines) is scanned to completion before any decision is made —
# deny > ask > allow — so a deny anywhere wins regardless of where it sits;
# only a deny short-circuits early, since nothing later could outrank it.
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
# Exit codes: 0 = allow, OR ask (permissionDecision:"ask" JSON on stdout — the
# harness escalates to the human's own permission prompt, and degrades to a
# blocked command with no code-level help needed when nobody is there to answer
# it: verified headless, see design.md Decision D3). 2 = deny (stderr is fed
# back to Claude). Any other code is a non-blocking error in the hooks API, so
# we never use one to deny.

set -u
set -f   # never glob while tokenising — keep `*` / `.*` literal in the command

input=$(cat)

# Without jq we cannot read the command -> fail OPEN. Documented above.
if ! command -v jq >/dev/null 2>&1; then
  echo "shell-guard: jq not found; guard disabled (brew install jq to enable)." >&2
  exit 0
fi

# Every split in this script — segments, pipeline stages, subshell bodies, the
# EXTRA pattern list — goes through awk. Without it each of those yields nothing
# and the matching loop simply never runs, so no arm is ever evaluated and the
# script falls through to `exit 0`: the guard silently stops guarding. Fail OPEN
# like the jq path (blocking every Bash call over a missing dependency is worse
# than not guarding), but say so, so the gap is visible rather than silent.
if ! command -v awk >/dev/null 2>&1; then
  echo "shell-guard: awk not found; guard disabled (cannot split the command)." >&2
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

# --- Decision-resolution state ------------------------------------------------
# SEVERITY RESOLUTION: deny > ask > allow, resolved ONCE after the *entire*
# command has been scanned — not by whichever arm is matched first. deny()
# still short-circuits the scan immediately (via `return 2` propagating up to
# an `exit 2` in the main loop below): deny is already the maximum severity, so
# nothing later in the command could change the outcome. ask() is different —
# it must NOT exit, or a deny-class arm in a later segment would never be seen
# (this was the exact regression: an early ask() used to `exit 0` mid-scan).
# Instead ask() records the pending decision here; only the FIRST ask recorded
# survives (ASK_PENDING guards against a later ask overwriting it), and it is
# emitted — if the scan reaches the end without ever hitting a deny — by the
# one `jq` call at the bottom of the script.
ASK_PENDING=0
ASK_REASON=""

# --- Helpers ----------------------------------------------------------------
# $1 = axis-1 class, shared by deny() and ask() below (design.md's AXIS 1,
#      `alternative: named|none` — independent of the `channel: deny|ask` axis
#      (AXIS 2) that picks WHICH of these two functions a matched arm calls):
#        none    - no safe variant of this action exists; keep the
#                  irreversibility warning, offer no alternative.
#        named   - a safe variant exists; print it instead of that warning.
#        neutral - severity unknown (the EXTRA arm only); print neither.
# $2 = human reason, naming the specific rule that matched.
# $3 = safe alternative text (class=named only).
# Both hand the command back as a copy-paste `!`-prefixed line: typed into the
# Claude Code prompt, the `!` prefix runs it in the user's own shell, which
# this hook never sees. $cmd is the original tool command.
deny() {
  # DENY-channel arm: irreversible harm, or harm an `ask` prompt could not let
  # a human judge (see design.md Decision D1). Blocks outright: exit 2, stderr.
  class="$1"; reason="$2"; alt="${3:-}"
  printf '%s\n' "⛔ shell-guard: blocked a dangerous command — $reason." >&2
  case "$class" in
    none)  printf '%s\n' "   ⚠️  This is destructive and IRREVERSIBLE. Verify the target before running." >&2 ;;
    named) printf '%s\n' "   → Safe alternative: $alt." >&2 ;;
  esac
  printf '%s\n' "   Variants of this command (reordered flags, different quoting, a wrapper prefix, \$HOME for ~, …) are blocked too." >&2
  printf '%s\n' "   To run it anyway, paste into the prompt (! runs it in your shell):" >&2
  printf '%s\n' "! $cmd" >&2
  printf '%s\n' "   Or set SHELL_GUARD_DISABLE=1 / see /shell-guard." >&2
  return 2
}

ask() {
  # ASK-channel arm (AXIS 2, guard-ask-escalation): harm that is reversible and
  # fully disclosed in the command text a human would read at a permission
  # prompt (see design.md Decision D1). Carries the exact same axis-1 class/
  # reason/alt message substance deny() uses — same escape hatch, same
  # variants clause — so the two channels differ only in delivery mechanism,
  # never in what they tell the human. When nobody is there to answer the
  # prompt (headless/background), the harness itself degrades this to a
  # blocked command — verified, see design.md Decision D3.
  #
  # SEVERITY RESOLUTION: this function does NOT exit or print. It records the
  # pending ask (first one wins — a later ask must not overwrite an earlier
  # arm's reason) and returns, so the caller keeps scanning the rest of the
  # command: a deny-class arm anywhere else — even a later segment — must
  # still win. The recorded message is only emitted, once, at the very end of
  # the script, and only if nothing denied along the way.
  [ "$ASK_PENDING" = 1 ] && return 0
  class="$1"; reason="$2"; alt="${3:-}"
  msg="🟡 shell-guard: this needs your OK — $reason."
  case "$class" in
    none)  msg="$msg
   ⚠️  This is destructive and IRREVERSIBLE. Verify the target before running." ;;
    named) msg="$msg
   → Safe alternative: $alt." ;;
  esac
  msg="$msg
   Variants of this command (reordered flags, different quoting, a wrapper prefix, \$HOME for ~, …) are blocked too.
   To run it anyway, paste into the prompt (! runs it in your shell):
! $cmd
   Or set SHELL_GUARD_DISABLE=1 / see /shell-guard."
  ASK_PENDING=1
  ASK_REASON="$msg"
  return 0
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
        deny none "recursive delete of a protected path"; return 2
      fi
      ;;
    dd)
      # Only `of=` to a raw DISK device class (KEEP IN SYNC with DEV_RE above) —
      # NOT all of /dev, so `dd of=/dev/null` and `dd of=file` are allowed.
      for a in "$@"; do
        na="${a//\"/}"; na="${na//\'/}"
        case "$na" in
          of=/dev/disk*|of=/dev/rdisk*|of=/dev/sd*|of=/dev/hd*|of=/dev/nvme*|of=/dev/vd*)
            deny none "dd onto a raw disk device"; return 2 ;;
        esac
      done
      ;;
    mkfs|mkfs.*|wipefs|newfs|newfs_*)
      deny none "filesystem creation/wipe ($c)"; return 2
      ;;
    diskutil)
      case "${1:-}" in
        eraseDisk|eraseVolume|reformat|zeroDisk|secureErase|partitionDisk|eraseall)
          deny none "destructive diskutil ($1)"; return 2 ;;
        apfs) case "${2:-}" in delete*|erase*) deny none "destructive diskutil (apfs $2)"; return 2 ;; esac ;;
      esac
      ;;
    reboot|shutdown|halt|poweroff)
      deny none "system halt/reboot ($c)"; return 2
      ;;
    sudo|doas|su|runuser|pkexec|gosu|sudoedit|setpriv)
      ask named "$c — privilege escalation" "run the command directly, without \`$c\`"
      ;;
    eval)
      # AXIS 2 channel-selection refinement (guard-ask-escalation, design.md
      # Decision D1's eval-exception): a fetched payload isn't visible to a
      # human at an ask prompt — same "can't approve what you can't see"
      # principle as detect_net_pipe's curl|sh arm below — so check the WHOLE
      # ORIGINAL command ($cmd, not just this stage or this segment) for a
      # download word: the fetch can be split from its eval across a `;`/
      # `&&`/`||`/newline, or indirected through a variable (`x=curl; eval
      # "$($x …)"`), so a per-segment check misses it (that was the bug).
      # has_download_word() is word-anchored, not a raw substring match, so
      # "curling"/"wgettable" stay ask — and case-insensitive, since macOS's
      # case-insensitive filesystem means `CURL` resolves to the same binary.
      # Detection of `eval` itself is unchanged — this only decides which
      # channel the already-matched eval arm resolves to.
      if has_download_word "$cmd"; then
        deny named "eval — arbitrary code execution" "run the intended command directly, without the eval indirection"; return 2
      else
        ask named "eval — arbitrary code execution" "run the intended command directly, without the eval indirection"
      fi
      ;;
    chmod)
      for a in "$@"; do
        case "$a" in 777|0777) ask named "chmod 777 — world-writable permissions" "chmod 755 (or the narrowest mode the task needs)" ;; esac
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

# Whole-command scope check for the eval/download exception above: is
# curl/wget/fetch present anywhere in $1 as an ISOLATED word — never a raw
# substring match, so "curling"/"wgettable" don't match — case-insensitively
# (bash-3.2-compatible: `tr`, not `${x,,}`)? Splits on the same shell
# metacharacters detect_net_pipe uses (stage boundaries), PLUS `=` within each
# resulting stage, so `x=curl` (assign, then reference the variable — the
# assignment is otherwise a single token with nothing after it, invisible to a
# leading-command-word check) is still caught without resolving what the
# variable expands to at runtime. Unlike detect_net_pipe, every word in a
# stage is checked, not just its leading command word, since this check is
# about a download word appearing ANYWHERE in the text an eval will run —
# not about identifying which stage is itself a running command.
has_download_word() {
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    stage="${stage//=/ }"   # VAR=curl -> VAR curl, so the value is its own word
    # shellcheck disable=SC2086
    set -- $stage
    for w in "$@"; do
      case "$w" in */*) w="${w##*/}" ;; esac
      w="${w#\\}"; w="${w//\"/}"; w="${w//\'/}"
      w=$(printf '%s' "$w" | tr '[:upper:]' '[:lower:]')
      case "$w" in curl|wget|fetch) return 0 ;; esac
    done
  done <<EOF_DL
$(printf '%s\n' "$1" | awk '{gsub(/&&|\|\||;/,"\n"); gsub(/[|&(){}]/,"\n"); gsub(/\140/,"\n")}1')
EOF_DL
  return 1
}

# Evaluate ONE command segment. Returns 2 (and prints) to block, 0 to allow.
evaluate_segment() {
  seg="$1"

  # -- structural checks (these only survive on the raw segment text) --------
  if [[ "$seg" =~ $DEV_RE ]]; then
    deny none "redirect onto a raw disk device"; return 2
  fi
  if [[ "$seg" =~ $TRUNC_RE ]]; then
    ask named "truncate a file to empty (\`: >\`)" "printf '' >"
  fi
  if [[ "$seg" =~ $FORK_RE ]]; then
    fn="${BASH_REMATCH[1]}"; body="${BASH_REMATCH[2]}"
    if [[ "$body" == *"|"* && "$body" == *"&"* && "$body" == *"$fn"* ]]; then
      deny none "fork bomb"; return 2
    fi
  fi
  # curl|sh — command-word-anchored (see detect_net_pipe).
  detect_net_pipe "$seg" || { deny named "network download piped into a shell" "download to a file, read it, then run it as a separate reviewed step"; return 2; }

  # User-supplied extra patterns (ERE), ;- or newline-separated.
  if [ -n "${EXTRA:-}" ]; then
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      [[ "$seg" =~ $pat ]] && { deny neutral "matches your configured SHELL_GUARD_EXTRA_PATTERNS rule: $pat"; return 2; }
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
# which fails open — acceptable for a convenience guard. A deny anywhere exits
# immediately (max severity — nothing later could change the outcome). An ask
# does NOT exit here (see ask()'s own comment) — the loop runs to completion
# so a deny in a LATER segment still wins; only once every segment has been
# scanned clean of any deny do we emit whichever ask was recorded first.
segments=$(printf '%s\n' "$cmd" | awk '{gsub(/&&|\|\||;/,"\n")}1')

# awk exists (checked at the top) but the call can still fail at runtime. $cmd
# is non-empty, so an empty split means exactly that — and an empty split would
# otherwise skip the loop below and reach `exit 0` as a silent allow.
if [ -z "$segments" ]; then
  echo "shell-guard: could not split the command (awk failed); guard skipped." >&2
  exit 0
fi

while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  evaluate_segment "$seg" || exit 2
done <<EOF
$segments
EOF

if [ "$ASK_PENDING" = 1 ]; then
  jq -n --arg reason "$ASK_REASON" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$reason}}'
fi
exit 0
