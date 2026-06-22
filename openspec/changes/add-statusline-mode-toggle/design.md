## Context

`plugins/statusline/statusline-command.sh` is invoked by Claude Code as a **fresh subprocess
on every render**: it reads a JSON event on stdin, prints two lines, and exits. Its header
codifies the constraints — one `jq` parse per render, short-lived `$TMPDIR` caches, pure-bash
arithmetic, clean degradation when a field is missing, macOS bash 3.2 / BSD userland but no
hard-fail elsewhere. Today it has a single output: the enriched two-line statusline.

The script's per-render cost is dominated by two bounded transcript reads (`head -n 500` and
`tail -n 500 | tail -r`, each piped through `grep` + a `jq` filter) that derive the
`task → latest` snippet, plus the rate-limit gauge/reset cache bookkeeping and the duration
humanising. Everything else — cwd compression, the 5-second-cached branch lookup, model, and
the `c:` context gauge — is cheap.

Because the process is recreated each render, **any switch a user makes must be visible to a
process that has not started yet**. A shell environment variable cannot do this: the running
Claude Code session captured its environment at launch and spawns the statusline with that
frozen copy, so `export STATUSLINE_MODE=lean` in a new shell would only affect a *future*
session. A small file the script re-reads each render is the only mechanism that makes a flip
take effect on the very next prompt of the **current** session — which is what "toggle at
runtime" requires.

## Goals / Non-Goals

**Goals:**

- A `lean` render mode — one compact line `cwd  [branch]  model  c:NN%` — alongside the
  existing `enriched` mode, switchable while Claude Code is running.
- The switch takes effect on the next render with no restart and no re-install.
- Lean does strictly less work than enriched (skips the enriched-only computations), so it is
  lighter as well as quieter.
- Default to `enriched`: an install with no conf renders exactly as it does today.
- Preserve every existing invariant — one `jq` parse, the caches, graceful degradation, bash
  3.2 / BSD portability — and keep install ⇄ uninstall symmetry for the new durable state.

**Non-Goals:**

- An environment-variable mode override (cannot affect an already-running session — see D2).
- Per-project (vs global) mode, more than two modes, or a user-defined custom layout.
- Any change to the enriched output, its colours, gauges, or layout.
- A general statusline config file beyond the single `STATUSLINE_MODE` key.

## Decisions

### D1 — Two modes; lean is a single line of {cwd, branch/worktree, model, `c:`}

`enriched` is today's full two-line output, untouched. `lean` collapses to one line:
compressed cwd (blue), git branch or `wt:` worktree token (yellow), model display name
(cyan), and the `c:` context gauge with its value-driven severity colour —
`~/cab/claude.ai  [main]  Opus 4.8  c:42%`. Lean **omits** `user@host`, the `task → latest`
prompt snippet, the `(effort)` suffix, the `s:`/`w:` rate-limit gauges, and every `⧗`/`⟲`
time suffix. **Why this subset:** it keeps the four things a glance most often needs — where
am I, on what branch, which model, how full is the context — and drops the identity banner,
the transcript-derived prose, and the slow-moving rate gauges that the user can always flip
back to. *Alternatives considered:* (a) drop only the time suffixes — too small to be worth a
mode; (b) a location-only line with no model/context — loses the two figures most worth
keeping; (c) keep two lines but trimmed — still spends the second line's vertical space.
(User-confirmed via the rendered preview: the single `cwd  [branch]  model  c:` line.)

### D2 — Mode is read from a file every render, never from the environment

The active mode is resolved each render by reading `~/.claude/statusline.conf`. **Why not an
env var:** the statusline runs as a child of the long-lived Claude Code process with the
environment frozen at that process's launch, so an env var changed mid-session can never
reach the current session's renders — it would silently fail the core "runtime" requirement.
A file re-read on each invocation is seen by the next render of the *running* session. The
per-render cost is one bounded file read, on the order of the `stat` calls the script already
makes for its caches. *Alternative considered:* env var → conf → default (the marketplace's
usual precedence). Rejected for this feature: the env tier buys nothing a running session can
use and adds a second source of truth to reason about. (User chose "command + conf flag",
explicitly declining the env-override variant.)

### D3 — Conf at `~/.claude/statusline.conf`, key `STATUSLINE_MODE`, parsed safely

Follow the marketplace config convention: a `~/.claude/<plugin>.conf` file of `KEY=VALUE`
lines, **read — never `source`d** — so a stray or hand-mangled conf can never execute shell.
Resolution reads the last `STATUSLINE_MODE=` line via `grep` + parameter expansion and
validates the result against the exact set `{enriched, lean}`; anything else, or an absent
file/key, falls through to the built-in default `enriched`. **Why:** matches the house pattern
(`shell-guard.conf`, `git-guard.conf`, `rtk-hook.conf`), keeps the parse injection-proof, and
makes every non-`{enriched,lean}` state fail soft to the safe default rather than to a broken
render. bash 3.2-safe: `grep`, `cut`/parameter expansion, and a `case` validation only.

### D4 — Default `enriched`, so existing installs are unchanged

