## Context

`notify.sh` already has an in-flight accounting layer, added in 0.5.0 and extended in 0.6.0. It
has two sources:

- **Authoritative** — `inflight_payload()`, which reads `background_tasks` out of the hook
  payload. Present on `Stop` and `SubagentStop` only.
- **Fallback** — `inflight_markers()`, which counts create-only marker directories under
  `$TMPDIR`, fed by the `PreToolUse`/`PostToolUse`/`SubagentStop` hooks matched on the `Agent`
  tool. Used when the payload carries no list.

Facts established by reading the Claude Code 2.1.220 binary, not from documentation:

- `background_tasks` is attached only to the `Stop` and `SubagentStop` hook inputs. The field's
  own embedded description states its purpose: *"In-flight background work (running/pending +
  backgrounded) registered in this session. Lets hooks distinguish 'session is done' from
  'session is paused waiting for background work to wake it'."*
- Entries are emitted for internal task kinds mapped to these public `type` values:
  `subagent`, `workflow`, `shell`, `monitor`, `MCP task`, `teammate`, `dream`,
  `auto-mode scan`, `cloud session`. Only entries whose status is `running` or `pending` are
  included.
- The `Notification` hook input is built without any task context. Its fields are `session_id`,
  `transcript_path`, `cwd`, `prompt_id`, `permission_mode`, `message`, `title`,
  `notification_type`.

`inflight_payload()` filters `select(.type == "subagent")`, so seven of the nine kinds are
invisible to it. A workflow is the case the user actually hit.

## Goals / Non-Goals

**Goals:**

- A turn that ends with agent-like background work still running never speaks a sign-off.
- An idle notification that arrives while such work is running speaks nothing.
- Coverage stays correct when the harness gains new background-task types.
- No new hooks, no new configuration keys, no new dependencies.

**Non-Goals:**

- Teaching the marker fallback about workflows. The fallback exists for older Claude Code
  versions whose `Stop` payload has no task list. Covering workflows there would need a
  `Workflow`-matched hook pair plus per-item completion tracking, and would buy nothing on
  2.1.220 where the authoritative list is available. This is a deliberate omission and will be
  recorded as a code comment so it is not mistaken for an oversight.
- Naming the kind of outstanding work in the spoken cue ("the workflow is still running"). The
  existing waiting pool already conveys "work is still out"; per-kind wording is a separate,
  larger phrasing change.
- Treating a background shell or a monitor as outstanding work.

## Decisions

**Block-list, not allow-list.** Count every entry whose type is not `shell` and not `monitor`.

The alternative was an allow-list of the seven agent-like types. Rejected because a task type
added by a future Claude Code release would then be silently ignored, producing exactly the
false all-clear this change exists to remove. With a block-list, an unknown type counts as
outstanding — the same "fail toward still in-flight" rule the script already applies to
unparseable marker timestamps in `prune_dir`. The cost of the safe direction is one spurious
waiting cue; the cost of the unsafe direction is a spoken lie.

`shell` and `monitor` are the two exclusions because both are commonly long-lived by design (a
background dev server, a `Monitor` watching for a condition) and neither returns a result the
way an agent does. Counting them would leave the sign-off permanently muted after the user
starts one.

The change is confined to the `jq` expression inside `inflight_payload()`.

**The busy marker is written from the authoritative source only.** The `Notification` handler
cannot see `background_tasks`, so the state has to be carried across events. Rather than
maintain a second, independent accounting, the marker is a cache of the authoritative count:
every code path that has just computed an authoritative in-flight number writes the marker when
that number is above zero and deletes it when it is zero.

That gives the marker the same coverage as the payload for free, including task types the
plugin has never heard of. It follows the file conventions already in the script: a create-only
file under `$TMPDIR`, keyed by session id, whose first line is the epoch, read with the existing
`read_ts` helper and aged out against the existing `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL`.

Alternatives considered:

- *Latch only at `Stop`.* Simpler, but a `SubagentStop` that drains the last agent would leave a
  stale marker until the next `Stop`. Writing at both refresh points costs nothing.
- *Re-derive from the marker directories in the `Notification` handler.* Would miss workflows,
  teammates, and cloud sessions — the exact gap being closed.

**Suppress, do not re-route.** While the marker is set, the idle notification speaks nothing at
all rather than borrowing the waiting pool. The `Stop` cue fired roughly a minute earlier and
already said work was outstanding; repeating it adds noise without new information. This was the
user's explicit choice.

Only the `idle` subtype is gated. `permission`, `agent_input`, `agent_done` and `neutral` stay
audible: each is still true, and each is the kind of message a user who stepped away needs to
hear.

**Clearing.** The `start` arm (`UserPromptSubmit`) deletes the marker: a new prompt proves the
user is present, so the idle cue has nothing left to protect them from. The existing TTL bounds
the worst case where no further authoritative event ever arrives.

## Risks / Trade-offs

- **A long-lived background shell no longer counts, so a genuine wait on one is mis-announced as
  "done".** → Accepted, and the deliberate reading of the user's choice. A background command
  the user started themselves is not work the session is blocked on; the reverse error (never
  saying "done" again) is worse and harder to notice.
- **A stale busy marker mutes the idle cue.** → Bounded two ways: any authoritative event with a
  zero count deletes it, and the existing TTL makes it expire. The failure is one missed idle
  reminder, not a wrong statement.
- **A false waiting cue when an unknown task type is actually inert.** → Accepted as the price
  of the block-list. The cue says work is outstanding, which is conservative and self-correcting
  at the next `Stop`.
- **`jq` absent.** → `inflight_payload()` already returns failure without `jq`, so the marker is
  never written and the plugin degrades to exactly today's marker-based behaviour.
- **Regression in the roll-up bookkeeping.** → Counting more kinds means `settle()` can now see a
  non-zero count from a workflow. The roll-up only fires when the count reaches zero, so the
  effect is a deferred roll-up, never a duplicated one. Covered by the existing roll-up tests
  plus the new ones.

## Migration Plan

None required. The change is behavioural inside one hook script, with no persisted state format
change: the busy marker is a new ephemeral `$TMPDIR` file that is created on demand and needs no
migration or teardown. Rollback is reverting the commit; `/plugin uninstall` remains a complete
revert of the plugin as a whole.

## Open Questions

None.
