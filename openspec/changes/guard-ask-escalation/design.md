# Design — guard-ask-escalation

## Status

**Blocked on verification.** Section "Decision D3 — the headless unknown" below has a
placeholder result. Nothing in sections D1/D2/D4/D5 ships until Task 1
(`tasks.md` §1) resolves it. This document specifies the taxonomy and the reasoning that
would apply *if* the gate says go; it does not assert the gate has been passed.

## Context

Both `shell-guard.sh` and `git-guard.sh` are `PreToolUse`/`Bash` hooks. Today both use
exactly one mechanism to stop a command: exit code 2, with the reason on stderr (verified
in both scripts' header comments — "Exit codes: 0 = allow, 2 = block (stderr is fed back
to Claude). Any other code is a non-blocking error in the hooks API, so we never use one
to deny."). Claude sees the block, reports it, and the human either accepts that or pastes
the `!`-prefixed override line the `deny()` helper hands back in both scripts.

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

## Decision D1 — shell-guard's catastrophic/hygiene taxonomy

**Criterion.** An arm stays `deny` when the harm it prevents is irreversible at the OS/
data/hardware level (data or a filesystem is gone, a disk is wiped) **or** when a human
reading the command text at an `ask` prompt could not actually tell what the command
will do (so an `ask` approval would be uninformed, not a real safety gate). An arm moves
to `ask` when the harm is reversible, or bounded to something the command's own text
already discloses, so a human glancing at the prompt has what they need to decide.

This is a judgment call the memo does not fully make for every arm — it hands over four
explicit examples per tier and leaves the rest to be worked out here, against the real
arm list in the script (not guessed).

### Arm-by-arm assignment (every real arm in `shell-guard.sh`)

