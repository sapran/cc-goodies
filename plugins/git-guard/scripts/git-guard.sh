#!/bin/bash
# cc-goodies / git-guard
# Block an aligned agent from ACCIDENTALLY writing a protected branch.
#
# Wired as a PreToolUse hook on the Bash tool. The tool call's JSON arrives on
# stdin; we read .tool_input.command and .cwd, work out which git action is
# being run and against which branch, and block (exit 2) when it would land on a
# protected branch. Anything that is not a protected-branch write is passed
# straight through untouched.
#
# This is a convenience guard, not a sandbox. It catches the plain accident
# (`git push origin main`, a commit while on `main`); it does NOT try to defeat
# deliberately hidden git (`bash -c "git push…"`, `$()`, `sudo -u USER git`,
# gitconfig aliases) — that is plan mode's job. See the README "Limitations".
#
# Default behaviour: block a local write while ON a protected branch, and block
# a push whose resolved target is a protected branch. Set
# GIT_GUARD_BLOCK_ALL_PUSH=1 to block every push regardless of target.
#
# Config, lowest to highest precedence:
#   built-in defaults  ->  ~/.claude/git-guard.conf (KEY=VALUE)  ->  environment
#
#   GIT_GUARD_MAIN_BRANCHES="main master"
#   GIT_GUARD_BLOCK_ALL_PUSH=1   # block every push, not just pushes to protected
#   GIT_GUARD_DISABLE=1          # turn the guard off without uninstalling
#
# "local write" covers `git commit`, `merge`, `pull`, `rebase`, `cherry-pick`,
# `revert`, `am` and a history-moving `reset --hard|--merge|--keep` while on a
# protected branch: each mutates the current branch like a commit.
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

MAIN_BRANCHES="${GIT_GUARD_MAIN_BRANCHES:-$(conf_get GIT_GUARD_MAIN_BRANCHES)}"; MAIN_BRANCHES="${MAIN_BRANCHES:-main master}"
BLOCK_ALL_PUSH="${GIT_GUARD_BLOCK_ALL_PUSH:-$(conf_get GIT_GUARD_BLOCK_ALL_PUSH)}"
DISABLE="${GIT_GUARD_DISABLE:-$(conf_get GIT_GUARD_DISABLE)}"

# Escape hatch.
[ -n "${DISABLE:-}" ] && [ "$DISABLE" != "0" ] && exit 0

# --- Helpers ----------------------------------------------------------------
# A branch is protected if it appears in MAIN_BRANCHES (word-split on spaces).
is_main() {
  for m in $MAIN_BRANCHES; do [ "$1" = "$m" ] && return 0; done
  return 1
}

current_branch() {
  gdir="$1"
  if [ -n "$gdir" ]; then
    git -C "$gdir" rev-parse --abbrev-ref HEAD 2>/dev/null
  else
    git rev-parse --abbrev-ref HEAD 2>/dev/null
  fi
}

# Extract the destination branch NAME from one push refspec token:
#   src:dst -> dst ; :dst (delete) -> dst ; +x -> x ; <name> (same-name) -> name ;
#   HEAD -> current branch. Surrounding quotes and a refs/heads/ prefix are stripped.
refspec_dst() {
  rs="${1//\"/}"; rs="${rs//\'/}"; rs="${rs#+}"
  case "$rs" in
    *:*) d="${rs##*:}" ;;
    *)   d="$rs" ;;
  esac
  d="${d#refs/heads/}"
  [ "$d" = "HEAD" ] && d="$(current_branch "$2")"
  printf '%s' "$d"
}

