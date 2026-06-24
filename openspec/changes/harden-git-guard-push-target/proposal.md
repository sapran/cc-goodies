## Why

git-guard resolves a push's target branch from the **literal refspec text** of the
command, then falls back to the **current branch name** when the command names no explicit
destination. It never asks git where the push would actually land. That is correct for the
forms it was built for — `git push origin develop:main` (explicit `src:dst`, blocked),
`git push` on a same-name upstream (lands on `develop`, allowed) — but it leaves a real
blind spot: a push whose **effective destination is a protected branch even though no
`:main` appears in the command**.

Two configurations route a plain `git push` from `develop` onto `origin/main` with nothing
in the command text to show it:

```
push.default = upstream      AND  branch.develop.merge = refs/heads/main
              ── or ──
remote.origin.push = refs/heads/develop:refs/heads/main
```

With either set, `git push` (or `git push origin`) on `develop` updates `main` on the
remote. git-guard sees no `:` in the command, falls back to `current_branch` → `develop`,
calls `is_main develop` → false, and **allows the push**. The guard's own output line in
that case (`develop -> main`) is exactly what a confused operator would read as "the guard
let a push to main through."

This is not the deliberate-evasion class the README explicitly disclaims (`bash -c`, `$()`,
gitconfig command-aliases — plan mode's job). It is an ordinary, declarative git
configuration silently changing where an *accidental* `git push` goes — precisely the
accident the guard exists to catch. Closing it keeps the guard honest about its one
promise: "a push whose resolved target is a protected branch is blocked."

> Note: the repository as currently configured (`push.default` unset → `simple`,
> `branch.develop.merge = refs/heads/develop`, no `remote.origin.push`) does **not** trigger
> this path — a bare push here goes to `origin/develop`. This change hardens the guard
> against the configurations that *would* trigger it, on this or any other clone.

## What Changes

- **Resolve the push target from git's push configuration when the command names no explicit
  refspec.** For the destination-less forms (bare `git push`, `git push <remote>`), the guard
  SHALL read `push.default` and the current branch's upstream from config (scoped with `-C`
  to the resolved repo dir): when `push.default` is `upstream`/`tracking` the destination is
  the basename of `branch.<src>.merge`; the other modes push same-name and are judged as
  today. (Verification showed `git rev-parse <src>@{push}` is unfit — it needs a materialised
  remote-tracking ref and fails, with localised errors, on the exact unfetched case we are
  closing; see design.md.)

- **Best-effort, fail-open, unchanged philosophy.** Missing/empty config falls back to
  today's current-branch behaviour and allows. `push.default=simple` with a mismatched
  upstream is intentionally **not** blocked — git refuses that push itself. No new dependency:
  `git` is already invoked by `current_branch`. The guard stays a convenience guard, not a
  sandbox.

- **Cover the explicit `remote.<remote>.push` refspec case.** A configured
  `remote.<remote>.push` refspec applies even to a bare push, independent of `push.default`.
  When the resolved remote has such refspecs, the guard SHALL extract each refspec's `dst`
  (the same `src:dst → dst` logic it applies to command-line refspecs) and block if any names
  a protected branch. Best-effort; unreadable config falls open.

- **(Recommended, adjacent) Check every positional refspec, not only the last.** The current
  push loop records only the *last* positional as the target, so `git push origin main
  develop` (two refspecs, pushes both) is judged on `develop` and slips `main` through. The
  same parse loop should test **each** positional refspec's resolved `dst`. This is a
  distinct gap from the config one but lives in the same code and the same "resolve the real
  target" intent — folded in here unless scoped out (see design.md "Adjacent gap").

- **Tests** extend `plugins/git-guard/tests/` with temp repos configured for each routing
  case (upstream→main, `remote.origin.push`→main, multi-refspec) asserting block (2), plus
  same-name-upstream and no-upstream cases asserting allow (0)/fail-open.

## Capabilities

### New Capabilities

- `git-guard-push-target`: git-guard resolves a push's effective destination branch — not
  merely the branch named in the command — and blocks when that destination is protected.
  For an explicit `src:dst` refspec the destination is `dst`; for a command with no explicit
  destination the destination is what git's push routing (`@{push}`, honouring
  `push.default` / `pushRemote` / upstream) and any `remote.<remote>.push` refspec resolve
  to; every positional refspec is judged, not only the last. Resolution is best-effort and
  fails open (allows) when git cannot determine the target.

### Modified Capabilities

<!-- None. git-guard has no prior spec in openspec/specs/ — its behaviour was documented
     only in the script header and README. This change introduces the first spec, scoped to
     push-target resolution (the surface this change touches). The local-write,
     branch-force, BLOCK_ALL_PUSH, and config-precedence behaviours remain governed by the
     script and README and are intentionally NOT spec'd here; this proposal does not change
     them. -->

## Impact

- **Code:** `plugins/git-guard/scripts/git-guard.sh`, the `action = push` block. Collect all
  positionals; drop a leading configured remote; if explicit refspecs remain, judge **each**
  via a new `refspec_dst` helper (`src:dst`/`:dst`/`+x`/same-name/`HEAD`/`refs/heads/`); if
  none remain (destination-less), resolve from `push.default` + `branch.<src>.merge` and scan
  `remote.<remote>.push`. Every new git call is wrapped so a non-zero/empty result falls back,
  never blocks spuriously.
- **Tests:** `plugins/git-guard/tests/` — add cases (synthetic stdin JSON against temp repos
  with the routing config set) for: upstream→protected (block), `remote.*.push`→protected
  (block), multi-refspec including protected (block), same-name upstream (allow), no upstream
  / detached (allow, fail-open). Follow the existing file-driven harness so live-hook
  literals do not trip shell-guard ([[guard-testing-via-files]]).
- **Docs:** `plugins/git-guard/README.md` — update "Limitations"/behaviour to state that
  config-routed and multi-refspec pushes are now resolved; `docs/shell-safety.md` if it
  enumerates what git-guard catches; root `README.md` git-guard row unchanged (one-liner
  still accurate). `CHANGELOG.md` entry.
- **Release:** per the release flow ([[cc-goodies-release-flow]]) a `fix:`-level bump of
  `plugins/git-guard/.claude-plugin/plugin.json` and the marketplace
  `metadata.version`, tag on the archive commit; main FF handed to the user as a `!`-line.
- **Dependencies:** none added — `git` and `jq` already required.
- **Compatibility / behaviour change:** a push that previously slipped through because it was
  config-routed to a protected branch will now be **blocked**. That is the intended fix, but
  it is a behaviour change: anyone relying on a config-routed push to main from a session
  gets the standard `!`-line escape hatch. Same-name-upstream and explicitly-different
  `src:dst` forms behave exactly as before.
- **Performance:** one extra `git rev-parse` (and at most one `git config --get-all`) per
  *push* command only — push verbs are rare and the guard already shells out to git for
  branch lookups. No change to non-push commands.
- **Out of scope:** deliberate evasion (`bash -c`, command substitution, gitconfig
  command-aliases) — unchanged, still plan mode's job; `git push --all/--mirror` (already
  blocked wholesale); resolving inline `-c push.default=…` overrides on the command line
  (treated as opaque today, kept so); any change to local-write or branch-force policy.
