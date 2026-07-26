## Context

`rules/shell-safety.md` carries 11 advisory items across 4 sections (Command execution,
Credentials, Untrusted input & prompt injection, When in doubt). It is always-loaded via
symlink into `~/.claude/rules/`. This proposal trims it under the current
context-engineering guidance (drop what's inferable, drop defensive guardrails a capable
model no longer needs). The boundary between "keep" and "drop" isn't mechanical, so it's
recorded here.

## Decision D1 — the keep/drop test

One test, applied per line: does this state a fact about *this system's* hooks — what
`shell-guard`/`git-guard`'s pattern matching structurally cannot see, how the hook-input
contract behaves, or a workflow affordance the hooks expose — that a capable model
cannot infer on its own? Or is it general shell/security hygiene the model already
defaults to, and/or something the hooks already enforce outright, and/or something
already asserted in the user's own private `security.md`?

The first survives; the second is dropped, on the reasoning that restating either buys
zero incremental safety (the hook already blocks it, or the model already avoids it) and
costs always-on context in every session in every project. Full per-line result is in
`proposal.md`'s classification table (1 keep / 10 drop / 2 add).

## Decision D2 — the credentials and prompt-injection bullets drop despite being "safety" topics

8 of the 10 dropped items sit under headings that read as safety-critical (Credentials;
Untrusted input & prompt injection), which makes them feel riskier to cut than, say, the
`/tmp`-is-untrusted line. They are dropped anyway:

- None of them describe anything `shell-guard`/`git-guard` can or can't see — they are
  pure model-judgment prose, exactly the "defensive guardrails a capable model no
  longer needs" category the context-engineering guidance targets, not a hook-contract
  fact.
- They duplicate the user's own private `~/.claude/rules/security.md` line for line
  (its Credential Handling and Prompt Injection Defense sections cover the same ground).
  Asserting the same rule twice, from two files, in the same loaded context is pure
  duplication, not added safety.
- Dropping them touches zero enforcement — they were never hook-enforced to begin with,
  so there is no enforcement regression, only removal of prose duplication. Nothing a
  guard currently blocks becomes unblocked by this change.

## Decision D3 — the hard constraint (memo "do NOT change" item 1)

Advisory prose is prunable; the guards are not. The two are different risk models:
`shell-guard`/`git-guard` defend against the tail (a mis-parsed path, a malformed
variable, an injected instruction), not the median, and their entire model-facing
surface is a five-line block message, not a system prompt. A thinned advisory file costs
a capable model nothing — it already avoids the median mistake. A thinned guard costs
the user their home directory on the one time the tail case happens. This proposal
touches zero lines of `plugins/shell-guard/scripts/*.sh` or
`plugins/git-guard/scripts/*.sh`, and the `shell-safety-advisory` spec states the
non-licence explicitly so a future reader can't cite this change as precedent for
thinning guard detection logic.

## Non-goals

- Not re-opening `guard-block-message-contract` or `guard-ask-escalation` — separate
  proposals in the same ranked set, targeting the guards' own model-facing messages and
  decision tiers, not this file.
- Not editing anything under `~/.claude/` (the user's private global config), even where
  its content overlaps `security.md` — noted as rationale only.
