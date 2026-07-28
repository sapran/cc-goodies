# Changelog

All notable changes to cc-goodies are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.14.0] - 2026-07-28

### Fixed

- **`shell-guard` no longer stops guarding in silence when `awk` is unavailable** (plugin
  `0.4.1` → `0.4.2`). Every split in the script — segments, pipeline stages, subshell
  bodies, the `SHELL_GUARD_EXTRA_PATTERNS` list — goes through `awk`. Without it each split
  yields nothing, no arm is ever evaluated, and the hook falls through to `exit 0`,
  indistinguishable from a clean allow: `rm -rf /` would pass unremarked.

  It still fails open, matching the existing missing-`jq` behaviour, because blocking every
  Bash call over a missing dependency is worse than not guarding. But it now says so, which
  is the whole point — the previous behaviour was the worst of both, an unguarded shell that
  looked guarded. A second check catches an `awk` that is present but fails at run time.
  The same fix is applied to `git-guard`. Both harnesses gained fail-open-and-warn cases.

### Added

- **`git-guard` gains an opt-in ask channel for on-branch writes** (plugin `0.2.4` →
  `0.3.0`). `GIT_GUARD_LOCAL_WRITE_CHANNEL=ask` routes a `commit`, `merge`, `pull`,
  `rebase`, `cherry-pick`, `revert`, `am`, or history-moving `reset` made **while on** a
  protected branch to your own permission prompt, instead of blocking it outright. The
  default is `deny`, so nothing changes for anyone who does not set it.

  This does not overturn Decision D2 of `guard-ask-escalation`, which rejected an ask
  channel for `git-guard`. D2 still sets the default. What it conflated was *what the
  default should be* with *whether the channel is expressible at all* — `git-guard`
  already lets you configure which branches are protected and how strict pushing is, so
  the channel was the one dimension hard-coded into the script. A user whose convention is
  "a local commit on `main` is fine, just never push it" previously had only two options:
  accept the full deny, or `GIT_GUARD_DISABLE=1`, which also switches off the push arms
  they wanted to keep.

  **Two arms stay deny-only and are not configurable — permanently, not pending a future
  setting:**

  - **Every push.** A human at an ask prompt cannot judge a push. The command text does
    not disclose remote state, so it cannot show whether the push fast-forwards or
    overwrites someone else's commits, and a destination-less `git push` does not even
    name its target branch (the guard resolves that from `push.default` and
    `remote.<remote>.push`). This is the same "can't approve what you can't see" criterion
    that keeps `curl … | bash` on `shell-guard`'s deny channel. A push also leaves the
    machine, so unlike a local write the reflog cannot undo it.
  - **A force `git branch -f|-D|-M|-C` naming a protected branch**, even though the script
    classifies it alongside local writes internally. It retargets a branch pointer while
    you are on some other branch — not the "I forgot to switch branches" accident this
    setting exists to soften — and it was closed as a bypass path once already.

  The setting **fails closed**: only the exact lowercase `ask` enables it, so `ASK`, `Ask`,
  `yes`, `1`, or an empty value all mean `deny`. This is deliberately the opposite of how
  `GIT_GUARD_DISABLE` and `GIT_GUARD_BLOCK_ALL_PUSH` parse, where "set to anything but 0"
  turns on the *stricter* behaviour; here the non-default value is the looser one.

  The ask output reuses `shell-guard`'s existing contract — `permissionDecision: "ask"` on
  stdout, exit 0, the same `!`-prefixed paste-to-override line — and keeps `shell-guard`'s
  severity discipline: a deny anywhere in a compound command still outranks an ask
  recorded earlier, and two ask-class segments emit exactly one decision object.

  **If the ask cannot be delivered, the guard denies rather than allowing.** `jq` is
  present (the hook exits without it), but the emit call itself can fail — `--arg` carries
  the whole command into the argument list, so a large enough tool call exceeds `ARG_MAX`.
  That previously produced exit 0 with no decision object, which the harness reads as a
  plain allow: the same command denied on the default channel but ran silently on the ask
  channel. A guard that cannot deliver its ask has made no decision, so it now falls back
  to the deny channel.

  **The prompt does not over-promise.** Approving a `permissionDecision: "ask"` releases
  the *whole* Bash command, but the guard classified only one segment of it. The reason
  text scopes its assurance to the matched write and to pushes the guard can resolve, and
  says plainly that approving releases the entire command line — rather than claiming
  nothing will be published, which a compound command containing a form the guard does not
  resolve (`bash -c "…"`, `sudo -u`) can falsify.

  **A broken command split no longer stops the guard silently.** If `awk` is missing or
  fails, the segment split yields nothing, no segment is judged, and the hook falls through
  to exit 0 — the guard quietly stops guarding. It still fails open (blocking every Bash
  call over a broken dependency would be worse), but now prints a one-line warning, the
  same way the missing-`jq` path already did.

  Test coverage grew from 57 to 126 cases across the two git-guard harnesses. Beyond the
  new third assertion form (exit 0 **plus** the JSON payload), the harnesses now assert
  `hookEventName` — without which a decision object is not routable and the ask silently
  degrades to an allow — cover the `~/.claude/git-guard.conf` path that `/git-guard`
  actually writes rather than only the environment variable, clear ambient `GIT_GUARD_*`
  variables so a developer's own settings cannot mask a failure, and fail loudly on a
  malformed case row instead of skipping it.

