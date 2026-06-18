#!/bin/bash
# cc-goodies / git-guard
# Block accidental writes to protected branches *before* they happen.
#
# Wired as a PreToolUse hook on the Bash tool. The tool call's JSON arrives on
# stdin; we read .tool_input.command and .cwd, work out which git action is
# being run and against which branch, and block (exit 2) when the active policy
# forbids it. Anything that is not a git commit/merge/push is passed straight
# through untouched.
#
# Policies (GIT_GUARD_POLICY, default 2):
#   1  block: push -> main.                  allow: commit main, commit/push dev.
#   2  block: push -> main, commit -> main.  allow: commit/push dev.   (default)
#   3  block: any push, commit -> main.      allow: commit dev/feature.
#
# Config, lowest to highest precedence:
#   built-in defaults  ->  ~/.claude/git-guard.conf (KEY=VALUE)  ->  environment
#
#   GIT_GUARD_POLICY=2
#   GIT_GUARD_MAIN_BRANCHES="main master"
#   GIT_GUARD_DEV_BRANCHES="develop"
#   GIT_GUARD_DISABLE=1        # turn the guard off without uninstalling
#
# "commit -> main" also covers `git merge` while on a protected branch (a merge
# mutates the current branch exactly like a commit). `git pull`/`git rebase` are
# NOT yet guarded — see README.
#
# Requires jq (used to parse the hook JSON). If jq is missing the guard cannot
# read the command, so it no-ops with a one-line warning rather than blocking
# every Bash call.
#
# Exit codes: 0 = allow (Claude Code runs the command), 2 = block (stderr is fed
# back to Claude). Any other code is a non-blocking error in the hooks API and
# would let the command run, so we never use one to deny.

set -u

input=$(cat)

# Without jq we cannot read the command -> fail OPEN (a guard that blocks every
# Bash call when a dependency is missing is worse than no guard). Documented.
if ! command -v jq >/dev/null 2>&1; then
  echo "git-guard: jq not found; guard disabled (brew install jq to enable)." >&2
  exit 0
fi

# Defence in depth: only act on the Bash tool.
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
[ "$tool" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -n "$cmd" ] || exit 0

# Fast path: nothing git-shaped, nothing to do.
case "$cmd" in *git*) ;; *) exit 0 ;; esac

# --- Effective configuration (env > conf file > default) --------------------
# The conf file is read with a safe KEY=VALUE parser, never `source`d, so a
# stray ~/.claude/git-guard.conf cannot execute arbitrary shell in the hook.
CONF="$HOME/.claude/git-guard.conf"
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

POLICY="${GIT_GUARD_POLICY:-$(conf_get GIT_GUARD_POLICY)}";                 POLICY="${POLICY:-2}"
MAIN_BRANCHES="${GIT_GUARD_MAIN_BRANCHES:-$(conf_get GIT_GUARD_MAIN_BRANCHES)}"; MAIN_BRANCHES="${MAIN_BRANCHES:-main master}"
DEV_BRANCHES="${GIT_GUARD_DEV_BRANCHES:-$(conf_get GIT_GUARD_DEV_BRANCHES)}";    DEV_BRANCHES="${DEV_BRANCHES:-develop}"
DISABLE="${GIT_GUARD_DISABLE:-$(conf_get GIT_GUARD_DISABLE)}"

# Escape hatch.
[ -n "${DISABLE:-}" ] && [ "$DISABLE" != "0" ] && exit 0

# --- Helpers ----------------------------------------------------------------
class_of() {
  b="$1"
  for m in $MAIN_BRANCHES; do [ "$b" = "$m" ] && { printf MAIN; return; }; done
  for m in $DEV_BRANCHES;  do [ "$b" = "$m" ] && { printf DEV;  return; }; done
  printf OTHER
}

current_branch() {
  gdir="$1"
  if [ -n "$gdir" ]; then
    git -C "$gdir" rev-parse --abbrev-ref HEAD 2>/dev/null
  else
    git rev-parse --abbrev-ref HEAD 2>/dev/null
  fi
}

