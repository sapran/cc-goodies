# Design — config-aware push-target resolution for git-guard

## The gap, mechanically

git-guard's push branch (script lines ≈ 182–209) computes the target like this:

```
target = <last positional token>
de-quote; strip src: prefix (src:dst -> dst); strip +; strip refs/heads/
if target in {"", HEAD}:  br = current_branch        # <-- the blind spot
else:                     br = target
is_main(br) ? block : allow
```

The fallback `br = current_branch` assumes *local branch name == remote branch name*. git
does not guarantee that. The destination of a destination-less push is decided by git's push
routing, which the guard never consults:

| Mechanism | Example | Where `git push` (on `develop`) lands | Guard today |
|---|---|---|---|
| same-name upstream (`simple`/`current`) | `branch.develop.merge=refs/heads/develop` | `origin/develop` | allow ✅ correct |
| upstream, different name | `push.default=upstream` + `branch.develop.merge=refs/heads/main` | `origin/main` | **allow ✗** |
| triangular push remote | `branch.develop.pushRemote=origin` + upstream→main | `origin/main` | **allow ✗** |
| explicit push refspec | `remote.origin.push=refs/heads/develop:refs/heads/main` | `origin/main` | **allow ✗** |
| `matching` | `push.default=matching` | every same-name branch pair | partial |

The three ✗ rows are the bug. They are plain declarative config, not evasion.

## Verification that killed the first design (`@{push}`)

The first draft delegated to git: `git rev-parse --abbrev-ref <src>@{push}`. Testing
disproved it. `@{push}` resolves to a name **only when the remote-tracking ref
(`refs/remotes/<remote>/<branch>`) has been materialised** — i.e. after a fetch. With the
routing configured but no fetch (`push.default=upstream`, `branch.develop.merge=refs/heads/main`,
no `refs/remotes/origin/main`), it errors:

```
fatal: upstream branch 'refs/heads/main' is not stored as a remote-tracking branch
```

Two fatal problems: (1) `git push` would *still* route to `main` in that state, so `@{push}`
would fall open on the exact gap we are closing; (2) the error text is **localised** (it
printed in Ukrainian on the dev machine), so parsing it for the upstream name is out.

## Decision: read the narrow config that actually decides the name

The full push precedence is intricate, but the part that can route a *destination-less* push
to a **differently-named** branch is small. Walking the modes:

