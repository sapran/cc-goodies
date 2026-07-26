## Context

`git-guard` and `shell-guard` are `PreToolUse`/`Bash` hooks (294 and 305 lines of bash,
147 combined test cases across `tests/cases.tsv`). The model never reads either script —
its only exposure is the ~5 lines `deny()` writes to stderr when a command is blocked.
Improving the guards for a stronger, faster-iterating model means treating that string as
a tool-result interface, not touching the detection logic behind it. This proposal is
scoped to that interface only, per the architecture memo's `guard-block-message-contract`
outline and its "What NOT to change" list.

## Verified facts — no non-retryable signal exists

The Claude Code hook API's `PreToolUse` response supports
`hookSpecificOutput.permissionDecision` ∈ `allow | deny | ask | defer`, plus
`permissionDecisionReason`, `additionalContext`, and `updatedInput`. None of these mark a
decision as non-retryable, and there is no separate signal that says "do not attempt a
variant of this command." A `deny` with exit 2 stops *this* invocation; it does not stop
the model from trying `rm -fr /` after `rm -rf /` was blocked. The only lever available to
discourage that is the content of the reason string itself — which is why the wording
defects in the current messages matter more on a model that iterates from failure faster,
not less.

This sets the ceiling for this change: it can make retrying *less attractive* (by naming
the rule, offering a real alternative, and stating that variants are also blocked) but it
cannot make retrying *impossible*. That would require either the guard's own
plan-mode/deny-list backstop (Layer 0/1, unchanged by this proposal) or a future
`permissionDecision: "ask"` tier (`guard-ask-escalation`, a separate, not-yet-decided
proposal) — neither is in scope here.

## Decision D1 — catastrophic vs. hygiene, derived from a single test

Every current `shell-guard` `deny()` call site was audited from the live script
(`plugins/shell-guard/scripts/shell-guard.sh`). The class assignment applies one test: **is
there a narrower or reparameterized form of the same command that achieves a plausible
legitimate goal safely?** If no — the only paths are "don't run it" or the human confirms
via the escape hatch — the arm is catastrophic and keeps the irreversibility framing with
no offered alternative, exactly as the script's own comment already argues (*"These are
CATASTROPHIC commands by design, so we front the line with an explicit irreversibility
warning — never a frictionless one-paste nuke,"* `shell-guard.sh:90-91`). If yes — a
concrete, nameable alternative exists — the arm is hygiene and the message names it
instead of claiming irreversibility.

**Catastrophic** (irreversible; no safe variant of the same action):

| Arm (script location) | Current reason string |
|---|---|
| `rm` recursive delete of a protected path | `"recursive delete of a protected path"` |
| `dd` onto a raw disk device | `"dd onto a raw disk device"` |
| `>`/`>|` redirect onto a raw disk device (`DEV_RE`) | `"redirect onto a raw disk device"` |
| `mkfs`/`mkfs.*`/`wipefs`/`newfs`/`newfs_*` | `"filesystem creation/wipe ($c)"` |
| destructive `diskutil` (`eraseDisk`, `reformat`, `zeroDisk`, `secureErase`, `partitionDisk`, `eraseall`, `apfs delete*`/`erase*`) | `"destructive diskutil ($1)"` / `"(apfs $2)"` |
| fork bomb (`FORK_RE`) | `"fork bomb"` |
| `reboot`/`shutdown`/`halt`/`poweroff` | `"system halt/reboot ($c)"` |
| `sudo`/`doas`/`su`/`runuser`/`pkexec`/`gosu`/`sudoedit`/`setpriv` | `"$c — privilege escalation"` |

`reboot`/`halt` and the privilege-escalation family are placed here even though they are
not literally "irreversible" in the data-loss sense `rm -rf /` is: there is no narrower
variant of "restart the host this session runs on" or of "gain elevated privileges" that
preserves the action's purpose while being safer — the only legitimate path in both cases
is a human doing it deliberately, outside the session, which is exactly what the escape
hatch already offers. They fail the same test the disk-destruction arms fail, so they get
the same framing.

**Hygiene** (a concrete safe variant exists):

| Arm | Current reason string | Safe alternative to name |
|---|---|---|
| `chmod 777`/`0777` | `"chmod 777 — world-writable permissions"` | `chmod 755` (or the narrowest mode the task needs) |
| `: >` truncate (`TRUNC_RE`) | `` "truncate a file to empty (\`: >\`)" `` | `printf '' >` |
| `eval` | `"eval — arbitrary code execution"` | run the intended command directly, without the `eval` indirection |
| network download piped into an interpreter (`detect_net_pipe`) | `"network download piped into a shell"` | download to a file, read it, then run it as a separate reviewed step |

