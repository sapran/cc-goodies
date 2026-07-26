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

## Two independent axes (cross-reference: `guard-ask-escalation`)

An earlier draft of this proposal, and the sibling proposal `guard-ask-escalation`, both
used "catastrophic" and "hygiene" as tier names. They were answering two *different*
questions with the same words — which is worse than answering with no words at all, since
a reader would assume one classification drives both the message content and the
permission routing, when in fact two independent axes are in play. Neither word appears in
this proposal as a tier name any more; both are retired to plain quotation of the script's
own comments where that quotation is load-bearing (see "Open questions" below).

- **AXIS 1 — `alternative: named | none`** (owned by *this* proposal,
  `guard-block-message-contract`). Question: **does a safe variant of this action exist to
  name in the message?** This axis governs the block message's second line only — the
  ⚠️ irreversibility framing (`alternative: none`) versus a named safe alternative
  (`alternative: named`). It says nothing about how the guard routes the decision.
- **AXIS 2 — `channel: deny | ask`** (owned by `guard-ask-escalation`, a separate,
  not-yet-decided proposal). Question: **can a human meaningfully approve this specific
  command from a permission prompt?** This axis governs
  `hookSpecificOutput.permissionDecision` — a hard block (`deny`) versus routing to the
  existing human-approval prompt (`ask`). It says nothing about what the message names as
  an alternative.

Neither axis can be derived from the other in general. The proof case is a network
download piped into an interpreter (`curl … | sh` and its `wget`/`fetch`/`bash`/`python`/…
siblings):

- **AXIS 1: `alternative: named`.** A safe variant is nameable and worth telling the
  model — download to a file, read it, then run it as a separate reviewed step (D1,
  below).
- **AXIS 2: `channel: deny`.** A human looking at a permission prompt sees the *command
  text* — the URL and the pipe — not the payload the URL serves. Approving
  `curl https://example.com/install.sh | sh` from the prompt is not an informed decision;
  the human cannot evaluate what they are approving. So this arm stays a hard block
  regardless of how good the named alternative is.

`curl|sh` is therefore `alternative: named` **+** `channel: deny` — proof that naming a
safe alternative (axis 1) and permitting human approval (axis 2) are independent
judgments, not the same judgment expressed twice. A reader who re-collapses these into one
"how bad is it" scale will misapply either this proposal's message contract or
`guard-ask-escalation`'s routing decision.

