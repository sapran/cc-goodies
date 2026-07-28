## Context

`shell-guard` splits its arms across two decision channels (deny / ask) under a criterion
recorded in `openspec/changes/archive/2026-07-26-guard-ask-escalation/design.md` Decision
D1: **deny** when the harm is irreversible, or when a human reading the command text at a
permission prompt could not tell what the command will actually do; **ask** when the harm
is reversible *and* fully disclosed by the command's own text.

The same proposal's Decision D2 evaluated an ask channel for `git-guard` and rejected it
outright, on three grounds: this repo's own convention that no write to `main`/`master`
originates from a Claude session; `ask` placing a `main`-push approval in the same
low-friction interface where routine tool calls are approved reflexively; and `git-guard`
having exactly one hazard class, leaving nothing to split.

D2 was right about this repo. What it did not separate is the difference between *what the
default should be* and *whether the user can express anything else*. `git-guard` already
has a configurable policy — `GIT_GUARD_MAIN_BRANCHES` chooses which branches are
protected, `GIT_GUARD_BLOCK_ALL_PUSH` chooses how strict pushing is — so channel policy is
the one dimension of its behaviour that is hard-coded. A published-plugin user whose
convention is "a local commit on `main` is fine, just never push it" has only two options
today: accept the full deny, or `GIT_GUARD_DISABLE=1`, which also disables the push arms
they want to keep. That is a genuine gap, and the workaround is strictly worse than the
setting being proposed.

## Goals / Non-Goals

**Goals:**

- Make the channel for one narrow class of arms expressible by the user.
- Keep shipped behaviour identical: the default stays `deny`, so this repo's dogfooding
  and the no-session-writes-to-`main` convention are untouched.
- Make the push guarantee *stronger and more explicit* than the requirement it replaces.
- Reuse `shell-guard`'s existing `ask` output contract exactly, rather than inventing a
  second message format for the same idea.

**Non-Goals:**

- Reversing Decision D2. The default channel does not change; only its expressibility.
- Making push configurable. This is excluded permanently, not deferred.
- Adding, widening, or narrowing any detection pattern. This change is channel selection
  only.
- Splitting `shell-guard`'s `SHELL_GUARD_EXTRA_PATTERNS` onto a user-selectable channel.
  That is the sibling gap noted in D1 and stays a separate proposal.

## Decisions

### Decision 1 — the setting governs on-branch writes only, never pushes

Push arms are excluded from configurability permanently. The reason is not tradition, it
is D1's *second* deny criterion: a human at an `ask` prompt cannot judge a push.

The command text does not disclose remote state, so it cannot reveal whether
`git push origin main` adds one commit or overwrites work someone else pushed an hour ago.
A destination-less `git push` does not even name its target branch — the guard resolves it
from `push.default` and `remote.<remote>.push` precisely because the text does not say
(`git-guard.sh:245-259`). Approving that is the same failure mode as approving
`curl … | bash`: the thing being approved is not visible in the thing being read.

There is a second, git-specific reason. Everything a local write does is recoverable
through the reflog; a push leaves the machine, reaches other clones, and can trigger CI or
a deploy before anyone notices. Local damage is reversible *in principle* and stays put;
published damage is neither.

*Alternative considered:* a third value such as `GIT_GUARD_PUSH_CHANNEL=ask`, for
symmetry. Rejected — symmetry is not a reason to offer a setting whose only effect is to
let a user approve something they cannot see. Leaving it out is a design statement, and
the spec states it as an unconditional guarantee so a future proposal must argue against
it explicitly rather than add it by analogy.

### Decision 2 — force `branch -f|-D|-M|-C` stays on the deny channel

The script currently classifies a force `branch` operation as `localwrite`
(`git-guard.sh:188-200`), so the mechanically simple choice would be to let the setting
cover it too. This design deliberately does not.

Three reasons. It is a different accident from the one the setting exists to soften: the
motivating case is "I forgot to switch branches and committed", whereas `branch -f main
<sha>` moves a protected branch pointer while the user is somewhere else entirely — an
action that is always deliberate about its target. It was closed as a bypass path once
already (recorded in session memory alongside the `rtk proxy git push` hardening), and
reopening it under a setting whose stated purpose is unrelated would undo that quietly.
And its blast radius is the branch pointer itself, not the working branch's history.