This is the exact four-arm set the architecture memo names as hygiene
(`chmod 777`, `: >`, `eval`, `curl|sh`); the memo's worked examples give alternatives for
three of the four (`chmod 777 → chmod 755`, `: > → printf '' >`, `curl|sh → download, read,
run reviewed`) but not for `eval` — this design supplies one, since the requirement
(`Requirement: Hygiene commands name a concrete safe alternative`) needs a nameable
alternative for every hygiene arm, not just three of four.

`git-guard`'s message space is a single class (a write would land on a protected branch)
and needs no catastrophic/hygiene split — it already earns its irreversibility-adjacent
framing (naming the exact branch, the routing mechanism, and an alternative workflow)
through specificity rather than a blanket warning line, which is why it already reads as
the reference implementation.

## Decision D2 — the EXTRA arm is a third, unclassifiable case

`SHELL_GUARD_EXTRA_PATTERNS` (`shell-guard.sh:273-280`) lets the user supply arbitrary ERE
patterns at install time. The guard has no way to know, at match time, whether a given
user pattern is catastrophic, hygiene, or neither — a user might block `git clean -fdx`
(the README's own example) or something far more or less severe. Forcing it into one of
the two classes above would mean either fabricating an irreversibility claim the guard
cannot support, or fabricating a safe alternative it cannot verify — both worse than
today's generic message. The fix scoped to this arm is narrower and fully justified by
defect #1 alone: name the literal pattern that matched, keep the framing neutral, and
still carry the variants-also-blocked clause and the escape hatch every other block
carries. This is a message-text change only — the `[[ "$seg" =~ $pat ]]` matching
mechanism is untouched.

## Decision D3 — "variants will also be blocked" as the retry-loop terminator

Because no structured non-retryable signal exists (see the verified-facts section above),
the only way to tell the model that rewording won't help is to say so in the message
itself. Both guards already resolve past the surface form that would make a naive retry
work — `shell-guard` normalizes flag order, quoting, and common wrappers before judging;
`git-guard` resolves the destination branch through config routing, not just refspec text.
The guards already defeat the accidental variant; the message just never told the model
that. Adding one clause makes the existing detection behavior legible instead of adding
new detection behavior — no regex or resolution logic changes.

## Decision D4 — reject `updatedInput` silent rewriting

The hook API allows a `PreToolUse` response to rewrite the command in place via
`updatedInput` (e.g. silently turning `chmod 777 x` into `chmod 755 x` and letting it
run). This proposal does not use it, per the architecture memo's explicit "do NOT change"
list: a guard that silently edits the command it was asked to run is worse than one that
blocks it, because the user loses visibility into what actually executed — they would see
a Bash call in the transcript that does not match what the model believed it ran. The
alternative is named in text; the model (or, if it pastes the `!` line, the human) decides
whether to run it. This is unconditional, not a judgment call by class — it applies to
both catastrophic and hygiene arms.

## Decision D5 — git-guard gets alignment only, not a rewrite

`git-guard`'s message was audited line by line
(`plugins/git-guard/scripts/git-guard.sh:114-125` for `deny()`, and every call site at
`git-guard.sh:197-278`). It already names the resolved branch for every blocking path —
explicit refspec, same-name bare push, `push.default=upstream`/`tracking` routing,
`remote.<remote>.push` routing, `push --all`/`--mirror`, and `branch -f|-D|-M` — already
names the protected set, already offers an alternative workflow line, already includes the
`!`-paste escape hatch and the `GIT_GUARD_DISABLE`/`/git-guard` pointer. None of that is a
defect. The only gap relative to the new contract is the variants-also-blocked clause,
which this proposal adds as one line with no change to branch resolution or routing logic.

## Open questions / non-goals

- **This does not close the retry loop, only shortens it.** A sufficiently determined
  model (or an actively evading one) can still ignore the message and try again; the
  guards were deliberately rewritten in 2026-06 to stop chasing that arms race, and plan
  mode (Layer 0) remains the backstop for deliberate evasion. This proposal targets the
  *aligned-but-uninformed* retry, not adversarial behavior.
- **`permissionDecision: "ask"` tiering is out of scope.** Routing hygiene arms to the
  human's existing permission prompt instead of a hard block-and-retry cycle is a plausible
  further improvement (`guard-ask-escalation` in the architecture memo), but it changes
  the safety posture and needs its own testing (notably: whether `ask` blocks indefinitely
  in a headless/background session). This proposal stays entirely on the exit-2 + stderr
  path and does not set `permissionDecision` anywhere.
- **The "no safe variant of `rm -rf /`" framing is the script's own stated design, not
  copied text.** The literal phrase used in some framings of this problem ("there is no
  safe variant of `rm -rf /`") does not appear in `shell-guard.sh`; the script's actual
  comment says commands are "CATASTROPHIC ... by design" and warrant "an explicit
  irreversibility warning." This design treats that comment as the source of the
  catastrophic-class rationale, not a paraphrase found verbatim in the code.
