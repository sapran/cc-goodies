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
# "commit -> main" also covers `git merge`, `git pull` and `git rebase` while on
# a protected branch: each mutates the current branch exactly like a commit, so
# they are all treated as a local write and gated by the same policy.
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

  # Walk past benign prefixes and command wrappers until we hit `git`; bail if some
  # other command. Wrappers are skipped so `timeout 60 git push origin main` and
  # `nice -n 5 git push …` are still judged. Each wrapper consumes its own options
  # AND any value those options take, so a wrapper option's value (`timeout -s KILL`,
  # `sudo -u alice`) is never mistaken for the command word. Resource wrappers also
  # swallow numeric positionals (duration/priority/CPU mask).
  while [ $# -gt 0 ]; do
    case "${1##*/}" in
      git) shift; break ;;
      timeout|nice|chrt|taskset|ionice)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -s|--signal|-k|--kill-after) shift; [ $# -gt 0 ] && shift ;;   # timeout SIG/DUR value
            -*) shift ;;
            [0-9]*) shift ;;                                               # duration/priority/mask
            *) break ;;
          esac
        done ;;
      sudo|doas)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -u|--user|-g|--group|-p|--prompt|-r|--role|-t|--type|-T|-U|-h|--host|-C|--close-from|-R|-D|--chdir)
              shift; [ $# -gt 0 ] && shift ;;
            -*) shift ;;
            *) break ;;
          esac
        done ;;
      env)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -u|--unset|-C|--chdir|-S|--split-string) shift; [ $# -gt 0 ] && shift ;;
            -*) shift ;;
            *=*) shift ;;                                                  # env VAR=val assignment
            *) break ;;
          esac
        done ;;
      xargs)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -I|--replace|-d|--delimiter|-E|--eof|-n|--max-args|-P|--max-procs|-L|--max-lines|-l|-s)
              shift; [ $# -gt 0 ] && shift ;;
            -*) shift ;;
            *) break ;;
          esac
        done ;;
      command|exec|builtin|nohup|time|setsid|stdbuf|su|runuser|pkexec|then|do|else)
        # Option-only wrappers: skip leading boolean options to reach the command.
        # Rare value-taking opts here (exec -a NAME, time -o FILE, su -c CMD) are a
        # documented residual.
        shift
        while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done ;;
      *) case "$1" in *=*) shift ;; *) return 0 ;; esac ;;   # VAR=val prefix, else not git
    esac
  done
  [ $# -gt 0 ] || return 0   # bare `git`

  # Parse git's global options to find the subcommand and an optional `-C dir`.
  # `aliases` collects inline `-c alias.NAME=VERB` definitions so they can be
  # resolved to the underlying verb below.
  cdir=""; verb=""; aliases=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) cdir="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
      -c) cval="${2:-}"; shift; [ $# -gt 0 ] && shift
          case "$cval" in
            alias.*=*) an="${cval#alias.}"; an="${an%%=*}"
                       av="${cval#*=}"; av="${av%% *}"   # first word of the expansion
                       aliases="$aliases${aliases:+ }$an=$av" ;;
          esac ;;
      --git-dir=*|--work-tree=*|--namespace=*) shift ;;
      --git-dir|--work-tree|--namespace) shift; [ $# -gt 0 ] && shift ;;
      -*) shift ;;
      *) verb="$1"; shift; break ;;
    esac
  done
  [ -n "$verb" ] || return 0

  # Resolve an inline-defined alias (`git -c alias.up=push up …`) to its real verb,
  # so the alias is judged as the action it performs. Persistent-config aliases in
  # ~/.gitconfig can't be seen from here and remain a documented gap.
  for amap in $aliases; do
    case "$amap" in "$verb="*) verb="${amap#*=}"; break ;; esac
  done

  # `xtarget`, when set, names the branch a verb acts on explicitly (e.g.
  # `branch -f main`) — judged by that branch's class rather than the current one.
  xtarget=""
  case "$verb" in
    commit|merge|pull|rebase|cherry-pick|revert|am) action="localwrite" ;;
    push)                                           action="push" ;;
    reset)
      # Only a history-moving reset counts; `git reset <path>` (unstage) does not.
      action=""
      for a in "$@"; do case "$a" in --hard|--merge|--keep) action="localwrite" ;; esac; done
      [ -n "$action" ] || return 0 ;;
    branch)
      # `-f|-D|-M|-C` force-reset / delete / force-rename / force-copy; `-m|-c`
      # rename / copy. All can clobber, move or replace a protected branch.
      bforce=0; brename=0
      for a in "$@"; do
        case "$a" in
          -f|--force|-D|-M|-C) bforce=1 ;;
          -m|--move|-c|--copy)  brename=1 ;;
        esac
      done
      [ "$bforce" = 1 ] || [ "$brename" = 1 ] || return 0
      # A rename/copy with one name targets the CURRENT branch; with two it moves
      # <old> -> <new>. Touching a protected branch on EITHER side counts, so judge
      # every positional, and for the single-name rename judge the current branch.
      np=0; hit=""
      for a in "$@"; do
        case "$a" in -*) continue ;; esac
        np=$((np+1)); nm="${a//\"/}"; nm="${nm//\'/}"
        [ "$(class_of "$nm")" = MAIN ] && { hit="$nm"; break; }
      done
      if [ -z "$hit" ] && [ "$brename" = 1 ] && [ "$np" -lt 2 ]; then
        cb="$(current_branch "${cdir:-$cwd}")"
        [ -n "$cb" ] && [ "$(class_of "$cb")" = MAIN ] && hit="$cb"
      fi
      [ -n "$hit" ] || return 0
      xtarget="$hit"
      action="localwrite" ;;
    update-ref)
      # Skip the value of `-m <reason>` so the reason text isn't taken as the ref.
      skipval=0
      for a in "$@"; do
        if [ "$skipval" = 1 ]; then skipval=0; continue; fi
        case "$a" in
          -m|--message) skipval=1 ;;
          -*) ;;
          *) xtarget="$a"; break ;;
        esac
      done
      xtarget="${xtarget#refs/heads/}"
      [ -n "$xtarget" ] || return 0
      action="localwrite" ;;
    checkout|switch)
      # `-B`/`-C` force-create-or-reset the named branch.
      cforce=0; prev=""
      for a in "$@"; do case "$a" in -B|-C) cforce=1 ;; esac; done
      [ "$cforce" = 1 ] || return 0
      for a in "$@"; do case "$prev" in -B|-C) xtarget="$a"; break ;; esac; prev="$a"; done
      [ -n "$xtarget" ] || return 0
      action="localwrite" ;;
    *)                                              return 0 ;;
  esac

  # Resolve the target branch + its class.
  if [ "$action" = "push" ]; then
    pushall=0; first=""; second=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --all|--mirror) pushall=1 ;;
        -o|--push-option|--receive-pack|--exec|--repo)
          [ $# -gt 1 ] && shift ;;   # these flags take a value token — skip it so
                                     # it isn't mistaken for the remote/refspec
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
    target="${target//\"/}"; target="${target//\'/}"   # de-quote refspec (`"main"` -> main)
    case "$target" in
      __ALL__|__CURRENT__) ;;
      *:*) target="${target##*:}" ;; # src:dst (incl. :dst delete) -> dst
    esac
    target="${target#+}"             # force-push shorthand: +main -> main
    target="${target#refs/heads/}"

    case "$target" in
      __ALL__)          br="all branches"; tclass="MAIN" ;;   # includes protected
      __CURRENT__|HEAD) br="$(current_branch "${cdir:-$cwd}")" # HEAD pushes the current branch
                        [ -n "$br" ] || return 0              # not a repo -> git will fail
                        tclass="$(class_of "$br")" ;;
      *)                br="$target"; tclass="$(class_of "$br")" ;;
    esac
  elif [ -n "$xtarget" ]; then
    xtarget="${xtarget//\"/}"; xtarget="${xtarget//\'/}"   # de-quote (`branch -f "main"`)
    br="$xtarget"; tclass="$(class_of "$br")"   # verb names the branch explicitly
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

# Split the command on shell separators — single | & ; and subshell/brace
# ( ) { } (which also covers && and ||) — plus physical newlines, and judge each
# piece. This keeps a `git` verb hidden behind a pipe, background, subshell or
# brace group from slipping past. Best-effort: wrappers (timeout/xargs/bash -c),
# command substitution, and aliases can still hide a verb — fail open, documented.
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  evaluate_segment "$seg" || exit 2
done <<EOF
$(printf '%s\n' "$cmd" | awk '{gsub(/[|&;(){}]/,"\n")}1')
EOF

exit 0
