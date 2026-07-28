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
# THREE expected outcomes (the `expect` column), stdout and stderr captured
# separately because each channel must be checked on BOTH streams:
#   expect=0    (allow): exit 0, and empty stdout — an allow must not leak JSON.
#   expect=2    (deny):  exit 2, the reason on STDERR, and empty stdout — the
#                        deny channel never emits JSON.
#   expect=ask  (ask):   exit 0 (same code as allow — only the token differs),
#                        empty STDERR, and a
#                        hookSpecificOutput.permissionDecision=="ask" object on
#                        STDOUT whose permissionDecisionReason carries the same
#                        message substance a deny would have printed.
# Every deny/ask case, regardless of channel, must carry the protected-branch
# list, a variants clause, the `! $cmd` escape hatch, and the disable pointer;
# a representative subset also has its exact reason phrase asserted.
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

# Reason-phrase lookup for a representative subset of case IDs — confirms the
# *existing* reason text (branch name / verb) is unchanged by the new variants
# line (task 3.3). IDs not listed here still get the generic assertions below.
reason_for() {
  case "$1" in
    commit-on-main)        printf '%s' "commit on protected branch 'main'" ;;
    merge-on-main)         printf '%s' "merge on protected branch 'main'" ;;
    push-origin-main)      printf '%s' "push to protected branch 'main'" ;;
    push-bare-on-main)     printf '%s' "push to protected branch 'main'" ;;
    push-multi-includes-main) printf '%s' "push to protected branch 'main'" ;;
    branch-D-main)         printf '%s' "branch on protected branch 'main'" ;;
    branch-f-main)         printf '%s' "branch on protected branch 'main'" ;;
    push-all)              printf '%s' "push --all/--mirror (touches protected branches)" ;;
    push-mirror)           printf '%s' "push --all/--mirror (touches protected branches)" ;;
    blockall-push-feature) printf '%s' "push (GIT_GUARD_BLOCK_ALL_PUSH is set)" ;;
    am-on-main)            printf '%s' "am on protected branch 'main'" ;;
    # Ask-channel cases carry the SAME reason substance as their deny twins —
    # the two channels differ only in delivery mechanism.
    ask-commit-on-main)    printf '%s' "commit on protected branch 'main'" ;;
    ask-merge-on-main)     printf '%s' "merge on protected branch 'main'" ;;
    ask-am-on-main)        printf '%s' "am on protected branch 'main'" ;;
    ask-reset-hard-on-main) printf '%s' "reset on protected branch 'main'" ;;
    ask-commit-on-master)  printf '%s' "commit on protected branch 'master'" ;;
    ask-push-origin-main)  printf '%s' "push to protected branch 'main'" ;;
    ask-branch-f-main)     printf '%s' "branch on protected branch 'main'" ;;
    ask-blockall-push-feature) printf '%s' "push (GIT_GUARD_BLOCK_ALL_PUSH is set)" ;;
  esac
}

# Clause checks shared by BOTH channels — $1 is the human-visible text for the
# channel under test (stderr for a deny, the parsed permissionDecisionReason for
# an ask), $2 the command, $3 the variants wording that channel must use.
# Sets msg_ok/msg_detail in the caller's scope.
#
# $3 is passed per channel rather than accepting either wording: deny() says
# variants "are blocked too" and ask() says they "are judged the same way" —
# each accurate for its own channel. Accepting either here would let a deny
# regress into the ask wording (or the reverse) without failing.
check_common_clauses() {
  ctext="$1"; ccmd="$2"; cvariants="$3"
  case "$ctext" in *"! $ccmd"*) ;; *) msg_ok=0; msg_detail="$msg_detail no-escape-hatch-line" ;; esac
  case "$ctext" in *"Protected: main master."*) ;; *) msg_ok=0; msg_detail="$msg_detail no-protected-list" ;; esac
  case "$ctext" in *"GIT_GUARD_DISABLE=1"*) ;; *) msg_ok=0; msg_detail="$msg_detail no-disable-pointer" ;; esac
  case "$ctext" in *"$cvariants"*) ;; *) msg_ok=0; msg_detail="$msg_detail no-variants-clause[want:$cvariants]" ;; esac
  rp=$(reason_for "$id")
  if [ -n "$rp" ]; then
    case "$ctext" in *"$rp"*) ;; *) msg_ok=0; msg_detail="$msg_detail unexpected-reason[want:$rp]" ;; esac
  fi
}

