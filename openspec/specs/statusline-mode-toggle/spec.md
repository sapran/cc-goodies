# statusline-mode-toggle Specification

## Purpose
TBD - created by archiving change add-statusline-mode-toggle. Update Purpose after archive.
## Requirements
### Requirement: Two render modes with enriched as the default

The statusline SHALL support exactly two render modes — `enriched` (the existing full
two-line output) and `lean` (a single compact line). The active mode SHALL be resolved on
every render. When no mode has been configured, the statusline SHALL render in `enriched`
mode, so that an installation carrying no mode configuration renders exactly as it did before
this capability existed.

#### Scenario: No configuration renders enriched

- **WHEN** the statusline renders and no mode configuration is present
- **THEN** it renders in `enriched` mode (the full two-line output), identical to its behaviour before this capability

#### Scenario: Configured lean mode renders lean

- **WHEN** the mode is configured as `lean`
- **THEN** the statusline renders in `lean` mode on the next render

### Requirement: Lean mode renders a single compact line

In `lean` mode the statusline SHALL render exactly one line containing the compressed working
directory, the git branch (or worktree token) when present, the model display name, and the
`c:` context-window gauge. The `c:` gauge SHALL retain the value-driven severity colour it
uses in enriched mode. Lean mode SHALL omit the `user@host` segment, the `task → latest`
prompt snippet, the effort suffix, the `s:` 5-hour and `w:` 7-day rate-limit gauges, and all
`⧗` elapsed-duration and `⟲` reset-countdown time suffixes.

#### Scenario: Lean renders cwd, branch, model, and context gauge on one line

- **WHEN** the statusline renders in `lean` mode with a cwd, a git branch, a model name, and a context-window percentage available
- **THEN** the output is a single line of the compressed cwd, the `[branch]` token, the model display name, and the `c:NN%` gauge — for example `~/cab/claude.ai  [main]  Opus 4.8  c:42%`

#### Scenario: Lean omits the enriched-only segments

- **WHEN** the statusline renders in `lean` mode
- **THEN** the output contains no `user@host` segment, no `task → latest` snippet, no `(effort)` suffix, no `s:` or `w:` rate-limit gauge, and no `⧗` or `⟲` time suffix

#### Scenario: Lean keeps the context gauge's severity colour

- **WHEN** the context gauge's value falls in a non-green severity tier (e.g. `c:92%`) and the mode is `lean`
- **THEN** the `c:` token is rendered in that tier's colour, exactly as it would be in enriched mode

#### Scenario: Lean shows the worktree token inside a worktree

- **WHEN** the statusline renders in `lean` mode and the event reports a worktree name
- **THEN** the line shows the `wt:` worktree token in place of the branch token, matching the enriched-mode git segment behaviour

### Requirement: Enriched mode is unchanged

`enriched` mode SHALL render the existing two-line statusline with no change to its content,
layout, colours, gauges, or degradation behaviour. The `statusline-severity-colours` and
`statusline-time-readouts` capabilities SHALL continue to describe enriched-mode rendering in
full; this capability SHALL NOT alter any of their requirements.

#### Scenario: Enriched mode matches the pre-existing output

- **WHEN** the statusline renders in `enriched` mode
- **THEN** it produces the same two-line output — `user@host`, cwd, branch/worktree, `task → latest`, then model, effort, and the `c:`/`s:`/`w:` gauges with their time suffixes — that it produced before this capability, governed by the existing statusline specs

### Requirement: Mode resolved each render from a configuration file, parsed safely

The active mode SHALL be read on every render from `~/.claude/statusline.conf`, from a
`STATUSLINE_MODE` key whose value is one of `enriched` or `lean`. The configuration file
SHALL be read, never executed (never `source`d): the value SHALL be extracted by text parsing
(such as a `grep` plus parameter expansion) so that arbitrary content in the file cannot run
as shell. A `STATUSLINE_MODE` value outside `{enriched, lean}`, an absent key, or an absent
file SHALL resolve to the default `enriched` mode without error.

#### Scenario: Mode change takes effect on the next render

- **WHEN** the `STATUSLINE_MODE` value in `~/.claude/statusline.conf` changes while a Claude Code session is running
- **THEN** the next render reads the new value and renders in the new mode, with no restart or re-install

#### Scenario: Invalid or absent value fails soft to enriched

- **WHEN** `~/.claude/statusline.conf` is absent, lacks a `STATUSLINE_MODE` key, or sets it to a value other than `enriched` or `lean`
- **THEN** the statusline renders in `enriched` mode and does not error

#### Scenario: The configuration file is never executed

- **WHEN** `~/.claude/statusline.conf` contains shell syntax beyond a `STATUSLINE_MODE=` assignment
- **THEN** the statusline reads the mode value by text parsing without executing any of the file's contents

### Requirement: Lean mode performs strictly less work than enriched

In `lean` mode the statusline SHALL NOT perform the enriched-only computations whose output it
does not display — specifically the transcript reads that derive the `task`/`latest` snippet,
the rate-limit gauge and reset-countdown bookkeeping, the elapsed-duration computation, and
the effort-from-settings fallback. Lean-mode output SHALL therefore be independent of the
transcript and rate-limit data.

#### Scenario: Lean output does not depend on the transcript

- **WHEN** the statusline renders in `lean` mode
- **THEN** its output is the same whether or not a transcript path is provided or readable, because lean mode does not read the transcript

#### Scenario: Lean output does not depend on rate-limit data

- **WHEN** the statusline renders in `lean` mode with rate-limit fields present in the event
- **THEN** the rate-limit gauges and reset countdowns are neither computed nor shown

### Requirement: A command toggles or sets the mode at runtime

The plugin SHALL provide a `/statusline-toggle` command that changes the persisted mode. With
no argument it SHALL flip the current mode (`enriched` → `lean`, `lean` → `enriched`, treating
an unset mode as `enriched`); with an `enriched` or `lean` argument it SHALL set that mode
explicitly. The command SHALL persist the value by writing the `STATUSLINE_MODE` key in
`~/.claude/statusline.conf`, updating only that key and preserving any other lines in the
file, and SHALL report the resulting mode and that it applies on the next render.

#### Scenario: Bare invocation flips the mode

- **WHEN** the current mode is `enriched` and the user runs `/statusline-toggle` with no argument
- **THEN** `STATUSLINE_MODE` is set to `lean` and the command reports that lean takes effect on the next render

#### Scenario: Argument sets an explicit mode

- **WHEN** the user runs `/statusline-toggle enriched`
- **THEN** `STATUSLINE_MODE` is set to `enriched` regardless of the prior value

#### Scenario: Other configuration lines are preserved

- **WHEN** `~/.claude/statusline.conf` contains lines other than `STATUSLINE_MODE`
- **THEN** toggling the mode rewrites only the `STATUSLINE_MODE` line and leaves the other lines unchanged

### Requirement: Uninstall removes the mode configuration

`/statusline-uninstall` SHALL remove `~/.claude/statusline.conf` as part of reverting the
plugin's durable state, completing the install ⇄ uninstall symmetry for the mode toggle. It
SHALL do so without error when the file is absent, and it SHALL continue to refuse to touch a
statusline configuration the user wired by hand.

#### Scenario: Uninstall deletes the conf when present

- **WHEN** `~/.claude/statusline.conf` exists and the user runs `/statusline-uninstall`
- **THEN** the conf is removed along with the rest of the plugin's installed state

#### Scenario: Uninstall is clean when the conf is absent

- **WHEN** `~/.claude/statusline.conf` does not exist and the user runs `/statusline-uninstall`
- **THEN** uninstall completes without error

