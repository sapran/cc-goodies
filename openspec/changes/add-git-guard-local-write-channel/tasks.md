## 1. Script implementation

- [ ] 1.1 Add `LOCAL_WRITE_CHANNEL` to the effective-configuration block in
      `plugins/git-guard/scripts/git-guard.sh`, using the existing `conf_get` parser and
      the env → conf → default precedence chain, defaulting to `deny`
- [ ] 1.2 Normalise the value to exactly `deny` or `ask`, treating every other value as
      `deny`, with a comment explaining why this parses differently (fail-closed) from
      `GIT_GUARD_DISABLE` / `GIT_GUARD_BLOCK_ALL_PUSH` (design.md Decision 3)
- [ ] 1.3 Port an `ask()` function from `plugins/shell-guard/scripts/shell-guard.sh`,
      emitting `permissionDecision: "ask"` JSON on stdout with exit 0 and carrying the
      same reason substance, `!`-prefixed paste line, and named-alternative text the
      existing `deny()` produces
- [ ] 1.4 Split the `localwrite` action into the ask-eligible **on-branch write** class
      (`commit`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `am`, history-moving
      `reset`) and the always-deny force `branch -f|-D|-M|-C` case, which currently share
      the `action="localwrite"` label (design.md Decision 2)
- [ ] 1.5 Route the on-branch write class to `ask()` when the setting is `ask`, leaving
      every other path — and the whole `push` branch — calling `deny()` unchanged
- [ ] 1.6 Add a comment at the decision point recording that push is deliberately not
      configurable, referencing the spec requirement, so a future change cannot add it by
      analogy without argument
- [ ] 1.7 Run `bash -n` and `shellcheck` on the modified script

## 2. Tests

- [ ] 2.1 Extend the git-guard harness with a third assertion form: exit 0 **plus** a
      `permissionDecision: "ask"` payload on stdout, matching how the shell-guard harness
      already asserts ask cases
- [ ] 2.2 Cover every on-branch write verb under both setting values (unset/`deny` → exit
      2; `ask` → ask payload) while on a protected branch
- [ ] 2.3 Assert force `branch -f|-D|-M|-C` on a protected branch still denies with the
      setting at `ask`
- [ ] 2.4 Assert every push routing path still denies with the setting at `ask`: explicit
      refspec, `+force` shorthand, `:branch` delete, `--all`/`--mirror`, destination-less
      push routed through `push.default` and `remote.<remote>.push`, and
      `GIT_GUARD_BLOCK_ALL_PUSH`
- [ ] 2.5 Assert unrecognised values (`ASK`, `Ask`, `yes`, `1`, empty) fail closed to deny
- [ ] 2.6 Assert non-protected-branch work is still allowed unchanged under both values
- [ ] 2.7 Assert the `jq`-missing fail-open path is unaffected by the setting
- [ ] 2.8 Route test commands and any dangerous literals through files rather than inline
      Bash arguments, since the live guards inspect the test harness's own commands

## 3. Documentation

- [ ] 3.1 Document the setting, its default, and its fail-closed parsing in
      `plugins/git-guard/README.md`, stating plainly that an approved ask is a real write
      to the protected branch
- [ ] 3.2 State in the README that push arms are never configurable, with the reason
- [ ] 3.3 Surface the setting in `plugins/git-guard/commands/git-guard.md` as display +
      confirmed diff, not a one-click enable (design.md Open Questions)
- [ ] 3.4 Reword the Layer 2 paragraph in `docs/shell-safety.md` from "git-guard emits no
      `ask`" to deny-by-default with an opt-in on-branch-write channel and permanently
      deny-only pushes
- [ ] 3.5 Update the `git-guard` row in `CLAUDE.md` to match
- [ ] 3.6 Verify `/git-guard-uninstall` still fully reverts the conf file including the
      new key (expected: yes, unchanged — it deletes the file)

## 4. Release and archive

- [ ] 4.1 Bump `plugins/git-guard/.claude-plugin/plugin.json` version
- [ ] 4.2 Bump `.claude-plugin/marketplace.json` `metadata.version` and refresh the
      git-guard description there if its summary changed
- [ ] 4.3 Add a `CHANGELOG.md` entry under the new marketplace version
- [ ] 4.4 Run `jq empty` on both manifests and `claude plugins validate plugins/git-guard`
- [ ] 4.5 Run `openspec validate add-git-guard-local-write-channel --strict`
- [ ] 4.6 Sync the delta into `openspec/specs/guard-decision-tiers/spec.md` and archive the
      change in the same PR as the code, per the repo's OpenSpec rule