pass=0; fail=0; total=0
tmpdirs=""
outfile=$(mktemp) || exit 1
errfile=$(mktemp) || exit 1
fakehome=$(mktemp -d) || exit 1
trap 'rm -f "$outfile" "$errfile"; rm -rf "$fakehome"' EXIT

# IFS=tab so columns split on TAB only; the command column keeps its spaces.
tab=$(printf '\t')
while IFS="$tab" read -r id branch expect command; do
  case "$id" in ''|\#*) continue ;; esac          # skip blanks + comments
  total=$((total+1))
  # A row whose columns were separated by SPACES instead of tabs lands entirely
  # in $id, leaving $command empty. Fail loudly: silently skipping it would let
  # a case vanish from the suite while the summary still reported all-passed.
  if [ -z "${command:-}" ]; then
    fail=$((fail+1))
    printf 'FAIL  %-26s malformed row (need 4 TAB-separated columns)\n' "$id"
    continue
  fi

  # A leading GIT_GUARD_*=value belongs to the guard's ENVIRONMENT (the hook
  # reads it from env, not from the command text) — strip it off and export it
  # for this invocation only. Any other VAR=val prefix (e.g. FOO=bar) is part of
  # the command under test and stays in the string.
  # Loops, so a case may set SEVERAL guard vars (e.g. BLOCK_ALL_PUSH together
  # with LOCAL_WRITE_CHANNEL, to prove one cannot override the other). Values
  # must not contain spaces — the split is on the first space.
  envassigns=""
  cmd="$command"
  while :; do
    case "$cmd" in
      GIT_GUARD_*=*\ *) envassigns="$envassigns ${cmd%% *}"; cmd="${cmd#* }" ;;
      *) break ;;
    esac
  done

  repo=$(make_repo "$branch") || { echo "FAIL  $id  (could not make repo)"; fail=$((fail+1)); continue; }
  tmpdirs="$tmpdirs $repo"

  json=$(MSG="$cmd" CWDV="$repo" jq -nc '{tool_name:"Bash",tool_input:{command:env.MSG},cwd:env.CWDV}')

  # Capture stdout and stderr into SEPARATE files — each channel is checked on
  # both streams (a deny must not leak JSON to stdout; an ask must not leak its
  # reason to stderr). HOME points at an empty dir so a real
  # ~/.claude/git-guard.conf on the developer's machine cannot perturb the
  # fail-closed default cases.
  # -u clears any GIT_GUARD_* the developer running the suite has exported.
  # Without it an ambient GIT_GUARD_BLOCK_ALL_PUSH=1 would make every push-deny
  # row pass for the WRONG reason, hiding the whole refspec-resolution arm.
  # shellcheck disable=SC2086
  printf '%s' "$json" | env -u GIT_GUARD_LOCAL_WRITE_CHANNEL -u GIT_GUARD_DISABLE \
    -u GIT_GUARD_BLOCK_ALL_PUSH -u GIT_GUARD_MAIN_BRANCHES \
    HOME="$fakehome" $envassigns bash "$script" >"$outfile" 2>"$errfile"
  got=$?
  out=$(cat "$outfile")
  err=$(cat "$errfile")

  # `ask` cases exit 0, same as a plain allow — only the expect TOKEN differs
  # from the numeric code compared against $got.
  case "$expect" in ask) exp_code=0 ;; *) exp_code="$expect" ;; esac

  msg_ok=1; msg_detail=""
  case "$expect" in
    2)
      if [ "$got" = "2" ]; then
        check_common_clauses "$err" "$cmd" "are blocked too"
        case "$out" in "") ;; *) msg_ok=0; msg_detail="$msg_detail unexpected-stdout-json" ;; esac
      fi
      ;;
    ask)
      if [ "$got" = "0" ]; then
        case "$err" in "") ;; *) msg_ok=0; msg_detail="$msg_detail unexpected-stderr" ;; esac
        # Exactly ONE decision object: a doubled emit would still parse as
        # "ask" field-wise, so count objects explicitly rather than relying on
        # the string compare below to notice.
        nobj=$(printf '%s' "$out" | jq -s 'length' 2>/dev/null)
        case "$nobj" in 1) ;; *) msg_ok=0; msg_detail="$msg_detail object-count[$nobj]" ;; esac
        pd=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
        reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
        # hookEventName is what makes this a ROUTABLE PreToolUse decision. Drop
        # it and the harness ignores the object — exit 0 then reads as a plain
        # allow, i.e. a silent fail-open that every other assertion here misses.
        hen=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)
        case "$hen" in PreToolUse) ;; *) msg_ok=0; msg_detail="$msg_detail bad-hookEventName[$hen]" ;; esac
        case "$pd" in ask) ;; *) msg_ok=0; msg_detail="$msg_detail bad-permissionDecision[$pd]" ;; esac
        check_common_clauses "$reason" "$cmd" "are judged the same way"
      fi
      ;;
    0)
      case "$out" in "") ;; *) msg_ok=0; msg_detail="$msg_detail unexpected-stdout-json" ;; esac
      # An allow must be silent on BOTH streams — a guard message printed while
      # still returning 0 would spam the transcript on every ordinary command.
      case "$err" in "") ;; *) msg_ok=0; msg_detail="$msg_detail unexpected-stderr" ;; esac
      ;;
  esac

  if [ "$got" = "$exp_code" ] && [ "$msg_ok" = 1 ]; then
    pass=$((pass+1))
    printf 'PASS  %-26s [%s] expect=%s got=%s\n' "$id" "$branch" "$expect" "$got"
  else
    fail=$((fail+1))
    printf 'FAIL  %-26s [%s] expect=%s got=%s msg_ok=%s%s  cmd=%s\n' "$id" "$branch" "$expect" "$got" "$msg_ok" "$msg_detail" "$cmd"
  fi
