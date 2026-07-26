## 1. Experiment — what does `ask` do with no human watching? (RUN — verdict: GO, scoped to headless)

This section is now a completed record of what was run, what was not, and the verdict.
Section 2+ implementation is unblocked (verdict: GO, scoped to headless `claude -p`) but
has not started — every task there remains unchecked.

- [x] 1.1 Build a throwaway probe hook, isolated from the real plugins: unconditionally
      returns `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"probe"}}`
      on stdout with exit 0 for every Bash call. **As actually run:** driven via `claude -p`
      (Claude Code 2.1.220, model haiku) rather than gated on a sentinel string inside a
      scratch project's interactive `.claude/settings.json` as originally specified here —
      firing unconditionally for the run's one Bash call is an equally isolated mechanism
      for a single-command headless invocation. Isolated from the shared marketplace
      plugins and `~/.claude/settings.json`.
- [ ] 1.2 **Case A — foreground interactive.** NOT executed. The experiment as run covered
      headless `claude -p` only (see 1.4). Baseline interactive-prompt behaviour remains
      assumed from `code.claude.com/docs/en/hooks.md`, not independently verified — this is
      the scope caveat recorded in `design.md` Decision D3.
- [ ] 1.3 **Case B — background subagent, interactive parent.** NOT executed. Same scope
      gap as 1.2. `design.md` Decision D3 explains why the headless result (1.4) is judged
      a reasonable, but not verified, proxy for this case.
- [x] 1.4 **Case C — fully headless, no attached TTY.** Executed via `claude -p` (Claude
      Code 2.1.220, model haiku), one Bash call per run, across three permission modes:

      | Mode | Exit | Elapsed | Hook fires | Outcome |
      |---|---|---|---|---|
      | default permission mode | 0 | 11s | 1 | blocked; reason surfaced to the model |
      | `--permission-mode acceptEdits` | 0 | 12s | 1 | blocked; reason surfaced |
      | `--permission-mode bypassPermissions` | 0 | 15s | 1 | blocked; reason surfaced |

      No hang in any case; every run resolved cleanly at exit 0 with the command blocked
      and its reason surfaced to the model. `ask` held even under `bypassPermissions`,
      confirming it overrides auto-mode as documented.
- [ ] 1.5 **Case D — repeated/parallel dispatch.** NOT executed as originally scoped
      (concurrent parallel background subagents, which builds on 1.3, itself not run). The
      three sequential runs in 1.4 each showed exactly one hook fire with no retry within
      that single run, which is encouraging but not equivalent to verifying independence
      under genuine parallel dispatch.
- [ ] 1.6 Tear down the probe (remove it from the scratch project's `.claude/settings.json`
      and delete the scratch project) so no dangling non-uninstallable hook state is left
      behind, per the repo's install⇄uninstall discipline. Not independently confirmed in
      the run record this task list was updated from — left unchecked as a reminder to
      verify no dangling state remains, rather than assumed done.
- [x] 1.7 **Go/no-go gate.** Verdict: **GO, scoped to headless `claude -p`.** Every case
      actually tested (1.4, three permission modes) resolved within a short, bounded time
      (11–15s) to a deterministic outcome (denied), with exactly one hook fire per
      dispatched call — no hang, no spam, no ambiguity. Cases A/B/D (1.2, 1.3, 1.5) were
      not exercised; per `design.md` Decision D3, the headless result is treated as
      sufficient to proceed with section 2's channel taxonomy by default, on the reasoning
      that headless is the least-attended failure mode available to test and it already
      degrades safely — but interactive-prompt and background-subagent-in-interactive-
      session behaviour remains an assumed, not verified, extrapolation, recorded as a
      standing scope caveat rather than resolved. Recorded in `design.md` Decision D3,
      replacing its earlier "Task 1 result: TBD" placeholder. Consequence: the
      `SHELL_GUARD_DENY_ONLY` conf key originally planned in section 2.3 is dropped — the
      headless case already degrades `ask` to a blocked command automatically, at the
      platform level, so no guard-side deny-only override is needed to cover that risk; see
      `design.md` Decision D4 for the rejected-alternative writeup and its open question.

