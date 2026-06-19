#!/bin/bash
# cc-goodies / shell-guard — direct-drive test runner.
#
# Drives the DEV script directly (never the live PreToolUse hook): builds the
# synthetic tool-call JSON with `jq -n`, reading the command from an ENV VAR so a
# dangerous literal never lands on a Bash command line — it lives only in
# cases.tsv, read at runtime. The dev script runs as a SUBPROCESS, which the live
# hook never sees, so testing `rm -rf /` here cannot self-block. Asserts the
# captured exit code (0 = allow, 2 = block).
#
# cases.tsv rows are SPACE-separated leading tokens; the command takes the rest:
#   <id> <expect 0|2> <cwd: - | HOME> <command …>
# `read -r id expect cwd command` keeps the command's own spaces (the last
# variable gets the remainder of the line) and needs no tabs — robust across the
# BSD/macOS tools this repo targets (an earlier awk `\0` split silently read zero
# rows under BSD awk).
#
# Usage: bash plugins/shell-guard/tests/run.sh   (exits non-zero on any failure)

set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/shell-guard.sh"
cases="$here/cases.tsv"

[ -f "$script" ] || { echo "FATAL: dev script not found: $script" >&2; exit 1; }
[ -f "$cases" ]  || { echo "FATAL: cases file not found: $cases" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

pass=0; fail=0; total=0
while read -r id expect cwd command; do
  case "$id" in ''|\#*) continue ;; esac           # skip blanks + comments
  [ -n "${command:-}" ] || continue
  total=$((total+1))

  # cwd sentinel: HOME selects the session-in-home glob-all case; - means none.
  case "$cwd" in HOME) cwdv="$HOME" ;; *) cwdv="" ;; esac

  json=$(MSG="$command" CWDV="$cwdv" jq -nc \
    '{tool_name:"Bash",tool_input:{command:env.MSG},cwd:env.CWDV}')
  printf '%s' "$json" | bash "$script" >/dev/null 2>&1
  got=$?

  if [ "$got" = "$expect" ]; then
    pass=$((pass+1))
    printf 'PASS  %-18s expect=%s got=%s\n' "$id" "$expect" "$got"
  else
    fail=$((fail+1))
    printf 'FAIL  %-18s expect=%s got=%s  cmd=%s\n' "$id" "$expect" "$got" "$command"
  fi
done < "$cases"

echo "-----"
echo "shell-guard: $pass/$total passed, $fail failed."
[ "$fail" -eq 0 ]
