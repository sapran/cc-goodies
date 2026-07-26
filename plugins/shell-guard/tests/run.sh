#!/bin/bash
# cc-goodies / shell-guard — direct-drive test runner.
#
# Drives the DEV script directly (never the live PreToolUse hook): builds the
# synthetic tool-call JSON with `jq -n`, reading the command from an ENV VAR so a
# dangerous literal never lands on a Bash command line — it lives only in
# cases.tsv, read at runtime. The dev script runs as a SUBPROCESS, which the live
# hook never sees, so testing `rm -rf /` here cannot self-block. Captures stdout
# and stderr SEPARATELY (never merged) and asserts, per case:
#   expect=0   (allow):  exit 0, empty stdout, no permissionDecision JSON leaked.
#   expect=2   (deny):   exit 2, the axis-1 (design.md) message on STDERR, and
#                        empty stdout — the deny channel never emits JSON.
#   expect=ask (ask):    exit 0, empty stderr, and a
#                        hookSpecificOutput.permissionDecision=="ask" JSON object
#                        on STDOUT carrying the SAME axis-1 message contract in
#                        permissionDecisionReason (guard-ask-escalation, AXIS 2 —
#                        composes with, does not replace, AXIS 1's class framing).
# The axis-1 class framing: `alternative: none` keeps the IRREVERSIBLE line and
# offers no alternative, `alternative: named` drops it and names a specific safe
# alternative, the EXTRA arm stays neutral (neither line) but names the matched
# pattern — plus the variants-also-{blocked} clause and the `! $cmd` escape
# hatch, present on every deny/ask case regardless of channel.
#
# cases.tsv rows are SPACE-separated leading tokens; the command takes the rest:
#   <id> <expect 0|2|ask> <cwd: - | HOME> <command …>
# `read -r id expect cwd command` keeps the command's own spaces (the last
# variable gets the remainder of the line) and needs no tabs — robust across the
# BSD/macOS tools this repo targets (an earlier awk `\0` split silently read zero
# rows under BSD awk).
#
# A leading `SHELL_GUARD_EXTRA_PATTERNS=value` in the command column belongs to
# the guard's ENVIRONMENT (read via the env var, not the command text) — it is
# stripped and exported for that one case only, mirroring git-guard's run.sh.
#
# A literal `\n` (backslash-n, two characters) anywhere in the command column
# is converted to a real embedded newline just before the JSON is built — the
# only way a line-oriented cases.tsv can express a command that genuinely
# spans physical lines (e.g. a fetch split from its `eval` by a line break).
#
# Usage: bash plugins/shell-guard/tests/run.sh   (exits non-zero on any failure)

set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/shell-guard.sh"
cases="$here/cases.tsv"

