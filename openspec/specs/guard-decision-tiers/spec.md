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

### Requirement: git-guard remains deny-only

`git-guard` SHALL NOT emit `permissionDecision: "ask"` for any arm. Every action that
today resolves to `deny()` (a local write while on a protected branch, a push whose
resolved target is a protected branch, or a force `branch` operation naming a protected
branch) SHALL continue to resolve to `permissionDecision: "deny"` (or the equivalent
exit-2/stderr path), with no behavioural change from this capability.

#### Scenario: A protected-branch push still denies outright

- **WHEN** a push resolves (directly or via config routing) to a protected branch
- **THEN** the hook resolves `permissionDecision: "deny"` and the push does not run —
  never `"ask"`

#### Scenario: A protected-branch local write still denies outright

- **WHEN** a `commit`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `am`, or
  history-moving `reset` runs while the current branch is protected
- **THEN** the hook resolves `permissionDecision: "deny"`, unchanged from today's
  behaviour

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

