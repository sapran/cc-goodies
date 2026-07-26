## Why

> **Status: blocked on verification.** This proposal rests on one untested assumption
> about how Claude Code's `ask` permission decision behaves in a headless/background
> session. The architecture memo (`~/.claude/plans/how-would-you-improve-nested-cookie.md`,
> outline #6, ranked P3) explicitly ranks it "needs decision" and states it "requires
> testing before adoption." Nothing below is settled. Task 1 is the experiment that
> decides whether the rest of this proposal should be implemented at all; every later
> task is gated on its result.

`git-guard` and `shell-guard` are both binary today: a matched arm calls `deny()`, which
prints a reason to stderr and returns exit code 2. That is the *only* signal the hook API
has ever offered these guards — verified in both scripts' own header comments ("Exit
codes: 0 = allow, 2 = block … Any other code is a non-blocking error"). Every arm gets
the same treatment whether it is `rm -rf /` (irreversible, catastrophic) or `chmod 777`
(a permission hygiene issue, trivially reversible with `chmod 755`).

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
genuinely catastrophic arms, less friction for the hygiene ones.

The catch: `ask` overriding auto-mode is exactly the property that makes it *unsafe* to
assume in a background or headless session, where the harness's own docs are silent on
what happens when there is no human to answer the prompt. This repo runs background
subagents routinely (see the `voice-notify` `SubagentStop`/waiting-cue work) and the same
harness increasingly runs headless (`-p`, scheduled/cron agents). If `ask` blocks
indefinitely or spams retries in that mode, tiering the guards would silently trade a
loud, safe failure (deny + explicit override) for a hang or a flood — worse than doing
nothing. That is why this is P3 and why Task 1 is the experiment, not the implementation.

## What Changes

*(Contingent on the Task 1 go/no-go gate — see `tasks.md` and `design.md`. Nothing here
ships if the gate says no-go.)*

- **`shell-guard` tiers its arms into two decision classes.** Catastrophic/irreversible
  arms keep the existing `deny()` path unchanged (exit 2 + stderr): recursive delete of a
  protected path, `dd`/redirect onto a raw disk device, `mkfs`/`wipefs`/`newfs`/destructive
  `diskutil`, fork bomb, and network download piped into an interpreter (`curl|sh`).
  Hygiene/policy arms move to `permissionDecision: "ask"` (JSON on stdout, exit 0):
  `chmod 777`, the `: >` truncate idiom, privilege escalation (`sudo`/`doas`/`su`/…), `eval`,
  and system halt/reboot. The full arm-by-arm assignment and the reasoning behind each is
  in `design.md`.
- **`git-guard` stays all-`deny`.** Argued explicitly in `design.md`, not assumed: this
  repo's own convention (`CLAUDE.md`, this repo's `git-guard` policy 2, and prior session
  memory on config-routed push blocking) is that a push to `main`/`master` cannot
  originate from a Claude session at all. `ask` would turn that bright line into a
  one-click bypass sitting in the same prompt the human is already approving other tool
  calls in — a materially different (weaker) guarantee than today's forced context-switch
  to a human-typed `!`-line.
- **A new conf key forces deny-only behaviour** for shell-guard, for use in headless/
  background/CI contexts where nobody is watching the permission prompt — following the
  existing `env var → ~/.claude/shell-guard.conf → built-in default` precedence and the
  existing non-sourcing `conf_get` parser. Its default polarity (on by default vs. opt-in)
  is decided by the Task 1 experiment, not by this proposal.
- **`updatedInput` is explicitly rejected.** The hook API lets a guard silently rewrite
  the command it just evaluated (e.g., `chmod 777` → `chmod 755`) before it runs. This
  proposal does not use that field anywhere, for either guard, for any arm. Reasoning in
  `design.md`.
- **Detection logic is untouched.** Every existing arm, every existing regex, every
  existing test case in `cases.tsv` keeps matching exactly what it matches today. This
  proposal only changes which of the two output channels (exit-2/stderr vs. JSON stdout
  with `permissionDecision`) a matched arm uses — it does not add, remove, or loosen a
  single detection rule, and it does not re-enter the wrapper/evasion arms race the
  guards were deliberately rewritten out of in 2026-06.
- **The `!`-paste escape hatch is preserved** on every arm, `ask` or `deny` — `ask`
  changes how a human is prompted, not the fallback text a block hands back.
- **Message wording is out of scope.** `permissionDecisionReason` will carry whatever
  string contract the sibling `guard-block-message-contract` proposal defines (memo P1).
  This proposal depends on that contract existing but does not define or redefine wording.

## Capabilities

### Added Capabilities

- `guard-decision-tiers`: the contract for which `permissionDecision` value each guard
  arm returns — catastrophic-arm deny, hygiene-arm ask, git-guard's all-deny stance and
  its rationale, the non-interactive deny-only fallback, and the invariants carried over
  unchanged from the binary model (escape hatch, fail-open on missing `jq`, unchanged
  detection logic, no `updatedInput` rewriting).

## Impact

- **Blocked by:** the Task 1 headless-`ask` experiment. No implementation task in
  `tasks.md` runs before its go/no-go gate resolves.
- **Depends on:** `guard-block-message-contract` (memo P1) for the actual wording carried
  in `permissionDecisionReason`; this proposal only fixes which `permissionDecision` value
  applies, not what the reason text says.
- **Scripts** (if go): `plugins/shell-guard/scripts/shell-guard.sh` gains a JSON-stdout
  path for the hygiene arms and a new conf key; `plugins/git-guard/scripts/git-guard.sh`
  is unchanged in behaviour (the deny-only decision is a documented stance, not a code
  change), though its header comment may gain a note that `ask` was considered and
  rejected, for future readers.
- **Conf files:** `~/.claude/shell-guard.conf` gains the new key (name/default TBD by
  the Task 1 result, specified in `design.md`); `~/.claude/git-guard.conf` is unchanged.
- **Tests:** `plugins/shell-guard/tests/cases.tsv` and `run.sh` need a decision-channel
  assertion (currently only exit codes are asserted — a case that now exits 0 with
  `permissionDecision: ask` in its stdout JSON must not be misread as a plain allow).
  `plugins/git-guard/tests/*` are unaffected (no behaviour change).
- **Docs:** both plugin READMEs, `docs/shell-safety.md` (Layer 2/3 tables gain a
  decision-tier column), and `rules/shell-safety.md` if the escape-hatch wording needs
  updating for the ask path.
- **Manifests:** `plugins/shell-guard/.claude-plugin/plugin.json` version bump (minor —
  additive: new output channel, new conf key) if the change proceeds; `git-guard`'s
  manifest is unaffected.
- **No new runtime dependency.** Still `jq` + `bash` only; fail-open on missing `jq` is
  preserved unchanged for both guards.
