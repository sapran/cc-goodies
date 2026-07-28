# guard-decision-tiers Specification

## Purpose
TBD - created by archiving change guard-ask-escalation. Update Purpose after archive.
## Requirements
### Requirement: shell-guard arms resolve to a deny or ask channel (AXIS 2)

`shell-guard` SHALL classify each of its detection arms onto exactly one of two channels
on AXIS 2 (`channel: deny | ask` — can a human meaningfully approve this specific
command?): the **deny channel**, which SHALL resolve to `permissionDecision: "deny"`, and
the **ask channel**, which SHALL resolve to `permissionDecision: "ask"`. The deny channel
SHALL comprise: recursive delete of a protected path, `dd` or a redirect onto a raw disk
device, `mkfs`/`wipefs`/`newfs`/destructive `diskutil`, a fork bomb, a network download
piped into an interpreter (`curl`/`wget`/`fetch` into a shell or language runtime), and
system halt/reboot (`reboot`/`shutdown`/`halt`/`poweroff`). The ask channel SHALL
comprise: `chmod 777`/`0777`, the `: >` truncate-to-empty idiom, privilege escalation
(`sudo`/`doas`/`su`/`runuser`/`pkexec`/`gosu`/`sudoedit`/`setpriv`), and `eval` — except
that an `eval` invocation whose argument contains a download command word (`curl`/`wget`/
`fetch`) SHALL resolve to the deny channel instead, per the dedicated requirement below.
Commands matching `SHELL_GUARD_EXTRA_PATTERNS` SHALL remain on the deny channel, since the
guard has no way to infer the severity of a user-supplied pattern.

#### Scenario: A deny-channel arm still denies outright

- **WHEN** a command matches a deny-channel arm (e.g. `rm -rf /`, `dd … of=/dev/disk0`,
  `mkfs.ext4 /dev/sda`, a fork bomb, `curl … | bash`, or `reboot`)
- **THEN** the hook resolves `permissionDecision: "deny"` and the command does not run

#### Scenario: An ask-channel arm asks instead of denying

- **WHEN** a command matches an ask-channel arm (e.g. `chmod 777 x`, `: > file`, `sudo apt
  update`, or `eval "some code"` with no download command word in its argument)
- **THEN** the hook resolves `permissionDecision: "ask"`, escalating to the human via the
  permission prompt, instead of an unconditional block

#### Scenario: User-configured extra patterns stay on the deny channel

- **WHEN** a command matches a pattern in `SHELL_GUARD_EXTRA_PATTERNS`
- **THEN** the hook resolves `permissionDecision: "deny"`, regardless of what the deny/ask
  channel split does for the built-in arms

### Requirement: an `eval` argument that fetches remote content stays on the deny channel

`shell-guard` SHALL resolve `permissionDecision: "deny"`, not `"ask"`, for an `eval`
invocation whose argument contains a download command word (`curl`, `wget`, or `fetch`),
even though `eval` is otherwise an ask-channel arm. This applies the same principle as the
network-download-piped-to-interpreter arm: a human reading the command text at an `ask`
prompt sees the URL, not the payload the URL serves at run time, so an `ask` approval
there would be uninformed. This requirement changes only which channel an already-matched
`eval` arm resolves to for this sub-case — it does not add a new detection pattern, and the
`eval` arm's trigger condition (command word == `eval`) is unchanged.

#### Scenario: `eval` fetching and running remote content is denied, not asked

