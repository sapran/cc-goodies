#!/bin/bash
# cc-goodies / statusline — mode-toggle verification harness (TDD).
#
# Authored from the OpenSpec change `add-statusline-mode-toggle` (proposal /
# design / spec / tasks 7.2–7.10), NOT from the script's render logic — it tests
# the *contract*, not the implementation. Drives the DEV script
# (plugins/statusline/statusline-command.sh) as a SUBPROCESS: each case builds
# synthetic stdin JSON with `jq -n` from env vars (never fixture text on a
# command line), points HOME at a FRESH temp dir per case so it controls
# ~/.claude/statusline.conf and never touches the real settings.json, and writes
# any conf/transcript fixture to a file inside that temp HOME at runtime. A temp
# git repo on `main` (mirror of git-guard's make_repo) is the cwd whenever a
# branch token is needed.
#
# Contract under test (from the spec/design):
#   * Two modes: `enriched` (today's two-line output) and `lean` (one line).
#   * Mode is read EACH render from $HOME/.claude/statusline.conf, key
#     STATUSLINE_MODE, validated to {enriched, lean}; absent/invalid => enriched.
#   * Lean line = compressed cwd + [branch]/wt: + model + `c:NN%` gauge, and
#     DROPS user@host, the task→latest snippet, the effort suffix, the s:/w:
#     gauges, and every ⧗/⟲ time suffix.
#   * The c: gauge keeps its severity colour; a red-band value (e.g. 92) emits
#     the bold-red SGR `1;38;5;196` (per tasks 3.2/7.4).
#   * The conf is READ, never sourced (a side-effecting line must not run).
#   * Lean does strictly less work: no transcript read, no rate-limit/reset
#     bookkeeping, etc. — so lean output is transcript-independent.
#   * The script itself writes no conf; jq is invoked exactly once per render.
#   * Toggle write recipe (task 7.10): updates only STATUSLINE_MODE, preserves
#     other keys; uninstall's `rm -f` removes the conf and is clean when re-run.
#
# Usage: bash plugins/statusline/tests/run.sh   (exits non-zero on any failure)

set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../statusline-command.sh"

[ -f "$script" ] || { echo "FATAL: dev script not found: $script" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "FATAL: jq required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FATAL: git required" >&2; exit 1; }

# Capture the REAL jq path before any PATH-shim case can shadow it, so the
# harness's own JSON building and the shim's `exec` both reach the genuine jq.
real_jq=$(command -v jq)

pass=0; fail=0; total=0
tmproot=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
cleanup() { rm -rf "$tmproot"; }
trap cleanup EXIT

ok()   { pass=$((pass+1)); total=$((total+1)); printf 'PASS  %s\n' "$1"; }
bad()  { fail=$((fail+1)); total=$((total+1)); printf 'FAIL  %s  -- %s\n' "$1" "$2"; }

# ---------------------------------------------------------------------------
# Glyphs / SGR the contract names, kept as variables so the source file itself
# stays plain ASCII-safe to grep and the assertions read clearly.
ARROW=$(printf '\342\206\222')        # → task→latest separator (enriched only)
HOURGLASS=$(printf '\342\247\227')    # ⧗ elapsed-duration suffix (enriched only)
RESETGLYPH=$(printf '\342\237\262')   # ⟲ reset-countdown suffix (enriched only)
RED_SGR='1;38;5;196'                  # bold-red severity band for c: >=75

# Build a throwaway git repo with one empty commit on branch $1. Echoes path.
# Mirrors git-guard/tests/run.sh make_repo (branch -M is default-name agnostic).
make_repo() {
  d=$(mktemp -d -p "$tmproot") || return 1
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name  t
  git -C "$d" commit -q --allow-empty -m x
  git -C "$d" branch -M "$1"
  printf '%s' "$d"
}

