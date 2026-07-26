## Why

`git-guard` and `shell-guard` are deterministic `PreToolUse`/`Bash` hooks. Their entire
model-facing surface is ~5 lines of stderr written by `deny()` when they block (exit 2).
The model never reads the bash that decided to block — the reason string **is** the
interface. Checked against the Claude Code hook API
(`hookSpecificOutput.permissionDecision` ∈ `allow|deny|ask|defer`, plus
`permissionDecisionReason`, `additionalContext`, `updatedInput`): there is no field that
marks a decision non-retryable. Wording is the only lever against a model retrying a
variant of a blocked command, and Claude-5-generation models iterate from failure faster —
an uninformative block yields more variant attempts, faster, not fewer.

Reading both scripts end to end surfaces three concrete defects in the message contract:

1. **`shell-guard`'s `SHELL_GUARD_EXTRA_PATTERNS` arm doesn't name its rule.** Every other
   `deny()` call site in the repo passes a specific reason (`"recursive delete of a
   protected path"`, `"dd onto a raw disk device"`, `"chmod 777 — world-writable
   permissions"`, …). The `EXTRA` arm (`plugins/shell-guard/scripts/shell-guard.sh:276`)
   is the one exception:
   ```
   [[ "$seg" =~ $pat ]] && { deny "matches a configured block pattern"; return 2; }
   ```
   The model is told a pattern matched, never which one. It cannot infer what varying its
   next command would need to avoid — blind retry is the only option the message leaves.

2. **One blanket `⚠️ IRREVERSIBLE` framing covers commands that have no safe variant and
   commands that plainly do.** `deny()`
   (`plugins/shell-guard/scripts/shell-guard.sh:86-98`) prints the same second line —
   `"⚠️  This is destructive and IRREVERSIBLE. Verify the target before running."` — for
   every call site, and offers no alternative, ever. The script's own comment justifies
   that stance: *"These are CATASTROPHIC commands by design, so we front the line with an
   explicit irreversibility warning — never a frictionless one-paste nuke."* That holds
   for `rm -rf /`, `dd … of=/dev/disk0`, `mkfs`, a fork bomb — there genuinely is no safer
   parameterization of "wipe this disk." It does **not** hold for `chmod 777` (→ `chmod
   755`), the `: >` truncate idiom (→ `printf '' >`), `eval` (→ run the intended command
   directly, without the indirection), or a `curl|sh` network pipe (→ download, read, then
   run as a separate reviewed step). Those have obvious safe variants; naming one ends the
   retry loop in one turn instead of three.

3. **Nothing in the message says a variant will also be blocked.** The guard resolves
   flags, quoting, and wrapper prefixes before judging a command, so a reworded or
   reordered retry lands on the same block — but the message never says so, leaving the
   `!`-paste escape hatch looking like one option among several instead of the only one
   that works.

The `: >` arm has already cost this repo a real regression: CHANGELOG `[0.7.1] -
2026-06-22` records `/statusline-toggle` (plugin `0.5.0` → `0.5.1`) tripping shell-guard
because its documented write recipe seeded a temp file with `: >`; the fix was to reseed
with `printf '' >`, plus a doc-lint regression test. A safe-alternative line on that block
message — naming `printf '' >` at the point of failure — would have let the *authoring*
turn self-correct instead of needing a follow-up release.

`git-guard`'s message (`plugins/git-guard/scripts/git-guard.sh:114-125`) is already the
reference implementation: it names the resolved branch (`"push to protected branch
'main'"`, `"$verb on protected branch '$br'"`), the routing mechanism when the block came
from config (`"push routed by push.default=upstream to protected branch '$up'"`,
`"push routed by remote.$remote.push to protected branch '$br'"`), the protected set, an
alternative workflow (`"Use a feature branch or 'develop'"`), the `!`-paste override, and
the disable pointer. It needs the same variants-also-blocked clause for cross-guard
consistency and nothing else — its branch/mechanism naming must not be touched.

## What Changes

- **`shell-guard`'s `deny()` gains a per-call-site class on axis 1** (`alternative: named`
  vs. `alternative: none` — see `design.md` for the two-axis vocabulary this proposal
  shares with the sibling `guard-ask-escalation` proposal) that changes the second line of
  the message: `alternative: none` call sites keep the `⚠️ IRREVERSIBLE` framing and offer
  no alternative; `alternative: named` call sites drop that framing and print the specific
  safe alternative for that arm instead.