*Alternative considered:* a separate `GIT_GUARD_FORCE_BRANCH_CHANNEL`. Rejected as
speculative — no user has asked for it, and every additional channel setting multiplies
the number of guard states that must be tested.

### Decision 3 — an unrecognised value fails closed

Any value that is not exactly `deny` or `ask` is treated as `deny`. A typo (`ASK`, `Ask`,
`yes`, `1`) must not silently loosen the guard.

This differs from how `GIT_GUARD_DISABLE` and `GIT_GUARD_BLOCK_ALL_PUSH` are parsed —
those treat "set and not `0`" as on, because for them "on" is the *stricter* state. Here
the non-default value is the *looser* state, so the same permissive parsing would be
backwards. This asymmetry is deliberate and worth a comment in the script, since it will
otherwise read as an inconsistency.

### Decision 4 — port `ask()` from shell-guard rather than generalise it

`shell-guard.sh` already contains the `ask()` implementation, its severity-resolution
discipline (`ASK_PENDING`, first-ask-wins, never exit mid-scan), and the exact JSON shape.
The straightforward move is to copy that function into `git-guard.sh` and adapt the
message text.

*Alternative considered:* extracting a shared `lib/ask.sh` sourced by both guards.
Rejected for now. The two guards are deliberately independent single-file hooks with no
shared runtime; introducing a sourced library adds a failure mode (a missing or unreadable
library file) to two hooks whose most important property is that they degrade gracefully.
The duplicated function is roughly 20 lines. If a third consumer ever appears, revisit.

Note that `git-guard`'s control flow is simpler than `shell-guard`'s here: it evaluates
one action and returns, rather than scanning many segments where a later deny must
outrank an earlier ask. The severity-resolution machinery can therefore be simplified —
but the "never exit 0 mid-evaluation" discipline should be preserved in comments so a
future arm addition does not reintroduce the bug D1 records.

## Risks / Trade-offs

- **A user opts in and then loses the guarantee they thought they had** → The setting name
  says `LOCAL_WRITE` and the README must state plainly that an approved ask is a real
  write to the protected branch. The reason string names the branch explicitly.
- **An ask is approved reflexively, so the opted-in user gets little protection** → This is
  inherent to the ask channel and was the core of D2's objection. Mitigated by scope: the
  default is unchanged, so nobody gets this behaviour without asking for it, and pushes —
  the arms where reflexive approval would be most costly — cannot be opted in at all.
- **A local write approved on `main` is pushed later without a second thought** → Real, and
  the honest limit of this design: local damage in git persists until someone notices.
  The push arms remain deny, so the *session* cannot publish it; a human still can.
- **Test surface grows** → The existing git-guard harness asserts exit codes only. It gains
  a third assertion form (exit 0 **plus** `permissionDecision` JSON on stdout) and a second
  axis (each on-branch-write verb under both setting values). `shell-guard`'s harness
  already does this and can be used as the pattern.
- **Two guards drift in their `ask()` implementations** → Accepted consequence of Decision
  4. Mitigate by keeping the message substance identical and cross-referencing both
  functions in comments.

## Migration Plan

No migration. The default preserves current behaviour, so an existing installation that
sets nothing sees no change. Rollback is deleting the setting from
`~/.claude/git-guard.conf` or unsetting the environment variable; no state persists
elsewhere. `/git-guard-uninstall` already deletes the conf file, so the existing teardown
path covers this setting without modification — no new install verb is introduced, so the
repo's install ⇄ uninstall symmetry rule needs nothing new.

## Open Questions

- Should `/git-guard` (the control-panel command) offer to set this interactively, or only
  display it? Displaying it is clearly right; offering to *enable* the looser mode from
  inside a Claude session is arguably the wrong place to make that choice, since the whole
  point is that the human is deciding to trust themselves. Recommendation: display and
  document, but require the user to write the conf value themselves or approve an explicit
  diff, consistent with how the other guard commands confirm before writing.
- Does the sibling gap in `shell-guard` (user patterns are deny-only, D1's noted follow-up)
  want the same treatment, and should the two settings be named consistently if so? Not
  resolved here; flagged so the naming can be chosen once rather than twice.