# Fresh temp HOME per call so ~/.claude/statusline.conf is fully controlled and
# the real settings.json is never read. Echoes the new HOME path.
fresh_home() {
  h=$(mktemp -d -p "$tmproot") || return 1
  mkdir -p "$h/.claude"
  printf '%s' "$h"
}

# Build the statusline stdin event with jq -n from env vars. Every field is
# optional; unset env vars become "". Uses the REAL jq explicitly so a PATH shim
# case cannot corrupt the harness's own JSON construction.
#   ST_CWD ST_MODEL ST_USED ST_RL5H ST_RL7D ST_RL5H_RESET ST_RL7D_RESET
#   ST_TRANSCRIPT ST_EFFORT ST_DUR_MS ST_WORKTREE
mk_stdin() {
  "$real_jq" -nc '
    {
      cwd: (env.ST_CWD // ""),
      model: { display_name: (env.ST_MODEL // "") },
      context_window: { used_percentage: (env.ST_USED // "") },
      rate_limits: {
        five_hour:  { used_percentage: (env.ST_RL5H // ""), resets_at: (env.ST_RL5H_RESET // "") },
        seven_day:  { used_percentage: (env.ST_RL7D // ""), resets_at: (env.ST_RL7D_RESET // "") }
      },
      worktree: { name: (env.ST_WORKTREE // "") },
      transcript_path: (env.ST_TRANSCRIPT // ""),
      effort: { level: (env.ST_EFFORT // "") },
      cost: { total_duration_ms: (env.ST_DUR_MS // "") }
    }'
}

# Render: pipe $1 (stdin JSON) to the dev script as a subprocess under HOME=$2,
# cwd=$3. Captures stdout to global $OUT and returns the script's exit code.
# PATH is forced to a clean value containing the real jq's dir unless the caller
# has pre-pended a shim dir via $SHIM_PATH.
render() {
  _stdin="$1"; _home="$2"; _cwd="$3"
  _path="${SHIM_PATH:-}"
  if [ -n "$_path" ]; then _path="$_path:$PATH"; else _path="$PATH"; fi
  OUT=$(cd "$_cwd" && printf '%s' "$_stdin" \
        | env -i HOME="$_home" PATH="$_path" TMPDIR="$tmproot" LANG=C \
              bash "$script" 2>/dev/null)
  return $?
}

# Count output lines. printf-captured $OUT loses one trailing newline to the
# command substitution, so a single-line render reports 1 and a two-line render
# reports 2 — exactly the enriched/lean distinction we assert.
nlines() { printf '%s' "$1" | grep -c ''; }

# ===========================================================================
# Case (a) — task 7.2: no conf => enriched, exactly 2 lines, has @ and s: gauge.
# ===========================================================================
case_a() {
  home=$(fresh_home); repo=$(make_repo main)
  stdin=$(ST_CWD="$repo" ST_MODEL="Opus 4.8" ST_USED="42" \
          ST_RL5H="30" ST_RL7D="20" ST_RL5H_RESET="2026-06-22T20:00:00Z" \
          ST_RL7D_RESET="2026-06-25T20:00:00Z" ST_EFFORT="high" \
          ST_DUR_MS="5000" mk_stdin)
  render "$stdin" "$home" "$repo"
  n=$(nlines "$OUT")
  if [ "$n" -eq 2 ] \
     && printf '%s' "$OUT" | grep -q '@' \
     && printf '%s' "$OUT" | grep -q 's:'; then
    ok "a/no-conf-enriched (2 lines, has @ and s:)"
  else
    bad "a/no-conf-enriched" "lines=$n want=2; @=$(printf '%s' "$OUT"|grep -qc '@';echo $?) s:=$(printf '%s' "$OUT"|grep -qc 's:';echo $?)"
  fi
}

# ===========================================================================
# Case (b) — task 7.3: conf STATUSLINE_MODE=lean => exactly 1 line; has model,
# c:, [main]; has NONE of @ s: w: arrow hourglass resetglyph or a '(' .
# Model "Opus 4.8" deliberately has no parens of its own.
# ===========================================================================
case_b() {
  home=$(fresh_home); repo=$(make_repo main)
  printf 'STATUSLINE_MODE=lean\n' > "$home/.claude/statusline.conf"
  stdin=$(ST_CWD="$repo" ST_MODEL="Opus 4.8" ST_USED="42" \
          ST_RL5H="30" ST_RL7D="20" ST_RL5H_RESET="2026-06-22T20:00:00Z" \
          ST_RL7D_RESET="2026-06-25T20:00:00Z" ST_EFFORT="high" \
          ST_DUR_MS="5000" mk_stdin)
  render "$stdin" "$home" "$repo"
  n=$(nlines "$OUT")
  miss=""
  printf '%s' "$OUT" | grep -q 'Opus 4.8' || miss="$miss model"
  printf '%s' "$OUT" | grep -q 'c:'       || miss="$miss c:"
  printf '%s' "$OUT" | grep -q '\[main\]' || miss="$miss [main]"
  pres=""
  printf '%s' "$OUT" | grep -q '@'              && pres="$pres @"
  printf '%s' "$OUT" | grep -q 's:'             && pres="$pres s:"
  printf '%s' "$OUT" | grep -q 'w:'             && pres="$pres w:"
  printf '%s' "$OUT" | grep -qF "$ARROW"        && pres="$pres arrow"
  printf '%s' "$OUT" | grep -qF "$HOURGLASS"    && pres="$pres hourglass"
  printf '%s' "$OUT" | grep -qF "$RESETGLYPH"   && pres="$pres resetglyph"
  printf '%s' "$OUT" | grep -qF '('             && pres="$pres ("
  if [ "$n" -eq 1 ] && [ -z "$miss" ] && [ -z "$pres" ]; then
    ok "b/lean-single-line (model c: [main]; no @ s: w: arrow hourglass reset '(')"
  else
    bad "b/lean-single-line" "lines=$n want=1; missing={$miss} present-but-forbidden={$pres}"
  fi
}

# ===========================================================================
# Case (c) — task 7.4: lean with context value 92 => output carries the bold-red
# SGR sequence 1;38;5;196 on the c: gauge.
# ===========================================================================
case_c() {
  home=$(fresh_home); repo=$(make_repo main)
  printf 'STATUSLINE_MODE=lean\n' > "$home/.claude/statusline.conf"
  stdin=$(ST_CWD="$repo" ST_MODEL="Opus 4.8" ST_USED="92" mk_stdin)
  render "$stdin" "$home" "$repo"
  if printf '%s' "$OUT" | grep -qF "$RED_SGR"; then
    ok "c/lean-context-92-red-sgr (contains $RED_SGR)"
  else
    bad "c/lean-context-92-red-sgr" "expected SGR $RED_SGR not found"
  fi
}

# ===========================================================================
# Case (d) — task 7.5: fail-soft. bogus mode => enriched (2 lines); a conf with
# no STATUSLINE_MODE key at all => enriched (2 lines).
# ===========================================================================
case_d() {
  # d1: bogus value
  home=$(fresh_home); repo=$(make_repo main)
  printf 'STATUSLINE_MODE=bogus\n' > "$home/.claude/statusline.conf"
  stdin=$(ST_CWD="$repo" ST_MODEL="Opus 4.8" ST_USED="42" \
          ST_RL5H="30" ST_RL7D="20" ST_EFFORT="high" ST_DUR_MS="5000" mk_stdin)
  render "$stdin" "$home" "$repo"
  n1=$(nlines "$OUT")
  [ "$n1" -eq 2 ] && d1=ok || d1=bad

  # d2: conf present but no STATUSLINE_MODE key
  home2=$(fresh_home); repo2=$(make_repo main)
  printf 'FOO=bar\n' > "$home2/.claude/statusline.conf"
  stdin2=$(ST_CWD="$repo2" ST_MODEL="Opus 4.8" ST_USED="42" \
           ST_RL5H="30" ST_RL7D="20" ST_EFFORT="high" ST_DUR_MS="5000" mk_stdin)
  render "$stdin2" "$home2" "$repo2"
  n2=$(nlines "$OUT")
  [ "$n2" -eq 2 ] && d2=ok || d2=bad

  if [ "$d1" = ok ] && [ "$d2" = ok ]; then
    ok "d/fail-soft-enriched (bogus->enriched 2 lines; no-key->enriched 2 lines)"
  else
    bad "d/fail-soft-enriched" "bogus lines=$n1 (want 2); no-key lines=$n2 (want 2)"
  fi
}

# ===========================================================================
# Case (e) — task 7.6: read-not-source. A conf line that WOULD create a sentinel
# IF the conf were sourced, alongside STATUSLINE_MODE=lean => render is lean
# (1 line) AND the sentinel is NOT created.
# ===========================================================================
case_e() {
  home=$(fresh_home); repo=$(make_repo main)
  sentinel="$home/SENTINEL_SOURCED"
  # Written to a file (never a command line). If `source`d this `touch` runs.
  {
    printf 'STATUSLINE_MODE=lean\n'
    printf 'touch %s\n' "$sentinel"
  } > "$home/.claude/statusline.conf"
  stdin=$(ST_CWD="$repo" ST_MODEL="Opus 4.8" ST_USED="42" mk_stdin)
  render "$stdin" "$home" "$repo"
  n=$(nlines "$OUT")
  if [ "$n" -eq 1 ] && [ ! -e "$sentinel" ]; then
    ok "e/conf-read-not-sourced (lean 1 line; sentinel absent)"
  else
    bad "e/conf-read-not-sourced" "lines=$n want=1; sentinel-exists=$([ -e "$sentinel" ] && echo yes || echo no)"
  fi
}

# ===========================================================================
# Case (f) — task 7.7: lean ignores the transcript. A lean render WITH a
# transcript whose content would surface a task must (1) contain no task text
# and (2) be byte-identical to the lean render with the transcript omitted.
# ===========================================================================
case_f() {
  home=$(fresh_home); repo=$(make_repo main)
  printf 'STATUSLINE_MODE=lean\n' > "$home/.claude/statusline.conf"
  tpath="$home/transcript.jsonl"
  marker="ZZZ_LEAN_TASK_MARKER_ZZZ"
  # A plausible transcript line: a user message whose text is the marker. If lean
  # read the transcript, this marker could surface in the task snippet.
  # shellcheck disable=SC2016  # $m is a jq --arg variable, not shell — single quotes are required
  "$real_jq" -nc --arg m "$marker" \
    '{type:"user",message:{role:"user",content:$m}}' > "$tpath"

  stdin_with=$(ST_CWD="$repo" ST_MODEL="Opus 4.8" ST_USED="42" \
               ST_TRANSCRIPT="$tpath" mk_stdin)
  render "$stdin_with" "$home" "$repo"; out_with="$OUT"

  stdin_without=$(ST_CWD="$repo" ST_MODEL="Opus 4.8" ST_USED="42" mk_stdin)
  render "$stdin_without" "$home" "$repo"; out_without="$OUT"

  no_marker=ok
  printf '%s' "$out_with" | grep -qF "$marker" && no_marker=bad
  if [ "$no_marker" = ok ] && [ "$out_with" = "$out_without" ]; then
    ok "f/lean-transcript-independent (no task text; identical with/without transcript)"
  else
    bad "f/lean-transcript-independent" "marker-present=$([ "$no_marker" = bad ] && echo yes || echo no); identical=$([ "$out_with" = "$out_without" ] && echo yes || echo no)"
  fi
}

# ===========================================================================
# Case (g) — task 7.8: mode re-read per render. Render with conf=enriched
# (2 lines), flip the conf to lean, render the SAME stdin again (1 line); assert
# the two outputs differ. Same HOME, same stdin — only the conf changes.
# ===========================================================================
case_g() {
  home=$(fresh_home); repo=$(make_repo main)
  stdin=$(ST_CWD="$repo" ST_MODEL="Opus 4.8" ST_USED="42" \
          ST_RL5H="30" ST_RL7D="20" ST_EFFORT="high" ST_DUR_MS="5000" mk_stdin)

  printf 'STATUSLINE_MODE=enriched\n' > "$home/.claude/statusline.conf"
  render "$stdin" "$home" "$repo"; out1="$OUT"; n1=$(nlines "$out1")

  printf 'STATUSLINE_MODE=lean\n' > "$home/.claude/statusline.conf"
  render "$stdin" "$home" "$repo"; out2="$OUT"; n2=$(nlines "$out2")

  if [ "$n1" -eq 2 ] && [ "$n2" -eq 1 ] && [ "$out1" != "$out2" ]; then
    ok "g/runtime-reread (enriched 2 lines -> lean 1 line; outputs differ)"
  else
    bad "g/runtime-reread" "first lines=$n1 (want 2); second lines=$n2 (want 1); differ=$([ "$out1" != "$out2" ] && echo yes || echo no)"
  fi
}

# ===========================================================================
# Case (h) — task 7.9: jq invoked exactly ONCE per render (both modes), with NO
# transcript. A PATH shim named `jq` appends a tick to a counter file then execs
# the REAL jq (captured before shimming). The shim counts EVERY jq the script
# spawns; the harness's own mk_stdin uses $real_jq directly, off-PATH, so it
# never bumps the counter.
# ===========================================================================
case_h() {
  shimdir=$(mktemp -d -p "$tmproot")
  counter="$tmproot/jq_count.$$"
  shim="$shimdir/jq"
  {
    printf '#!/bin/bash\n'
    printf 'printf x >> "%s"\n' "$counter"
    printf 'exec "%s" "$@"\n' "$real_jq"
  } > "$shim"
  chmod +x "$shim"

  # --- lean, no transcript ---
  : > "$counter"
  home=$(fresh_home); repo=$(make_repo main)
  printf 'STATUSLINE_MODE=lean\n' > "$home/.claude/statusline.conf"
  stdin=$(ST_CWD="$repo" ST_MODEL="Opus 4.8" ST_USED="42" mk_stdin)
  SHIM_PATH="$shimdir" render "$stdin" "$home" "$repo"
  lean_count=$(wc -c < "$counter" | tr -d ' ')

  # --- enriched, no transcript ---
  : > "$counter"
  home2=$(fresh_home); repo2=$(make_repo main)
  printf 'STATUSLINE_MODE=enriched\n' > "$home2/.claude/statusline.conf"
  stdin2=$(ST_CWD="$repo2" ST_MODEL="Opus 4.8" ST_USED="42" \
           ST_RL5H="30" ST_RL7D="20" ST_EFFORT="high" ST_DUR_MS="5000" mk_stdin)
  SHIM_PATH="$shimdir" render "$stdin2" "$home2" "$repo2"
  enriched_count=$(wc -c < "$counter" | tr -d ' ')

  if [ "$lean_count" = "1" ] && [ "$enriched_count" = "1" ]; then
    ok "h/jq-once-per-render (lean=$lean_count enriched=$enriched_count, no transcript)"
  else
    bad "h/jq-once-per-render" "lean jq=$lean_count (want 1); enriched jq=$enriched_count (want 1)"
  fi
}

# ===========================================================================
# Case (i) — task 7.9 tail: the script writes NO conf. After a clean lean render
# with a fresh HOME (conf supplied by us), the assertion is the OTHER direction:
# with a clean HOME and NO conf supplied, a render must NOT create the conf.
# ===========================================================================
case_i() {
  home=$(fresh_home); repo=$(make_repo main)
  # No conf written: a clean HOME. The script must not author one.
  stdin=$(ST_CWD="$repo" ST_MODEL="Opus 4.8" ST_USED="42" \
          ST_RL5H="30" ST_RL7D="20" ST_EFFORT="high" ST_DUR_MS="5000" mk_stdin)
  render "$stdin" "$home" "$repo"
  if [ ! -e "$home/.claude/statusline.conf" ]; then
    ok "i/script-writes-no-conf (statusline.conf absent after render)"
  else
    bad "i/script-writes-no-conf" "script created $home/.claude/statusline.conf"
  fi
}

# ===========================================================================
# Case (j) — task 7.10: toggle write recipe + uninstall rm.
# Mirror the DOCUMENTED toggle write: update only STATUSLINE_MODE, preserve the
# unrelated key FOO=bar; then the uninstall `rm -f` removes the conf and is clean
# when re-run on an absent file. This is the command's contract, exercised here
# as a shell function so the harness verifies the recipe independent of the .md.
# ===========================================================================

# toggle_write CONF MODE — set STATUSLINE_MODE=$MODE in $CONF, updating only that
# key and preserving every other line (rewrite-if-present, append-if-absent).
# This is the recipe tasks 4.3 / 7.10 prescribe.
toggle_write() {
  _conf="$1"; _mode="$2"
  mkdir -p "$(dirname "$_conf")"
  _tmp="$_conf.tmp.$$"
  if [ -f "$_conf" ]; then
    grep -v '^STATUSLINE_MODE=' "$_conf" > "$_tmp" 2>/dev/null || : > "$_tmp"
  else
    : > "$_tmp"
  fi
  printf 'STATUSLINE_MODE=%s\n' "$_mode" >> "$_tmp"
  mv "$_tmp" "$_conf"
}

case_j() {
  home=$(fresh_home)
  conf="$home/.claude/statusline.conf"
  {
    printf 'FOO=bar\n'
    printf 'STATUSLINE_MODE=enriched\n'
  } > "$conf"

  toggle_write "$conf" lean

  mode_now=$(grep '^STATUSLINE_MODE=' "$conf" | tail -n 1)
  mode_now="${mode_now#*=}"
  foo_kept=ok
  grep -q '^FOO=bar$' "$conf" || foo_kept=bad
  # exactly one STATUSLINE_MODE line (rewrite, not duplicate)
  modecount=$(grep -c '^STATUSLINE_MODE=' "$conf")

  recipe=ok
  [ "$mode_now" = "lean" ] || recipe=bad
  [ "$foo_kept" = ok ]     || recipe=bad
  [ "$modecount" = "1" ]   || recipe=bad

  # uninstall conf-removal step: rm -f removes it, and is clean when re-run.
  rm -f "$conf"; rm1=$?
  rm -f "$conf"; rm2=$?   # absent file: still 0
  rm_clean=ok
  [ "$rm1" -eq 0 ] || rm_clean=bad
  [ "$rm2" -eq 0 ] || rm_clean=bad
  [ ! -e "$conf" ] || rm_clean=bad

  if [ "$recipe" = ok ] && [ "$rm_clean" = ok ]; then
    ok "j/toggle-write+uninstall-rm (mode=lean, FOO=bar kept, single key; rm -f clean x2)"
  else
    bad "j/toggle-write+uninstall-rm" "mode=$mode_now foo=$foo_kept modecount=$modecount rm1=$rm1 rm2=$rm2 absent=$([ ! -e "$conf" ] && echo yes || echo no)"
  fi
}

# ---------------------------------------------------------------------------
case_a
case_b
case_c
case_d
case_e
case_f
case_g
case_h
case_i
case_j

echo "-----"
echo "statusline mode-toggle: $pass/$total passed, $fail failed."
[ "$fail" -eq 0 ]
