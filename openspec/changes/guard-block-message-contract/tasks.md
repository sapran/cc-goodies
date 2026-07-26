## 1. Message contract — shell-guard (`scripts/shell-guard.sh`)

- [ ] 1.1 Give `deny()` an axis-1 class parameter (`alternative: named` | `alternative:
      none` — see `design.md`'s two-axis section; this is the axis owned by this
      proposal, not the `channel: deny | ask` axis owned by `guard-ask-escalation`)
      alongside the existing reason string, so the second output line branches:
      `alternative: none` keeps `⚠️  This is destructive and IRREVERSIBLE. Verify the
      target before running.` and offers no alternative; `alternative: named` drops that
      line and prints a `→` safe-alternative line specific to the arm.
- [ ] 1.2 Mark every `alternative: none` call site with that class (no text change to
      their reason strings): `rm` recursive-delete-of-protected-path, `dd` onto a raw disk
      device, the `DEV_RE` redirect-onto-a-raw-disk-device structural check, `mkfs` /
      `wipefs` / `newfs`, destructive `diskutil`, the `FORK_RE` fork-bomb check, and
      `reboot|shutdown|halt|poweroff`.
- [ ] 1.3 Mark the `alternative: named` call sites and add each one's safe-alternative
      text: `chmod 777`/`0777` → `chmod 755` (or the narrowest mode the task needs); the
      `TRUNC_RE` `: >` idiom → `printf '' >`; `eval` → run the intended command directly
      instead of through `eval`; `detect_net_pipe`'s `curl`/`wget`/`fetch`-into-interpreter
      match → download to a file, read it, then run it as a separate reviewed step; and the
      `sudo`/`doas`/`su`/`runuser`/`pkexec`/`gosu`/`sudoedit`/`setpriv` privilege-escalation
      arm → run the command directly, without `sudo` (or whichever privilege-escalation
      prefix matched). (`sudo` is `alternative: named` on this axis — see `design.md` D1 —
      independent of whatever channel `guard-ask-escalation` eventually assigns it.)
- [ ] 1.4 Fix the `EXTRA` arm (`shell-guard.sh:276`): interpolate the literal matched
      pattern into the reason (e.g. `"matches your configured SHELL_GUARD_EXTRA_PATTERNS
      rule: $pat"`), replacing the current `"matches a configured block pattern"`. Keep
      its framing neutral — neither the `alternative: none` irreversibility line nor an
      invented `alternative: named` alternative, since the guard cannot know a
      user-supplied pattern's severity. No change to the `EXTRA` matching mechanism
      itself.
- [ ] 1.5 Add one new line to every `deny()` message stating that variants of the blocked
      command (reordered flags, different quoting, a wrapper prefix, `$HOME` for `~`, …)
      are also blocked, so the `!`-paste line is the only path forward.
- [ ] 1.6 Confirm the `!`-paste escape-hatch line and the `SHELL_GUARD_DISABLE=1` /
      `/shell-guard` pointer are unchanged and present in every message, regardless of
      `alternative: named`/`alternative: none` class.
- [ ] 1.7 No change to any regex (`DEV_RE`, `FORK_RE`, `TRUNC_RE`), `skip_wrappers`,
      `is_cata_target`, `eval_stage`, or `detect_net_pipe` matching logic — message text
      and classification only. `bash -n` and `shellcheck` clean.

## 2. Message contract — git-guard (`scripts/git-guard.sh`) — alignment only

- [ ] 2.1 Add the same variants-also-blocked line to `deny()`'s output, phrased for
      git-guard's own variant space (a differently-phrased commit/merge/push that still
      resolves to the same protected branch is judged the same way, not just the exact
      command text blocked).
- [ ] 2.2 Re-verify every existing reason string still names its branch and, where
      applicable, the routing mechanism (`push to protected branch '$br'`, `push routed by
      push.default=upstream to protected branch '$up'`, `push routed by remote.$remote.push
      to protected branch '$br'`, `$verb on protected branch '$br'`) — confirm none of this
      is degraded by the new line.