deny() {
  # $1 = human reason
  printf '%s\n' "⛔ git-guard (policy $POLICY): blocked $1." >&2
  printf '%s\n' "   Protected: $MAIN_BRANCHES. Use a feature branch or '${DEV_BRANCHES%% *}'." >&2
  printf '%s\n' "   Override: run it yourself in a terminal, set GIT_GUARD_DISABLE=1, or see /git-guard." >&2
  return 2
}

# Evaluate ONE command segment. Returns 2 (and prints) to block, 0 to allow.
evaluate_segment() {
  seg="$1"
  # shellcheck disable=SC2086
  set -- $seg
  [ $# -gt 0 ] || return 0

  # Walk past benign prefixes until we hit `git`; bail if some other command.
  while [ $# -gt 0 ]; do
    case "$1" in
      git) shift; break ;;
      *=*|sudo|command|exec|builtin|nice|nohup|time|env) shift ;;
      *) return 0 ;;   # not a git invocation (e.g. `echo git push ...`)
    esac
  done
  [ $# -gt 0 ] || return 0   # bare `git`

  # Parse git's global options to find the subcommand and an optional `-C dir`.
  cdir=""; verb=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) cdir="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      -c) shift; [ $# -gt 0 ] && shift ;;
      --git-dir=*|--work-tree=*|--namespace=*) shift ;;
      --git-dir|--work-tree|--namespace) shift; [ $# -gt 0 ] && shift ;;
      -*) shift ;;
      *) verb="$1"; shift; break ;;
    esac
  done
  [ -n "$verb" ] || return 0

  case "$verb" in
    commit|merge) action="localwrite" ;;
    push)         action="push" ;;
    *)            return 0 ;;
  esac

  # Resolve the target branch + its class.
  if [ "$action" = "push" ]; then
    pushall=0; first=""; second=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --all|--mirror) pushall=1 ;;
        -*) ;;                       # other flags don't name a branch
        *)
          if [ -z "$first" ]; then first="$1"
          elif [ -z "$second" ]; then second="$1"
          fi ;;
      esac
      shift
    done
    if [ "$pushall" = "1" ]; then
      target="__ALL__"
    elif [ -n "$second" ]; then
      target="$second"               # `git push <remote> <refspec>`
    else
      target="__CURRENT__"           # `git push` or `git push <remote>`
    fi
    case "$target" in
      __ALL__|__CURRENT__) ;;
      *:*) target="${target##*:}" ;; # src:dst (incl. :dst delete) -> dst
    esac
    target="${target#refs/heads/}"

    case "$target" in
      __ALL__)     br="all branches"; tclass="MAIN" ;;      # includes protected
      __CURRENT__) br="$(current_branch "${cdir:-$cwd}")"
                   [ -n "$br" ] || return 0                 # not a repo -> git will fail
                   tclass="$(class_of "$br")" ;;
      *)           br="$target"; tclass="$(class_of "$br")" ;;
    esac
  else
    br="$(current_branch "${cdir:-$cwd}")"
    [ -n "$br" ] || return 0
    tclass="$(class_of "$br")"
  fi

  # Apply policy. Unknown policy values fall back to the protective default (2).
  case "$POLICY" in
    1)
      [ "$action" = "push" ] && [ "$tclass" = "MAIN" ] && { deny "push to protected branch '$br'"; return 2; }
      ;;
    3)
      [ "$action" = "push" ] && { deny "push to '$br' (policy 3 blocks all pushes)"; return 2; }
      [ "$action" = "localwrite" ] && [ "$tclass" = "MAIN" ] && { deny "$verb on protected branch '$br'"; return 2; }
      ;;
    *)   # 2 and any unrecognised value
      [ "$action" = "push" ] && [ "$tclass" = "MAIN" ] && { deny "push to protected branch '$br'"; return 2; }
      [ "$action" = "localwrite" ] && [ "$tclass" = "MAIN" ] && { deny "$verb on protected branch '$br'"; return 2; }
      ;;
  esac
  return 0
}

# Split the command on shell separators (&&, ||, ;) and physical newlines, then
# judge each piece independently. Best-effort: exotic quoting can hide a verb,
# which fails open — acceptable for a convenience guard, documented in README.
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  evaluate_segment "$seg" || exit 2
done <<EOF
$(printf '%s\n' "$cmd" | awk '{gsub(/&&|\|\||;/,"\n")}1')
EOF

exit 0
