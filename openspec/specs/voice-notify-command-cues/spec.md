# voice-notify-command-cues Specification

## Purpose
TBD - created by archiving change voice-notify-shell-and-blocked-cues. Update Purpose after archive.
## Requirements
### Requirement: Duration-gated completion cue for foreground commands

The plugin SHALL announce a foreground shell command when it completes, but only when the
command ran for at least a configurable threshold (`CLAUDE_VOICE_NOTIFY_CMD_QUIET_UNDER`,
default approximately 60 seconds). A command shorter than the threshold SHALL be silent, because
a user who is still at the keyboard has already seen it finish. The elapsed time SHALL be taken
from the harness-supplied duration on the completion event where one is provided, falling back to
the plugin's own start record. A command is foreground when its completion carries no background
task id.

#### Scenario: Long command speaks on completion

- **WHEN** a foreground shell command completes having run longer than the configured threshold
- **THEN** a completion cue is spoken naming the command's purpose

#### Scenario: Quick command stays silent

- **WHEN** a foreground shell command completes having run for less than the configured threshold
- **THEN** no cue is spoken

#### Scenario: Threshold of zero speaks for every command

- **WHEN** the threshold is configured as zero and any foreground command completes
- **THEN** the completion cue is spoken regardless of how long the command ran

#### Scenario: Missing duration falls back to the start record

- **WHEN** a completion event carries no duration field but a start record exists for that command
- **THEN** the elapsed time is computed from the start record rather than the cue being skipped

### Requirement: Command completion cue distinguishes outcomes

The completion cue SHALL distinguish a command that succeeded, one that failed, one that was
interrupted, and one that timed out, so the outcome is clear without looking at the screen. A
failure SHALL be routed through the failure event the harness fires when a tool call does not
complete normally, and the interrupted and timed-out cases SHALL be identified from that event's
own flags rather than inferred.

#### Scenario: Success is distinguishable from failure

- **WHEN** a long foreground command completes successfully
- **THEN** the cue announces completion, drawn from a different pool than the failure phrasing

#### Scenario: Failure is announced as a failure

- **WHEN** a long foreground command fails
- **THEN** the cue announces that it did not succeed

#### Scenario: Timeout has its own phrasing

- **WHEN** a command's failure event indicates it timed out
- **THEN** the cue says so, distinctly from an ordinary failure

#### Scenario: Interruption has its own phrasing

- **WHEN** a command's failure event indicates it was interrupted
- **THEN** the cue says so, distinctly from an ordinary failure

### Requirement: Still-running cue for a command that outlives a threshold

The plugin SHALL announce a shell command that is still running after a configurable interval
(`CLAUDE_VOICE_NOTIFY_CMD_RUNNING_AFTER`, default approximately 45 seconds), so a user who
stepped away learns that the session is busy rather than stuck. Because the harness fires no
event while a command runs, this cue SHALL be produced by the elected watcher defined below. Each
command SHALL receive at most one still-running cue. Setting the interval to zero SHALL disable
the still-running cue while leaving the completion cue intact.

#### Scenario: Command still running past the interval is announced

- **WHEN** a shell command has been running longer than the configured interval and has not yet
  been announced
- **THEN** a still-running cue is spoken naming the command's purpose

#### Scenario: Each command is announced at most once while running

- **WHEN** a command that already received a still-running cue is still running at a later poll
- **THEN** no further still-running cue is spoken for it

#### Scenario: Short command is never announced as running

- **WHEN** a command completes before the configured interval elapses
- **THEN** no still-running cue is spoken for it

#### Scenario: Interval of zero disables the running cue only

- **WHEN** the still-running interval is configured as zero
- **THEN** no still-running cue is ever spoken, and completion cues still behave normally

### Requirement: An announced command always reports its completion

A command that was announced as still running SHALL have its completion announced when it
finishes, regardless of the completion threshold. Having been told that a command is running, the
user SHALL NOT be left without the matching all-clear.

#### Scenario: Announced command reports completion below the threshold

- **WHEN** a command received a still-running cue and then completes in less time than the
  completion threshold requires
- **THEN** its completion cue is spoken anyway

#### Scenario: Announced command that fails still reports

- **WHEN** a command received a still-running cue and then fails, times out, or is interrupted
- **THEN** the matching outcome cue is spoken

### Requirement: One watcher elected per session