done < "$cases"

# --- jq-missing fail-open, under BOTH channel values -------------------------
# Not expressible as a cases.tsv row: it needs the guard's PATH emptied, not a
# different command. The guard must warn and ALLOW, and the channel setting must
# not change that — the jq probe runs before any channel logic is reached.
nojq_repo=$(make_repo main) && tmpdirs="$tmpdirs $nojq_repo"
nojq_json=$(MSG="git commit -m x" CWDV="$nojq_repo" jq -nc \
  '{tool_name:"Bash",tool_input:{command:env.MSG},cwd:env.CWDV}')
# bash must be invoked by ABSOLUTE path: `env PATH=<empty> bash …` would look
# bash itself up in the emptied PATH and die 127 before the guard ever runs.
bashbin=$(command -v bash)
emptydir=$(mktemp -d) && tmpdirs="$tmpdirs $emptydir"
for chan in unset ask; do
  total=$((total+1))
  if [ "$chan" = "unset" ]; then
    printf '%s' "$nojq_json" | env PATH="$emptydir" HOME="$fakehome" \
      "$bashbin" "$script" >"$outfile" 2>"$errfile"
  else
    printf '%s' "$nojq_json" | env PATH="$emptydir" HOME="$fakehome" \
      GIT_GUARD_LOCAL_WRITE_CHANNEL="$chan" "$bashbin" "$script" >"$outfile" 2>"$errfile"
  fi
  got=$?
  out=$(cat "$outfile")
  if [ "$got" = "0" ] && [ -z "$out" ]; then
    pass=$((pass+1))
    printf 'PASS  %-26s [%s] expect=0 got=%s\n' "nojq-failopen-$chan" "main" "$got"
  else
    fail=$((fail+1))
    printf 'FAIL  %-26s [%s] expect=0 got=%s stdout=%s\n' "nojq-failopen-$chan" "main" "$got" "$out"
  fi
done

# --- the CONF-FILE channel path ---------------------------------------------
# Every TSV row sets the channel through the ENVIRONMENT, but `/git-guard`
# configures this feature by writing ~/.claude/git-guard.conf — so without these
# cases the suite proves the feature works via a path no user takes, and a key
# name drifting between commands/git-guard.md and this script would pass
# everything while the documented path silently did nothing.
conf_repo=$(make_repo main) && tmpdirs="$tmpdirs $conf_repo"
conf_json=$(MSG="git commit -m x" CWDV="$conf_repo" jq -nc \
  '{tool_name:"Bash",tool_input:{command:env.MSG},cwd:env.CWDV}')
mkdir -p "$fakehome/.claude"

