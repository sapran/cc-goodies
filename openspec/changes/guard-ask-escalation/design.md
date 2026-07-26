# Design — guard-ask-escalation

## Status

**Verified — Task 1 passed.** The go/no-go gate (`tasks.md` §1) has been run: a throwaway
probe hook returning `permissionDecision: "ask"` for every Bash call, driven by `claude -p`
(Claude Code 2.1.220, model haiku), across three headless runs — default permission mode,
`--permission-mode acceptEdits`, `--permission-mode bypassPermissions` — one Bash call
each. Every run resolved in 11–15s at exit 0, with exactly one hook fire and the command
blocked with its reason surfaced to the model: no hang, no retry spam, and `ask` held even
under `bypassPermissions` (confirming the docs' "overrides auto-mode" claim). Full per-run
detail and the verdict are in Decision D3 below, including exactly what scope this verdict
covers and does not cover.

**Scope caveat (carried forward, not resolved by the experiment).** Only headless
`claude -p` was exercised. An `ask` fired inside a subagent of a live *interactive*
session, or at the top level of an interactive session, was **not** tested — the
documented interactive behaviour (a permission prompt a human answers) is assumed from
`code.claude.com/docs/en/hooks.md`, not independently verified here. See Decision D3.

## Context

Both `shell-guard.sh` and `git-guard.sh` are `PreToolUse`/`Bash` hooks. Today both use
exactly one mechanism to stop a command: exit code 2, with the reason on stderr (verified
in both scripts' header comments — "Exit codes: 0 = allow, 2 = block … Any other code is a
non-blocking error in the hooks API, so we never use one to deny."). Claude sees the block,
reports it, and the human either accepts that or pastes the `!`-prefixed override line the
`deny()` helper hands back in both scripts.

Claude Code's hook API supports a richer contract than either script uses. Verified
against `code.claude.com/docs/en/hooks.md`:

```json
{"hookSpecificOutput": {"hookEventName": "PreToolUse",
  "permissionDecision": "allow" | "deny" | "ask" | "defer",
  "permissionDecisionReason": "...", "additionalContext": "...", "updatedInput": {...}}}
```

- `allow` — the tool runs; `permissionDecisionReason` is not shown to the user in the
  same way a block reason is (this is not the interesting case for guards).
- `deny` — blocks the tool call; the reason is what Claude sees (functionally similar to
  today's exit-2/stderr path, but delivered as JSON on stdout with exit 0 instead).
- `ask` — escalates to the human via the permission prompt, **and overrides auto-mode**
  (i.e., it can interrupt a session running with `defaultMode` other than `plan`, which
  otherwise wouldn't stop for a prompt at all). `permissionDecisionReason` is shown to the
  human at the prompt.
- `defer` — falls through to the harness's normal permission flow (as if the hook hadn't
  run at all for this decision). Not used anywhere in this proposal — noted for
  completeness, since the contract was evaluated in full rather than cherry-picked.
- `updatedInput` — lets a hook rewrite the tool call's input before it runs. Evaluated and
  explicitly rejected — see Decision D5.

This proposal is scoped to the `allow`/`deny`/`ask` axis for `shell-guard`, and to keeping
`git-guard` exactly as it is today (all `deny`, no code change).

## Two independent axes (cross-reference to `guard-block-message-contract`)

Two sibling proposals classify the same guard arms, but along two different, independent
questions — they must not collapse into one taxonomy, and this document deliberately avoids
naming either side "catastrophic" or "hygiene," since those words used to describe a single
collapsed axis and now belong to neither one:

- **AXIS 1 — `alternative: named | none`**, owned by `guard-block-message-contract`.
  Question: *does a safe variant of this action exist to name in the message?*
- **AXIS 2 — `channel: deny | ask`**, owned by **this proposal**. Question: *can a human
  meaningfully approve this specific command?*

**Proof the axes are independent:** `curl … | bash` (network download piped into an
interpreter) is `alternative: named` on AXIS 1 — "download it, read it, then run it as a
separate step" is a real, tellable safe path, and `guard-block-message-contract` names it.
But it is `channel: deny` on AXIS 2 — a human reading the command text at an `ask` prompt
sees the URL, not the payload the URL serves at run time, so an `ask` approval there would
be uninformed, not a real safety gate. A command can score `named` on one axis and `deny`
on the other; the two questions do not imply each other, and a future reader must not
re-collapse them into a single "how bad is this" scale.

`permissionDecisionReason`'s actual wording — including whatever text AXIS 1 contributes
for arms with a named alternative — is entirely `guard-block-message-contract`'s territory
(memo P1). This proposal only fixes which `permissionDecision` value (AXIS 2: `deny` or
`ask`) a given arm resolves to; it neither defines nor redefines message text.

## Decision D1 — shell-guard's AXIS 2 channel assignment (`deny` vs. `ask`)

**Criterion.** An arm resolves to the **deny channel** when the harm it prevents is
irreversible at the OS/data/hardware level (data or a filesystem is gone, a disk is
wiped), is disruptive in a way no narrower variant could soften, **or** when a human
reading the command text at an `ask` prompt could not actually tell what the command will
do (so an `ask` approval would be uninformed, not a real safety gate). An arm resolves to
the **ask channel** when the harm is reversible and bounded to something the command's own
text already discloses, so a human glancing at the prompt has what they need to decide.

This is a judgment call the memo does not fully make for every arm — it hands over four
explicit examples per side and leaves the rest to be worked out here, against the real arm
list in the script (not guessed).

### Arm-by-arm assignment (every real arm in `shell-guard.sh`)

| Arm (as matched in the script) | Channel | Reasoning |
|---|---|---|
| Recursive delete of a protected path (`rm -rf`/`-fr`/`--no-preserve-root` on `/`, `~`, `$HOME`, a top-level system dir, or `$HOME`-cwd glob-all) | **deny** | Irreversible data loss at scale. Explicit in the memo's deny-channel examples. |
| `dd … of=/dev/disk*` etc. (raw disk device) | **deny** | Irreversible hardware-level overwrite. Explicit in the memo. |
| `mkfs`/`mkfs.*`/`wipefs`/`newfs`/`newfs_*` | **deny** | Same class as `dd` to a device — irreversible filesystem destruction. Explicit in the memo (`mkfs`); generalized to its siblings in the same `case` arm. |
| Destructive `diskutil` (`eraseDisk`, `eraseVolume`, `reformat`, `zeroDisk`, `secureErase`, `partitionDisk`, `eraseall`, `apfs delete*`/`erase*`) | **deny** | Not named in the memo but is the macOS-native sibling of `mkfs`/`dd`-to-device — same irreversibility, same criterion. |
| Redirect onto a raw disk device (`> /dev/disk0`, `>| /dev/rdisk1`, …) | **deny** | Same irreversibility as the `dd` arm; it is the `DEV_RE` structural check the script explicitly keeps "KEEP IN SYNC" with the `dd` arm's `of=` glob — they are one hazard class in the code itself. |
| Fork bomb (`:(){ :|:& };:` and renamed variants) | **deny** | Explicit in the memo. Also fails the "informed `ask`" half of the criterion for a different reason: a live fork bomb can degrade the machine badly enough that the very prompt asking for permission may never render or be answerable — `ask` is not a safe fallback for a hazard that can prevent its own approval from being seen. |
| Network download piped into an interpreter (`curl`/`wget`/`fetch` stage → `sh`/`bash`/`zsh`/`dash`/`ksh`/`python`/`perl`/`ruby`/`node`/`php`) | **deny** | Not in the memo's four examples — a deliberate call, not an oversight. The command text a human sees at an `ask` prompt is `curl URL \| bash`; the actual payload that will execute is **not** visible in that text — it lives at a URL, fetched at run time, and can be anything, including everything else in this table's deny column. See the AXIS 1/AXIS 2 proof case above: this arm is `alternative: named` (download, read, then run) and `channel: deny` at the same time. |
| System halt/reboot (`reboot`/`shutdown`/`halt`/`poweroff`) | **deny** | Reassigned from an earlier draft's `ask` — the user's explicit call. No narrower variant exists to disclose or approve: it is binary, not parameterizable like `chmod 777` → `chmod 755`. And unlike `chmod`, its blast radius is not "one file" — it destroys the current session and any running background work the instant it executes, which is not a decision that fits a one-click approval even though the command text is fully legible. Disruptive-and-irreversible-to-the-session is enough to keep it on the deny channel under this design's criterion, even without data loss. |
| Privilege escalation (`sudo`/`doas`/`su`/`runuser`/`pkexec`/`gosu`/`sudoedit`/`setpriv`) | **ask** | `sudo` is explicit in the memo; generalized to the whole arm (the script already treats all eight as one `case` branch, one reason string) — the user's explicit call. Its safe alternative is literally "run it without sudo," and a human can judge a specific invocation on sight; this matches the repo's own workflow — e.g. `brew install jq`-style setup commands a human routinely approves inline. (Whatever runs *under* `sudo` might itself be opaque — same "can't see the payload" problem as `curl\|sh` — but that is a pre-existing detection gap this proposal does not attempt to close, distinct from the escalation arm itself.) |
| `eval` | **ask, with one exception** | Explicit in the memo. `eval`'s argument is ordinarily present in the command text the human is reading (e.g. `eval "some code"`), so — unlike a piped download — the human usually *can* read what will run. The exception, closing a hole an earlier draft only flagged, is below. |
| `chmod 777`/`0777` | **ask** | Explicit in the memo. Trivially reversible (`chmod 755`) and fully disclosed in the command text. |
| `: > file` (truncate-to-empty idiom) | **ask** | Explicit in the memo, and the specific motivating case: this is the arm that produced a real false positive (`/statusline-toggle`'s write recipe, `CHANGELOG.md` `0.7.1`) before the recipe was rewritten to `printf '' >`. Note this is a *deliberate exception* to a strict reading of the irreversibility half of the criterion — the file's prior contents genuinely are gone once this runs, no different in kind from `rm`. It stays on the ask channel anyway because (a) the blast radius is one file, not a filesystem, (b) it is the arm the repo has direct evidence collides with legitimate tooling, and (c) `ask` turning a known false-positive class into a one-prompt override — instead of an exit-2 report-and-repaste cycle — is the concrete, already-observed benefit this whole proposal exists to capture. |
| `SHELL_GUARD_EXTRA_PATTERNS` (user-configured ERE patterns) | **deny (unchanged)** | Out of this taxonomy by design: the guard has no way to know the severity of a user's own pattern, so channeling it would be a guess. Kept on the existing `deny()` path — identical to today's behaviour — rather than inventing a severity flag for user patterns, which would be new surface this proposal doesn't need. A user who wants their custom pattern to `ask` instead of `deny` has no way to express that yet; noted as a possible follow-up, not built here. |

Every row above is the *existing* detection logic (same `case` arms, same regexes, same
`eval_stage`/`evaluate_segment` structure in `shell-guard.sh`) — this table only assigns,
per already-matched arm, which of the two output paths (`deny()` vs. a new `ask()`) fires.
No pattern is added, removed, widened, or narrowed.

### `eval`'s exception: a download-fetching payload stays on the deny channel

An earlier draft of this table flagged `eval "$(curl http://x)"` (the repo's own
`eval_curl` test case, `plugins/shell-guard/tests/cases.tsv`) as "known imprecision" —
inheriting `ask` from the `eval` arm despite fetching remote code. Under this design's own
criterion that is wrong, for the same reason `curl | bash` is wrong: the human reading the
`ask` prompt sees `eval "$(curl http://x)"` — the URL, not the payload that URL serves at
run time. Approving that `ask` is exactly as uninformed as approving `curl … | bash`; the
`eval` wrapper doesn't change what the human can and can't see.

Verified before asserting it, against the actual script rather than the memo's
"most likely" framing: `detect_net_pipe()` (`plugins/shell-guard/scripts/shell-guard.sh`,
the pipeline-stage splitter around lines 229–250) splits the segment text on literal `|`
characters to find a download stage feeding an interpreter stage. `eval "$(curl http://x)"`
contains no `|` — the fetch-then-execute happens through command substitution and `eval`,
not a pipe — so `detect_net_pipe` does not, and structurally cannot, catch this form. The
`eval_curl` test case is denied *today* only because its command word is `eval`, matched by
`eval_stage`'s own `case` dispatch, which runs independently of (and, in the segment
evaluation order, before) `detect_net_pipe` is even relevant to it.

**Rule:** when the `eval` arm's argument contains a download command word (`curl`/`wget`/
`fetch`), the channel is **`deny`**, not `ask`. This is a channel-selection refinement for
an arm that already matches — not a new detection pattern, not a new arm, and not a
re-entry into the wrapper/evasion arms race the guards were deliberately rewritten out of
in 2026-06 (Decision D6). The `eval` arm's trigger condition (command word == `eval`) is
unchanged; only which of the two output channels that already-matched arm resolves to now
depends on text already present in the same already-captured command line. This is the
same "a human cannot approve a payload they cannot see" principle applied consistently to
every arm that can smuggle a fetched payload past an `ask` prompt — not an attempt to chase
a new evasion form, and not a reason to expand detection surface elsewhere.

## Decision D2 — git-guard stays all-`deny`

Argued explicitly, not assumed, per the task's own instruction to check the source and
repo history rather than take the memo's "most likely" at face value.

**Evidence for keeping it deny-only:**

1. **`CLAUDE.md` states the convention directly**, in Git workflow: *"This repo eats its
   own dog food — `git-guard` (policy 2) blocks commits/pushes to `main` from a Claude
   session. That's intentional. Push `main` from a terminal, or fast-forward `develop` →
   `main` with explicit user confirmation."* This is not an incidental default; it is a
   stated project rule, verified in the file this proposal was required to read.
2. **Session memory records the guard was hardened, not softened, on this exact point**
   (`rtk-proxy-bypasses-git-guard` memory: the guard was tightened specifically to close
   an `rtk proxy git push …main` bypass and a `branch -f main` bypass, with the note
   "main/master pushes can't originate from a session — do develop/tag steps in-session,
   hand the user a `!`-prefixed line for the main FF"). The trend on this specific
   guarantee has been strictly toward "no session-originated write to `main`," never
   toward relaxing it.
3. **`ask` would put a `main`-push approval in the same UI surface as every other tool
   approval** the human is already routinely accepting in an agentic session — a context
   where the muscle-memory response is "yes, continue." A push to `main` is exactly the
   one action this repo has decided should require a human to *leave* that flow (open a
   terminal, type the command themselves), not click through it. `deny` forces that
   context switch; `ask` would remove it. That is a real weakening, not a friction
   reduction, for the one arm class git-guard has (protected-branch write).
4. **git-guard has no internal deny/ask channel split to make.** Unlike shell-guard's
   dozen distinct arms spanning "wipe a disk" to "chmod a file," git-guard has exactly one
   hazard class — a write landing on a protected branch — reached through many verbs
   (`commit`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `am`, history-moving
   `reset`, force `branch`, and every `push` routing path including the config-resolved
   destination-less-push cases). Splitting *within* that class (e.g., "local commit while
   on `main`" as `ask`, "force-push to `main`" as `deny`) was considered and rejected: the
   local-write case is exactly the accident this repo's own history shows recurring
   (a stray commit or rebase while still on `main`), and it is no less worth a hard stop
   than the push case — both are reachable by the same category of slip (forgot to switch
   branches), and both share the identical override cost today (one `!`-line).

**Conclusion:** git-guard ships with **no code change**. The only artifact is a
documentation note (tasks.md §3) recording that `ask` was evaluated and rejected, so a
future proposal doesn't have to re-derive this reasoning from nothing.

## Decision D3 — the headless question, resolved

**This was the load-bearing unresolved question; it is no longer open.** `ask` overrides
auto-mode — stated in the verified contract above — which is exactly the property needed
for it to be useful (it can interrupt a session that wouldn't otherwise stop). The Claude
Code hooks docs did not state what happens when `ask` fires and there is no human attached
to answer it: block indefinitely, time out and fall through to some default, or spam
repeated prompt attempts. This repo runs background subagents as routine practice (see the
`voice-notify` `SubagentStop`/in-flight-accounting work, archived under
`openspec/changes/archive/2026-07-08-waiting-on-subagents-cue/`, which exists precisely
because this harness's background-agent model produces turn boundaries with no human
watching a specific piece of work) and headless/scripted invocation is a realistic and
increasing mode of use — so the question was worth resolving before adopting the taxonomy
in D1.

### Experiment as run

A throwaway probe hook, returning `permissionDecision: "ask"` unconditionally for every
Bash call (with `permissionDecisionReason: "probe"`), was driven three times via
`claude -p` (Claude Code 2.1.220, model haiku), one Bash call issued per run:

| Mode | Exit | Elapsed | Hook fires | Outcome |
|---|---|---|---|---|
| headless `claude -p`, default permission mode | 0 | 11s | 1 | blocked; reason surfaced to the model |
| `claude -p --permission-mode acceptEdits` | 0 | 12s | 1 | blocked; reason surfaced |
| `claude -p --permission-mode bypassPermissions` | 0 | 15s | 1 | blocked; reason surfaced |

**Findings:**

- **No hang.** Every case resolved in 11–15s, exit 0.
- **No prompt spam.** Exactly one hook fire per run — the model did not retry variants of
  the blocked command.
- **`ask` degrades to deny-with-reason** when no human can be asked. The command never ran,
  in any of the three modes.
- **`ask` overrides `bypassPermissions`.** Even in bypass mode the command was blocked,
  confirming the docs' "overrides auto-mode" claim directly. `ask` is therefore never
  *weaker* than `deny` in a non-interactive session — the worrying failure mode (a headless
  run silently proceeding as if allowed) did not occur in any tested case.

### Scope this verdict covers, and what it does not

This is the honest boundary, not a rounding-up: only **Case C (fully headless)**, as
originally scoped in `tasks.md` §1.4, was exercised — across three permission-mode
variants instead of the single pass originally specified, which is strictly *more*
thorough headless coverage than planned, not less. **Cases A (foreground interactive), B
(background subagent, interactive parent), and D (parallel dispatch)** from the original
`tasks.md` §1 scope were **not executed**. The documented interactive behaviour — a real
permission prompt a human answers — is assumed from `code.claude.com/docs/en/hooks.md`,
not independently verified by this experiment. `tasks.md` §1 records exactly which
sub-tasks were run versus superseded, per sub-task.

### Verdict

**GO, scoped to headless/non-interactive `claude -p` sessions.** All three headless runs
were bounded, deterministic (denied, not hung or ambiguous), and produced no spam — the
gate's own GO criterion, satisfied for every case actually tested. Proceed with D1's
channel taxonomy as the default behaviour for shell-guard.

The reasoning that made this safe to generalize past the tested modes: the risk this gate
existed to rule out was specifically the *unattended* failure mode — a hang, an ambiguous
timeout, or a spam-retry loop with nobody watching. Headless `claude -p` is the least
forgiving version of "nobody is watching" available to test (no TTY, no interactive harness
state at all), and it already resolves cleanly. A background subagent inside an
*interactive* parent session (untested Case B) has strictly *more* context available to the
harness than bare headless does — an attached human session exists, even if not looking at
that specific subagent's turn — so it is reasonable to expect it degrades at least as
safely. That expectation is an inference from the tested case, not independent
verification, and is flagged as such (see the scope caveat above and in Status) rather than
silently treated as equivalent.

**Consequence for D4 (the deny-only conf key):** because headless mode already degrades
`ask` to a blocked command automatically, at the platform level, without any guard-side
code needed, the deny-only override key considered in an earlier draft is now redundant for
the risk it was designed to cover. See D4 below.

## Decision D4 — rejected alternative: a deny-only conf key

An earlier draft of this proposal specified a `SHELL_GUARD_DENY_ONLY` conf key (following
the existing `env var → ~/.claude/shell-guard.conf → built-in default` precedence and the
existing non-sourcing `conf_get()` parser) that would force every ask-channel arm back to
`deny()`, for headless/background/CI contexts where nobody is watching the permission
prompt. **Dropped.** The Task 1 experiment (Decision D3) shows the platform already does
this automatically: in every headless case tested, `ask` degraded to a blocked command with
no code-level intervention needed. A conf key that manually forces the same outcome the
platform already guarantees is dead weight — extra config surface, an extra test-matrix
cell, and an extra thing that can drift out of sync with what actually happens — for a risk
that turned out not to require a guard-side mitigation.

**Open question, not decided here:** a deny-only override might still be worth keeping for
a *different* reason than the one this proposal originally built it for — an operator who
runs fully **interactive** sessions but wants the stricter, no-`ask`-ever behaviour anyway
(a simple preference for today's all-`deny` posture, or an unattended-adjacent setup this
experiment didn't test). That is a legitimate, separate use case from "headless needs a
safety net," and this proposal does not resolve it either way — it is flagged here as a
possible follow-up, not silently reintroduced as a requirement and not silently foreclosed.

Not attempted, and still not needed given the above: auto-detecting "is this session
interactive" from inside the hook. The `PreToolUse` JSON payload fields available to the
hook were not found, in the material read for this proposal, to carry an interactivity
flag — inventing one would violate the "invent nothing" constraint this proposal is written
under. The platform-level degrade observed in D3 means this hook-side detection is not
needed to cover the headless risk; if the open question above is ever picked up, it would
need its own answer for how (or whether) interactivity can be told apart from inside the
hook.

No equivalent key is needed for git-guard (D2: it never emits `ask`, so there is nothing to
fall back from).

## Decision D5 — `updatedInput` rewriting is rejected

The hook API allows a `PreToolUse` hook to hand back `updatedInput`, silently substituting
a different command for the one Claude asked to run — e.g., rewriting `chmod 777 x` into
`chmod 755 x` in place. This proposal does not use `updatedInput` anywhere, for either
guard, for any arm, under any channel.

**Reasoning:** a guard that silently edits the command is worse than one that blocks it.
Blocking preserves the property that the human — reading Claude's report, or the tool
transcript — can always see exactly what was proposed and exactly what happened to it. A
silent rewrite breaks that: the user loses the ability to see what actually ran, because
what ran is no longer what was asked for and no longer visible as a distinct fact. This
holds even for a rewrite that looks obviously safe (`777` → `755`) — the guard would be
making a judgment call about intent that belongs to the human or to Claude reasoning about
the reported block, not to a pattern-matching hook. This is item 4 of the memo's "What NOT
to change" list, applied here rather than merely cited: `deny` and `ask` both **stop and
report**; neither one **substitutes**. A suggested alternative belongs in
`permissionDecisionReason` text (the sibling `guard-block-message-contract` proposal's
territory), never in `updatedInput`.

## Decision D6 — detection logic is untouched; no re-entry into the evasion arms race

Every regex, every `case` arm, every wrapper-skip, every segment/stage splitter in both
scripts is unmodified by this proposal. The only change (verified go by D3's gate) is which
of two *output* mechanisms (`deny()`'s exit-2/stderr vs. a new `ask()`'s JSON-stdout/exit-0)
a given, already-matched arm uses — including the `eval` arm's argument-content exception in
D1, which is a channel-selection check on text the arm already captured, not a new pattern.
This proposal does not add a single new detection pattern, does not attempt to catch a new
evasion form, and does not revisit the 2026-06 decision to keep these guards deliberately
minimal (memo "What NOT to change" item 2; the guards' own header comments state the
accidents-not-evasion scope directly). A more capable model finding more evasion variants is
not addressed by channeling the decision, and this proposal does not try to address it.

## Open questions / non-goals

- **Exact wording of `permissionDecisionReason` for ask-channel arms** is not specified
  here — it is the explicit territory of the sibling `guard-block-message-contract`
  proposal (AXIS 1, memo P1). This proposal's `ask()` helper needs *a* reason string to
  exist (mirroring `deny()`'s existing single-reason-argument shape) but does not fix its
  content.
- **Per-user-pattern severity for `SHELL_GUARD_EXTRA_PATTERNS`** (letting an operator mark
  their own custom pattern as `ask` instead of `deny`) is a plausible follow-up, not built
  here — see the D1 table row for why it stays `deny`-only as-is.
- **Whether a deny-only override should exist for interactive operators who want stricter
  behaviour anyway** is not decided — see D4's open question.
- **Auto-detecting non-interactive sessions** is not attempted, and the D3 result means it
  is not needed to cover the risk this proposal was built against — see D4's closing note.
- **`defer`** is not used anywhere in this proposal; noted in the contract section for
  completeness, not because it has a use here.
