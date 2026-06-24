#!/bin/bash
# git-guard routing test runner.
#
# Companion to run.sh for cases that depend on a repo's PUSH CONFIGURATION
# (push.default, a branch's upstream, remote.<remote>.push, pushRemote). The
# simple cases.tsv harness can only set the checked-out branch; these cases need
# `git config` set per repo, so each is spelled out here.
#
# Like run.sh, the command under test is piped to the DEV script as JSON on stdin
# (never executed in this runner's shell), so the live PreToolUse hook never sees
# it and a temp repo can be configured to route a bare push onto `main`.
#
# Exit: 0 if every case matches its expected code, non-zero otherwise.

set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/git-guard.sh"

[ -f "$script" ] || { echo "FATAL: dev script not found: $script" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FATAL: git required" >&2; exit 1; }

pass=0; fail=0; total=0; tmpdirs=""

# Build a throwaway repo with one empty commit, checked out on $1. Echoes path.
mkrepo() {
  d=$(mktemp -d) || return 1
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name  t
  git -C "$d" commit -q --allow-empty -m x
  git -C "$d" branch -M "$1"
  printf '%s' "$d"
}

# run <id> <expect> <repo> <command>
run() {
  id="$1"; expect="$2"; repo="$3"; cmd="$4"
  total=$((total+1))
  json=$(MSG="$cmd" CWDV="$repo" jq -nc '{tool_name:"Bash",tool_input:{command:env.MSG},cwd:env.CWDV}')
  printf '%s' "$json" | bash "$script" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1)); printf 'PASS  %-34s expect=%s got=%s\n' "$id" "$expect" "$got"
  else
    fail=$((fail+1)); printf 'FAIL  %-34s expect=%s got=%s  cmd=%s\n' "$id" "$expect" "$got" "$cmd"
  fi
}

# --- BLOCK: push.default=upstream routes a bare push develop -> main ----------
r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" config push.default upstream
git -C "$r" config branch.develop.remote origin
git -C "$r" config branch.develop.merge  refs/heads/main
run upstream-routes-bare-to-main 2 "$r" "git push"

# --- BLOCK: same, with an explicit remote arg (`git push origin`) -------------
r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" remote add origin /tmp/git-guard-test-none.git
git -C "$r" config push.default upstream
git -C "$r" config branch.develop.remote origin
git -C "$r" config branch.develop.merge  refs/heads/main
run upstream-routes-remotearg-to-main 2 "$r" "git push origin"

# --- BLOCK: triangular pushRemote does not hide the upstream branch name ------
r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" config push.default upstream
git -C "$r" config branch.develop.pushRemote upstream
git -C "$r" config branch.develop.merge      refs/heads/main
run upstream-triangular-to-main 2 "$r" "git push"

# --- BLOCK: a configured remote.<remote>.push refspec targets main -----------
r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" remote add origin /tmp/git-guard-test-none.git
git -C "$r" config branch.develop.remote origin
git -C "$r" config remote.origin.push refs/heads/develop:refs/heads/main
run remote-push-refspec-to-main 2 "$r" "git push"

# --- ALLOW: push.default=upstream but upstream is the SAME name --------------
r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" config push.default upstream
git -C "$r" config branch.develop.remote origin
git -C "$r" config branch.develop.merge  refs/heads/develop
run upstream-same-name 0 "$r" "git push"

# --- ALLOW: push.default=simple, same-name upstream -------------------------
r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" config push.default simple
git -C "$r" config branch.develop.remote origin
git -C "$r" config branch.develop.merge  refs/heads/develop
run simple-same-name 0 "$r" "git push"

# --- ALLOW: push.default=simple with a MISMATCHED upstream ------------------
# git itself REFUSES this push (upstream name != current branch name), so it can
# never reach `main`; the guard must NOT block it.
r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" config push.default simple
git -C "$r" config branch.develop.remote origin
git -C "$r" config branch.develop.merge  refs/heads/main
run simple-mismatch-not-blocked 0 "$r" "git push"

# --- ALLOW: an explicit refspec OVERRIDES push.default routing --------------
r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" remote add origin /tmp/git-guard-test-none.git
git -C "$r" config push.default upstream
git -C "$r" config branch.develop.remote origin
git -C "$r" config branch.develop.merge  refs/heads/main
run explicit-refspec-overrides 0 "$r" "git push origin develop"

# Clean every temp repo.
for d in $tmpdirs; do rm -rf "$d"; done

echo "-----"
echo "git-guard routing: $pass/$total passed, $fail failed."
[ "$fail" -eq 0 ]
