## ADDED Requirements

### Requirement: Every block reason names the specific rule that matched

Every message either guard's `deny()` writes to stderr on a block SHALL name the specific
rule that matched — never a generic phrase that could apply to more than one rule. This
applies to every call site in both scripts, including the `shell-guard`
`SHELL_GUARD_EXTRA_PATTERNS` (`EXTRA`) arm, which is the one call site in the repo that
currently fails this (`"matches a configured block pattern"`).

#### Scenario: A built-in shell-guard arm names its rule

- **WHEN** a command is blocked by a built-in `shell-guard` arm (e.g. a recursive delete of
  a protected path, `dd` onto a raw disk device, `chmod 777`)
- **THEN** the reason text identifies that specific arm, not a generic "blocked" phrase

#### Scenario: The EXTRA arm names the matched pattern

- **WHEN** a command is blocked because it matches a user-configured
  `SHELL_GUARD_EXTRA_PATTERNS` entry
- **THEN** the reason text includes the literal pattern that matched, so the model can
  identify what to avoid, instead of the generic "matches a configured block pattern"

#### Scenario: git-guard names the branch and, when applicable, the routing mechanism

- **WHEN** a git command is blocked because it would write a protected branch
- **THEN** the reason text names the resolved branch, and — when the block came from
  destination-less push routing rather than an explicit refspec — the mechanism that
  resolved it (e.g. `push.default=upstream`, `remote.<remote>.push`)

### Requirement: Irreversibility framing is reserved for commands with no safe variant

A block message SHALL carry explicit irreversibility framing (a warning that the action is
destructive and cannot be undone) only for commands in the catastrophic class — those for
which no narrower or reparameterized form of the same command achieves a plausible
legitimate goal safely. The catastrophic class comprises: `rm` recursive delete of a
protected path; `dd` onto a raw disk device; a `>` redirect onto a raw disk device; `mkfs`
/ `wipefs` / `newfs`; destructive `diskutil` (`eraseDisk`, `eraseVolume`, `reformat`,
`zeroDisk`, `secureErase`, `partitionDisk`, `eraseall`, destructive `apfs` subcommands); a
fork bomb; system halt/reboot (`reboot`, `shutdown`, `halt`, `poweroff`); and privilege
escalation (`sudo`, `doas`, `su`, `runuser`, `pkexec`, `gosu`, `sudoedit`, `setpriv`). For
these arms the message SHALL offer no suggested alternative — only the escape hatch.

#### Scenario: A catastrophic command keeps the irreversibility warning

- **WHEN** a command matching a catastrophic-class arm is blocked
- **THEN** the message states the action is destructive and irreversible, and offers no
  alternative command — only the `!`-paste escape hatch

#### Scenario: A non-catastrophic command does not carry irreversibility framing

- **WHEN** a command matching a hygiene-class arm is blocked
- **THEN** the message does not claim the action is irreversible

### Requirement: Hygiene commands name a concrete safe alternative

A block message for a command in the hygiene class — one where a narrower parameterization
or a reviewed multi-step alternative achieves the same plausible legitimate goal safely —
SHALL name that alternative in the message text. The hygiene class comprises: `chmod
777`/`0777`; the `: >` truncate-to-empty idiom; `eval`; and a network download piped into
an interpreter (`curl`/`wget`/`fetch` followed by a shell or language runtime).

#### Scenario: chmod 777 names a narrower mode

- **WHEN** `chmod 777` (or `0777`) is blocked
- **THEN** the message names a narrower alternative (e.g. `chmod 755`)

#### Scenario: the truncate idiom names its replacement

- **WHEN** the `: >` truncate-to-empty idiom is blocked
- **THEN** the message names `printf '' >` as the safe equivalent

#### Scenario: eval names running the command directly

- **WHEN** `eval` is blocked
- **THEN** the message names running the intended command directly, without the `eval`
  indirection, as the alternative

#### Scenario: a network-download pipe names the reviewed-execution path

- **WHEN** a `curl`/`wget`/`fetch` pipeline stage feeding an interpreter is blocked
- **THEN** the message names downloading to a file, reading it, then running it as a
  separate step as the alternative

### Requirement: A pattern of unknown severity is neither catastrophic nor hygiene

A block from a user-configured `SHELL_GUARD_EXTRA_PATTERNS` entry SHALL NOT carry the
catastrophic irreversibility framing, because the guard cannot know the severity of a
user-supplied pattern, and SHALL NOT fabricate a safe alternative it cannot verify. It
SHALL still name the matched pattern (per the rule-naming requirement above) and carry the
variants-also-blocked clause and the escape hatch like every other block.

#### Scenario: An EXTRA-pattern block stays neutral

- **WHEN** a command is blocked by a user-configured `SHELL_GUARD_EXTRA_PATTERNS` entry
- **THEN** the message neither claims the action is irreversible nor suggests a specific
  alternative command, but does name the matched pattern

### Requirement: Every block states that variants will also be blocked

Every message either guard writes on a block SHALL state that variants of the same
command — different flag order, quoting, a wrapper prefix, or (for git-guard) a
differently-phrased command that resolves to the same protected branch — are also blocked,
so the model does not read the block as a reason to try a rephrased form.

#### Scenario: shell-guard states variants are also blocked

- **WHEN** shell-guard blocks a command
- **THEN** the message states that reworded or reordered variants of the same command will
  also be blocked

#### Scenario: git-guard states variants are also blocked

- **WHEN** git-guard blocks a command
- **THEN** the message states that a differently-phrased command resolving to the same
  protected branch will also be blocked

### Requirement: The escape hatch is present in every blocked message

Every block message, regardless of class or which guard produced it, SHALL include the
command handed back as a ready-to-paste `!`-prefixed line, and SHALL point at the guard's
disable mechanism. This requirement is unconditional — no class or arm is exempt.

#### Scenario: A catastrophic block includes the escape hatch

- **WHEN** a catastrophic-class command is blocked
- **THEN** the message includes the `!`-prefixed re-paste line and the disable pointer

#### Scenario: A hygiene block includes the escape hatch

- **WHEN** a hygiene-class command is blocked
- **THEN** the message includes the `!`-prefixed re-paste line and the disable pointer

#### Scenario: A git-guard block includes the escape hatch

- **WHEN** git-guard blocks a command
- **THEN** the message includes the `!`-prefixed re-paste line and the `GIT_GUARD_DISABLE`
  / `/git-guard` pointer, unchanged from today

### Requirement: git-guard and shell-guard share one message contract

`git-guard` and `shell-guard` block messages SHALL follow the same structural contract —
name the matched rule, apply class-appropriate framing, state that variants are also
blocked, and include the escape hatch — while `git-guard`'s existing branch-naming,
routing-mechanism-naming, protected-set listing, and alternative-workflow line (`"Use a
feature branch or 'develop'"`) remain exactly as they are today. This requirement
constrains the *shell-guard* side to converge on the existing `git-guard` reference
quality; it does not permit `git-guard`'s message to regress toward `shell-guard`'s
pre-change state.

#### Scenario: git-guard's reference content is preserved

- **WHEN** git-guard's message is updated for the new variants-also-blocked clause
- **THEN** the resolved branch name, the protected-branch list, the routing-mechanism
  phrase (when applicable), and the alternative-workflow line are unchanged from before
  this change

#### Scenario: shell-guard converges on the same contract elements

- **WHEN** shell-guard's message is updated
- **THEN** it carries the same contract elements git-guard already carries: a
  rule-specific reason, a variants-also-blocked clause, and the escape hatch — with the
  addition of the catastrophic/hygiene framing split that git-guard, having only one
  message class, does not need
