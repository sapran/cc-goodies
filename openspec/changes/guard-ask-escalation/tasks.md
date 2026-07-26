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

- [ ] 2.1 Add a JSON-stdout emitter (`ask()`, mirroring the existing `deny()` shape) that
      prints the `hookSpecificOutput.permissionDecision: "ask"` object with
      `permissionDecisionReason` and exits 0 — used only by the arms assigned to the ask
      channel below (see `design.md` Decision D1 for the full arm list and reasoning).
- [ ] 2.2 Re-point the ask-channel arms (`chmod 777`, `: >` truncate, privilege escalation,
      and `eval` when its argument has no download command word — see `design.md`
      Decision D1 for the final list) from `deny()` to `ask()`. Deny-channel arms
      (recursive delete of a protected path, `dd`/redirect onto a raw disk device,
      `mkfs`/`wipefs`/`newfs`/destructive `diskutil`, fork bomb, `curl|sh`, and system
      halt/reboot) are untouched — same `deny()` call, same exit-2/stderr path, as today.
- [ ] 2.3 Within the `eval` arm, check whether its argument contains a download command
      word (`curl`/`wget`/`fetch`); if so, call `deny()` instead of `ask()`. Per
      `design.md` Decision D1's `eval`-exception writeup and the dedicated requirement in
      `specs/guard-decision-tiers/spec.md` — this is a channel-selection check on
      already-matched-arm text, not a new detection pattern.
- [ ] 2.4 Confirm the `!`-paste escape-hatch line is present, unchanged, in both the
      `deny()` and the new `ask()` output.
- [ ] 2.5 Confirm the missing-`jq` fail-open path is untouched (still exits 0 with a
      one-line warning before either `deny()` or `ask()` can be reached).
- [ ] 2.6 `bash -n plugins/shell-guard/scripts/shell-guard.sh` and
      `shellcheck plugins/shell-guard/scripts/shell-guard.sh` clean.

## 3. git-guard — no code change, document the rejected alternative

- [ ] 3.1 Add a short header-comment note in `plugins/git-guard/scripts/git-guard.sh`
      (near the existing exit-code comment) recording that `permissionDecision: "ask"`
      was evaluated and rejected for this guard, with a one-line pointer to this change's
      `design.md` for the reasoning, so a future reader doesn't re-litigate it from
      scratch.
- [ ] 3.2 No behavioural change: `plugins/git-guard/tests/run.sh` and
      `run-routing.sh` should pass unmodified, confirming this.

## 4. Tests — decision-channel assertions

- [ ] 4.1 Extend `plugins/shell-guard/tests/run.sh` (and `cases.tsv` if its format needs
      a decision-channel column) so an `ask` case is asserted on its actual output — exit 0
      **and** `hookSpecificOutput.permissionDecision == "ask"` in stdout JSON — not
      misread as a plain allow (today's harness only asserts exit codes).
- [ ] 4.2 Add one case per newly ask-channel arm (`chmod 777`, `: >`, `sudo`, `eval` with
      no download word — per `design.md` Decision D1) confirming it now resolves to `ask`,
      plus one case per still-deny-channel arm (`rm -rf /`, `dd` to device, `mkfs`, fork
      bomb, `curl|sh`, `reboot`) confirming it is still a plain exit-2/stderr `deny` with
      no JSON on stdout. Add a dedicated case for `eval "$(curl http://x)"` (the existing
      `eval_curl` case in `cases.tsv`) confirming it stays on the deny channel despite
      `eval` otherwise being ask-channel — see `design.md` Decision D1's `eval`-exception
      writeup.
- [ ] 4.3 Full `plugins/shell-guard/tests/run.sh` green; `plugins/git-guard/tests/run.sh`
      and `run-routing.sh` green and unmodified in expected outcomes.

## 5. Docs

- [ ] 5.1 `plugins/shell-guard/README.md`: document the two AXIS 2 channels (deny/ask) and
      that `ask` requires the harness's own permission-prompt UI (link the go/no-go
      finding in `design.md` Decision D3 for context on the verified headless behaviour and
      its scope caveat).
- [ ] 5.2 `docs/shell-safety.md`: Layer 3 (shell-guard) table/prose gains a decision-channel
      note; Layer 2 (git-guard) prose gains one line stating it remains all-deny and why,
      cross-referencing this change.
- [ ] 5.3 `rules/shell-safety.md`: check whether the escape-hatch wording still holds
      verbatim now that some arms surface as a permission prompt instead of a stderr
      block; update only if it no longer describes what actually happens.
- [ ] 5.4 Bump `plugins/shell-guard/.claude-plugin/plugin.json` version (minor —
      additive); `git-guard`'s manifest is unaffected (no behaviour change).
- [ ] 5.5 `CHANGELOG.md` entry recording the channel split and the Task 1 finding that
      justified shipping it (verified GO, scoped to headless `claude -p`; see `design.md`
      Decision D3).

## 6. Release

- [ ] 6.1 `jq empty plugins/shell-guard/.claude-plugin/plugin.json` and
      `jq empty .claude-plugin/marketplace.json`.
- [ ] 6.2 `claude plugins validate plugins/shell-guard`.
- [ ] 6.3 Commit on the change branch (separate commits: script, tests, docs, per repo
      convention), push, open a draft PR to `develop`. Archive + `main` FF happen after
      review, per the repo release flow.