# conf_case <id> <conf-line> <expect 0|2|ask> [VAR=value]
conf_case() {
  cid="$1"; cline="$2"; cexpect="$3"; cenv="${4:-}"
  total=$((total+1))
  printf '%s\n' "$cline" > "$fakehome/.claude/git-guard.conf"
  # shellcheck disable=SC2086
  printf '%s' "$conf_json" | env -u GIT_GUARD_LOCAL_WRITE_CHANNEL HOME="$fakehome" \
    $cenv bash "$script" >"$outfile" 2>"$errfile"
  cgot=$?
  cout=$(cat "$outfile")
  case "$cexpect" in ask) cexp=0 ;; *) cexp="$cexpect" ;; esac
  cok=1
  if [ "$cexpect" = "ask" ]; then
    cpd=$(printf '%s' "$cout" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
    [ "$cpd" = "ask" ] || cok=0
  else
    [ -z "$cout" ] || cok=0
  fi
  if [ "$cgot" = "$cexp" ] && [ "$cok" = 1 ]; then
    pass=$((pass+1))
    printf 'PASS  %-26s [conf] expect=%s got=%s\n' "$cid" "$cexpect" "$cgot"
  else
    fail=$((fail+1))
    printf 'FAIL  %-26s [conf] expect=%s got=%s json_ok=%s line=%s\n' "$cid" "$cexpect" "$cgot" "$cok" "$cline"
  fi
}

conf_case conf-ask             'GIT_GUARD_LOCAL_WRITE_CHANNEL=ask'   ask
conf_case conf-ask-quoted      'GIT_GUARD_LOCAL_WRITE_CHANNEL="ask"' ask
conf_case conf-ask-spaced      'GIT_GUARD_LOCAL_WRITE_CHANNEL = ask' ask
conf_case conf-upper-denies    'GIT_GUARD_LOCAL_WRITE_CHANNEL=ASK'   2
conf_case conf-commented-out   '#GIT_GUARD_LOCAL_WRITE_CHANNEL=ask'  2
# Documents current behaviour: conf_get does not strip a trailing comment, so
# the value becomes "ask # …" and fails closed. Fail-closed is the safe
# direction; pinned here so the choice is deliberate rather than accidental.
conf_case conf-trailing-note   'GIT_GUARD_LOCAL_WRITE_CHANNEL=ask # local commits ok' 2
conf_case conf-env-beats-conf  'GIT_GUARD_LOCAL_WRITE_CHANNEL=ask'   2 GIT_GUARD_LOCAL_WRITE_CHANNEL=deny
rm -f "$fakehome/.claude/git-guard.conf"

# --- a failed ask DELIVERY must fall back to deny, never to allow ------------
# jq is present (the guard exits without it), but the emit CALL can still fail —
# --arg carries the whole command into argv, so a large tool call hits E2BIG.
# Before the fallback existed, that produced exit 0 with no JSON: a silent
# allow. Simulated with a jq shim that fails only for the `-n` emit form.
askfail_bin=$(mktemp -d) && tmpdirs="$tmpdirs $askfail_bin"
realjq=$(command -v jq)
{
  printf '%s\n' '#!/bin/bash'
  # Deliberately unexpanded — this is the shim's source, not this shell's code.
  # shellcheck disable=SC2016
  printf '%s\n' '[ "${1:-}" = "-n" ] && exit 1'
  printf 'exec %s "$@"\n' "$realjq"
} > "$askfail_bin/jq"
chmod +x "$askfail_bin/jq"
total=$((total+1))
printf '%s' "$conf_json" | env PATH="$askfail_bin:$PATH" HOME="$fakehome" \
  GIT_GUARD_LOCAL_WRITE_CHANNEL=ask bash "$script" >"$outfile" 2>"$errfile"
afgot=$?
afout=$(cat "$outfile"); aferr=$(cat "$errfile")
afok=1
[ -z "$afout" ] || afok=0
case "$aferr" in *"⛔ git-guard: blocked"*) ;; *) afok=0 ;; esac
if [ "$afgot" = "2" ] && [ "$afok" = 1 ]; then
  pass=$((pass+1))
  printf 'PASS  %-26s expect=2 got=%s\n' "askfail-falls-back-deny" "$afgot"
else
  fail=$((fail+1))
  printf 'FAIL  %-26s expect=2 got=%s stdout=%s\n' "askfail-falls-back-deny" "$afgot" "$afout"
fi

# Clean every temp repo.
for d in $tmpdirs; do rm -rf "$d"; done

echo "-----"
echo "git-guard: $pass/$total passed, $fail failed."
[ "$fail" -eq 0 ]