[ -f "$script" ] || { echo "FATAL: dev script not found: $script" >&2; exit 1; }
[ -f "$cases" ]  || { echo "FATAL: cases file not found: $cases" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

outfile=$(mktemp) || { echo "FATAL: mktemp failed" >&2; exit 1; }
errfile=$(mktemp) || { echo "FATAL: mktemp failed" >&2; exit 1; }
trap 'rm -f "$outfile" "$errfile"' EXIT

# --- Message-content assertion tables (axis 1, design.md) -------------------
# Membership is by AXIS-1 CLASS, independent of AXIS-2 channel (deny vs ask) —
# the same id lookup applies whether the case's expect is 2 or ask; only which
# captured stream (stderr vs the parsed JSON reason) the checks run against
# differs. IDs not listed in either set get no class assertion (ALLOW cases
# produce no reason text; the EXTRA-arm case `extra_pattern` is asserted
# separately below since it is neither class — see the "A pattern of unknown
# severity" spec requirement).
none_ids=" rm_root rm_tilde rm_home rm_nopreserve rm_fr_usr rm_r_force_etc rm_glob_home dd_disk2 redirect_disk0 mkfs_sda wipefs_sdb diskutil_erase reboot shutdown forkbomb timeout_rm env_rm nice_rm compound_rm pipe_rm subshell_rm ask_deny_chmod_rm ask_deny_trunc_mkfs ask_deny_sudo_rm deny_ask_rm_chmod deny_ask_mkfs_sudo "
named_ids=" sudo_rm sudo_apt doas_reboot eval_curl eval_plain chmod_777 chmod_R_0777 trunc_colon curl_bash wget_sh ask_ask_first_wins ask_only_no_deny eval_split_semi eval_split_andand eval_split_newline eval_multiline_paren eval_var_indirect eval_fetch_then_cat eval_curling_benign eval_wgettable_benign eval_upper_curl "

# The specific safe-alternative substring each `alternative: named` id must
# carry — one entry per arm (sudo/doas share the privilege-escalation arm but
# name their own matched prefix; eval_curl and eval_plain share eval's wording
# regardless of which channel — deny vs ask — their download-word check picks).
alt_substring() {
  case "$1" in
    sudo_rm|sudo_apt|ask_ask_first_wins|ask_only_no_deny)
                              printf '%s' "without \`sudo\`" ;;
    doas_reboot)              printf '%s' "without \`doas\`" ;;
    eval_curl|eval_plain|eval_split_semi|eval_split_andand|eval_split_newline|eval_multiline_paren|eval_var_indirect|eval_fetch_then_cat|eval_curling_benign|eval_wgettable_benign|eval_upper_curl)
                              printf '%s' "without the eval indirection" ;;
    chmod_777|chmod_R_0777)   printf '%s' "chmod 755" ;;
    trunc_colon)              printf '%s' "printf '' >" ;;
    curl_bash|wget_sh)        printf '%s' "download to a file" ;;
  esac
}

# Run the axis-1 class checks (IRREVERSIBLE / Safe alternative / EXTRA-pattern
# framing, per design.md) against $2, the text captured for THIS case's
# channel (stderr for a deny, the parsed permissionDecisionReason for an ask).
# Mutates the caller's msg_ok/msg_detail — matches this script's existing
# no-`local` convention (see CLAUDE.md's bash-3.2 note).
check_axis1() {
  cid="$1"; ctext="$2"
  case "$none_ids" in
    *" $cid "*)
      case "$ctext" in *"IRREVERSIBLE"*) ;; *) msg_ok=0; msg_detail="$msg_detail missing-IRREVERSIBLE"; esac
      case "$ctext" in *"Safe alternative"*) msg_ok=0; msg_detail="$msg_detail unexpected-Safe-alternative" ;; esac
      ;;
  esac
  case "$named_ids" in
    *" $cid "*)
      case "$ctext" in *"IRREVERSIBLE"*) msg_ok=0; msg_detail="$msg_detail unexpected-IRREVERSIBLE" ;; esac
      case "$ctext" in *"Safe alternative"*) ;; *) msg_ok=0; msg_detail="$msg_detail missing-Safe-alternative" ;; esac
      sub=$(alt_substring "$cid")
      if [ -n "$sub" ]; then
        case "$ctext" in *"$sub"*) ;; *) msg_ok=0; msg_detail="$msg_detail missing-alt-substring[$sub]" ;; esac
      fi
      ;;
  esac
  if [ "$cid" = "extra_pattern" ]; then
    case "$ctext" in *"IRREVERSIBLE"*) msg_ok=0; msg_detail="$msg_detail unexpected-IRREVERSIBLE" ;; esac
    case "$ctext" in *"Safe alternative"*) msg_ok=0; msg_detail="$msg_detail unexpected-Safe-alternative" ;; esac
    case "$ctext" in *"ZZZ_TEST_PATTERN_ZZZ"*) ;; *) msg_ok=0; msg_detail="$msg_detail missing-matched-pattern" ;; esac
  fi
}

# Escape hatch + variants clause, shared verbatim by deny() and ask() — checked
# against $2, the same per-channel text check_axis1 above uses.
check_common_clauses() {
  ctext="$1"; ccmd="$2"
  case "$ctext" in *"! $ccmd"*) ;; *) msg_ok=0; msg_detail="$msg_detail no-escape-hatch-line"; esac
  case "$ctext" in *"are blocked too"*) ;; *) msg_ok=0; msg_detail="$msg_detail no-variants-clause"; esac
}