With no conf present the script takes the enriched path exactly as before. **Why:** the
feature is strictly additive and opt-in; no current user sees a different statusline until
they run `/statusline-toggle`. This also means `/statusline-install` needs no change — the
conf is created lazily by the first toggle, not at install time. (User-confirmed: default
enriched.)

### D5 — Lean *gates* the enriched-only work, it does not compute-then-hide

The mode is resolved early, and the expensive, enriched-only computations are wrapped so they
run only when `mode = enriched`: the two transcript reads (`task`/`latest`), the rate-limit
gauge percentages + reset-epoch cache, the duration humanising, and the effort-from-settings
fallback. Lean computes only the shared-cheap fields (cwd compression, the cached branch
lookup, worktree shortening) plus model and the `c:` gauge. **Why:** lean should be genuinely
lighter — the transcript reads are the script's heaviest per-render cost, and there is no
reason to pay for output that is discarded. *Alternative considered:* compute everything as
today and only branch at the final `printf`. Rejected — simpler by a hair but wastes the
costliest work on every lean render, defeating half the point of a lean mode. The trade-off is
a mode conditional around a few compute blocks; the shared cheap fields stay unconditional so
both paths reuse them.

### D6 — `/statusline-toggle`: bare flips, optional argument sets, frictionless

`/statusline-toggle` reads the current mode (default `enriched` when the conf/key is absent)
and, with no argument, writes the opposite; an optional `enriched` or `lean` argument sets a
mode explicitly. It updates **only** the `STATUSLINE_MODE=` line — rewriting that line if
present, appending it if not — and leaves any other lines in the conf intact. It reports the
new mode and that it applies on the next render, and does **not** prompt for confirmation.
**Why no confirm:** the action is a local, display-only, trivially reversible flag (run it
again to flip back); a blocking prompt on every toggle would defeat the "quick runtime
switch" purpose. This is consistent with the marketplace rule reserving confirmation for
hard-to-reverse or shared-config edits — the conf is plugin-owned and the change is a single
validated token. *Alternative considered:* separate `/statusline-lean` + `/statusline-enriched`
commands — more surface for no gain; one verb with an optional argument covers both.

### D7 — `/statusline-uninstall` removes the conf (install ⇄ uninstall symmetry)

`~/.claude/statusline.conf` is the one piece of durable external state this change adds. Per
the marketplace's symmetry rule, durable external state needs a dedicated, ownership-guarded
revert. The conf is created by `/statusline-toggle` and removed by the extended
`/statusline-uninstall`, which deletes it when present and no-ops cleanly when absent. The
conf is wholly plugin-managed (only ever the `STATUSLINE_MODE` key our command writes), so
removing it on uninstall is unambiguously safe — unlike the `statusLine` settings key,
uninstall still refuses to touch a statusline the user wired by hand. **Why here and not a new
`/statusline-install` step:** there is nothing to set up at install (default is enriched); the
state only exists once a user opts in, so its lifecycle is toggle-creates ⇄ uninstall-removes.

### D8 — Surviving segments keep their existing colours; `c:` keeps severity colour

In lean mode cwd stays blue, the branch/worktree token stays yellow, the model stays cyan,
and the `c:` gauge keeps the value-driven severity colour from `statusline-severity-colours`
(it is pure-bash and the gauge's whole purpose is at-a-glance severity). The `c:` integer and
`gauge_sgr` helper are already computed cheaply and are shared by both paths. **Why:** lean is
a *subset* of enriched, not a restyle; reusing the same colours keeps the two modes visually
coherent and avoids introducing a second palette.

## Risks / Trade-offs

- **Per-render conf read adds I/O** → it is a single bounded file read (often a cache-warm
  stat + small read), negligible beside the existing branch/task/latest cache stats; mode
  resolution does no `jq` and spawns no subprocess.
- **Conf could contain arbitrary text (hand-edited or hostile)** → the conf is **read, never
  `source`d**, parsed with `grep`/parameter expansion, and validated to `{enriched, lean}`;
  any other content fails soft to `enriched` and never executes.
- **A mode branch duplicates a little render logic** → accepted (D5): the alternative wastes
  the costliest work on every lean render; shared cheap fields stay unconditional to limit the
  duplication to the final per-mode `printf` plus the gates around the enriched-only blocks.
- **Two sessions toggling at once** → last writer wins on a single-key file; harmless, since
  the value is a display flag and the next render simply reflects whatever was last written.
- **Lean hides the rate-limit gauges some users watch** → that is the explicit purpose of the
  mode; enriched remains the default and one `/statusline-toggle` away.

## Migration Plan

Additive and opt-in — no migration. A fresh install with no conf renders exactly as before.
Rollback at any granularity: `/statusline-toggle` (or `/statusline-toggle enriched`) returns
to enriched; `/statusline-uninstall` removes the conf along with the rest of the install;
deleting `~/.claude/statusline.conf` by hand also reverts to the default.

## Open Questions

None. The lean layout, the default mode, and the file-based (non-env) toggle mechanism were
settled with the user before drafting; the command name `/statusline-toggle` and the
single-key conf format follow existing marketplace conventions.