- **WHEN** an `eval` command's argument contains `curl`, `wget`, or `fetch` (e.g. `eval
  "$(curl http://x)"`)
- **THEN** the hook resolves `permissionDecision: "deny"`, not `"ask"`

#### Scenario: `eval` without a download command word still asks

- **WHEN** an `eval` command's argument contains no `curl`/`wget`/`fetch` command word
- **THEN** the hook resolves `permissionDecision: "ask"`, per the ask-channel default for
  the `eval` arm

### Requirement: the escape hatch and fail-open behaviour are preserved on every channel

Every arm, regardless of channel, SHALL continue to hand back the exact command as a
ready-to-paste `!`-prefixed override line, exactly as `deny()` does today. Both guards
SHALL continue to fail open (allow the command, print a one-line warning) when `jq` is
unavailable, before any channel or decision logic is reached.

#### Scenario: A denied deny-channel command still offers the paste-to-override line

- **WHEN** a deny-channel arm blocks a command
- **THEN** the response includes the unmodified original command as a `!`-prefixed line
  the human can paste into their own shell

#### Scenario: An asked ask-channel command still offers the paste-to-override line

- **WHEN** an ask-channel arm resolves to `"ask"` and the human declines the prompt
- **THEN** the response includes the unmodified original command as a `!`-prefixed line,
  identical in form to the deny-channel response

#### Scenario: Missing jq fails open regardless of channel

- **WHEN** `jq` is not available on the system running either guard
- **THEN** the hook prints a one-line warning and allows the command, before any
  deny/ask channel classification or decision is evaluated

### Requirement: detection logic is unchanged by channeling

Introducing decision channels SHALL NOT add, remove, widen, or narrow any existing
detection pattern, `case` arm, wrapper-skip rule, or command/segment/stage-splitting
behaviour in either guard. Channeling SHALL only select which output mechanism
(`deny`/exit-2-stderr vs. `ask`/JSON-stdout-exit-0) an already-matched arm uses. The one
permitted refinement under this requirement is channel-selection based on
already-matched-arm argument text (the `eval`/download-command-word exception above) — it
changes no detection pattern, only which channel that already-matched arm resolves to.

#### Scenario: A command that was allowed before channeling is still allowed after

- **WHEN** a command matched no arm in either guard before this capability existed
- **THEN** it still matches no arm after channeling is introduced, and runs unmodified

#### Scenario: A command that was blocked before channeling is still blocked or asked, never silently allowed

- **WHEN** a command matched a specific arm before this capability existed
- **THEN** after channeling, it still matches that same arm and resolves to either `deny`
  or `ask` per the taxonomy — never falls through to a plain allow as a side effect of
  introducing channels

### Requirement: no silent command rewriting via `updatedInput`

Neither guard SHALL use the hook API's `updatedInput` field to substitute a different
command for the one that was evaluated, for any arm, under any channel. A suggested safe
alternative MAY be included as text within `permissionDecisionReason`, but the command
that actually runs (when one runs) SHALL always be the one Claude originally proposed,
never a guard-modified substitute.

#### Scenario: An ask-channel decision never substitutes a rewritten command

- **WHEN** an ask-channel arm resolves to `"ask"` and the human approves it
- **THEN** the command that runs is byte-for-byte the command Claude originally proposed,
  not a guard-rewritten variant

#### Scenario: A reason may suggest an alternative without applying it

- **WHEN** an ask-channel arm's `permissionDecisionReason` names a safer alternative
  command
- **THEN** that alternative is text shown to the human only — it is never substituted into
  `updatedInput` or otherwise run automatically

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

Any value other than the exact string `ask` SHALL be treated as `deny`, so a
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

- **WHEN** `GIT_GUARD_LOCAL_WRITE_CHANNEL` resolves to any value other than the exact
  lowercase `ask` (for example `ASK`, `yes`, `1`, or `asky`)
- **THEN** the hook treats it as `deny` and blocks on-branch writes as usual

#### Scenario: An asked on-branch write carries the same message substance as a denial

- **WHEN** an on-branch write resolves to `ask` under the setting
- **THEN** the `permissionDecisionReason` names the specific rule that matched and includes
  the unmodified original command as a `!`-prefixed paste-to-override line, in the same
  form the deny channel already uses

#### Scenario: A failed ask delivery falls back to deny, never to allow

- **WHEN** the guard has resolved an on-branch write to `ask` but cannot emit the decision
  object (for example the `jq` invocation fails because the command text is large enough to
  exceed the argument limit)
- **THEN** the hook resolves `permissionDecision: "deny"` (exit 2, reason on stderr) rather
  than exiting 0 with no object, which the harness would read as a plain allow

#### Scenario: The ask reason does not promise anything about unmatched command segments

- **WHEN** an on-branch write resolves to `ask` as part of a compound command that also
  contains a form the guard does not resolve (`bash -c "…"`, `sudo -u`, a gitconfig alias)
- **THEN** the `permissionDecisionReason` scopes its assurance to the matched write and to
  pushes the guard can resolve, and states that approving releases the whole command — it
  SHALL NOT claim unconditionally that nothing will be published

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