pass=0; fail=0; total=0
while read -r id expect cwd command; do
  case "$id" in ''|\#*) continue ;; esac           # skip blanks + comments
  [ -n "${command:-}" ] || continue
  total=$((total+1))

  # cwd sentinel: HOME selects the session-in-home glob-all case; - means none.
  case "$cwd" in HOME) cwdv="$HOME" ;; *) cwdv="" ;; esac

  # A leading SHELL_GUARD_EXTRA_PATTERNS=value belongs to the guard's
  # ENVIRONMENT (the hook reads it from env, not from the command text) —
  # strip it off and export it for this invocation only.
  envassign=""
  cmd="$command"
  case "$cmd" in
    SHELL_GUARD_EXTRA_PATTERNS=*\ *) envassign="${cmd%% *}"; cmd="${cmd#* }" ;;
  esac

  # cases.tsv is line-oriented (one case per physical line), so a case that
  # needs to test a REAL embedded newline in the command (e.g. a fetch split
  # from its `eval` across a line break) can't just put one in the row. A
  # literal two-char `\n` in the command column is converted to an actual
  # newline here, right before the JSON is built — the guard script itself
  # only ever sees a real newline, same as it would from a live multi-line
  # Bash tool call.
  cmd="${cmd//\\n/$'\n'}"

  json=$(MSG="$cmd" CWDV="$cwdv" jq -nc \
    '{tool_name:"Bash",tool_input:{command:env.MSG},cwd:env.CWDV}')

  # Capture stdout and stderr into SEPARATE files — every channel (allow, deny,
  # ask) now needs both streams checked (deny must NOT leak JSON to stdout, ask
  # must NOT leak its reason to stderr), not just stderr as before.
  if [ -n "$envassign" ]; then
    key="${envassign%%=*}"; val="${envassign#*=}"
    printf '%s' "$json" | env "$key=$val" bash "$script" >"$outfile" 2>"$errfile"
  else
    printf '%s' "$json" | bash "$script" >"$outfile" 2>"$errfile"
  fi
  got=$?
  out=$(cat "$outfile")
  err=$(cat "$errfile")

  # `ask` cases exit 0, same as plain allow — only the expect TOKEN differs
  # from the numeric code compared against $got.
  case "$expect" in ask) exp_code=0 ;; *) exp_code="$expect" ;; esac

  msg_ok=1; msg_detail=""
  case "$expect" in
    2)
      if [ "$got" = "2" ]; then
        check_common_clauses "$err" "$cmd"
        check_axis1 "$id" "$err"
        case "$out" in "") ;; *) msg_ok=0; msg_detail="$msg_detail unexpected-stdout-json"; esac
      fi
      ;;
    ask)
      if [ "$got" = "0" ]; then
        case "$err" in "") ;; *) msg_ok=0; msg_detail="$msg_detail unexpected-stderr"; esac
        pd=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
        reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
        case "$pd" in ask) ;; *) msg_ok=0; msg_detail="$msg_detail bad-permissionDecision[$pd]"; esac
        check_common_clauses "$reason" "$cmd"
        check_axis1 "$id" "$reason"
      fi
      ;;
    0)
      case "$out" in "") ;; *) msg_ok=0; msg_detail="$msg_detail unexpected-stdout-json"; esac
      ;;
  esac

  if [ "$got" = "$exp_code" ] && [ "$msg_ok" = 1 ]; then
    pass=$((pass+1))
    printf 'PASS  %-18s expect=%s got=%s\n' "$id" "$expect" "$got"
  else
    fail=$((fail+1))
    printf 'FAIL  %-18s expect=%s got=%s msg_ok=%s%s  cmd=%s\n' "$id" "$expect" "$got" "$msg_ok" "$msg_detail" "$command"
  fi
done < "$cases"

echo "-----"
echo "shell-guard: $pass/$total passed, $fail failed."
[ "$fail" -eq 0 ]