## [0.13.0] - 2026-07-28

### Fixed

- **`voice-notify` no longer says "all done" while a workflow is still running** (plugin
  `0.6.0` → `0.7.0`). A turn that ended with background work outstanding spoke a turn-end
  sign-off (*"Okay, that took a bit, but it's done."*), and the idle notification a minute
  later added *"I'm waiting for your input."* Both said the opposite of what was happening.

  The in-flight count read `background_tasks` but kept only entries of type `subagent`.
  Claude Code reports nine kinds there — `subagent`, `workflow`, `shell`, `monitor`,
  `MCP task`, `teammate`, `dream`, `auto-mode scan`, `cloud session` — so a running
  **workflow** resolved to zero in flight and the sign-off fired. The marker fallback missed
  it too: those markers are fed by a hook matched on the `Agent` tool, and a workflow is not
  an `Agent` call.

  The count is now a **block-list**: everything except `shell` and `monitor`. Those two are
  excluded because a `run_in_background` command is often a long-lived server and a monitor
  is a standing watch — counting either would mute the sign-off for the rest of the session.
  A block-list rather than a list of accepted kinds, so a task type added by a future Claude
  Code counts as outstanding by default; that errs toward "still working", which costs a
  spurious waiting cue instead of a spoken untruth.

  The idle notification had a second, separate cause: its payload carries **no** in-flight
  list at all — only `Stop` and `SubagentStop` are given one. Those two now cache the answer
  in a `$TMPDIR` busy marker, and the idle cue reads it and stays silent while work is
  outstanding. Silent rather than repeating the waiting cue, which `Stop` already spoke a
  minute earlier. Permission prompts, an agent asking a question, and an agent reporting a
  result all still speak — each is still true. A new prompt clears the marker and the
  existing `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` ages it out, so it can never mute the cue for
  good, and `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` disables it with the rest of the path.

  No new hooks, no new configuration, no dependency changes. The suite grew from 92 cases to
  118, covering each background-work kind, both exclusions, an unrecognised kind, and the
  marker's whole lifecycle.

### Changed

- **`voice-notify` completion phrasing** — *"— that one's back"* → *"— is back"*, *"—
  all wrapped up"* → *"— wrapped up"*, and the failure suffix *"— that one came back empty"*
  → *"— that one has failed"*, which describes the outcome rather than the result.

## [0.12.0] - 2026-07-26

### Added

