## REMOVED Requirements

### Requirement: git-guard remains deny-only

**Reason**: Superseded. This requirement conflated two separate things: the *default*
channel policy for `git-guard` (which does not change — it stays deny) and whether that
channel is *expressible by the user* (which this change makes possible, for one narrow
class of arms only). It is replaced by the two requirements added below, which keep the
shipped behaviour byte-for-byte identical and make the push guarantee **stronger** than
the removed text did, by stating explicitly that no configuration can ever move a push arm
onto the ask channel.

**Migration**: None required. `GIT_GUARD_LOCAL_WRITE_CHANNEL` defaults to `deny`, so an
installation that sets nothing behaves exactly as it does today. Users who want the looser
behaviour opt in explicitly.

## ADDED Requirements

### Requirement: git-guard is deny-only by default, with an opt-in on-branch-write ask channel

`git-guard` SHALL resolve every arm to `permissionDecision: "deny"` (or the equivalent
exit-2/stderr path) unless the user has explicitly opted in otherwise. `git-guard` SHALL
read a `GIT_GUARD_LOCAL_WRITE_CHANNEL` setting through the same precedence chain as its
other settings (environment → `~/.claude/git-guard.conf` → built-in default), whose
built-in default SHALL be `deny`.

When, and only when, `GIT_GUARD_LOCAL_WRITE_CHANNEL` is set to `ask`, the **on-branch
write class** SHALL resolve to `permissionDecision: "ask"` instead of `deny`. That class
comprises `commit`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `am`, and a
history-moving `reset --hard|--merge|--keep`, in each case judged against the current
branch while that branch is protected.

A force `branch -f|-D|-M|-C` operation naming a protected branch SHALL NOT be part of this
class and SHALL remain on the deny channel under every value of the setting, because it
moves or deletes a protected branch pointer without the user being on that branch.

Any value other than the exact strings `deny` and `ask` SHALL be treated as `deny`, so a
typo or a malformed conf entry fails closed rather than silently loosening the guard.

Introducing this setting SHALL NOT add, remove, widen, or narrow any detection pattern; it
SHALL only select which output mechanism an already-matched arm uses.

#### Scenario: With no configuration, an on-branch write still denies

- **WHEN** a `commit` runs while the current branch is protected and
  `GIT_GUARD_LOCAL_WRITE_CHANNEL` is unset
- **THEN** the hook resolves `permissionDecision: "deny"`, identical to the behaviour
  before this setting existed

#### Scenario: With the setting on ask, an on-branch write escalates instead of blocking

- **WHEN** a `commit`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `am`, or
  history-moving `reset` runs while the current branch is protected and
  `GIT_GUARD_LOCAL_WRITE_CHANNEL=ask`
- **THEN** the hook resolves `permissionDecision: "ask"` on stdout with exit 0, escalating
  to the human's permission prompt instead of blocking outright

#### Scenario: A force branch operation stays denied even when the setting is ask

- **WHEN** `git branch -f main <commit>` (or `-D`/`-M`/`-C` naming a protected branch) runs
  with `GIT_GUARD_LOCAL_WRITE_CHANNEL=ask`
- **THEN** the hook resolves `permissionDecision: "deny"`, unchanged by the setting

#### Scenario: An unrecognised value fails closed

- **WHEN** `GIT_GUARD_LOCAL_WRITE_CHANNEL` is set to any value other than `deny` or `ask`
  (for example `ASK`, `yes`, or an empty-but-present entry)
- **THEN** the hook treats it as `deny` and blocks on-branch writes as usual

#### Scenario: An asked on-branch write carries the same message substance as a denial

- **WHEN** an on-branch write resolves to `ask` under the setting
- **THEN** the `permissionDecisionReason` names the specific rule that matched and includes
  the unmodified original command as a `!`-prefixed paste-to-override line, in the same
  form the deny channel already uses

### Requirement: git-guard push arms are never configurable onto the ask channel

`git-guard` SHALL resolve every push arm to `permissionDecision: "deny"` regardless of any
configuration value, present or future. No setting SHALL be able to move a push onto the
ask channel. This SHALL hold across every push routing path the guard resolves: an
explicit refspec, the `+force` shorthand, a `:branch` delete, `--all`/`--mirror`, a
destination-less push whose target the guard resolves from git config (`push.default` and
`remote.<remote>.push`), and every push when `GIT_GUARD_BLOCK_ALL_PUSH` is set.

The reason is the same principle that keeps a network download piped into an interpreter
on `shell-guard`'s deny channel: the human reading the command text at an `ask` prompt
cannot see what the push will actually do. The command text does not disclose remote
state, so it cannot show whether the push fast-forwards or overwrites another person's
commits, and a destination-less `git push` does not even name the branch it will land on.
An approval there would be uninformed, and unlike a local write the effect leaves the
machine and reaches other clones and CI.

#### Scenario: A protected-branch push denies even with the local-write channel set to ask

- **WHEN** a push resolves (directly or via config routing) to a protected branch and
  `GIT_GUARD_LOCAL_WRITE_CHANNEL=ask`
- **THEN** the hook resolves `permissionDecision: "deny"` and the push does not run —
  never `"ask"`

#### Scenario: A destination-less config-routed push denies regardless of configuration

- **WHEN** a bare `git push` resolves through `push.default` or `remote.<remote>.push` to a
  protected branch, under any value of `GIT_GUARD_LOCAL_WRITE_CHANNEL`
- **THEN** the hook resolves `permissionDecision: "deny"`

#### Scenario: Block-all-push remains a deny under every configuration

- **WHEN** `GIT_GUARD_BLOCK_ALL_PUSH` is set and any push is attempted, under any value of
  `GIT_GUARD_LOCAL_WRITE_CHANNEL`
- **THEN** the hook resolves `permissionDecision: "deny"`