| Arm (as matched in the script) | Tier | Reasoning |
|---|---|---|
| Recursive delete of a protected path (`rm -rf`/`-fr`/`--no-preserve-root` on `/`, `~`, `$HOME`, a top-level system dir, or `$HOME`-cwd glob-all) | **deny** | Irreversible data loss at scale. Explicit in the memo's catastrophic list. |
| `dd … of=/dev/disk*` etc. (raw disk device) | **deny** | Irreversible hardware-level overwrite. Explicit in the memo. |
| `mkfs`/`mkfs.*`/`wipefs`/`newfs`/`newfs_*` | **deny** | Same class as `dd` to a device — irreversible filesystem destruction. Explicit in the memo (`mkfs`); generalized to its siblings in the same `case` arm. |
| Destructive `diskutil` (`eraseDisk`, `eraseVolume`, `reformat`, `zeroDisk`, `secureErase`, `partitionDisk`, `eraseall`, `apfs delete*`/`erase*`) | **deny** | Not named in the memo but is the macOS-native sibling of `mkfs`/`dd`-to-device — same irreversibility, same criterion. |
| Redirect onto a raw disk device (`> /dev/disk0`, `>| /dev/rdisk1`, …) | **deny** | Same irreversibility as the `dd` arm; it is the `DEV_RE` structural check the script explicitly keeps "KEEP IN SYNC" with the `dd` arm's `of=` glob — they are one hazard class in the code itself. |
| Fork bomb (`:(){ :|:& };:` and renamed variants) | **deny** | Explicit in the memo. Also fails the "informed `ask`" half of the criterion for a different reason: a live fork bomb can degrade the machine badly enough that the very prompt asking for permission may never render or be answerable — `ask` is not a safe fallback for a hazard that can prevent its own approval from being seen. |
| Network download piped into an interpreter (`curl`/`wget`/`fetch` stage → `sh`/`bash`/`zsh`/`dash`/`ksh`/`python`/`perl`/`ruby`/`node`/`php`) | **deny** | Not in the memo's four examples — a deliberate call, not an oversight. The command text a human sees at an `ask` prompt is `curl URL \| bash`; the actual payload that will execute is **not** visible in that text — it lives at a URL, fetched at run time, and can be anything, including everything else in this table's deny column. Approving `ask` here would be approving a blank check, which fails this design's own "informed prompt" half of the criterion. This is the one place this taxonomy diverges from a pure irreversibility test: the direct effect of the pipe itself is not irreversible, but what it enables is unbounded and invisible, so it stays `deny`. |
| System halt/reboot (`reboot`/`shutdown`/`halt`/`poweroff`) | **ask** | Not in the memo's four examples. Disruptive (interrupts whatever else is running) but not data-destructive — the machine comes back, nothing is deleted or overwritten. The command text fully discloses the effect ("this will reboot the machine"), so a human at the prompt has everything needed to decide. This is a policy/annoyance boundary, exactly `ask`'s intended shape. |
| Privilege escalation (`sudo`/`doas`/`su`/`runuser`/`pkexec`/`gosu`/`sudoedit`/`setpriv`) | **ask** | `sudo` is explicit in the memo; generalized to the whole arm (the script already treats all eight as one `case` branch, one reason string). The escalation itself is visible and reversible (running a command as root doesn't, by itself, destroy anything — whatever runs *under* it might, but that is the same "can't see the payload" problem as `curl\|sh` only if the sudo'd command is itself opaque, which is a pre-existing detection gap this proposal does not attempt to close). Treating `sudo` as `ask` matches its actual role in this repo's own workflow — e.g. `brew install jq`-style setup commands a human routinely approves inline. |
| `eval` | **ask** | Explicit in the memo. Narrower than `curl\|sh`: `eval`'s argument is ordinarily present in the command text the human is reading (e.g. `eval "some code"`), so — unlike a piped download — the human usually *can* read what will run. Known imprecision, stated here rather than hidden: `eval "$(curl http://x)"` (the repo's own `eval_curl` test case) combines both arms; because tiering is by matched-arm identity and the script's `case` dispatches on the command word (`eval`), this composite hits the `eval` arm and inherits `ask`, even though it also fetches remote code. This is not a new detection gap — the detection logic is unchanged — it is an existing ambiguity in a compound command now inheriting a tier via the arm that happens to match first. Flagged for the implementer, not silently accepted. |
| `chmod 777`/`0777` | **ask** | Explicit in the memo. Trivially reversible (`chmod 755`) and fully disclosed in the command text. |
| `: > file` (truncate-to-empty idiom) | **ask** | Explicit in the memo, and the specific motivating case: this is the arm that produced a real false positive (`/statusline-toggle`'s write recipe, `CHANGELOG.md` `0.7.1`) before the recipe was rewritten to `printf '' >`. Note this is a *deliberate exception* to a strict reading of the irreversibility criterion — the file's prior contents genuinely are gone once this runs, no different in kind from `rm`. It is tiered `ask` anyway because (a) the blast radius is one file, not a filesystem, (b) it is the arm the repo has direct evidence collides with legitimate tooling, and (c) `ask` turning a known false-positive class into a one-prompt override — instead of an exit-2 report-and-repaste cycle — is the concrete, already-observed benefit this whole proposal exists to capture. |
| `SHELL_GUARD_EXTRA_PATTERNS` (user-configured ERE patterns) | **deny (unchanged)** | Out of this taxonomy by design: the guard has no way to know the severity of a user's own pattern, so tiering it would be a guess. Kept on the existing `deny()` path — identical to today's behaviour — rather than invented a severity flag for user patterns, which would be new surface this proposal doesn't need. A user who wants their custom pattern to `ask` instead of `deny` has no way to express that yet; noted as a possible follow-up, not built here. |

Every row above is the *existing* detection logic (same `case` arms, same regexes, same
`eval_stage`/`evaluate_segment` structure in `shell-guard.sh`) — this table only assigns,
per already-matched arm, which of the two output paths (`deny()` vs. a new `ask()`) fires.
No pattern is added, removed, widened, or narrowed.

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
4. **git-guard has no internal catastrophic/hygiene split to tier.** Unlike shell-guard's
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

## Decision D3 — the headless unknown (go/no-go gate)

**This is the load-bearing unresolved question.** `ask` overrides auto-mode — stated in
the verified contract above — which is exactly the property needed for it to be useful
(it can interrupt a session that wouldn't otherwise stop). The Claude Code hooks docs do
not state what happens when `ask` fires and there is no human attached to answer it:
block indefinitely, time out and fall through to some default, or spam repeated prompt
attempts. This repo runs background subagents as routine practice (see the `voice-notify`
`SubagentStop`/in-flight-accounting work, archived under
`openspec/changes/archive/2026-07-08-waiting-on-subagents-cue/`, which exists precisely
because this harness's background-agent model produces turn boundaries with no human
watching a specific piece of work) and headless/scripted invocation is a realistic and
increasing mode of use.

**Task 1 result: TBD.** `tasks.md` §1 specifies the experiment (a throwaway sentinel-
matching probe hook, run across foreground/background/headless/parallel cases) and its
go/no-go gate. This section is the place that result gets recorded once the experiment
runs — replace this paragraph with the actual findings (per-case: hang/timeout/spam/
clean-resolve, and wall-clock numbers where relevant) before starting any implementation
task in `tasks.md` §2+.

**What each outcome implies for D1/D4:**

- **Go (bounded, deterministic, no spam in every case)** — proceed with D1's taxonomy as
  the default behaviour; the conf key from D4 becomes an opt-out for operators who know
  they run headless.
- **No-go (hang, ambiguous timeout, or spam in any case)** — either this proposal does not
  proceed at all, or it ships with `ask` off by default everywhere and the D4 conf key
  becomes the opt-**in**, restricted to operators who have separately confirmed their own
  sessions are always interactively attended. The taxonomy in D1 does not change in this
  branch — only the default polarity of whether it's ever reached.
- **Inconsistent across cases** — bind the default to the worst observed case (per
  `tasks.md` 1.7), not an average, since a guard's job is to hold under the failure mode,
  not the common case.

## Decision D4 — the deny-only conf key

Follows the existing precedence both scripts already use — `env var → ~/.claude/<plugin>.conf
→ built-in default` — and the existing `conf_get()` parser (grep + parameter expansion,
never `source`d, so a stray or adversarial conf file cannot execute shell). Provisional
name: `SHELL_GUARD_DENY_ONLY` (boolean, same shape as the existing `SHELL_GUARD_DISABLE`).
When set, every arm tiered `ask` in D1 falls back to `deny()` — i.e., exactly today's
behaviour, selectable per session or per operator (set in CI env, a cron wrapper, or
`~/.claude/shell-guard.conf` on a box that only ever runs headless).

The key's **default polarity is not fixed by this design** — it is fixed by the D3 result
(see above). This document does not presuppose an answer; recording the mechanism without
the polarity is deliberate, matching the task's framing that the assumption is unresolved.

No equivalent key is needed for git-guard (D2: it never emits `ask`, so there is nothing
to fall back from).

Not attempted: auto-detecting "is this session interactive" from inside the hook. The
`PreToolUse` JSON payload fields available to the hook were not found, in the material
read for this proposal, to carry an interactivity flag — inventing one would violate the
"invent nothing" constraint this proposal is written under. If the Task 1 experiment
surfaces such a signal incidentally, that is worth a follow-up proposal; it is out of
scope here.

## Decision D5 — `updatedInput` rewriting is rejected

The hook API allows a `PreToolUse` hook to hand back `updatedInput`, silently substituting
a different command for the one Claude asked to run — e.g., rewriting `chmod 777 x` into
`chmod 755 x` in place. This proposal does not use `updatedInput` anywhere, for either
guard, for any arm, under any tier.

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
scripts is unmodified by this proposal. The only change (contingent on D3's gate) is which
of two *output* mechanisms (`deny()`'s exit-2/stderr vs. a new `ask()`'s JSON-stdout/exit-0)
a given, already-matched arm uses. This proposal does not add a single new pattern, does
not attempt to catch a new evasion form, and does not revisit the 2026-06 decision to keep
these guards deliberately minimal (memo "What NOT to change" item 2; the guards' own
header comments state the accidents-not-evasion scope directly). A more capable model
finding more evasion variants is not addressed by tiering the decision channel, and this
proposal does not try to address it.

## Open questions / non-goals

- **Exact wording of `permissionDecisionReason` for `ask` arms** is not specified here —
  it is the explicit territory of the sibling `guard-block-message-contract` proposal
  (memo P1). This proposal's `ask()` helper needs *a* reason string to exist (mirroring
  `deny()`'s existing single-reason-argument shape) but does not fix its content.
- **Per-user-pattern severity for `SHELL_GUARD_EXTRA_PATTERNS`** (letting an operator mark
  their own custom pattern as `ask` instead of `deny`) is a plausible follow-up, not built
  here — see the D1 table row for why it stays `deny`-only as-is.
- **Auto-detecting non-interactive sessions** is not attempted — see D4's closing note.
- **`defer`** is not used anywhere in this proposal; noted in the contract section for
  completeness, not because it has a use here.