| `push.default` | destination branch name for source `develop` | dangerous? |
|---|---|---|
| `simple` (default ≥2.0) | same name; **refuses** if upstream name differs | no — git blocks it |
| `current` | same name | no |
| `matching` | every same-name pair | no (won't create `main` from `develop`) |
| `nothing` | none (errors without a refspec) | no |
| `upstream` / `tracking` | basename of `branch.develop.merge` — **may differ** | **YES** |

So the only config that silently sends a bare `git push` from `develop` onto a different
`main` is `push.default=upstream` (+ a mismatched `branch.<src>.merge`). That is a two-line
config read — not a reimplementation of git's precedence — and it needs no tracking ref:

```sh
pd=$(git -C "$dir" config push.default 2>/dev/null)              # empty -> simple default
case "$pd" in
  upstream|tracking)
    up=$(git -C "$dir" config "branch.$src.merge" 2>/dev/null); up="${up#refs/heads/}"
    [ -n "$up" ] && is_main "$up" && block ;;
esac
```

The same-name modes are already covered: the guard blocks a destination-less push while the
current branch *is* protected (`is_main "$src"`). And `simple` with a mismatched upstream is
**deliberately not blocked** — git refuses that push itself, so it can never reach `main`;
blocking it would be a false positive.

This is best-effort and **fail-open**: empty/missing config falls through to allow. No new
dependency; `current_branch` already shells to git.

## The other vector: explicit `remote.<remote>.push`

A configured `remote.<remote>.push` refspec applies even to a bare push, independent of
`push.default`. Resolve the remote (`branch.<src>.pushRemote` → `remote.pushDefault` →
`branch.<src>.remote` → `origin`, or the remote named on the command line) and judge each
push refspec's destination with the same extraction used for command-line refspecs:

```sh
for spec in $(git -C "$dir" config --get-all "remote.$remote.push" 2>/dev/null); do
  is_main "$(refspec_dst "$spec" "$dir")" && block
done
```

Refspecs carry no spaces, so word-splitting the config values is safe and keeps the loop in
the current shell — a `… | while read` pipe would run in a subshell that cannot `deny`.

## Distinguishing remote from refspec (the arg model)

`git push [<remote>] [<refspec>...]`. The guard drops a leading positional that is a
**configured** remote (`git config --get remote.<x>.url` succeeds), and treats whatever
remains as explicit refspecs:

- refspecs present → judge **each** (explicit refspecs override `push.default`; this is also
  where the multi-refspec gap is closed);
- no refspecs → destination-less → the config resolution above.

A URL or unknown name is left as a refspec (best-effort); since it carries a colon it
extracts a harmless non-branch `dst` while any real protected refspec beside it is still
caught.

## Adjacent gap (recommended to fold in): only the last positional is checked

The push loop records only `last="$1"` for positionals, so a multi-refspec push is judged on
just the final one:

```
git push origin main develop      # pushes BOTH; guard checks develop, misses main
```

This is a *different* gap (command-line, not config) but lives in the same loop and the same
"judge the real target(s)" intent. Fix: accumulate every positional refspec and test each
resolved `dst`. Recommended to include — it is cheap and closes a sibling hole — but it can
be scoped out into its own change if you want this proposal to stay strictly about config
routing. **Decision needed from the user.**

## Alternatives considered

- **Parse `push.default` + branch/remote config in bash and compute the target ourselves.**
  Rejected: re-implements git's precedence, drifts across git versions, more code than the
  delegation it replaces.
- **Block every push that has no explicit `:dst` unless the upstream is same-name.** Rejected:
  too aggressive — it would block ordinary `git push` on feature branches the moment upstream
  resolution hiccups; the fail-open delegation is more precise.
- **Switch users to `GIT_GUARD_BLOCK_ALL_PUSH=1`.** That already exists and *does* cover this
  case, but it is a blunt instrument (blocks all pushes, including to feature branches) and is
  opt-in; the default policy should still be correct for the targeted-protected case.
- **Do nothing / document only.** Rejected: the guard's single promise is "a push whose
  resolved target is protected is blocked." A config-routed push to main violates that
  promise silently — the worst failure mode for a safety guard (false sense of safety).

## Risks & mitigations

- **Extra git calls in the hook.** Only on `push` verbs (rare), and the guard already shells
  to git. Bounded: at most one `rev-parse` + one `config --get-all` per push command.
- **`@{push}` semantics across git versions.** It is stable and old (git ≥ 2.5). Fail-open on
  any error means a surprising version simply reverts to today's behaviour, never a spurious
  block.
- **Behaviour change.** A previously-allowed config-routed push to main now blocks. Intended,
  and the standard `!`-line escape hatch covers the rare legitimate case.
- **False completeness.** `matching` mode and exotic refspecs may still slip; the spec scopes
  the guarantee to upstream/pushRemote routing + `remote.*.push`, and the README "Limitations"
  must say so rather than imply total coverage.

## Test plan

Two file-driven runners (the command under test is piped as JSON to the dev script as a
subprocess, so the live hook never sees it — [[guard-testing-via-files]]):

- **`tests/cases.tsv` + `run.sh`** — cases needing only a checked-out branch. New rows:
  `push-multi-includes-main` (`git push origin main develop` → block, the multi-refspec gap),
  `push-multi-all-safe` (all-unprotected multi-refspec → allow), `push-bare-no-upstream`
  (bare push, no config → allow / fail-open). All 49 pass.
- **`tests/run-routing.sh`** — cases needing per-repo `git config` (pure config, no fetch /
  fake-remote ref required):

| Case | Repo config | Command | Expect |
|---|---|---|---|
| upstream-routes-bare-to-main | `push.default=upstream`, merge=refs/heads/main | `git push` | block (2) |
| upstream-routes-remotearg-to-main | + remote `origin` | `git push origin` | block (2) |
| upstream-triangular-to-main | upstream + `branch.develop.pushRemote` | `git push` | block (2) |
| remote-push-refspec-to-main | `remote.origin.push=…develop:…main` | `git push` | block (2) |
| upstream-same-name | upstream, merge=refs/heads/develop | `git push` | allow (0) |
| simple-same-name | `simple`, merge=refs/heads/develop | `git push` | allow (0) |
| simple-mismatch-not-blocked | `simple`, merge=refs/heads/main | `git push` | allow (0) — git refuses |
| explicit-refspec-overrides | upstream→main + remote `origin` | `git push origin develop` | allow (0) |

All 8 pass. The existing `push-origin-main` / `HEAD:main` / `+main` / `:main` rows in
cases.tsv remain the regression lock for the explicit-`src:dst` path.
