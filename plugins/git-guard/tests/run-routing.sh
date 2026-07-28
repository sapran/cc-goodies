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
# Empty HOME so a real ~/.claude/git-guard.conf cannot perturb these cases.
fakehome=$(mktemp -d) || exit 1
trap 'rm -rf "$fakehome"' EXIT

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

# run <id> <expect> <repo> <command> [VAR=value …]
# Trailing VAR=value arguments are passed to the guard's environment, so a case
# can pin GIT_GUARD_LOCAL_WRITE_CHANNEL for that invocation only.
run() {
  id="$1"; expect="$2"; repo="$3"; cmd="$4"; shift 4
  total=$((total+1))
  json=$(MSG="$cmd" CWDV="$repo" jq -nc '{tool_name:"Bash",tool_input:{command:env.MSG},cwd:env.CWDV}')
  # Capture stdout: exit 0 no longer means only "allow" — it also means "ask,
  # object on stdout". Comparing exit codes alone would let a routine push that
  # spuriously started asking pass as a clean allow.
  out=$(printf '%s' "$json" | env -u GIT_GUARD_LOCAL_WRITE_CHANNEL -u GIT_GUARD_DISABLE \
    -u GIT_GUARD_BLOCK_ALL_PUSH -u GIT_GUARD_MAIN_BRANCHES HOME="$fakehome" "$@" \
    bash "$script" 2>/dev/null)
  got=$?
  case "$expect" in ask) exp=0 ;; *) exp="$expect" ;; esac
  ok=1
  if [ "$expect" = "ask" ]; then
    pd=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
    [ "$pd" = "ask" ] || ok=0
  else
    [ -z "$out" ] || ok=0
  fi
  if [ "$got" = "$exp" ] && [ "$ok" = 1 ]; then
    pass=$((pass+1)); printf 'PASS  %-34s expect=%s got=%s\n' "$id" "$expect" "$got"
  else
    fail=$((fail+1)); printf 'FAIL  %-34s expect=%s got=%s stdout_ok=%s  cmd=%s\n' "$id" "$expect" "$got" "$ok" "$cmd"
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

# --- BLOCK: config-routed pushes are NEVER routed onto the ask channel -------
# The destination-less cases are the sharpest argument for keeping push
# deny-only: the command text is just `git push`, so a human at an ask prompt
# would not even see which branch it lands on. GIT_GUARD_LOCAL_WRITE_CHANNEL=ask
# must not reach these.
r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" config push.default upstream
git -C "$r" config branch.develop.remote origin
git -C "$r" config branch.develop.merge  refs/heads/main
run ask-upstream-routes-bare-to-main 2 "$r" "git push" GIT_GUARD_LOCAL_WRITE_CHANNEL=ask

r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" remote add origin /tmp/git-guard-test-none.git
git -C "$r" config branch.develop.remote origin
git -C "$r" config remote.origin.push refs/heads/develop:refs/heads/main
run ask-remote-push-refspec-to-main 2 "$r" "git push" GIT_GUARD_LOCAL_WRITE_CHANNEL=ask

r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" config push.default upstream
git -C "$r" config branch.develop.pushRemote upstream
git -C "$r" config branch.develop.merge      refs/heads/main
run ask-upstream-triangular-to-main 2 "$r" "git push" GIT_GUARD_LOCAL_WRITE_CHANNEL=ask

# --- ALLOW: the channel setting does not widen routing either ----------------
r=$(mkrepo develop); tmpdirs="$tmpdirs $r"
git -C "$r" config push.default upstream
git -C "$r" config branch.develop.remote origin
git -C "$r" config branch.develop.merge  refs/heads/develop
run ask-upstream-same-name 0 "$r" "git push" GIT_GUARD_LOCAL_WRITE_CHANNEL=ask

# --- `git -C <dir>` resolves the branch in THAT repo, on both channels -------
# Belongs here, not in cases.tsv: the guard resolves `-C` against the path in
# the command, and only this harness knows the temp repo's absolute path. A
# `git -C .` row would resolve against the tests directory and pass for the
# wrong reason.
prot=$(mkrepo main);    tmpdirs="$tmpdirs $prot"
feat=$(mkrepo feature); tmpdirs="$tmpdirs $feat"
run dashC-localwrite-to-main      2   "$feat" "git -C $prot commit -m x"
run ask-dashC-localwrite-to-main  ask "$feat" "git -C $prot commit -m x" GIT_GUARD_LOCAL_WRITE_CHANNEL=ask
run dashC-push-to-main            2   "$feat" "git -C $prot push origin main" GIT_GUARD_LOCAL_WRITE_CHANNEL=ask

# --- a custom protected list reaches the ask reason too ----------------------
rel=$(mkrepo release); tmpdirs="$tmpdirs $rel"
run ask-custom-main-branches ask "$rel" "git commit -m x" GIT_GUARD_MAIN_BRANCHES=release GIT_GUARD_LOCAL_WRITE_CHANNEL=ask

# Clean every temp repo.
for d in $tmpdirs; do rm -rf "$d"; done

echo "-----"
echo "git-guard routing: $pass/$total passed, $fail failed."
[ "$fail" -eq 0 ]