- **The `EXTRA` arm's reason names the literal matched pattern** instead of the generic
  `"matches a configured block pattern"`. Its framing stays neutral (it claims neither the
  `alternative: none` irreversibility line nor a fabricated `alternative: named`
  alternative) because the guard cannot know the severity of a user-supplied pattern.
- **Every block message (both guards) gains one new line** stating that variants of the
  same command — reordered flags, different quoting, a wrapper prefix, `$HOME` for `~` —
  are also blocked, so the `!`-paste line reads as the only path forward, not a
  suggestion among several.
- **`git-guard`'s message gains the same variants-also-blocked line.** Its branch naming,
  routing-mechanism naming, protected-set listing, alternative-workflow line, `!`-paste
  override, and disable pointer are unchanged.
- **The `!`-paste escape hatch stays in every message, in both guards, unconditionally.**
- **No detection-logic change.** Every regex, wrapper-skip list, target-resolution rule,
  and the `EXTRA` pattern-matching mechanism itself are untouched — only the reason string
  the `EXTRA` arm passes to `deny()` changes. This is not a re-entry into the
  wrapper/evasion arms race the guards were deliberately rewritten out of in 2026-06.
- **No `updatedInput` silent rewriting.** Safe alternatives are named in text; the guard
  never substitutes or edits the command it blocked.
- **Stays on the exit-2 + stderr path.** Routing arms by channel (`permissionDecision:
  "deny"` vs. `"ask"`) is axis 2, a separate, orthogonal, not-yet-decided proposal
  (`guard-ask-escalation` — see `design.md` for the two-axis cross-reference); this axis-1
  change does not touch `permissionDecision` at all.
- **New test coverage: message-content assertions.** Both `tests/run.sh` harnesses
  currently discard stderr (`>/dev/null 2>&1`) and assert only the exit code. This change
  captures stderr and asserts on its content — the reason names the rule, the class
  framing is correct, the variants clause is present, the escape hatch line is present —
  because a message-only change is otherwise untested by exit-code assertions alone.

## Capabilities

### Added Capabilities

- `guard-block-messaging`: the shared contract both guards' block messages satisfy — every
  reason names the rule that matched, `alternative: none` and `alternative: named` arms
  (axis 1 — see `design.md`) are framed differently, a variants-also-blocked clause and the
  `!`-paste escape hatch are always present, and `git-guard`'s existing branch/mechanism
  detail is preserved under the same contract. No such capability spec exists yet for
  either guard's messaging; this is the first.

## Impact

- **`plugins/shell-guard/scripts/shell-guard.sh`**: `deny()` and every one of its call
  sites (`rm`, `dd`, `mkfs|wipefs|newfs`, `diskutil`, `reboot|shutdown|halt|poweroff`,
  `sudo`-family, `eval`, `chmod 777`, the `DEV_RE`/`TRUNC_RE`/`FORK_RE` structural checks,
  `detect_net_pipe`, and the `EXTRA` loop). Reason strings, framing, and the new clause
  only — no regex or resolution logic changes.
- **`plugins/git-guard/scripts/git-guard.sh`**: `deny()` only, adding the variants clause.
  No change to branch resolution, push-target routing, or any `evaluate_segment` logic.
- **Tests**: `plugins/shell-guard/tests/run.sh` + `cases.tsv`, `plugins/git-guard/tests/run.sh`
  + `cases.tsv` — stderr capture and content assertions; new `EXTRA`-arm case(s) asserting
  the matched pattern is named.
- **Docs**: `plugins/shell-guard/README.md` and `plugins/git-guard/README.md` ("What a
  block looks like" example transcripts), `docs/shell-safety.md` (Layer 2/3 sections that
  describe the message shape).
- **Versions**: `plugins/shell-guard/.claude-plugin/plugin.json` (`0.3.1` → `0.3.2`),
  `plugins/git-guard/.claude-plugin/plugin.json` (`0.2.3` → `0.2.4`) — patch bumps,
  following the precedent of the `0.2.2` → `0.2.3` git-guard push-target fix, which was
  also a message/behavior "Fixed" entry, not additive. Marketplace `metadata.version`
  (`0.10.0` → `0.10.1`) and a `CHANGELOG.md` entry.
- **Not touched**: detection logic in either script, the `EXTRA` pattern-matching
  mechanism, `updatedInput`, `permissionDecision` tiering (left to `guard-ask-escalation`),
  install/uninstall surface (neither guard's uninstall path changes — this proposal adds
  no durable external state).