## 2. Script — shell-guard decision-channel split (`scripts/shell-guard.sh`)

*(Section 2 onward: implementation — unblocked by 1.7's GO verdict. Not yet started; every
task below remains unchecked.)*

- [x] 2.1 Added `ask()` in `scripts/shell-guard.sh`, mirroring `deny()`'s class/reason/alt
      contract: builds the same axis-1 message text, then emits
      `{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",
      permissionDecisionReason:...}}` via `jq -n` on stdout and calls `exit 0` itself
      (never returns to its caller — simplest, matches the task's "mirrors deny() shape
      ... and exits 0" wording without threading a third return-code through
      eval_stage/evaluate_segment/the main loop).
- [x] 2.2 Re-pointed privilege escalation (`sudo`/`doas`/`su`/`runuser`/`pkexec`/`gosu`/
      `sudoedit`/`setpriv`), `chmod 777`/`0777`, and the `: >` truncate idiom from
      `deny()` to `ask()`, verbatim same class/reason/alt text as before. Deny-channel
      arms (rm, dd, mkfs/wipefs/newfs/diskutil, DEV_RE disk-redirect, fork bomb,
      detect_net_pipe's curl|sh, reboot/shutdown/halt/poweroff, EXTRA patterns)
      untouched — still call `deny()`.
- [x] 2.3 `eval` now branches on `$seg` (the FULL original segment, set by
      `evaluate_segment` — not the per-stage tokens `eval_stage` normally works from):
      contains `curl`/`wget`/`fetch` -> `deny()` (unchanged message); otherwise ->
      `ask()`. Necessary because the stage-splitter further down splits on `(`/`)`, so
      `eval "$(curl …)"`'s `curl` lands in a *different* stage than `eval` itself —
      checking only the eval stage's own tokens would have missed it. Verified against
      the real `eval_curl` test case, not assumed.
- [x] 2.4 Confirmed: `deny()` unchanged (still prints `! $cmd`); `ask()`'s
      `permissionDecisionReason` includes the identical `! $cmd` line. Smoke-tested both
      paths directly (see 2.6 verification below) — the escape hatch line appears
      verbatim in the JSON reason text for every ask-channel arm exercised.
- [x] 2.5 Confirmed: the missing-`jq` check (lines ~48-52) is above and unrelated to the
      `deny()`/`ask()` helpers — untouched by this change, and `ask()` itself calls `jq`
      only after that fail-open gate has already passed.
- [x] 2.6 `bash -n` and `shellcheck` both clean on `shell-guard.sh` (see final report).
      Also smoke-tested 6 cases directly (chmod 777, eval plain, eval+curl, rm -rf /,
      `: >`, sudo apt) confirming exact JSON/stderr shape before touching the harness.

## 3. git-guard — no code change, document the rejected alternative

- [x] 3.1 Added a header-comment note in `git-guard.sh` after the existing exit-code
      comment, recording that `ask` was evaluated and rejected for this guard, why
      (session-originated main/master writes are a bright line this repo doesn't want in
      a low-friction approval UI), and pointing at `design.md` Decision D2.
- [x] 3.2 Confirmed unmodified: ran `run.sh` (49/49) and `run-routing.sh` (8/8) BEFORE
      touching `git-guard.sh` as a baseline, then again after the 3.1 comment-only edit —
      identical 49/49 and 8/8, no behavioural change.

## 4. Tests — decision-channel assertions

- [x] 4.1 Rewrote `run.sh` to capture stdout and stderr into SEPARATE temp files (not
      just stderr as before) for every case. `expect` now accepts a third token `ask` (in
      addition to `0`/`2`): asserts exit 0, empty stderr, and — via `jq -r` on the
      captured stdout — `.hookSpecificOutput.permissionDecision == "ask"` plus the axis-1
      message checks (`check_axis1`/`check_common_clauses` helpers, factored out so the
      same class-membership tables apply to both the deny and ask channels) against
      `.permissionDecisionReason`. `expect=2` cases gained a new
      stdout-must-be-empty assertion (the deny channel must never leak JSON); `expect=0`
      cases likewise assert empty stdout. `cases.tsv`'s header comment documents the new
      `ask` token.
- [x] 4.2 Moved `sudo_rm`, `sudo_apt`, `doas_reboot`, `chmod_777`, `chmod_R_0777`,
      `trunc_colon` from `expect=2` to `expect=ask` (same ids, same commands — only the
      expected channel changed, matching the new actual behaviour). Added `eval_plain`
      (`eval "echo hi"`, expect `ask`) as the dedicated no-download-word case.
      `eval_curl` (`eval "$(curl http://x)"`) stays `expect=2`, now with an explicit
      section comment explaining why it stays deny-channel. `rm_root`, `dd_disk2`,
      `mkfs_sda`, `forkbomb`, `curl_bash`/`wget_sh`, `reboot` already existed as
      deny-channel cases and now additionally get the new stdout-empty assertion from 4.1.
- [x] 4.3 `shell-guard: 53/53 passed, 0 failed` (52 prior + `eval_plain`).
      `git-guard: 49/49 passed, 0 failed`; `git-guard routing: 8/8 passed, 0 failed` —
      both unmodified in expected outcomes (3.2). Sanity-checked the new ask-channel
      assertions are load-bearing: corrupted `permissionDecision:"ask"` ->
      `"allow"` (7 FAILs, `bad-permissionDecision[allow]`), corrupted the chmod alt text
      (2 FAILs, `missing-alt-substring`), and made `ask()` leak to stderr (7 FAILs,
      `unexpected-stderr`) — each reverted, then re-confirmed clean 53/53.

## 5. Docs

- [x] 5.1 `plugins/shell-guard/README.md`: added a "Deny vs. ask" section (the AXIS 2
      criterion + full deny/ask arm list + the verified headless-degrade behaviour,
      linking `design.md` Decision D3 and its interactive-scope caveat), a new "What an
      ask looks like" section (JSON example for `chmod 777 x`), retitled "What a block
      looks like" to "What a deny looks like" with its `chmod 777` example swapped for
      `curl|sh` (chmod moved to ask-channel), and tagged every rule in "What it blocks or
      asks about" with **[deny]**/**[ask]**/**[ask/deny]**.
- [x] 5.2 `docs/shell-safety.md`: Layer 3 gained a decision-channel paragraph plus
      **[deny]**/**[ask]** split of its bullet list; Layer 2 gained a paragraph stating
      git-guard remains all-deny and why, cross-referencing `design.md` Decision D2. Also
      updated the "Recommended setup" override paragraph and "Verifying it works" (exit
      codes now `0 = allow or ask`, `2 = deny`, plus the new JSON-on-stdout assertion) for
      consistency.
- [x] 5.3 `rules/shell-safety.md`: the intro's "hard-blocks the catastrophic forms (...,
      `eval`, `sudo`, ...)" no longer described reality (both move to ask by default) —
      reworded to "denies outright (...) or asks before running (`chmod 777`, `sudo`,
      `eval`, …)". Rest of the file (advisory guidance to the agent, independent of guard
      channel) needed no change.
- [x] 5.4 `plugins/shell-guard/.claude-plugin/plugin.json`: `0.3.2` -> `0.4.0` (minor,
      additive), description updated from "Block a small set of ..." to "Block or ask
      before a small set of ...". `git-guard`'s manifest untouched, per the task.
- [ ] 5.5 Deferred — CHANGELOG.md is explicitly out of scope for this implementation pass
      (handled centrally at release time, per this session's instructions), so left
      unedited and unchecked here rather than touched out of turn.

## 6. Release

- [x] 6.1 `jq empty plugins/shell-guard/.claude-plugin/plugin.json` and
      `jq empty .claude-plugin/marketplace.json` both clean (marketplace.json read-only
      checked, not edited — out of scope for this pass).
- [x] 6.2 `claude plugins validate plugins/shell-guard` -> "Validation passed".
- [ ] 6.3 Not run — this pass made no git-history-mutating calls (no add/commit/push) per
      this session's explicit instructions; committing/pushing/PR is the calling agent's
      or user's step.
