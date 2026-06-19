#!/bin/bash
# git-guard test runner.
#
# Drives the DEV script (plugins/git-guard/scripts/git-guard.sh) directly: for
# each case it builds a throwaway git repo checked out on the case's branch,
# synthesises the PreToolUse tool-call JSON (command read from an env var, never
# a command line), pipes it to the dev script as a SUBPROCESS, and asserts the
# exit code. Running the dev script as a subprocess means the LIVE PreToolUse
# hook never sees these commands — so a temp repo can sit on `main` and we can
# feed it `git push origin main` without self-blocking.
#
# Cases live in cases.tsv (id <TAB> branch <TAB> expect <TAB> command), written
# with the editor (not a Bash call), so dangerous literals never hit a shell.
#
# Exit: 0 if every case matches its expected code, non-zero otherwise.

set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/git-guard.sh"
cases="$here/cases.tsv"

[ -f "$script" ] || { echo "FATAL: dev script not found: $script" >&2; exit 1; }
[ -f "$cases" ]  || { echo "FATAL: cases file not found: $cases" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FATAL: git required" >&2; exit 1; }

# Build a throwaway repo with one empty commit, checked out on $1. Echoes path.
make_repo() {
  d=$(mktemp -d) || return 1
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name  t
  git -C "$d" commit -q --allow-empty -m x
  # Force-rename the initial branch to the target — silent and default-name
  # agnostic (git init may start on `main` or `master`), unlike `checkout -b`
  # which errors when the target already matches the default.
  git -C "$d" branch -M "$1"
  printf '%s' "$d"
}

pass=0; fail=0; total=0
tmpdirs=""

# IFS=tab so columns split on TAB only; the command column keeps its spaces.
tab=$(printf '\t')
while IFS="$tab" read -r id branch expect command; do
  case "$id" in ''|\#*) continue ;; esac          # skip blanks + comments
  [ -n "${command:-}" ] || continue
  total=$((total+1))

  # A leading GIT_GUARD_*=value belongs to the guard's ENVIRONMENT (the hook
  # reads it from env, not from the command text) — strip it off and export it
  # for this invocation only. Any other VAR=val prefix (e.g. FOO=bar) is part of
  # the command under test and stays in the string.
  envassign=""
  cmd="$command"
  case "$cmd" in
    GIT_GUARD_*=*\ *) envassign="${cmd%% *}"; cmd="${cmd#* }" ;;
  esac

  repo=$(make_repo "$branch") || { echo "FAIL  $id  (could not make repo)"; fail=$((fail+1)); continue; }
  tmpdirs="$tmpdirs $repo"

  json=$(MSG="$cmd" CWDV="$repo" jq -nc '{tool_name:"Bash",tool_input:{command:env.MSG},cwd:env.CWDV}')

  if [ -n "$envassign" ]; then
    key="${envassign%%=*}"; val="${envassign#*=}"
    printf '%s' "$json" | env "$key=$val" bash "$script" >/dev/null 2>&1
  else
    printf '%s' "$json" | bash "$script" >/dev/null 2>&1
  fi
  got=$?

  if [ "$got" = "$expect" ]; then
    pass=$((pass+1))
    printf 'PASS  %-26s [%s] expect=%s got=%s\n' "$id" "$branch" "$expect" "$got"
  else
    fail=$((fail+1))
    printf 'FAIL  %-26s [%s] expect=%s got=%s  cmd=%s\n' "$id" "$branch" "$expect" "$got" "$cmd"
  fi
done < "$cases"

# Clean every temp repo.
for d in $tmpdirs; do rm -rf "$d"; done

echo "-----"
echo "git-guard: $pass/$total passed, $fail failed."
[ "$fail" -eq 0 ]