Mid-flight announcement requires a poller, and the plugin SHALL run at most one per session
rather than one per command. A command dispatch SHALL record its start and then attempt to claim
a create-only watcher election; only the claimant SHALL poll. The watcher SHALL exit once no
command start records and no unresolved permission reminders remain, and the next dispatch SHALL
elect a fresh watcher. The watcher SHALL bound its own lifetime below the hook timeout under
which it runs, since a hook process that exceeds its timeout is killed by the harness. An
election claim left behind by a process that never released it SHALL be reclaimed after a bounded
interval, so the plugin cannot be wedged into permanent silence.

#### Scenario: Only one watcher runs for a burst of commands

- **WHEN** several shell commands are dispatched close together
- **THEN** exactly one watcher is elected and the other dispatches only record their start

#### Scenario: Watcher exits when nothing is outstanding

- **WHEN** every recorded command has completed and no permission reminder is pending
- **THEN** the watcher exits and leaves no process running

#### Scenario: A later command elects a new watcher

- **WHEN** a command is dispatched after a previous watcher has exited
- **THEN** a new watcher is elected and mid-flight announcement resumes

#### Scenario: Abandoned election is reclaimed

- **WHEN** the election claim is older than the bounded reclaim interval and no watcher is running
- **THEN** the claim is reclaimed and a new watcher can be elected

#### Scenario: Watcher stops before its hook timeout

- **WHEN** a watcher has run for its self-imposed maximum lifetime
- **THEN** it exits on its own rather than being killed at the hook timeout

### Requirement: Background command completion is detected by task id

A shell command run in the background SHALL have its completion announced, even though the
harness fires no completion event for it. At launch the plugin SHALL record the background task
id reported on the launch acknowledgement together with the command's purpose. At each event that
carries the harness's list of running tasks, a recorded id that is no longer present in that list
SHALL be treated as finished: its completion cue SHALL be spoken and its record removed. The cue
SHALL name the command, not merely report that something finished.

#### Scenario: Finished background command is announced by name

- **WHEN** a recorded background task id is absent from the running-task list at a later event
- **THEN** a completion cue naming that command is spoken and its record is removed

#### Scenario: Still-running background command is not announced

- **WHEN** a recorded background task id is still present in the running-task list
- **THEN** no completion cue is spoken for it and its record is kept

#### Scenario: Launch acknowledgement is not a completion

- **WHEN** a background command's launch acknowledgement arrives immediately after dispatch
- **THEN** the id and purpose are recorded and no completion cue is spoken

#### Scenario: Each background command is announced once

- **WHEN** a background command's completion has been announced and further events carrying the
  running-task list arrive
- **THEN** no further cue is spoken for that command

#### Scenario: Absent task list leaves records intact

- **WHEN** an event carries no running-task list
- **THEN** no background completion is inferred and no record is removed

### Requirement: Command cues never speak the command text

The plugin SHALL speak only the model-authored description of a shell command and SHALL NEVER
speak the command string itself. A command line may contain credentials, tokens, or paths that
must not be read aloud, and is in any case not speakable text. When no description is available
the cue SHALL fall back to an anonymous form naming no specifics.

#### Scenario: Description is spoken, command is not

- **WHEN** a command cue is spoken for a call that has both a command string and a description
- **THEN** the spoken text contains the description and no part of the command string

#### Scenario: Missing description falls back to the anonymous form

- **WHEN** a command cue is due for a call that carries no description
- **THEN** an anonymous cue is spoken and the command string is still not spoken

#### Scenario: Credentials on a command line are never voiced

- **WHEN** a command string contains a token, password, or other secret
- **THEN** none of it reaches the speech engine

### Requirement: Command cues do not change what counts as outstanding work

Announcing shell commands SHALL NOT change the in-flight accounting that governs the turn-end
sign-off. A running background shell command SHALL remain excluded from the count of outstanding
agent-like work, exactly as before this capability existed, so that a long-lived background
process cannot mute the sign-off for the rest of the session. Announcing a completion and gating
the sign-off are separate decisions.

#### Scenario: A running background command does not suppress the sign-off

- **WHEN** a turn ends while a background shell command is still running and no agent-like work is
  outstanding
- **THEN** the ordinary turn-end sign-off is spoken, not the waiting cue

#### Scenario: A running foreground command does not appear in the count