Two more rows make the independence concrete (the axis-2 values below are
`guard-ask-escalation`'s assignment, taken as given here, not re-derived):

| Arm | AXIS 1 (`alternative`) | AXIS 2 (`channel`) |
|---|---|---|
| `sudo` (and the privilege-escalation family) | `named` — run it without `sudo` | `ask` |
| `reboot`/`halt` (and the rest of the system-halt family) | `none` — no narrower "restart the host" exists | `deny` |
| `curl … \| sh` (network pipe into an interpreter) | `named` — download, read, run reviewed | `deny` |

`sudo` and `curl|sh` share an axis-1 value (`named`) but land on opposite axis-2 values
(`ask` vs. `deny`) — the clearest single demonstration that the axes are orthogonal: naming
a safe alternative does not imply a human can safely approve the command from a prompt,
and vice versa.

**Composition, not competition.** This proposal owns axis 1 and the message text only; it
does not set `permissionDecision` anywhere (see "Open questions" below). When
`guard-ask-escalation` lands and starts setting `permissionDecision: "ask"` for axis-2
`ask` arms, the reason string surfaced to the human at that approval prompt is
`permissionDecisionReason` — the same field, and the same message contract, this proposal
defines. The two proposals compose: this one decides what the message says, that one
decides which channel delivers it. Implementing `guard-ask-escalation` should not require
re-deriving message text, and implementing this proposal does not need to wait on
`guard-ask-escalation`'s routing decision.

## Decision D1 — `alternative: named` vs. `alternative: none`, derived from a single test

Every current `shell-guard` `deny()` call site was audited from the live script
(`plugins/shell-guard/scripts/shell-guard.sh`). The class assignment applies axis 1's test
(above): **does a safe variant of this action exist to name in the message?** If no — the
only paths are "don't run it" or the human confirms via the escape hatch — the arm is
classed `alternative: none` and keeps the irreversibility framing with no offered
alternative, exactly as the script's own comment already argues (*"These are CATASTROPHIC
commands by design, so we front the line with an explicit irreversibility warning — never
a frictionless one-paste nuke,"* `shell-guard.sh:90-91`). If yes — a concrete, nameable
alternative exists — the arm is classed `alternative: named` and the message names it
instead of claiming irreversibility.

**`alternative: none`** (irreversible; no safe variant of the same action):

| Arm (script location) | Current reason string |
|---|---|
| `rm` recursive delete of a protected path | `"recursive delete of a protected path"` |
| `dd` onto a raw disk device | `"dd onto a raw disk device"` |
| `>`/`>|` redirect onto a raw disk device (`DEV_RE`) | `"redirect onto a raw disk device"` |
| `mkfs`/`mkfs.*`/`wipefs`/`newfs`/`newfs_*` | `"filesystem creation/wipe ($c)"` |
| destructive `diskutil` (`eraseDisk`, `reformat`, `zeroDisk`, `secureErase`, `partitionDisk`, `eraseall`, `apfs delete*`/`erase*`) | `"destructive diskutil ($1)"` / `"(apfs $2)"` |
| fork bomb (`FORK_RE`) | `"fork bomb"` |
| `reboot`/`shutdown`/`halt`/`poweroff` | `"system halt/reboot ($c)"` |

`reboot`/`halt` is placed here even though it is not literally "irreversible" in the
data-loss sense `rm -rf /` is: there is no narrower variant of "restart the host this
session runs on" that preserves the action's purpose while being safer — the only
legitimate path is a human doing it deliberately, outside the session, which is exactly
what the escape hatch already offers. It fails axis 1's test the same way the
disk-destruction arms do, so it gets the same framing.

The privilege-escalation family does *not* fail that test — see the `alternative: named`
table below for why `sudo` moved out of this class.

**`alternative: named`** (a concrete safe variant exists):

| Arm | Current reason string | Safe alternative to name |
|---|---|---|
| `chmod 777`/`0777` | `"chmod 777 — world-writable permissions"` | `chmod 755` (or the narrowest mode the task needs) |
| `: >` truncate (`TRUNC_RE`) | `` "truncate a file to empty (\`: >\`)" `` | `printf '' >` |
| `eval` | `"eval — arbitrary code execution"` | run the intended command directly, without the `eval` indirection |
| network download piped into an interpreter (`detect_net_pipe`) | `"network download piped into a shell"` | download to a file, read it, then run it as a separate reviewed step |
| `sudo`/`doas`/`su`/`runuser`/`pkexec`/`gosu`/`sudoedit`/`setpriv` | `"$c — privilege escalation"` | run the command directly, without `sudo` (or whichever privilege-escalation prefix matched) |

The architecture memo's original four-arm set in this class — `chmod 777`, `: >`, `eval`,
`curl|sh` — maps directly onto the first four rows above; the memo's worked examples give
alternatives for three of the four (`chmod 777 → chmod 755`, `: > → printf '' >`,
`curl|sh → download, read, run reviewed`) but not for `eval` — this design supplies one,
since the requirement (`Requirement: Commands classed alternative: named name a concrete
safe alternative`) needs a nameable alternative for every `alternative: named` arm, not
just three of four.

The privilege-escalation family is a fifth arm added to this class in this revision. An
earlier draft folded it into `alternative: none` on the same "no narrower form exists"
reasoning used for `rm -rf /` and `reboot` — but that reasoning fails axis 1's actual test
for `sudo`: axis 1 asks whether a safe variant exists to *name*, and `sudo`'s safe variant
is literally "run it without `sudo`" — exactly the shape of a named alternative. This is
the one substantive reclassification in this revision; `reboot`/`halt` was re-checked
against the same question and stays `alternative: none`, since no narrower "restart the
host" form exists. Note that this reclassification is purely an axis-1 change: whether a
human can meaningfully approve a `sudo` command from a permission prompt is axis 2's
question, owned by `guard-ask-escalation` (see the cross-reference section above) — axis 1
saying `named` here does not imply or depend on axis 2's `channel` value for the same arm.

`git-guard`'s message space is a single class (a write would land on a protected branch)
and needs no `alternative: named`/`alternative: none` split — it already earns its
irreversibility-adjacent framing (naming the exact branch, the routing mechanism, and an
alternative workflow) through specificity rather than a blanket warning line, which is why
it already reads as the reference implementation.

## Decision D2 — the EXTRA arm is a third, unclassifiable case

`SHELL_GUARD_EXTRA_PATTERNS` (`shell-guard.sh:273-280`) lets the user supply arbitrary ERE
patterns at install time. The guard has no way to know, at match time, whether a given
user pattern is `alternative: none`, `alternative: named`, or neither — a user might block
`git clean -fdx` (the README's own example) or something far more or less severe. Forcing
it into one of the two axis-1 classes above would mean either fabricating an
irreversibility claim the guard cannot support, or fabricating a safe alternative it
cannot verify — both worse than today's generic message. The fix scoped to this arm is
narrower and fully justified by defect #1 alone: name the literal pattern that matched,
keep the framing neutral, and still carry the variants-also-blocked clause and the escape
hatch every other block carries. This is a message-text change only — the
`[[ "$seg" =~ $pat ]]` matching mechanism is untouched.

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
whether to run it. This is unconditional, not a judgment call by class — it applies
regardless of axis-1 class (`alternative: named` or `alternative: none`).

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
- **`permissionDecision: "ask"` tiering is out of scope for this proposal.** Axis 2
  (`channel: deny | ask`, cross-referenced above) is `guard-ask-escalation`'s job, not this
  one's — it changes the safety posture and needs its own testing (notably: whether `ask`
  blocks indefinitely in a headless/background session). This proposal stays entirely on
  the exit-2 + stderr path and does not set `permissionDecision` anywhere, for any arm —
  including `sudo`, whose axis-1 `alternative: named` classification in D1 says nothing
  about whether `guard-ask-escalation` eventually routes it to `ask` or leaves it `deny`.
- **The "no safe variant of `rm -rf /`" framing is the script's own stated design, not
  copied text — and the word "CATASTROPHIC" in the quote below is the script's own comment
  wording, not this proposal's axis-1 label.** The literal phrase used in some framings of
  this problem ("there is no safe variant of `rm -rf /`") does not appear in
  `shell-guard.sh`; the script's actual comment (`shell-guard.sh:90-91`) says commands are
  "CATASTROPHIC ... by design" and warrant "an explicit irreversibility warning." D1 quotes
  that comment verbatim because it is where the `alternative: none` class's rationale comes
  from, not because this proposal names its axis-1 classes "catastrophic" and "hygiene" —
  it does not. The classes are `alternative: named` and `alternative: none` throughout;
  neither retired word appears anywhere else in this proposal.
