## 1. Message contract — shell-guard (`scripts/shell-guard.sh`)

- [x] 1.1 `deny()` now takes `$1` = axis-1 class (`none`|`named`|`neutral`), `$2` =
      reason, `$3` = safe-alternative text (named only). `class=none` keeps `⚠️  This is
      destructive and IRREVERSIBLE. Verify the target before running.`; `class=named`
      drops that line and prints `   → Safe alternative: $alt.` instead; `class=neutral`
      prints neither (the EXTRA arm — see 1.4).
- [x] 1.2 Every call site classed `none` (reason strings unchanged): `rm` recursive
      delete, `dd` onto a raw disk device, `DEV_RE` redirect-onto-a-raw-disk-device,
      `mkfs`/`wipefs`/`newfs`, both destructive-`diskutil` sites, `FORK_RE` fork bomb, and
      `reboot|shutdown|halt|poweroff`.
- [x] 1.3 Every call site classed `named` with its alternative text: `chmod 777`/`0777` →
      `"chmod 755 (or the narrowest mode the task needs)"`; `TRUNC_RE` `: >` → `"printf ''
      >"`; `eval` → `"run the intended command directly, without the eval indirection"`;
      `detect_net_pipe` → `"download to a file, read it, then run it as a separate
      reviewed step"`; privilege-escalation family → `"run the command directly, without
      \`$c\`"` (names the actual matched prefix — `sudo`, `doas`, …). Verified live output
      for `rm -rf ~`, `chmod 777`, `sudo rm -rf /`, and the EXTRA arm before wiring tests.
- [x] 1.4 EXTRA arm reason is now `"matches your configured SHELL_GUARD_EXTRA_PATTERNS
      rule: $pat"`, classed `neutral`. `[[ "$seg" =~ $pat ]]` matching itself untouched.
- [x] 1.5 Variants-also-blocked line added inside `deny()` itself (fires for every class,
      unconditionally): `"Variants of this command (reordered flags, different quoting, a
      wrapper prefix, \$HOME for ~, …) are blocked too."`
- [x] 1.6 Confirmed present and unchanged in every class via the new run.sh content
      assertions (52/52 pass) — `! $cmd` line and `SHELL_GUARD_DISABLE=1 / see
      /shell-guard.` pointer.
- [x] 1.7 No regex/skip_wrappers/is_cata_target/eval_stage/detect_net_pipe logic touched —
      diff is message text + one leading `deny` argument per call site. `bash -n` and
      `shellcheck` both clean (verified).

## 2. Message contract — git-guard (`scripts/git-guard.sh`) — alignment only

- [x] 2.1 Added one line to `deny()`: `"Variants of this command — different phrasing,
      flags, or a wrapper prefix that still resolves to the same protected branch — are
      blocked too."`
- [x] 2.2 No call sites touched; run.sh now asserts (for a representative id per
      reason-shape) that `push to protected branch 'main'`, `$verb on protected branch
      'main'`, `push --all/--mirror (...)`, and the `GIT_GUARD_BLOCK_ALL_PUSH` reason are
      unchanged, plus `Protected: main master.` on every blocking case (49/49 pass).
- [x] 2.3 Confirmed no change to branch resolution / push-target routing / refspec
      parsing / `evaluate_segment` — diff is one new `printf` line in `deny()` only.
      `bash -n` and `shellcheck` both clean (verified).

## 3. Tests — message-content assertions

- [x] 3.1 `run.sh` now captures stderr per case (`2>&1 >/dev/null` idiom, stdout
      discarded) and asserts: `none`-class cases carry `IRREVERSIBLE` and NOT `Safe
      alternative`; `named`-class cases (incl. both `sudo_rm`/`sudo_apt` and
      `doas_reboot`) carry `Safe alternative` plus an arm-specific substring and NOT
      `IRREVERSIBLE`; every blocking case carries `are blocked too` and `! $cmd`.
      Sanity-checked the assertions are load-bearing (not vacuous) by deliberately
      corrupting one expected substring and confirming the harness then reports FAIL.
- [x] 3.2 Added `extra_pattern` to `cases.tsv`: `SHELL_GUARD_EXTRA_PATTERNS=
      ZZZ_TEST_PATTERN_ZZZ echo hello ZZZ_TEST_PATTERN_ZZZ world`, expect 2. `run.sh`
      gained env-assignment stripping (mirroring git-guard's) to set the env var per-case,
      and asserts the reason contains the literal pattern with neither `IRREVERSIBLE` nor
      `Safe alternative`.
- [x] 3.3 `plugins/git-guard/tests/run.sh`: same stderr-capture idiom; asserts
      `Protected: main master.`, `are blocked too`, `GIT_GUARD_DISABLE=1`, `! $cmd` on
      every blocking case, plus the exact reason phrase for a representative id per
      reason-shape (commit/merge, push-to-branch, branch-force, `--all/--mirror`,
      `GIT_GUARD_BLOCK_ALL_PUSH`).
- [x] 3.4 statusline's case (k) doc-lint (`: >` idiom absent from `statusline-toggle.md`)
      still passes unmodified — confirmed in the 3.5 full-suite run; noted here per the
      task that shell-guard's own `named`-class message for `TRUNC_RE` now names
      `printf '' >`, the same fix that doc-lint enforces.
- [x] 3.5 Full suite green: shell-guard 52/52, git-guard 49/49, git-guard routing 8/8,
      statusline 19/19 (all four commands run and reported below).

## 4. Docs + release

- [x] 4.1 `plugins/shell-guard/README.md` "What a block looks like" now shows both
      framings: `rm -rf ~` (`none`, unchanged plus the variants line) and `chmod 777 x`
      (`named`, dropped irreversibility line, `→ Safe alternative:` line, variants line),
      with a lead-in paragraph explaining the class split and the EXTRA-arm pattern
      naming.
- [x] 4.2 `plugins/git-guard/README.md` "What a block looks like": added the
      variants-also-blocked line to the transcript and one sentence below it; branch
      naming/protected-set/alternative-workflow text untouched.
- [x] 4.3 `docs/shell-safety.md`: updated the "Recommended setup" override paragraph
      (the only spot quoting message shape/irreversibility framing) to describe the
      per-class split and the variants clause. Layer 2/3 sections themselves don't quote
      message text (they point to each README's "Full detail" link), so no change needed
      there — confirmed by grep for `stderr`/`deny(`/`message` finding no other hits.
- [x] 4.4 Bumped `plugins/shell-guard/.claude-plugin/plugin.json` 0.3.1 → 0.3.2 and
      `plugins/git-guard/.claude-plugin/plugin.json` 0.2.3 → 0.2.4.
- [ ] 4.5 NOT DONE — out of scope for this agent per explicit harness instruction
      ("Do NOT edit `.claude-plugin/marketplace.json` or `CHANGELOG.md` — handled
      centrally at the end"). Marketplace version bump + CHANGELOG entry deferred to
      whoever runs the centralized release step.
- [x] 4.6 All four checks run and passed: `jq empty` on both plugin.json files and
      marketplace.json (read-only check, no edit made), `claude plugins validate
      plugins/shell-guard` → "Validation passed", `claude plugins validate
      plugins/git-guard` → "Validation passed".
- [ ] 4.7 NOT DONE — out of scope for this agent per explicit harness instruction ("Run
      NO git commands... I handle all git"). No commit/push/PR performed; files are
      edited in the worktree only.
