## 1. Experiment — what does `ask` do with no human watching? (BLOCKING, run first)

Nothing in section 2+ may be implemented before this section's gate resolves. This
section is a specification of the experiment, not its execution — running it is a
separate, later action by whoever picks this up.

- [ ] 1.1 Build a throwaway probe hook, isolated from the real plugins: a script that,
      for any Bash command containing a unique sentinel string (e.g.
      `__ASK_PROBE_7f3a__`), unconditionally emits
      `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"probe"}}`
      on stdout with exit 0, and no-ops (exit 0, no output) for everything else. Wire it
      as a `PreToolUse`/`Bash` hook in a **scratch project's** `.claude/settings.json`
      (never the shared marketplace plugins, never `~/.claude/settings.json`) so the
      probe cannot leak into any other session.
- [ ] 1.2 **Case A — foreground interactive.** In a normal interactive session, run the
      sentinel command. Record: does the permission prompt appear as expected, and does
      approving/denying it behave like a normal tool-permission prompt (baseline sanity
      check — confirms the probe itself works before testing the risky cases).
- [ ] 1.3 **Case B — background subagent, interactive parent.** From an interactive
      session, dispatch a subagent via the `Agent` tool with background execution (the
      mode this repo's own `voice-notify` `SubagentStop` work confirms runs without
      blocking the parent turn) whose task is to run the sentinel command. Record:
      wall-clock time to resolution, whether the tool call returns/hangs, whether a
      prompt is ever surfaced to the human (and if so, whether the human is even looking
      at the right place — the parent turn may have already ended), and what the
      subagent's tool-result content looks like if it does resolve.
- [ ] 1.4 **Case C — fully headless, no attached TTY.** Invoke Claude Code in its
      non-interactive/scripted mode (whatever the current headless entry point is —
      confirm the exact invocation against `code.claude.com/docs` at experiment time,
      since this proposal does not assume one) with a prompt that runs the sentinel
      command, and no terminal attached to answer any prompt. Record the same signals as
      1.3: hang vs. timeout vs. immediate resolution, and the process's exit behaviour
      (does the whole run hang, error out, or silently proceed as if allowed/denied).
- [ ] 1.5 **Case D — repeated/parallel dispatch.** Repeat 1.3 with several parallel
      background subagents each hitting the sentinel command in the same turn. Record
      whether the outcomes are independent (no spam) or whether multiple prompts/hangs
      compound.
- [ ] 1.6 Tear down the probe (remove it from the scratch project's `.claude/settings.json`
      and delete the scratch project) so no dangling non-uninstallable hook state is left
      behind, per the repo's install⇄uninstall discipline.
- [ ] 1.7 **Go/no-go gate.** Using 1.2–1.5's findings:
      - **GO** — proceed to section 2 — only if, in every one of Cases B/C/D, `ask`
        resolves within a short, bounded time (no indefinite hang) to a deterministic
        outcome (deny or allow), and does not produce more than one prompt/attempt per
        dispatched call (no spam).
      - **NO-GO, ship deny-only** — if any of Cases B/C/D hangs indefinitely, times out
        into an ambiguous state, or spams — do not tier the guards by default. Either
        stop here (do not implement section 2), or implement section 2 with `ask` gated
        fully **off by default**, reachable only behind the conf key from task 2.3 for
        operators who have separately confirmed their own sessions are always
        interactively attended (documented as an explicit, informed opt-in, not a
        default).
      - **Ambiguous / inconsistent across cases** (e.g., safe in Case B but not Case C) —
        do not average this into a single verdict. Treat the *worst* observed case as
        binding for the default, and document per-case findings in `design.md` so the
        conf key's default can be justified against the specific mode that fails.
      - Record the verdict and the evidence for each case directly in `design.md`
        (replacing its "Task 1 result: TBD" placeholder) before starting section 2.

## 2. Script — shell-guard decision-channel split (`scripts/shell-guard.sh`)