- **`voice-notify` names the agent's purpose, and says when the work comes back** (plugin
  `0.5.0` → `0.6.0`). A subagent fan-out used to be voiced anonymously — one generic
  *"Spinning up some helpers"* at dispatch and, by design, **silence** on every completion.
  You learned that work had been delegated, never what it was, and never that it returned;
  the only echo was the waiting cue at `Stop`, after which the all-clear never came.

  The dispatch cue now names the work — one agent alone (*"Handing off — review script
  changes."*), two in full, three or more as a count plus the first (*"Five helpers,
  starting with review script changes."*). Because Claude Code fires the dispatch hook once
  per agent, the cue can't know its burst size at the instant the first agent fires, so the
  speaker claims the burst create-only and waits `CLAUDE_VOICE_NOTIFY_SUBAGENT_COLLECT`
  seconds (default 2) for its siblings to register first.

  Completions are voiced once each, when the result reaches the parent session, with a
  distinct pool for an agent that came back empty. The two cases arrive through different
  events, and the split is what keeps any agent from being announced twice: a **foreground**
  agent's new `PostToolUse`/`Agent` hook carries both the description and a completed
  response, while a **background** agent's `PostToolUse` is a launch acknowledgement fired
  milliseconds after dispatch — that one only records the agent's id and purpose, and the
  cue waits for `SubagentStop`, where the agent is still listed in its own
  `background_tasks` with its description. A foreground agent that errors or that you
  interrupt never reaches `PostToolUse`, so `PostToolUseFailure` is hooked as well and
  routes to the same failure phrasing.

  Individual cues are capped at `CLAUDE_VOICE_NOTIFY_AGENT_NAME_CAP` (default 3) concurrent
  agents so a wide sweep doesn't become a monologue, and a roll-up (*"All five helpers are
  back."*) closes the batch — but only when the cap or a waiting cue left something unsaid.
  A small fan-out named all the way through already ended with its own all-clear.

  `background_tasks` also replaces marker counting as the in-flight source at `Stop` and
  `SubagentStop`, retiring the stale-marker wedge that `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL`
  exists to paper over; the markers remain as the fallback for Claude Code versions that
  don't send the field, so nothing regresses. Naming completions makes two `say` calls
  overlap for the first time, so all cues now serialise through a create-only `$TMPDIR`
  lock and **drop** rather than queue under contention. Agent descriptions are
  model-authored, so they are stripped of control characters, truncated on a word boundary
  at `CLAUDE_VOICE_NOTIFY_AGENT_DESC_MAX` (default 60), have `say`'s `[[…]]` directive
  syntax neutralised, and are always passed as a single quoted argument.

  New knobs: `CLAUDE_VOICE_NOTIFY_AGENT_NAMES=off` restores the anonymous `0.5.0` cues
  wholesale, plus `..._AGENT_NAME_CAP`, `..._AGENT_DESC_MAX` and
  `..._SUBAGENT_COLLECT`. Missing `jq`, a non-macOS host, and both existing mutes degrade
  exactly as before. The suite grew from 40 cases to 92; all state stays in `$TMPDIR`, so
  `/plugin uninstall` remains the complete revert.

## [0.11.0] - 2026-07-26

Reassesses four plugins against the design assumptions of the Claude 5 generation: judgment
framing over prescriptive rules, progressive disclosure over upfront loading, and no
repetition across context layers. The guards are never read by a model, so their work is
interface work on the one string a model does see; the skills are read in full, so theirs is
architecture.

### Added

- **`shell-guard` routes hygiene-class blocks to the permission prompt** (plugin `0.3.1` →
  `0.4.1`). Arms resolve on a decision channel: commands a human can meaningfully judge now
  escalate to the prompt they are already looking at, instead of costing a round-trip through
  a pasted escape-hatch line. The catastrophic arms still refuse outright, and so does a
  network fetch inside an `eval` argument — the approver would see the URL, never the payload.
  Verified first that escalation is safe unattended: in headless runs, including under bypass
  mode, it resolves in seconds, fires once, and degrades to a refusal carrying the same
  reason, so it is never weaker than refusing. `git-guard` stays refuse-only by design.

  Review of the first cut caught a way this weakened the guard, fixed in `0.4.1`: the ask
  emitter ended the process on its first match, so a later segment of a compound command was
  never scanned and an escalation could front a refusal — `chmod 777 …; rm -rf /` surfaced as
  a prompt naming only the `chmod`. Decisions are now resolved after the whole command is
  scanned, with a refusal anywhere outranking an escalation anywhere. The same first-match
  shape had narrowed the fetch-inside-`eval` exception to a single segment; it now tokenizes
  the whole command, matches whole words, folds case, and follows assignment indirection.

- **Both guards name the rule they matched, and the way out** (`git-guard` `0.2.3` →
  `0.2.4`). The block message is a guard's only model-facing interface and the hook API has
  no non-retryable signal, so wording is the sole lever against a model retrying variants.
  Arms with no narrower form keep an explicit irreversibility warning; arms with a safe
  variant now name it concretely. The user-pattern arm, which previously emitted an unnamed
  reason and so guaranteed blind retry, now names the literal pattern it matched. Every
  message states that variants are blocked too. Both test harnesses gained stderr-content
  assertions, having previously asserted exit codes alone.

### Changed

- **`project-scope` is now a router over its references** (plugin `0.2.1` → `0.3.2`).
  `SKILL.md` drops from 287 to 91 lines; mechanics live only in `references/`. Removes the
  constants that had become judgment suppressors rather than scaffolding — a stopword list, a
  substring heuristic, fixed result caps, fixed budget options, a question-overflow rule — and
  collapses a red-flag list to one invariant. Phase 1 inventory delegates to a subagent so the
  large catalog stream stays out of the main context, and Phase 3 asks about an ambiguous
  theme up front instead of resolving it by keyword match. Behaviour is unchanged.

- **`session-finalise` states its invariant instead of an eight-step script** (plugin `0.2.1`
  → `0.3.1`). The skill encoded its phase contract three times and claimed the order was a
  safety property; only one edge is — cleanup must not run before pending work is saved.
  `SKILL.md` drops from 151 to 95 lines with phase detail in six reference files. The memory
  phase stops reciting a path rule, schema and index format the harness now supplies natively
  and becomes reconciliation against what was already captured; tracker detection describes
  the capability sought rather than enumerating vendors, so it no longer fails closed on an
  unlisted one. Two user-specific product rules leave the plugin. Consent gates unchanged.

- **Skill descriptions carry trigger surface, not capability prose.** A description is
  always-on context in every session where the plugin is installed. `project-scope`'s dropped
  from 92 to 52 words, its command description from 233 to 58 characters, and its marketplace
  entry likewise; `session-finalise`'s was already trigger-only and is untouched. Trigger
  coverage was verified rather than assumed.

- **`rules/shell-safety.md` trimmed to what a model cannot infer** — 47 to 34 lines. Most of
  it had become a restatement of default behaviour or a duplicate of the guards' own
  enforcement. Two facts were missing and are now stated: that a leading directory change is
  invisible to `git-guard`, which resolves the branch from the session working directory
  unless the repository is named explicitly, and that a refusal or declined escalation can be
  overridden by running the command directly in a terminal. Trimming advice is not licence to
  weaken enforcement, and the spec says so.

- **`project-scope`'s conflict rule no longer names specific third-party plugins.** The rule —
  never silently remove a resource the user's global `CLAUDE.md` declares authoritative or
  always-on — illustrated itself with three named
  examples, one of which was the `caveman` plugin removed elsewhere in this release. Named
  examples date; the rule does not. They are now described by kind (a memory store, a local
  model endpoint, a session-start output style), so the guidance stays correct as a user's
  plugin set churns. Behaviour of the audit passes is unchanged.

### Removed

- **`statusline` no longer renders the `caveman` plugin's mode badge** (plugin `0.6.0` →
  `0.7.0`). The badge was added in `0.8.0` so the two plugins could coexist under Claude
  Code's single `statusLine` slot; it rendered only when the caveman plugin's
  `.caveman-active` flag was present, and with caveman uninstalled that guard fails on
  every render. Removing it deletes this repo's only cross-plugin coupling — a fixed-path
  read of `.caveman-active` and `.caveman-statusline-suffix`, two files another
  marketplace owns — along with the 43 lines of escape-injection hardening those reads
  needed and 8 of the harness's 19 cases (11 remain, all passing). The enriched second
  line now ends with the `c:`/`s:`/`w:` gauges; for any install without an active caveman
  flag the render is **byte-identical** to `0.10.0` (the current release), and `lean` was
  never affected.
  `STATUSLINE_CAVEMAN` and `CAVEMAN_STATUSLINE_SAVINGS` are no longer read — setting them
  does nothing, and they can be dropped from shell profiles. If you still run caveman and
  want its badge, wire the caveman plugin's own `caveman-statusline.sh` into the
  `statusLine` slot instead of this statusline.

