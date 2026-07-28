## Why

`git-guard` is deny-only for every arm, decided deliberately in
`openspec/changes/archive/2026-07-26-guard-ask-escalation/design.md` Decision D2. That
decision is correct **for this repo**, whose stated convention is that no write to
`main`/`master` originates from a Claude session at all. But `git-guard` is a published
plugin, and the decision is currently baked into the code rather than expressed as a
setting. A user whose convention is "a local commit on `main` is fine, just never push it"
has no way to say so — their only options are the full deny or `GIT_GUARD_DISABLE=1`,
which turns the guard off entirely, including the push arms they actually want.

The gap is not that the channel is wrong; it is that the channel is not expressible. This
mirrors the same gap already recorded for `shell-guard` in D1 ("A user who wants their
custom pattern to `ask` instead of `deny` has no way to express that yet").

## What Changes

- Add `GIT_GUARD_LOCAL_WRITE_CHANNEL=deny|ask` to `git-guard`, following the existing
  precedence chain (env → `~/.claude/git-guard.conf` → built-in default).
- **The default is `deny`, so shipped behaviour does not change.** This repo's dogfooding
  and the no-session-writes-to-`main` convention are preserved untouched.
- When set to `ask`, only the **on-branch write class** routes to `permissionDecision:
  "ask"`: `commit`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `am`, and a
  history-moving `reset --hard|--merge|--keep` performed *while the current branch is
  protected*.
- **Force `branch -f|-D|-M|-C` naming a protected branch stays deny-only**, even though
  the script currently classifies it as `localwrite`. It is a different action from the
  accident this setting exists to soften: it moves or deletes a protected branch pointer
  without the user being on that branch, and it is a bypass path that was deliberately
  closed once already.
- **Push arms stay deny-only and are NOT configurable** — no setting can move them to
  `ask`. This includes every push routing path: explicit refspecs, the `+force`
  shorthand, `:branch` deletes, `--all`/`--mirror`, the config-routed destination-less
  push, and `GIT_GUARD_BLOCK_ALL_PUSH`.
- The `ask` output reuses `shell-guard`'s existing contract exactly: `permissionDecision:
  "ask"` JSON on stdout with exit 0, the same `!`-prefixed paste-to-override line, and the
  same named-alternative text. No new message format is invented.
- No detection logic changes. No pattern is added, widened, or narrowed; the setting only
  selects which output mechanism an already-matched local-write arm uses.

Not breaking: the default preserves current behaviour for every existing user.

## Capabilities

### New Capabilities

None. This changes the channel policy of an existing capability rather than introducing a
new one.

### Modified Capabilities

- `guard-decision-tiers`: the requirement **"git-guard remains deny-only"** becomes
  "git-guard is deny-only by default, with an opt-in ask channel for the local-write class
  only". The push scenarios under that requirement are strengthened rather than relaxed —
  they become unconditional, explicitly stating that no configuration can move a push arm
  onto the ask channel.

## Impact

- `plugins/git-guard/scripts/git-guard.sh` — config parsing (one `conf_get`), an `ask()`
  function ported from `shell-guard.sh`, and channel selection at the `localwrite`
  decision point. The `push` branch is untouched.
- `plugins/git-guard/README.md` — document the new setting, its default, and the explicit
  statement that push is not configurable.
- `plugins/git-guard/commands/git-guard.md` — surface the setting in the control panel
  command, consistent with how the existing settings are presented.
- `docs/shell-safety.md` — Layer 2's "git-guard emits no `ask`" paragraph needs rewording
  to "deny by default, with an opt-in local-write channel; push is always deny".
- `CLAUDE.md` — the git-guard row in the plugin table mentions the guard's behaviour.
- Tests: the existing git-guard harness asserts exit codes only (`0` allow / `2` deny). It
  needs a third assertion form for the ask case (exit 0 **plus** `permissionDecision` JSON
  on stdout), which is the form `shell-guard`'s tests already use.
- No new dependency. `jq` is already required by both guards, and the fail-open path is
  unchanged.