deny() {
  # $1 = human reason. Always hand the blocked command back as a copy-paste
  # `!`-prefixed line: typed into the Claude Code prompt, the `!` prefix runs it
  # in the user's own shell, which this hook never sees. $cmd is the original,
  # unmodified tool command, so the line below re-runs exactly what was attempted.
  printf '%s\n' "⛔ git-guard: blocked $1." >&2
  printf '%s\n' "   Protected: $MAIN_BRANCHES. Use a feature branch or 'develop'." >&2
  printf '%s\n' "   To run it anyway, paste into the prompt (! runs it in your shell):" >&2
  printf '%s\n' "! $cmd" >&2
  printf '%s\n' "   Or set GIT_GUARD_DISABLE=1 / see /git-guard." >&2
  return 2
}

# Evaluate ONE command segment. Returns 2 (and prints) to block, 0 to allow.
evaluate_segment() {
  seg="$1"
  # shellcheck disable=SC2086
  set -- $seg
  [ $# -gt 0 ] || return 0

  # Walk past benign prefixes and common (non-evasive) wrappers until we reach
  # `git`; bail if the segment runs some other command. A flat skip — no
  # per-wrapper option-value tables — handles the accident form (`timeout 60 git
  # push …`); a misparse just fails open, the correct bias for a convenience
  # guard. `rtk [proxy]` is recognised because it is the user's ubiquitous git
  # prefix (`rtk proxy git push …` must be unwrapped to the real git).
  while [ $# -gt 0 ]; do
    case "${1##*/}" in
      git) shift; break ;;
      rtk) shift; [ "${1:-}" = "proxy" ] && shift ;;            # rtk [proxy] git …
      sudo|doas|env|nohup|timeout|nice|chrt|ionice|taskset|setsid|stdbuf|command|exec|builtin|xargs|time)
        shift; while [ $# -gt 0 ]; do case "$1" in -*|[0-9]*|*=*) shift;; *) break;; esac; done ;;
      *) case "$1" in *=*) shift;; *) return 0;; esac ;;        # VAR=val prefix, else not git
    esac
  done
  [ $# -gt 0 ] || return 0   # bare `git`

  # Parse git's global options to find the subcommand and an optional `-C dir`
  # (cross-repo branch resolution; the README promises it). The `-c key=val`
  # value and `--git-dir/--work-tree/--namespace` values are skipped, not
  # interpreted — resolving inline aliases is out of scope by design.
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

  # Classify the verb. `localwrite` is judged against the current branch; `push`
  # resolves its own target below; `branch` (force ops) names its target.
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
      # Only a force op can clobber/replace a protected branch: `-f|-D|-M|-C`.
      # Scan positional names; block the first one that is protected.
      bforce=0
      for a in "$@"; do case "$a" in -f|--force|-D|-M|-C) bforce=1 ;; esac; done
      [ "$bforce" = 1 ] || return 0
      for a in "$@"; do
        case "$a" in -*) continue ;; esac
        nm="${a//\"/}"; nm="${nm//\'/}"
        is_main "$nm" && { xtarget="$nm"; break; }
      done
      [ -n "$xtarget" ] || return 0
      action="localwrite" ;;
    *)                                              return 0 ;;
  esac

  # Resolve the target branch and apply the single policy.
  if [ "$action" = "push" ]; then
    [ -n "${BLOCK_ALL_PUSH:-}" ] && [ "$BLOCK_ALL_PUSH" != "0" ] && { deny "push (GIT_GUARD_BLOCK_ALL_PUSH is set)"; return 2; }
    gdir="${cdir:-$cwd}"

    # Collect positionals (the remote and/or refspecs); skip flags and the flags
    # that take a value token so the value isn't mistaken for a refspec.
    pushall=0; positionals=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --all|--mirror) pushall=1 ;;
        -o|--push-option|--receive-pack|--exec|--repo)
          [ $# -gt 1 ] && shift ;;   # value token — skip
        -*) ;;                       # other flags don't name a branch
        *)  positionals="$positionals $1" ;;
      esac
      shift
    done
    [ "$pushall" = "1" ] && { deny "push --all/--mirror (touches protected branches)"; return 2; }

    # `git push [<remote>] [<refspec>...]`. Drop a leading positional that is a
    # CONFIGURED remote; whatever remains are explicit refspecs.
    # shellcheck disable=SC2086
    set -- $positionals
    remote=""
    if [ $# -gt 0 ]; then
      rname="${1//\"/}"; rname="${rname//\'/}"
      if git -C "$gdir" config --get "remote.$rname.url" >/dev/null 2>&1; then
        remote="$rname"; shift
      fi
    fi

    if [ $# -gt 0 ]; then
      # Explicit refspec(s) override push.default: judge EVERY one, not just the last.
      for rs in "$@"; do
        br="$(refspec_dst "$rs" "$gdir")"
        is_main "$br" && { deny "push to protected branch '$br'"; return 2; }
      done
      return 0
    fi

    # Destination-less push (`git push`, `git push <remote>`): git resolves the
    # target from config, not from the command text — resolve it the same way.
    src="$(current_branch "$gdir")"
    [ -n "$src" ] || return 0          # not a repo -> git will fail anyway

    # Same-name routing (push.default simple/current/matching/nothing/unset): the
    # target shares the source name, so a bare push while ON a protected branch
    # lands on it. (push.default=simple with a different-named upstream makes git
    # REFUSE the push, so it never reaches a protected branch — no block needed.)
    is_main "$src" && { deny "push to protected branch '$src'"; return 2; }

    # push.default=upstream|tracking routes to the configured upstream branch,
    # whose name may DIFFER from the source — the silent develop->main case. Read
    # it from config (not `@{push}`, which needs a materialised remote-tracking ref).
    pd="$(git -C "$gdir" config push.default 2>/dev/null)"
    case "$pd" in
      upstream|tracking)
        up="$(git -C "$gdir" config "branch.$src.merge" 2>/dev/null)"; up="${up#refs/heads/}"
        [ -n "$up" ] && is_main "$up" && { deny "push routed by push.default=upstream to protected branch '$up'"; return 2; }
        ;;
    esac

    # A configured remote.<remote>.push refspec applies even to a bare push.
    [ -n "$remote" ] || remote="$(git -C "$gdir" config "branch.$src.pushRemote" 2>/dev/null)"
    [ -n "$remote" ] || remote="$(git -C "$gdir" config remote.pushDefault 2>/dev/null)"
    [ -n "$remote" ] || remote="$(git -C "$gdir" config "branch.$src.remote" 2>/dev/null)"
    [ -n "$remote" ] || remote="origin"
    # Refspecs carry no spaces; word-splitting the config values is safe and keeps
    # the loop in THIS shell (a `... | while read` subshell could not deny).
    # shellcheck disable=SC2046
    for spec in $(git -C "$gdir" config --get-all "remote.$remote.push" 2>/dev/null); do
      br="$(refspec_dst "$spec" "$gdir")"
      is_main "$br" && { deny "push routed by remote.$remote.push to protected branch '$br'"; return 2; }
    done
    return 0
  elif [ -n "$xtarget" ]; then
    br="$xtarget"                                        # branch -f|-D|-M|-C named it
    is_main "$br" && { deny "$verb on protected branch '$br'"; return 2; }
  else
    br="$(current_branch "${cdir:-$cwd}")"
    [ -n "$br" ] || return 0
    is_main "$br" && { deny "$verb on protected branch '$br'"; return 2; }
  fi
  return 0
}

# Split the command on shell separators — single | & ; and subshell/brace
# ( ) { } (which also covers && and ||) — plus physical newlines, and judge each
# piece. This keeps a `git` verb hidden behind a pipe, background, subshell or
# brace group from slipping past. Best-effort: wrappers, command substitution
# and aliases can still hide a verb — fail open, documented.
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  evaluate_segment "$seg" || exit 2
done <<EOF
$(printf '%s\n' "$cmd" | awk '{gsub(/[|&;(){}]/,"\n")}1')
EOF

exit 0