### Fixed

- **`project-scope` reported another model's token costs as the session's.** The catalog-cache
  lookup read an arbitrary first key, so against a cache carrying only Claude-4-generation
  entries every Claude-5 session silently got Opus figures, non-deterministically across cache
  orderings — while the reference prose described a fallback the code never implemented. A
  skill cannot learn its own model ID programmatically, so the model self-states it and the
  query resolves exact, then family, then unavailable, disclosing every non-exact match and
  excluding unavailable figures from the budget sum.

## [0.10.0] - 2026-07-08

### Added

- **`voice-notify` now speaks a distinct *waiting* cue when a turn ends while background
  subagents are still running** (plugin `0.4.0` → `0.5.0`). The `0.9.0` change reserved the
  `Stop` "your turn" sign-off for true turn-end but added no guard, because its spike found
  `Stop` fires only after every `SubagentStop`. That holds for **blocking/foreground**
  subagents; it does **not** hold for **background** subagents, where the `Agent` tool
  dispatches agents that run without blocking and the main turn can end while they keep
  working (Claude Code fires `Stop` without waiting; a `SubagentStop` fires later per agent).
  The symptom: the main session goes idle and can accept input while its background agents are
  still running, and `Stop` speaks a false "All done." Now the plugin keeps a per-session,
  ephemeral count of in-flight subagents — the existing `PreToolUse(Agent)` dispatch hook
  records each spawn, and a new `SubagentStop` hook records each completion keyed by the
  event's `agent_id` (so a duplicate stop counts once) — and at `Stop` compares the two. If
  any subagents are still in flight it speaks a distinct waiting cue (*"Not done yet, the
  agents are still working."*) from its own phrase pool, **bypassing** the quiet-on-quick-turns
  gate, instead of the turn-end sign-off. When nothing is in flight — every ordinary turn, and
  any turn whose subagents were foreground and so finished first (spawn count equals completion
  count) — `Stop` behaves exactly as before, so there is no regression on the common path.
- The count lives in two **create-only** marker directories under `$TMPDIR`
  (`vn-<session>.spawn.d` and `vn-<session>.done.d`), so concurrent asynchronous hooks only
  ever create distinct paths and never race a read-modify-write on a shared counter. Each
  marker stores its creation epoch; at every `Stop`, markers older than the new
  `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` (seconds, default `3600`) are pruned, so a subagent that
  never reports completion — a crash, or a dispatch you denied — cannot wedge the count into a
  permanent *waiting* state.
- The existing `CLAUDE_VOICE_NOTIFY_SUBAGENT=off` now disables the whole subagent path — the
  dispatch cue, the in-flight tracking, **and** the waiting cue — so `Stop` signs off exactly
  as it did before in-flight tracking existed. The global mute (`CLAUDE_VOICE_NOTIFY=off`), the
  non-macOS no-op, and the missing-`jq` fallback all apply to the new `SubagentStop` event as
  before, and every marker is ephemeral `$TMPDIR` state so `/plugin uninstall` remains the full
  revert. Adds test-harness cases for the spawn/done accounting, the waiting cue (distinct from
  the sign-off and dispatch pools), the quiet-gate bypass, the foreground-balances-to-sign-off
  no-regression path, the TTL prune (including a custom TTL and a base-10 parse guard so a
  leading-zero `CLAUDE_VOICE_NOTIFY_SUBAGENT_TTL` can't turn the arithmetic octal, error under
  `set -u`, and silence `Stop`), and mute/no-op coverage for the new event (25 → 40).

## [0.9.0] - 2026-07-02

### Added

- **`voice-notify` now voices the subagent-working pause distinctly from a real turn-end**
  (plugin `0.3.0` → `0.4.0`). Previously only `Stop` ("your turn") and `Notification` had a
  voice, so a turn that dispatched subagents and paused while they ran sounded no different from
  one that had genuinely finished — a long silence, then eventually "your turn". A new
  `PreToolUse` hook on the `Agent` (subagent-dispatch) tool now speaks a distinct *still-working*
  cue (*"Spinning up some helpers, back in a bit."*) from its own phrase pool, routed through the
  existing composer so it varies in wording and cadence like the other cues. Because a fan-out
  fires the hook once per subagent, the cue is **debounced** to one per burst: the first fire
  speaks and stamps an epoch to a single ephemeral per-session `$TMPDIR` file
  (`vn-<session>.dispatch`), and further fires within `CLAUDE_VOICE_NOTIFY_SUBAGENT_DEBOUNCE`
  seconds (default 10) stay silent. A subagent *finishing* is silent by design, and — verified
  against Claude Code 2.1.197 with a logging hook — `Stop` fires only once at true turn-end
  (never mid-pause), so "your turn" stays honest with no extra guard needed. Mute just this cue
  with `CLAUDE_VOICE_NOTIFY_SUBAGENT=off`; the global mute (`CLAUDE_VOICE_NOTIFY=off`), the
  non-macOS no-op, and the missing-`jq` fallback all apply to the new event as before, and the
  marker is ephemeral `$TMPDIR` state so `/plugin uninstall` remains the full revert. Adds 13
  test-harness cases (distinct pool, debounce collapse, speak-after-window, silent finish, both
  mutes, non-macOS no-op).

## [0.8.0] - 2026-06-30

### Added

- **`statusline` renders the `caveman` plugin's mode badge** (plugin `0.5.1` → `0.6.0`). Claude
  Code allows only one `statusLine` command, so the [`caveman`](https://github.com/JuliusBrussee/caveman)
  plugin's own statusline badge and this one previously competed for the single slot — pick this
  statusline and you lost the `[CAVEMAN]` indicator. The enriched second line now ends with the
  caveman badge (and its optional `~NN% saved` suffix) whenever caveman mode is active —
  e.g. `Opus 4.8 (high)  c:42% s:10% w:5%  [CAVEMAN] ~38% saved`. The badge is read-only against
  the caveman plugin's existing state files (`.caveman-active`, `.caveman-statusline-suffix`) under
  `${CLAUDE_CONFIG_DIR:-~/.claude}`, adds **no `jq` parse**, and applies the same hardening the
  caveman script does (symlink refusal, 64-byte read cap, lower-case + `[a-z0-9-]` strip, control-byte
  strip, mode whitelist) so a planted state file can't inject terminal escapes. It renders only in
  `enriched` mode — `lean` stays byte-identical — and is **fail-soft**: when caveman is not installed
  (the flag file is absent) the statusline renders exactly as before, with no badge and no error.
  Opt out with `STATUSLINE_CAVEMAN=0` (whole segment) or `CAVEMAN_STATUSLINE_SAVINGS=0` (savings only,
  reusing the caveman plugin's own knob). Adds 8 harness cases covering render, hardening, savings,
  opt-out, fail-soft, lean-exclusion, and a whitelist pin.

## [0.7.2] - 2026-06-24

### Fixed

- **`git-guard` now resolves config-routed and multi-refspec push targets** (plugin `0.2.2` →
  `0.2.3`). A destination-less push (`git push` / `git push <remote>`) whose target git would
  route onto a protected branch via configuration was previously judged only by the literal
  refspec text, falling back to the current branch name — so a push that `push.default=upstream`
  (with the branch's upstream `branch.<b>.merge` pointing at `main`) or a `remote.<remote>.push`
  refspec sends to `main` slipped through with no `:main` anywhere in the command. The guard now
  reads that routing from git config — not `<src>@{push}`, which needs a materialised
  remote-tracking ref and fails (with localised errors) on the exact unfetched case being closed —
  so resolution holds before any fetch. Every positional refspec is now judged rather than only the
  last, so `git push origin main develop` is blocked on `main`. `push.default=simple` with a
  mismatched upstream is intentionally not blocked (git refuses that push itself), and any routing
  the guard cannot resolve fails open; `push.default=matching` and exotic multi-remote routing
  remain out of scope (documented in the plugin README). Adds a config-driven test runner
  (`tests/run-routing.sh`, 8 cases) plus multi-refspec and bare-push rows in `cases.tsv`.

## [0.7.1] - 2026-06-22

### Fixed

- **`/statusline-toggle` no longer trips `shell-guard`** (plugin `0.5.0` → `0.5.1`). The
  command's documented write recipe seeded its temp file with the `: >` truncate-to-empty
  idiom, which the sibling `shell-guard` plugin hard-blocks — so on a setup running both
  plugins, invoking `/statusline-toggle` failed at the guard before writing the mode. The
  recipe now seeds the temp file with `printf '' >` and appends the preserved lines; the
  atomic same-directory `mv` is unchanged, so the result is identical. The statusline test
  harness gains a regression case that lints the command doc for the blocked idiom. No change
  to the statusline script or to the toggle's behaviour.

## [0.7.0] - 2026-06-22

### Added

- **`statusline` gains a runtime `enriched`/`lean` mode toggle** (plugin `0.4.1` → `0.5.0`).
  The statusline now renders in one of two modes, switchable while Claude Code is running:
  `enriched` (the default — today's full two-line output, unchanged) or `lean`, a single
  compact line of compressed cwd, git branch (or a `wt:` worktree token), model, and the `c:`
  context gauge — `~/cab/claude.ai  [main]  Opus 4.8  c:42%`. Lean drops `user@host`, the
  `task → latest` prompt snippet, the `(effort)` tag, the `s:` (5-hour) and `w:` (7-day)
  rate-limit gauges, and every `⧗`/`⟲` time suffix; the `c:` gauge keeps its value-driven
  severity colour. Lean is genuinely lighter, not just trimmed — it skips the enriched-only
  work behind the dropped segments (both transcript reads, the rate-limit/reset bookkeeping,
  the duration humanising, the effort-from-settings fallback), so it does strictly less I/O
  per render. The mode is a `STATUSLINE_MODE` key in `~/.claude/statusline.conf` that the
  script re-reads on every render (read, never `source`d; any value outside `{enriched, lean}`
  or an absent file/key fails soft to `enriched`), so a flip reaches the already-running
  session on the next prompt. A new `/statusline-toggle` command flips the mode, or sets it
  with an `enriched`/`lean` argument; `/statusline-install` is unchanged and writes no conf,
  and `/statusline-uninstall` now also removes `~/.claude/statusline.conf`, preserving the
  install ⇄ uninstall symmetry. Still one `jq` parse per render and nothing written outside
  the script's `$TMPDIR` cache; ships a 10-case test harness under `plugins/statusline/tests/`.

## [0.6.0] - 2026-06-22

### Changed

- **`voice-notify` phrasing is more natural and varied, and `Stop` now stays quiet on quick
  turns** (plugin `0.2.1` → `0.3.0`). Both events share one composer that always speaks a core
  phrase and *sometimes* (≈40%, `CLAUDE_VOICE_NOTIFY_GARNISH_PCT`) prefixes a short lead-in
  joined by a `[[slnc 250]]` prosody pause — multiplicative variety from small pools rather than
  a flat list, with a comma-and-pause cadence that reads as spoken, not recited. `Notification`
  now routes by message subtype — a brisk pool for permission prompts, a gentle pool for
  idle/waiting — and the first-person rewrite is allow-list only: unrecognised wording falls
  back to a neutral cue instead of being mangled by the old catch-all (e.g. no more "I Code
  is…"). A new `UserPromptSubmit` hook stamps the turn start to `$TMPDIR`; on `Stop`, turns
  shorter than `CLAUDE_VOICE_NOTIFY_QUIET_UNDER` seconds (default 20, set 0 to speak every turn)
  are skipped — you only hear "done" for the long task you walked away from — and clearly long
  turns draw a wait-acknowledging sign-off. No new dependencies; state is an ephemeral
  per-session `$TMPDIR` file, so `/plugin uninstall` remains the full revert. `say`-absent,
  muted (`CLAUDE_VOICE_NOTIFY=off`), and missing-`jq` paths still no-op cleanly.

## [0.5.1] - 2026-06-21

### Fixed

- **`statusline` muted text was washed out on light terminal backgrounds.** The prompt/task
  summary, the `⧗`/`⟲` time suffixes, and the effort tag used the ANSI *dim* attribute
  (`2;37` dim-white, `2;36` dim-cyan). On a light background the dim attribute lowers a
  colour's intensity *toward* the light background, so these elements rendered as
  near-invisible pale grey. They now use deterministic 256-colour indices instead — muted
  text → `38;5;243` (a flat medium grey), the effort tag → `38;5;37` (solid teal, still tied
  to the cyan model name) — matching the existing rationale for the line-2 gauges, which
  already use 256-colour indices to stay legible on a light background. No layout, parsing, or
  dependency change; only the SGR codes for already-present elements.

## [0.5.0] - 2026-06-21

### Changed

- **`statusline` line-2 usage gauges are now coloured by fill level.** The `c:`, `s:`, and
  `w:` gauges were a single flat colour regardless of value; each is now coloured from its own
  percentage by ascending severity tiers. The context gauge (`c:`) uses a four-tier ramp —
  green below 25%, yellow at 25, amber at 50, red at 75 — while the 5-hour (`s:`) and 7-day
  (`w:`) rate-limit gauges use three tiers (amber at 50, red at 80 and 75 respectively). A new
  pure-bash `gauge_sgr` helper maps a value to a 256-colour SGR code from a list of ascending
  `min:sgr` tier tokens; the fixed indices (green 34, gold 178, amber 208, red 196) keep
  amber/red legible on a light background where ANSI-16 yellow washes out, and the critical red
  tier is bolded for a second, colour-independent signal. The `⧗`/`⟲` time suffixes move to a
  neutral dim grey so the now-coloured percentage stays the primary figure. Colour selection is
  integer comparison — no new dependency, no extra `jq` call — so the single-parse-per-render
  budget and the two-line layout are unchanged.

## [0.4.0] - 2026-06-21

### Added

- **`statusline` line 2 gains time readouts beside its usage gauges.** The context gauge
  (`c:`) now carries the session's elapsed wall-clock time, marked with an hourglass `⧗`
  (counts up, from `cost.total_duration_ms`); the `s:`/`w:` rate-limit gauges each carry a
  countdown to when that window resets, marked with `⟲` (counts down, from
  `rate_limits.five_hour.resets_at` / `rate_limits.seven_day.resets_at`). A shared pure-bash
  humaniser renders a compact two-unit token (`3d4h` / `2h45m` / `23m`); each suffix is
  optional and renders nothing when its source field is absent, so the layout degrades to the
  previous output. The reset epochs are cached alongside the existing rate-limit percentages,
  so the countdowns — and the `s:`/`w:` gauges themselves — now stay live across renders where
  Claude Code omits the `rate_limits` object, recomputing the remaining time each render; a
  lapsed (past) epoch shows no countdown. Still one `jq` parse per render, no new dependency,
  and nothing written outside the script's private `$TMPDIR` cache, so `/plugin uninstall`
  remains the full revert.

## [0.3.0] - 2026-06-21

### Added

- **`gpt-search` plugin** — deep web research from a Claude Code session, backed by the
  **Codex MCP**, with a project-local cache so the same search isn't paid for twice. It checks
  `.claude/cache/search/*.md` by keyword overlap first (offering reuse / re-search / new-query
  on a relevant hit), calls the Codex MCP read-only on a miss, then formats the result
  (summary, key facts, sourced links) and stores it under
  `.claude/cache/search/YYYY-MM-DD_<topic>.md` with YAML frontmatter. Ships as an
  **auto-activating skill** plus a thin **`/gpt-search`** command alias. Depends on the Codex
  MCP (`mcp__codex__codex` / `mcp__codex__codex-reply`) as a documented **prerequisite** — it
  bundles **no `.mcp.json`** (bring your own) and degrades gracefully with a hint when the MCP
  is absent, rather than hard-failing. No hook and nothing written outside its own directory at
  install time, so `/plugin uninstall` is the complete revert; the on-use cache is
  user-clearable (`rm -rf .claude/cache/search/`). Migrated from a local user-level skill.
- **`rtk-hook` gains a `/rtk-hook` control panel and a pause switch.** The hook script now
  reads `~/.claude/rtk-hook.conf` and honours `RTK_HOOK_DISABLE=1` (env > conf > default), so
  RTK rewriting can be paused without uninstalling — commands then run unrewritten. The new
  `/rtk-hook` command leads with the `ON`/`PAUSED` state, offers pause/resume, and folds in the
  old hand-wired-duplicate cleanup as a menu option. This brings rtk-hook in line with the
  `git-guard` / `shell-guard` shape (a `/<name>` control command plus a conf file), and adds a
  small `tests/` harness.

### Changed

- **`git-guard` / `shell-guard` blocks now hand the command back as a copy-paste
  `!`-line.** Every block prints the original command prefixed with `!` on its own
  unindented line — typed into the Claude Code prompt, the `!` prefix runs it in the
  user's own shell, which the hook never gates, so overriding a one-off block is a
  single copy-paste (`! git push origin main`). shell-guard fronts the line with an
  explicit "destructive and IRREVERSIBLE — verify the target" warning, since the
  commands it blocks are catastrophic by design. No change to what either guard blocks
  or to its exit codes; the deny *message* is the only thing that changed. READMEs and
  `docs/shell-safety.md` updated to show the new output.
- **`git-guard` / `shell-guard` pause/resume is now a first-class choice.** `/git-guard`
  and `/shell-guard` lead with the guard's current `ON`/`PAUSED` state and present **pause**
  and **resume** as explicit menu options (writing or clearing `GIT_GUARD_DISABLE` /
  `SHELL_GUARD_DISABLE`), preserving any other keys. No behaviour change to the hooks
  themselves — the `*_DISABLE` toggle already existed; this just surfaces it instead of
  burying it in an "enable/disable" sub-bullet. Each guard README gains a **Pause / resume**
  section.
- **Docs clarify how hook plugins activate.** The `git-guard`, `shell-guard`, and
  `voice-notify` READMEs and the two guard config commands now state that hooks are declared
  inline in `plugin.json`, so installing the plugin is the whole install — the hook
  activates on install, stays active across plugin updates, and writes nothing to
  `settings.json` (there is no separate hook-install step, and an inline hook can't be
  "manually uninstalled" short of removing the plugin). `voice-notify` documents
  `CLAUDE_VOICE_NOTIFY=off` as its pause/mute path.
- **Install ⇄ uninstall rule softened — hook plugins need no install command.** `CLAUDE.md`,
  `README.md` and `CONTRIBUTING.md` now state that an inline hook self-activates on `/plugin
  install`, so a `/<name>-install` command is only for durable-state setup (e.g. `statusline`'s
  `statusLine` key); a `/<name>-uninstall` can stand alone, and the revert may live in the
  `/<name>` control command. The symmetry is about reversible *verbs*, not a mandatory
  install/uninstall command pair.

### Removed

- **`/rtk-hook-install`** — folded into `/rtk-hook` (option [3], "remove hand-wired duplicate").
  `/rtk-hook-uninstall` now also deletes `~/.claude/rtk-hook.conf`; its settings.json restore
  step is unchanged.

## [0.2.0] - 2026-06-20

### Added

- **`shell-guard` plugin** — a `PreToolUse`/`Bash` hook that hard-blocks (exit 2) a small
  set of *catastrophic* shell commands before they run: recursive deletes of `/`,
  `$HOME`/`~`, or a top-level system directory (and any `--no-preserve-root`); `dd` or a
  `>` redirect onto a raw disk device; `mkfs`/`wipefs`/`newfs`; destructive `diskutil`;
  fork bombs; a network download piped into an interpreter (`curl|sh`); the `: >`
  truncate-to-empty idiom; `chmod 777`; `eval`; privilege escalation (`sudo`/`doas`/…);
  and system halt/reboot (`reboot`/`shutdown`/`halt`/`poweroff`). It resolves the target
  and skips common wrappers, catching re-ordered-flag variants a string list misses, while
  deliberately allowing ordinary work (`rm -rf ./build`, `dd … of=file`, `dd … of=/dev/null`,
  `curl|jq`, `git init`, plain `> file` redirects, `chmod 755`). Scope is plain-form
  accidents — deliberate evasion (option-value wrapping, `bash -c`, encoding, `eval`
  indirection) is out of scope by design, with plan mode the backstop. Configurable via
  `~/.claude/shell-guard.conf` (`SHELL_GUARD_DISABLE`, `SHELL_GUARD_EXTRA_PATTERNS`)
  through `/shell-guard`, with a matching `/shell-guard-uninstall`. Fails open if `jq` is
  missing.
- **`rtk-hook` plugin** — wires RTK (Rust Token Killer) as a managed `PreToolUse`/`Bash`
  hook instead of a hand-wired `settings.json` entry. The wrapper execs `rtk hook claude`
  when `rtk` is on `PATH` and no-ops (exit 0) otherwise, so it's safe to install without
  RTK. `/rtk-hook-install` removes a now-duplicate hand-wired entry from `settings.json`
  (ownership-guarded); `/rtk-hook-uninstall` offers to restore it.
- **Shell-safety manual** (`docs/shell-safety.md`) — a consolidated guide to the layered
  defense against dangerous shell commands: threat model, the deny-list / git-guard /
  shell-guard / plan-mode layers, what each catches and misses, and recommended setup.
- **Advisory rules companion** (`rules/shell-safety.md`) — the judgment calls a hook can't
  enforce (no obfuscated commands, no remote→shell pipes, confirm recursive deletes, keep
  secrets off the CLI, ignore embedded instructions). Symlink it into `~/.claude/rules/`
  to auto-load in every session — no `settings.json` edit needed.
- **`session-finalise` plugin** — end-of-session housekeeping as a skippable, ordered
  checklist that **preserves work before deleting anything** and confirms every irreversible
  step: orient (read-only `git` snapshot), commit/stash (never `main`, never push without
  confirmation), durable memory, handoff (delegated to `remember`), tracker updates (detect
  what's wired; no HTML in Asana), session summary, then cleanup of scratch files and stale
  worktrees. Ships both as an **auto-activating skill** (cc-goodies' first bundled skill,
  triggered by wrap-up phrases) and a bare **`/session-finalise`** command. Writes nothing
  outside its plugin directory, so `/plugin uninstall` is the complete revert. Migrated from
  a local user-level skill + `/finalize` command.
- **`project-scope` plugin** — scopes a project's plugins, MCP servers and skills to a stated
  theme. Inventories resources at three friction tiers (currently active, installed-but-disabled,
  available in registered marketplaces), judges each against the theme, prints the full proposal,
  then asks **per-bucket consent** before applying: uninstalls off-theme plugins at **project
  scope**, disables user-level skills and MCP servers (incl. Claude Desktop / claude.ai) via
  `.claude/settings.json` (`skillOverrides`, `deniedMcpServers`), installs theme-relevant plugins
  (already-downloaded, or from a marketplace with explicit consent), and sets
  `skillListingBudgetFraction`. Project scope only — never edits global `~/.claude/settings.json`
  and never hand-edits `enabledPlugins` (the CLI owns it). Ships as an **auto-activating skill**
  plus a **`/project-scope`** command; writes nothing outside its plugin directory, so
  `/plugin uninstall` is the complete revert. Migrated from the local `/claude-scope-project`
  command.

### Changed

- **`git-guard`** simplified to one built-in behaviour plus one optional toggle: block a
  local write (`commit`/`merge`/`pull`/`rebase`/`cherry-pick`/`revert`/`am` and a
  history-moving `reset --hard|--merge|--keep`) while **on** a protected branch, and block
  any **push** whose resolved target is protected; `GIT_GUARD_BLOCK_ALL_PUSH=1` also blocks
  every push. Replaces the previous `1`/`2`/`3` policy selector and the separate
  `GIT_GUARD_DEV_BRANCHES` list. Also guards `branch -D|-f|-M <protected>`, recognises the
  `rtk proxy git …` prefix, and unwraps common non-evasive wrappers. Deliberately hidden
  git (`bash -c "…"`, command substitution, `sudo -u USER git`, gitconfig aliases) is out
  of scope by design; plan mode is the backstop.

### Fixed

- **README shell uninstall** — the one-shot "Remove everything" steps now flag
  `/statusline-uninstall` as a required pre-step. The `claude plugins` CLI can't drop the
  `statusLine` key or delete the `~/.claude/team-statusline.sh` copy, so the statusline
  kept rendering after the plugins were removed.

## [0.1.0]

### Added

- Initial marketplace with three plugins: **`voice-notify`** (spoken macOS
  notifications), **`statusline`** (enriched two-line statusline), and **`git-guard`**
  (protected-branch guard for `commit`/`merge`/`push`).
