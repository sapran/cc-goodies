## Why

> **Status: verified, unblocked.** The go/no-go gate this proposal was written behind
> (`tasks.md` §1, `design.md` Decision D3) has been run and passed. `permissionDecision:
> "ask"` was probed with a throwaway hook returning `ask` for every Bash call, driven by
> `claude -p` (Claude Code 2.1.220, model haiku), across three headless runs (default
> permission mode, `--permission-mode acceptEdits`, `--permission-mode bypassPermissions`),
> one Bash call each. Every run: exit 0, 11–15s elapsed, exactly one hook fire, the command
> blocked with its reason surfaced to the model — no hang, no prompt-retry spam, and `ask`
> held even under `bypassPermissions`, confirming the docs' "overrides auto-mode" claim.
> Full record and a scope caveat (only headless `claude -p` was tested; interactive/
> background-subagent behaviour is assumed from the docs, not independently verified) live
> in `tasks.md` §1 and `design.md` Decision D3. The rest of this proposal is no longer
> contingent on an open question — implementation (`tasks.md` §2+) has not started.

`git-guard` and `shell-guard` are both binary today: a matched arm calls `deny()`, which
prints a reason to stderr and returns exit code 2. That is the *only* signal the hook API
has ever offered these guards — verified in both scripts' own header comments ("Exit
codes: 0 = allow, 2 = block … Any other code is a non-blocking error"). Every arm gets
the same treatment whether it is `rm -rf /` (irreversible, no safe way to approve it blind)
or `chmod 777` (trivially reversible with `chmod 755`, and fully disclosed in the command
text).

Claude Code's hook API has since grown a richer contract — verified against
`code.claude.com/docs/en/hooks.md`:

```json
{"hookSpecificOutput": {"hookEventName": "PreToolUse",
  "permissionDecision": "allow" | "deny" | "ask" | "defer",
  "permissionDecisionReason": "...", "additionalContext": "...", "updatedInput": {...}}}
```

`ask` escalates to the human via the permission prompt they are already looking at, and
**overrides auto-mode**. Today, overriding a shell-guard block costs a full round-trip:
Claude reports the block, the human reads the reason, copies the `!`-prefixed line the
guard hands back, and pastes it into the prompt to run it themselves. For an arm that
turns out to be a false positive — the repo has already shipped one, the `: >`
truncate-to-empty idiom tripping `/statusline-toggle`'s write recipe (fixed in `0.7.1`,
`CHANGELOG.md`) — `ask` would have let the human approve it in the same prompt they were
already reading, instead of costing a full paste-and-rerun cycle. Same safety posture for
arms that stay on the deny channel, less friction for the ones that move to the ask
channel.

The catch: `ask` overriding auto-mode is exactly the property that makes it *unsafe* to
assume in a background or headless session, where the harness's own docs were silent on
what happens when there is no human to answer the prompt. This repo runs background
subagents routinely (see the `voice-notify` `SubagentStop`/waiting-cue work) and the same
harness increasingly runs headless (`-p`, scheduled/cron agents). If `ask` had blocked
indefinitely or spammed retries in that mode, tiering the guards would have silently traded
a loud, safe failure (deny + explicit override) for a hang or a flood — worse than doing
nothing. That was why this started as P3, gated behind an experiment before implementation.
The experiment (`tasks.md` §1) now shows `ask` degrades cleanly to deny-with-reason in
headless mode — no hang, no flood — so that risk did not materialize for the scope tested.
Interactive-prompt behaviour is not independently verified here and is called out as a
scope caveat above and in `design.md` Decision D3, not assumed away.

## What Changes

*(The Task 1 go/no-go gate has passed — see `tasks.md` §1 and `design.md` Decision D3.
Everything below is now cleared to implement; no task in `tasks.md` §2+ has started yet.)*

- **`shell-guard` splits its arms across two channels on AXIS 2 (`channel: deny | ask` —
  can a human meaningfully approve this specific command?).** The **deny channel** keeps
  the existing `deny()` path unchanged (exit 2 + stderr): recursive delete of a protected
  path, `dd`/redirect onto a raw disk device, `mkfs`/`wipefs`/`newfs`/destructive
  `diskutil`, fork bomb, network download piped into an interpreter (`curl|sh`), and
  system halt/reboot (`reboot`/`shutdown`/`halt`/`poweroff`). The **ask channel** moves to
  `permissionDecision: "ask"` (JSON on stdout, exit 0): `chmod 777`, the `: >` truncate
  idiom, privilege escalation (`sudo`/`doas`/`su`/…), and `eval` — except when `eval`'s
  own argument contains a download command word (`curl`/`wget`/`fetch`), which stays on
  the deny channel for the same reason `curl|sh` does: a human at the prompt sees the URL,
  not the payload it serves. The full arm-by-arm assignment and the reasoning behind each
  is in `design.md`.
- **Two independent axes, not one.** `guard-block-message-contract` owns AXIS 1
  (`alternative: named | none` — does a safe variant of this action exist to name in the
  message?); this proposal owns AXIS 2 (`channel: deny | ask`, above). The proof case that
  they are independent, not the same question twice: `curl|sh` is `alternative: named`
  (download, read, then run is worth telling the model) but `channel: deny` (a human at a
  prompt sees the URL, not the payload, so approval would be uninformed). Neither axis is
  named "catastrophic" or "hygiene" — those words described a single collapsed axis and
  now belong to neither. See `design.md`'s "Two independent axes" section for the full
  argument.
