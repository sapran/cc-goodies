#!/bin/bash
# cc-goodies / shell-guard — direct-drive test runner.
#
# Drives the DEV script directly (never the live PreToolUse hook): builds the
# synthetic tool-call JSON with `jq -n`, reading the command from an ENV VAR so a
# dangerous literal never lands on a Bash command line — it lives only in
# cases.tsv, read at runtime. The dev script runs as a SUBPROCESS, which the live
# hook never sees, so testing `rm -rf /` here cannot self-block. Asserts the
# captured exit code (0 = allow, 2 = block) AND, for blocking cases, the stderr
# message content: the axis-1 (design.md) class framing — `alternative: none`
# keeps the IRREVERSIBLE line and offers no alternative, `alternative: named`
# drops it and names a specific safe alternative, the EXTRA arm stays neutral
# (neither line) but names the matched pattern — plus the variants-also-blocked
# clause and the `! $cmd` escape hatch, present on every blocking case.
#
# cases.tsv rows are SPACE-separated leading tokens; the command takes the rest:
#   <id> <expect 0|2> <cwd: - | HOME> <command …>
# `read -r id expect cwd command` keeps the command's own spaces (the last
# variable gets the remainder of the line) and needs no tabs — robust across the
# BSD/macOS tools this repo targets (an earlier awk `\0` split silently read zero
# rows under BSD awk).
#
# A leading `SHELL_GUARD_EXTRA_PATTERNS=value` in the command column belongs to
# the guard's ENVIRONMENT (read via the env var, not the command text) — it is
# stripped and exported for that one case only, mirroring git-guard's run.sh.
#
# Usage: bash plugins/shell-guard/tests/run.sh   (exits non-zero on any failure)

set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/shell-guard.sh"
cases="$here/cases.tsv"

[ -f "$script" ] || { echo "FATAL: dev script not found: $script" >&2; exit 1; }
[ -f "$cases" ]  || { echo "FATAL: cases file not found: $cases" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

# --- Message-content assertion tables (axis 1, design.md) -------------------
# IDs not listed in either set get no class assertion (ALLOW cases produce no
# deny message; the EXTRA-arm case `extra_pattern` is asserted separately below
# since it is neither class — see the "A pattern of unknown severity" spec
# requirement).
none_ids=" rm_root rm_tilde rm_home rm_nopreserve rm_fr_usr rm_r_force_etc rm_glob_home dd_disk2 redirect_disk0 mkfs_sda wipefs_sdb diskutil_erase reboot shutdown forkbomb timeout_rm env_rm nice_rm compound_rm pipe_rm subshell_rm "
named_ids=" sudo_rm sudo_apt doas_reboot eval_curl chmod_777 chmod_R_0777 trunc_colon curl_bash wget_sh "

# The specific safe-alternative substring each `alternative: named` id must
# carry — one entry per arm (sudo/doas share the privilege-escalation arm but
# name their own matched prefix).
alt_substring() {
  case "$1" in
    sudo_rm|sudo_apt)       printf '%s' "without \`sudo\`" ;;
    doas_reboot)            printf '%s' "without \`doas\`" ;;
    eval_curl)               printf '%s' "without the eval indirection" ;;
    chmod_777|chmod_R_0777)  printf '%s' "chmod 755" ;;
    trunc_colon)              printf '%s' "printf '' >" ;;
    curl_bash|wget_sh)        printf '%s' "download to a file" ;;
  esac
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

  json=$(MSG="$cmd" CWDV="$cwdv" jq -nc \
    '{tool_name:"Bash",tool_input:{command:env.MSG},cwd:env.CWDV}')

  # Capture stderr only (stdout discarded) so message-content assertions can
  # run against it; `2>&1 >/dev/null` duplicates stderr to the substitution
  # BEFORE redirecting stdout away, the standard stderr-only capture idiom.
  if [ -n "$envassign" ]; then
    key="${envassign%%=*}"; val="${envassign#*=}"
    err=$(printf '%s' "$json" | env "$key=$val" bash "$script" 2>&1 >/dev/null)
  else
    err=$(printf '%s' "$json" | bash "$script" 2>&1 >/dev/null)
  fi
  got=$?

  msg_ok=1; msg_detail=""
  if [ "$expect" = "2" ] && [ "$got" = "2" ]; then
    case "$err" in *"! $cmd"*) ;; *) msg_ok=0; msg_detail="$msg_detail no-escape-hatch-line"; esac
    case "$err" in *"are blocked too"*) ;; *) msg_ok=0; msg_detail="$msg_detail no-variants-clause"; esac

    case "$none_ids" in
      *" $id "*)
        case "$err" in *"IRREVERSIBLE"*) ;; *) msg_ok=0; msg_detail="$msg_detail missing-IRREVERSIBLE"; esac
        case "$err" in *"Safe alternative"*) msg_ok=0; msg_detail="$msg_detail unexpected-Safe-alternative" ;; esac
        ;;
    esac

    case "$named_ids" in
      *" $id "*)
        case "$err" in *"IRREVERSIBLE"*) msg_ok=0; msg_detail="$msg_detail unexpected-IRREVERSIBLE" ;; esac
        case "$err" in *"Safe alternative"*) ;; *) msg_ok=0; msg_detail="$msg_detail missing-Safe-alternative" ;; esac
        sub=$(alt_substring "$id")
        if [ -n "$sub" ]; then
          case "$err" in *"$sub"*) ;; *) msg_ok=0; msg_detail="$msg_detail missing-alt-substring[$sub]" ;; esac
        fi
        ;;
    esac

    if [ "$id" = "extra_pattern" ]; then
      case "$err" in *"IRREVERSIBLE"*) msg_ok=0; msg_detail="$msg_detail unexpected-IRREVERSIBLE" ;; esac
      case "$err" in *"Safe alternative"*) msg_ok=0; msg_detail="$msg_detail unexpected-Safe-alternative" ;; esac
      case "$err" in *"ZZZ_TEST_PATTERN_ZZZ"*) ;; *) msg_ok=0; msg_detail="$msg_detail missing-matched-pattern" ;; esac
    fi
  fi

  if [ "$got" = "$expect" ] && [ "$msg_ok" = 1 ]; then
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