- **WHEN** in-flight work is evaluated while command start records exist
- **THEN** those records do not contribute to the count of outstanding agent-like work

#### Scenario: The busy marker is unaffected by commands

- **WHEN** only shell commands are outstanding
- **THEN** no busy marker is written and the idle notification cue speaks as before

### Requirement: Distinct phrasing for the command states

The still-running cue and the command completion cues SHALL be drawn from phrase pools distinct
from the turn-end sign-off pools, the subagent pools, and the attention pools, so a command state
is distinguishable by ear from an agent state and from a turn boundary. Each cue SHALL be
assembled through the existing composition (optional leading garnish joined to a core by a brief
prosody pause), and the prosody pause SHALL never be voiced as literal text. Cues SHALL be
serialised through the existing speech lock so a command cue never overlaps an agent cue.

#### Scenario: Command cue is not an agent cue

- **WHEN** a still-running command cue is spoken
- **THEN** its core is drawn from the command pool and not from the subagent or sign-off pools

#### Scenario: Composition reused

- **WHEN** a command cue is spoken with a garnish selected
- **THEN** the cue is `<garnish><pause><core>` with the pause inaudible as text, exactly as for
  the other cues

#### Scenario: Command and agent cues do not overlap

- **WHEN** a command cue and an agent cue become due at the same moment
- **THEN** they are spoken one after the other, or the contended one is dropped, never overlapped

### Requirement: Command state is ephemeral and self-cleaning

State recording command starts, announced commands, background task ids, and the watcher election
SHALL be ephemeral per-session state under the system temp directory, written create-only or
within uniquely named entries so concurrent asynchronous hooks never perform a read-modify-write
on shared state. The plugin SHALL write nothing outside the system temp directory and its own
plugin directory, so `/plugin uninstall` remains a complete revert with no teardown command.
Records older than the configured TTL SHALL be pruned, so a command whose completion is never
observed cannot keep the watcher alive or produce a cue long after the fact. Missing or corrupt
state SHALL degrade harmlessly — treated as "nothing running", never erroring.

#### Scenario: State lives only in temp

- **WHEN** the plugin records a command start, an announcement, or a background task id
- **THEN** the only files or directories written are under the system temp directory, keyed to the
  session

#### Scenario: Stale command record is pruned

- **WHEN** a command start record is older than the configured TTL and its completion was never
  observed
- **THEN** the record is pruned, no cue is spoken for it, and it does not keep a watcher alive

#### Scenario: Missing state is harmless

- **WHEN** a command completion event arrives with no matching start record
- **THEN** the event is handled using the harness-supplied duration and no error occurs

### Requirement: Command cue configuration is env-var only and degrades cleanly

All behaviour SHALL be governed by environment variables following the existing precedence (env
var → built-in default), introducing no configuration file and no install command. A dedicated
mute (`CLAUDE_VOICE_NOTIFY_CMD=off`) SHALL disable the entire command path — the still-running
cue, the completion cues, the background-completion detection, the watcher, and all command state
— leaving every other cue unchanged. The events SHALL honour the existing global mute, the
non-macOS no-op, and the missing-`jq` fallback exactly as the existing events do. Numeric knobs
SHALL be validated so a malformed value falls back to its default rather than breaking the hook.

#### Scenario: Global mute wins

- **WHEN** the global mute is set
- **THEN** no command cue is spoken regardless of the command configuration

#### Scenario: Command mute disables the whole path

- **WHEN** the command mute is set but the global mute is not
- **THEN** no command state is written, no watcher is elected, no command cue is spoken, and agent
  and turn-end cues behave exactly as before this capability existed

#### Scenario: Non-macOS no-op preserved

- **WHEN** the speech command is unavailable
- **THEN** the command events exit cleanly without speaking or erroring

#### Scenario: Missing jq degrades to silence on this path

- **WHEN** `jq` is unavailable
- **THEN** command cues are skipped rather than spoken with wrong or empty content, and the other
  cues keep their existing fallback behaviour

#### Scenario: Malformed configuration falls back to defaults

- **WHEN** a numeric knob is set to a non-numeric value
- **THEN** the built-in default is used and the hook completes normally

#### Scenario: Defaults require no configuration

- **WHEN** none of the new environment variables are set
- **THEN** the plugin uses its built-in defaults and the command cues work without configuration

