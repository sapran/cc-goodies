## 1. Resolve config-routed push target (config read, NOT `@{push}`)

> Design pivot — verification showed `git rev-parse <src>@{push}` requires a materialised
> remote-tracking ref and fails (with localised errors) on the exact unfetched case we close.
> Switched to a direct config read. See design.md "Verification that killed the first design".

- [x] 1.1 In `plugins/git-guard/scripts/git-guard.sh` `action = push` block, collect ALL positionals; drop a leading positional that is a configured remote (`git -C <dir> config --get remote.<x>.url`); whatever remains are explicit refspecs
- [x] 1.2 Explicit-refspec path unchanged in spirit: judge each remaining refspec via the new `refspec_dst` helper (de-quote, strip `+`/`refs/heads/`, `src:dst`/`:dst` → dst, single token → same-name, `HEAD` → current branch) and `is_main` → block
- [x] 1.3 Destination-less path (no refspecs left): `src` = current branch; read `push.default` (empty → simple default) and, for `upstream`/`tracking`, `branch.<src>.merge` basename — no `@{push}`, no tracking ref required
- [x] 1.4 Block when the resolved upstream is protected (`deny "push routed by push.default=upstream to protected branch '<br>'"`); same-name modes fall back to the existing `is_main "$src"` block; `push.default=simple` with a mismatched upstream is intentionally NOT blocked (git refuses it)
- [x] 1.5 Every new `git` invocation wrapped (`2>/dev/null`, empty-result guarded) so a git error or non-repo never produces a spurious block (fail-open)

## 2. Cover explicit `remote.<remote>.push` refspecs

- [x] 2.1 Derive the target remote: the explicit `<remote>` positional if given; else `branch.<src>.pushRemote` → `remote.pushDefault` → `branch.<src>.remote` → `origin` (best-effort, via `git config --get`)
- [x] 2.2 Read `git -C "$dir" config --get-all "remote.<remote>.push"` (word-split loop, not a `| while read` subshell — must stay in-shell to `deny`); for each refspec extract `dst` via `refspec_dst`, and block on the first protected `dst`
- [x] 2.3 Best-effort: no remote resolved or unreadable config falls open (allow)

## 3. Adjacent gap — judge every positional refspec (FOLDED IN)

- [x] 3.1 Folded in: replaced the single `last="$1"` with accumulation of all positionals; the explicit-refspec path runs `refspec_dst` + `is_main` over each, blocking on the first protected target (tested by `push-multi-includes-main`)
- [x] 3.2 N/A — folded in, not scoped out

## 4. Tests

- [x] 4.1 No-config cases added to `tests/cases.tsv`; config-dependent cases in a new `tests/run-routing.sh` (file-driven; commands piped as JSON to the dev script subprocess, never run in the harness shell — [[guard-testing-via-files]])
- [x] 4.2 Block (2) cases: upstream→main (bare + remote-arg), triangular pushRemote→main, `remote.origin.push`→main (run-routing.sh); multi-refspec including main (cases.tsv)
- [x] 4.3 Allow (0) / fail-open cases: same-name upstream, simple same-name, simple mismatch (git refuses → not blocked), explicit-refspec-overrides (run-routing.sh); bare push no-upstream + all-safe multi-refspec (cases.tsv)
- [x] 4.4 Regression locks: existing `push-origin-main` / `HEAD:main` / `+main` / `:main` / quoted cases still block; full suite 49/49 + routing 8/8 green
- [x] 4.5 `bash -n` + `shellcheck` clean on both the script and the new runner

## 5. Docs & release

- [x] 5.1 Updated `plugins/git-guard/README.md`: "What it catches" gains config-routed + multi-refspec bullets; "Limitations" notes `matching`/exotic routing still falls open
- [x] 5.2 Updated `docs/shell-safety.md` push row (each refspec + config-routed target); root `README.md` git-guard row verified still accurate (unchanged)
- [x] 5.3 `CHANGELOG.md` entry under git-guard — landed in `chore(release)` commit `5fd963e` (`## [0.7.2] - 2026-06-24`)
- [x] 5.4 Release per [[cc-goodies-release-flow]]: `fix:` bump git-guard `0.2.2`→`0.2.3` + marketplace `0.7.1`→`0.7.2` (`5fd963e`); archive commit + annotated `v0.7.2` tag on develop; `main` FF handed to user as a `!`-line