*(Section 2 onward: implementation. Do not start until 1.7's gate says GO, or GO with the
deny-only-by-default fallback.)*

- [ ] 2.1 Add a JSON-stdout emitter (`ask()`, mirroring the existing `deny()` shape) that
      prints the `hookSpecificOutput.permissionDecision: "ask"` object with
      `permissionDecisionReason` and exits 0 — used only by the arms assigned `ask` in
      the taxonomy below (see `design.md` for the full arm list and reasoning).
- [ ] 2.2 Re-point the hygiene arms (`chmod 777`, `: >` truncate, privilege escalation,
      `eval`, system halt/reboot — see `design.md` for the final list, contingent on the
      Task 1 result) from `deny()` to `ask()`. Catastrophic arms (recursive delete of a
      protected path, `dd`/redirect onto a raw disk device, `mkfs`/`wipefs`/`newfs`/
      destructive `diskutil`, fork bomb, `curl|sh`) are untouched — same `deny()` call,
      same exit-2/stderr path, as today.
- [ ] 2.3 Add the deny-only conf key (name and default polarity fixed by the 1.7 verdict;
      provisionally `SHELL_GUARD_DENY_ONLY`), read via `conf_get` at the existing
      `env var → conf file → default` precedence. When set, every arm that would emit
      `ask` falls back to `deny()` instead — i.e., the pre-this-change behaviour,
      selectable per session/operator.
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
      a decision-tier column) so an `ask` case is asserted on its actual output — exit 0
      **and** `hookSpecificOutput.permissionDecision == "ask"` in stdout JSON — not
      misread as a plain allow (today's harness only asserts exit codes).
- [ ] 4.2 Add one case per re-tiered arm (`chmod 777`, `: >`, `sudo`, `eval`, `reboot` —
      per the final taxonomy) confirming it now resolves to `ask`, plus one case per
      still-catastrophic arm (`rm -rf /`, `dd` to device, `mkfs`, fork bomb, `curl|sh`)
      confirming it is still a plain exit-2/stderr `deny` with no JSON on stdout.
- [ ] 4.3 Add a case exercising `SHELL_GUARD_DENY_ONLY` (or whatever task 2.3 named it):
      a hygiene arm that would normally `ask` falls back to `deny` when the key is set.
- [ ] 4.4 Full `plugins/shell-guard/tests/run.sh` green; `plugins/git-guard/tests/run.sh`
      and `run-routing.sh` green and unmodified in expected outcomes.

## 5. Docs

- [ ] 5.1 `plugins/shell-guard/README.md`: document the two decision tiers, the new conf
      key, and that `ask` requires the harness's own permission-prompt UI (link the
      go/no-go finding for context on why it's conditional).
- [ ] 5.2 `docs/shell-safety.md`: Layer 3 (shell-guard) table/prose gains a decision-tier
      note; Layer 2 (git-guard) prose gains one line stating it remains all-deny and why,
      cross-referencing this change.
- [ ] 5.3 `rules/shell-safety.md`: check whether the escape-hatch wording still holds
      verbatim now that some arms surface as a permission prompt instead of a stderr
      block; update only if it no longer describes what actually happens.
- [ ] 5.4 Bump `plugins/shell-guard/.claude-plugin/plugin.json` version (minor —
      additive); `git-guard`'s manifest is unaffected (no behaviour change).
- [ ] 5.5 `CHANGELOG.md` entry recording the tiering, the conf key, and (if relevant) the
      Task 1 finding that justified shipping it.

## 6. Release

- [ ] 6.1 `jq empty plugins/shell-guard/.claude-plugin/plugin.json` and
      `jq empty .claude-plugin/marketplace.json`.
- [ ] 6.2 `claude plugins validate plugins/shell-guard`.
- [ ] 6.3 Commit on the change branch (separate commits: script, tests, docs, per repo
      convention), push, open a draft PR to `develop`. Archive + `main` FF happen after
      review, per the repo release flow.
