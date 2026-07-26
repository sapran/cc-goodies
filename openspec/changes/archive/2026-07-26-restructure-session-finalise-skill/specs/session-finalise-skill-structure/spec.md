## ADDED Requirements

### Requirement: Invariant-framed instruction, not an enumerated script

The `session-finalise` skill SHALL state its ordering requirement as a single invariant —
nothing is destroyed or discarded before it is saved and confirmed — rather than as a
numbered, sequentially-followed script whose every position is implied to matter equally.
Phase names MAY still be listed for reference, but the skill SHALL NOT claim that following
a fixed step order is itself the safety mechanism when only part of that order is actually
load-bearing.

#### Scenario: Destructive phase depends on the invariant, not a step number

- **WHEN** the skill reaches a phase that deletes files or removes a worktree
- **THEN** it has already surfaced and (where applicable) committed or explicitly deferred
  any work that phase would otherwise destroy, regardless of which numbered position either
  phase occupies

#### Scenario: Non-destructive phases are not falsely bound to a fixed order

- **WHEN** the skill proposes which phases apply to a given session (e.g. memory, handoff,
  tracker updates, summary)
- **THEN** it does not require or imply that these phases must run in a specific relative
  order to remain safe, since none of them can destroy prior work

### Requirement: Progressive disclosure with no duplicated contract

The phase/gate contract SHALL exist in exactly one place at a time: a short router in
`SKILL.md` naming phases and invariants, with phase mechanics living in `references/`,
loaded only when a phase applies. `README.md` SHALL NOT re-render the phase/gate table;
it SHALL point at the skill instead. No phase's procedural detail SHALL be present in more
than one of `SKILL.md`, `references/`, and `README.md` simultaneously.

#### Scenario: SKILL.md names a phase without re-describing its mechanics

- **WHEN** SKILL.md refers to a phase that has a `references/` file
- **THEN** SKILL.md states when to consult that file rather than restating its procedure

#### Scenario: README does not duplicate the phase table

- **WHEN** a user reads `README.md` for what the skill does
- **THEN** the phase/gate contract is not rendered a second time in full; the README
  summarizes and points at the skill

#### Scenario: A reference file's content is actually consulted, not orphaned

- **WHEN** a phase with reference-only detail (e.g. the cleanup phase's worktree-and-project-dir
  removal rule) applies during a run
- **THEN** that detail is applied correctly, demonstrating the reference was read rather than
  silently skipped in favor of a router summary alone

### Requirement: Memory phase is reconciliation against auto-memory, not schema authorship

The durable-memory phase SHALL treat the harness's automatic memory-saving as the primary
mechanism and limit itself to reconciliation: reading the project's `MEMORY.md`, judging what
this session established that no existing file records, and what recorded memory is now stale
given what's observed on disk. The phase SHALL NOT restate the memory directory path, the
project-slug derivation rule, the frontmatter type enum, or the `MEMORY.md` index format as
skill-owned content — those are supplied natively by the harness. The phase MAY still instruct
matching an existing file's frontmatter shape when authoring a new memory file, as a
harness-agnostic fallback for the case where no example file yet exists.

#### Scenario: Session establishes a fact auto-memory did not capture

- **WHEN** the session produces a durable fact (decision, gotcha, non-obvious config) that no
  file in the project's memory store records
- **THEN** the phase proposes saving it, without first reciting the memory path/schema/index
  conventions as if they were the skill's own rules

#### Scenario: Recorded memory is stale

- **WHEN** an existing memory file no longer matches what the session observes on disk
- **THEN** the phase flags it as stale and proposes an update, rather than leaving reconciliation
  implicit

#### Scenario: No existing memory file to copy from

- **WHEN** the project's memory store has no existing file for the phase to pattern-match
- **THEN** the phase still knows how to author one via the standard frontmatter shape rather
  than fabricating an undocumented format or refusing to save the fact

### Requirement: Tracker detection describes the capability, not an enumerated vendor list

Tracker detection SHALL identify whether a task-tracker capability is reachable in the current
session — an MCP tool or CLI that can read, comment on, label, or change the status of a
tracked item — rather than matching available tool names against a fixed vendor substring list.
Detection SHALL NOT fail closed on a tracker vendor the skill's content does not happen to name.

#### Scenario: An unlisted tracker vendor is still detected

- **WHEN** a session has a tracker MCP tool or CLI available whose vendor name does not appear
  in any fixed list the skill's content might once have enumerated
- **THEN** the phase still recognizes it as a tracker capability by what the tool does, and
  proposes tracker updates through it

#### Scenario: No tracker capability is reachable

- **WHEN** no MCP tool or CLI in the session offers tracker-like read/write capability
- **THEN** the phase emits a plain-text checklist of the changes for the user to apply manually,
  and does not fabricate an integration

#### Scenario: Detection stays precise

- **WHEN** the session has a tool that is unrelated to task tracking but superficially resembles
  one by name
- **THEN** the phase does not misclassify it as a tracker capability merely from a name match

### Requirement: No user-specific product preferences in plugin content

The skill, its references, its command, and its README SHALL NOT encode any single user's
product or tool preferences (e.g. a rule that one tracker's edits must avoid HTML, or a
standing preference for one CLI over an equivalent MCP integration) as if they were a rule
every installer of the plugin inherits. Such preferences belong in the operator's own global
configuration, not in distributed plugin content.

#### Scenario: Tracker phase carries no vendor-specific formatting rule

- **WHEN** the tracker phase proposes an update to a specific tracker
- **THEN** it does not impose a hard-coded formatting constraint (e.g. "no HTML") that the
  skill itself asserts as a universal rule rather than deriving from the tool's own
  documented constraints or the user's own configuration

#### Scenario: No standing tool-preference rule between equivalent integrations

- **WHEN** more than one integration path could perform the same tracker update (e.g. both an
  MCP server and a CLI are available)
- **THEN** the skill's content does not assert a fixed preference for one over the other as
  plugin policy

### Requirement: Consent gates and save-before-destroy ordering are preserved unchanged

Every mutating action SHALL still require explicit confirmation before it executes: commits,
pushes, tracker mutations, file deletions, and worktree/Claude-Code-project-dir removals.
Commits SHALL still never target `main`. Pushes SHALL still never happen without explicit
confirmation stating exactly what will be pushed where. Work capable of being lost SHALL
still be surfaced and preserved (committed, stashed, or explicitly deferred with the user's
knowledge) before any destructive cleanup step runs. This restructure changes how the skill's
instructions are organized; it SHALL NOT change what is safe to do without asking.

#### Scenario: Every mutation still confirms

- **WHEN** the skill is about to commit, push, mutate a tracker item, delete a file, or remove
  a worktree or its Claude Code project dir
- **THEN** it asks for explicit confirmation before performing that action, exactly as before
  the restructure

#### Scenario: Commits never target main

- **WHEN** the skill proposes a commit
- **THEN** the target branch is `develop` or another non-`main` branch, never `main`

#### Scenario: Cleanup still runs only after preservation

- **WHEN** the skill reaches a step that deletes scratch files or removes a worktree
- **THEN** any uncommitted work relevant to that path has already been surfaced, and either
  committed, stashed, or explicitly confirmed as discardable by the user
