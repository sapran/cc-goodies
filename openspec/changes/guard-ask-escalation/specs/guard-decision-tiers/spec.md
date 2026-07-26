## ADDED Requirements

> **Gating note.** Every requirement below is contingent on the Task 1 headless-`ask`
> experiment (`tasks.md` §1) resolving go, per `design.md` Decision D3. None of these
> requirements are implemented, and this capability does not exist, until that gate
> resolves. The requirements describe the contract this change would establish if it
> proceeds.

### Requirement: shell-guard arms are tiered into catastrophic (deny) and hygiene (ask)

`shell-guard` SHALL classify each of its detection arms into exactly one of two decision
tiers: **catastrophic**, which SHALL resolve to `permissionDecision: "deny"`, and
**hygiene**, which SHALL resolve to `permissionDecision: "ask"`. The catastrophic tier
SHALL comprise: recursive delete of a protected path, `dd` or a redirect onto a raw disk
device, `mkfs`/`wipefs`/`newfs`/destructive `diskutil`, fork bomb, and a network download
piped into an interpreter (`curl`/`wget`/`fetch` into a shell or language runtime). The
hygiene tier SHALL comprise: `chmod 777`/`0777`, the `: >` truncate-to-empty idiom,
privilege escalation (`sudo`/`doas`/`su`/`runuser`/`pkexec`/`gosu`/`sudoedit`/`setpriv`),
`eval`, and system halt/reboot (`reboot`/`shutdown`/`halt`/`poweroff`). Commands matching
`SHELL_GUARD_EXTRA_PATTERNS` SHALL remain in the catastrophic (deny) tier, since the guard
has no way to infer the severity of a user-supplied pattern.

#### Scenario: A catastrophic arm still denies outright

- **WHEN** a command matches a catastrophic arm (e.g. `rm -rf /`, `dd … of=/dev/disk0`,
  `mkfs.ext4 /dev/sda`, a fork bomb, or `curl … | bash`)
- **THEN** the hook resolves `permissionDecision: "deny"` and the command does not run

#### Scenario: A hygiene arm asks instead of denying

- **WHEN** a command matches a hygiene arm (e.g. `chmod 777 x`, `: > file`, `sudo apt
  update`, `eval "…"`, or `reboot`)
- **THEN** the hook resolves `permissionDecision: "ask"`, escalating to the human via the
  permission prompt, instead of an unconditional block

#### Scenario: User-configured extra patterns stay deny-tier

- **WHEN** a command matches a pattern in `SHELL_GUARD_EXTRA_PATTERNS`
- **THEN** the hook resolves `permissionDecision: "deny"`, regardless of what the
  catastrophic/hygiene split does for the built-in arms

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

### Requirement: non-interactive sessions can force deny-only behaviour

`shell-guard` SHALL support a configuration key, resolved via the existing
`env var → ~/.claude/shell-guard.conf → built-in default` precedence and the existing
non-sourcing `conf_get` parser, that forces every hygiene-tier arm to resolve
`permissionDecision: "deny"` instead of `"ask"`, for use in headless, background, or
otherwise unattended sessions where an `ask` prompt would have no human to answer it. The
default polarity of this key (tiering on by default with this key as an opt-out, vs.
tiering off by default with this key as an opt-in) SHALL be fixed by the Task 1 experiment
result recorded in `design.md`, not assumed by this requirement.

#### Scenario: The deny-only key overrides the hygiene tier

- **WHEN** the deny-only configuration key is set and a command matches a hygiene-tier arm
- **THEN** the hook resolves `permissionDecision: "deny"`, exactly as if the arm were
  catastrophic-tier

#### Scenario: The deny-only key does not affect the catastrophic tier

- **WHEN** the deny-only configuration key is set and a command matches a catastrophic-tier
  arm
- **THEN** the hook resolves `permissionDecision: "deny"`, identical to its behaviour with
  the key unset (no observable change)

#### Scenario: The deny-only key is read with the existing precedence

- **WHEN** the deny-only key is set as an environment variable, as a
  `~/.claude/shell-guard.conf` line, or not at all
- **THEN** the environment variable wins over the conf file, the conf file wins over the
  built-in default, and a malformed or adversarial conf file value cannot cause anything
  beyond a KEY=VALUE string read (never sourced/executed)

### Requirement: the escape hatch and fail-open behaviour are preserved for every tier

Every arm, regardless of tier, SHALL continue to hand back the exact command as a
ready-to-paste `!`-prefixed override line, exactly as `deny()` does today. Both guards
SHALL continue to fail open (allow the command, print a one-line warning) when `jq` is
unavailable, before any tier or decision logic is reached.

#### Scenario: A denied catastrophic command still offers the paste-to-override line

- **WHEN** a catastrophic-tier arm blocks a command
- **THEN** the response includes the unmodified original command as a `!`-prefixed line
  the human can paste into their own shell

#### Scenario: An asked hygiene command still offers the paste-to-override line

- **WHEN** a hygiene-tier arm resolves to `"ask"` and the human declines the prompt
- **THEN** the response includes the unmodified original command as a `!`-prefixed line,
  identical in form to the catastrophic-tier deny response

#### Scenario: Missing jq fails open regardless of tier

- **WHEN** `jq` is not available on the system running either guard
- **THEN** the hook prints a one-line warning and allows the command, before any
  catastrophic/hygiene classification or `ask`/`deny` decision is evaluated

### Requirement: detection logic is unchanged by tiering

Introducing decision tiers SHALL NOT add, remove, widen, or narrow any existing detection
pattern, `case` arm, wrapper-skip rule, or command/segment/stage-splitting behaviour in
either guard. Tiering SHALL only select which output mechanism (`deny`/exit-2-stderr vs.
`ask`/JSON-stdout-exit-0) an already-matched arm uses.

#### Scenario: A command that was allowed before tiering is still allowed after

- **WHEN** a command matched no arm in either guard before this capability existed
- **THEN** it still matches no arm after tiering is introduced, and runs unmodified

#### Scenario: A command that was blocked before tiering is still blocked or asked, never silently allowed

- **WHEN** a command matched a specific arm before this capability existed
- **THEN** after tiering, it still matches that same arm and resolves to either `deny` or
  `ask` per the taxonomy — never falls through to a plain allow as a side effect of adding
  tiers

### Requirement: no silent command rewriting via `updatedInput`

Neither guard SHALL use the hook API's `updatedInput` field to substitute a different
command for the one that was evaluated, for any arm, under any tier. A suggested safe
alternative MAY be included as text within `permissionDecisionReason`, but the command
that actually runs (when one runs) SHALL always be the one Claude originally proposed,
never a guard-modified substitute.

#### Scenario: A hygiene-tier ask never substitutes a rewritten command

- **WHEN** a hygiene-tier arm resolves to `"ask"` and the human approves it
- **THEN** the command that runs is byte-for-byte the command Claude originally proposed,
  not a guard-rewritten variant

#### Scenario: A reason may suggest an alternative without applying it

- **WHEN** a hygiene-tier arm's `permissionDecisionReason` names a safer alternative
  command
- **THEN** that alternative is text shown to the human only — it is never substituted into
  `updatedInput` or otherwise run automatically