- [ ] 2.3 No change to branch resolution, push-target routing, refspec parsing, or any
      `evaluate_segment` logic. `bash -n` and `shellcheck` clean.

## 3. Tests — message-content assertions

- [ ] 3.1 `plugins/shell-guard/tests/run.sh`: stop discarding stderr (the runner currently
      pipes both streams to `/dev/null` via `bash "$script" >/dev/null 2>&1`); capture it
      per case and add content assertions: `alternative: none` cases assert the
      `⚠️  ... IRREVERSIBLE` line and the absence of a safe-alternative line;
      `alternative: named` cases (including `sudo`) assert the specific safe-alternative
      substring for that arm; every blocking case asserts the new variants-also-blocked
      line and the `! $cmd` escape-hatch line are present.
- [ ] 3.2 `plugins/shell-guard/tests/cases.tsv`: add case(s) exercising
      `SHELL_GUARD_EXTRA_PATTERNS` with a distinctive test pattern, asserting exit 2 and,
      via the new message assertions, that the reason names the literal matched pattern
      rather than the generic string.
- [ ] 3.3 `plugins/git-guard/tests/run.sh`: same stderr-capture change; assert the
      reference-quality content (resolved branch name, protected-branch list, routing
      mechanism phrase where applicable) is unchanged and the new variants-also-blocked
      line is present on every blocking case.
- [ ] 3.4 Extend or confirm the existing doc-lint regression test for command-body recipes
      (the statusline `tests/run.sh` check added in `0.7.1` that lints
      `statusline-toggle.md` for the blocked `: >` idiom) still passes, and note in the
      test comments that the safe-alternative line in shell-guard's own `alternative:
      named` message now names the same fix (`printf '' >`) the doc-lint check enforces.
- [ ] 3.5 Full suite green: `bash plugins/shell-guard/tests/run.sh`,
      `bash plugins/git-guard/tests/run.sh`, `bash plugins/git-guard/tests/run-routing.sh`,
      `bash plugins/statusline/tests/run.sh`.

## 4. Docs + release

- [ ] 4.1 `plugins/shell-guard/README.md` "What a block looks like": refresh the example
      transcript(s) to show both framings — an `alternative: none` example (`rm -rf ~`,
      unchanged except the new variants line) and an `alternative: named` example (e.g.
      `chmod 777 x`) showing the dropped irreversibility line, the safe-alternative line,
      and the variants line.
- [ ] 4.2 `plugins/git-guard/README.md` "What a block looks like": refresh the example
      transcript to include the new variants-also-blocked line; no other change.
- [ ] 4.3 `docs/shell-safety.md`: update the Layer 2 (git-guard) and Layer 3 (shell-guard)
      sections wherever they describe or quote the block-message shape, to match the new
      per-class contract and the variants clause.
- [ ] 4.4 Bump `plugins/shell-guard/.claude-plugin/plugin.json` (`0.3.1` → `0.3.2`) and
      `plugins/git-guard/.claude-plugin/plugin.json` (`0.2.3` → `0.2.4`) — patch bumps,
      following the `0.2.2` → `0.2.3` git-guard push-target-fix precedent (a "Fixed" entry,
      not additive).
- [ ] 4.5 Bump marketplace `metadata.version` (`0.10.0` → `0.10.1`) in
      `.claude-plugin/marketplace.json` and add a `CHANGELOG.md` entry under `### Fixed`
      referencing both plugin bumps and the three defects fixed.
- [ ] 4.6 `jq empty plugins/shell-guard/.claude-plugin/plugin.json`,
      `jq empty plugins/git-guard/.claude-plugin/plugin.json`,
      `jq empty .claude-plugin/marketplace.json`; `claude plugins validate
      plugins/shell-guard` and `claude plugins validate plugins/git-guard`.
- [ ] 4.7 Commit on the change branch, push, open a draft PR to `develop`. (Archive + `main`
      fast-forward happen after review, per the repo release flow.)