- **`git-guard` stays all-`deny`.** Argued explicitly in `design.md`, not assumed: this
  repo's own convention (`CLAUDE.md`, this repo's `git-guard` policy 2, and prior session
  memory on config-routed push blocking) is that a push to `main`/`master` cannot
  originate from a Claude session at all. `ask` would turn that bright line into a
  one-click bypass sitting in the same prompt the human is already approving other tool
  calls in — a materially different (weaker) guarantee than today's forced context-switch
  to a human-typed `!`-line.
- **No new conf key.** An earlier draft planned a deny-only override conf key for headless
  sessions. Dropped: the experiment shows the platform already degrades `ask` to a blocked
  command automatically in headless mode, so a guard-side override would be redundant for
  the risk it was built to cover. `design.md` Decision D4 records this as a rejected
  alternative and flags an open, separate question (a deny-only override for interactive
  operators who want it anyway) that this proposal does not resolve.
- **`updatedInput` is explicitly rejected.** The hook API lets a guard silently rewrite
  the command it just evaluated (e.g., `chmod 777` → `chmod 755`) before it runs. This
  proposal does not use that field anywhere, for either guard, for any arm. Reasoning in
  `design.md`.
- **Detection logic is untouched.** Every existing arm, every existing regex, every
  existing test case in `cases.tsv` keeps matching exactly what it matches today. This
  proposal only changes which of the two output channels (exit-2/stderr vs. JSON stdout
  with `permissionDecision`) a matched arm uses — it does not add, remove, or loosen a
  single detection rule, and it does not re-enter the wrapper/evasion arms race the
  guards were deliberately rewritten out of in 2026-06. The one exception worth naming
  precisely: the `eval` arm's *channel* (not its detection) now depends on whether its
  already-captured argument text contains a download command word — the `eval` arm still
  matches exactly what it matches today; only which channel that match resolves to changes
  for that sub-case. `design.md` verifies this against `detect_net_pipe()`'s actual
  behaviour (it splits on `|` and so does not catch `eval "$(curl …)"` today) before
  asserting it, and frames the fix as the same "a human can't approve a payload they can't
  see" principle applied consistently, not new evasion-chasing.
- **The `!`-paste escape hatch is preserved** on every arm, `ask` or `deny` — `ask`
  changes how a human is prompted, not the fallback text a block hands back.
- **Message wording is out of scope.** `permissionDecisionReason` will carry whatever
  string contract the sibling `guard-block-message-contract` proposal defines (AXIS 1,
  memo P1). This proposal depends on that contract existing but does not define or
  redefine wording.

## Capabilities

### Added Capabilities

- `guard-decision-tiers`: the contract for which `permissionDecision` value each guard
  arm returns — AXIS 2 channel assignment (deny-channel arms, ask-channel arms, and the
  `eval`/download-fetch exception), git-guard's all-deny stance and its rationale, and the
  invariants carried over unchanged from the binary model (escape hatch, fail-open on
  missing `jq`, unchanged detection logic, no `updatedInput` rewriting).

## Impact

- **Verified:** the Task 1 go/no-go gate (`tasks.md` §1) has passed — **GO, scoped to
  headless `claude -p`** (Claude Code 2.1.220, model haiku; 3 runs, 11–15s each, exit 0,
  one hook fire, no hang, no spam). Full record and the interactive-scope caveat in
  `tasks.md` §1 and `design.md` Decision D3. Implementation (`tasks.md` §2+) has not
  started — every task there is unchecked.
- **Depends on:** `guard-block-message-contract` (AXIS 1, memo P1) for the actual wording
  carried in `permissionDecisionReason`; this proposal only fixes which
  `permissionDecision` value (AXIS 2) applies, not what the reason text says. See
  `design.md`'s "Two independent axes" section for the split and its proof case.
- **Scripts:** `plugins/shell-guard/scripts/shell-guard.sh` gains a JSON-stdout path for
  the ask-channel arms and a channel-selection check on the `eval` arm's argument (deny
  when it contains a download command word); `plugins/git-guard/scripts/git-guard.sh` is
  unchanged in behaviour (the deny-only decision is a documented stance, not a code
  change), though its header comment may gain a note that `ask` was considered and
  rejected, for future readers.
- **Conf files:** none. An earlier draft's `SHELL_GUARD_DENY_ONLY` key is dropped — the
  Task 1 result shows headless sessions already degrade `ask` to a blocked command
  automatically, at the platform level, so a guard-side override is redundant for the risk
  it was built to cover. See `design.md` Decision D4 for the rejected-alternative writeup
  and its open question about a possible different use case. `~/.claude/git-guard.conf` is
  unchanged.
- **Tests:** `plugins/shell-guard/tests/cases.tsv` and `run.sh` need a decision-channel
  assertion (currently only exit codes are asserted — a case that now exits 0 with
  `permissionDecision: ask` in its stdout JSON must not be misread as a plain allow), plus
  a case confirming `eval "$(curl http://x)"` stays on the deny channel.
  `plugins/git-guard/tests/*` are unaffected (no behaviour change).
- **Docs:** both plugin READMEs, `docs/shell-safety.md` (Layer 2/3 tables gain a
  decision-channel column), and `rules/shell-safety.md` if the escape-hatch wording needs
  updating for the ask path.
- **Manifests:** `plugins/shell-guard/.claude-plugin/plugin.json` version bump (minor —
  additive: new output channel) when the change ships; `git-guard`'s manifest is
  unaffected.
- **No new runtime dependency.** Still `jq` + `bash` only; fail-open on missing `jq` is
  preserved unchanged for both guards.
