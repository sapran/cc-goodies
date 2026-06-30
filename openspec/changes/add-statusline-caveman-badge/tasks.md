## 1. Badge segment in the statusline script

- [x] 1.1 Add a `caveman_badge()` helper to `plugins/statusline/statusline-command.sh` that resolves `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, reads `.caveman-active`, and returns the badge string — replicating the caveman hardening verbatim: `[ -L ]` symlink refusal, `head -c 64` read cap, lower-case + `tr -cd 'a-z0-9-'`, and the mode whitelist (`off|lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress`); unrecognised → empty output.
- [x] 1.2 Map the flag value to a label inside the helper: `full` or empty → `[CAVEMAN]`; any other whitelisted mode → `[CAVEMAN:<MODE>]` upper-cased; render in colour `38;5;172`.
- [x] 1.3 Append the savings suffix from `.caveman-statusline-suffix` when present and not a symlink: `head -c 64`, strip control bytes (`tr -d '\000-\037'`), render in the badge colour after the badge.
- [x] 1.4 Gate the segment on the opt-out env vars: `STATUSLINE_CAVEMAN=0` suppresses the whole segment; `CAVEMAN_STATUSLINE_SAVINGS=0` suppresses only the savings suffix; default on.
- [x] 1.5 Call the helper only inside the `enriched` render block, appended after the `c:`/`s:`/`w:` gauge printfs as the last segment of L2 (before the closing newline); leave the `lean` path untouched. Use no `jq` — plain-bash reads only.
- [x] 1.6 Short-circuit immediately when `.caveman-active` is absent so the common (no-caveman) path adds negligible work.

## 2. Tests

- [x] 2.1 Add cases to `plugins/statusline/tests/run.sh` (real temp config dir; pipe synthetic stdin JSON; assert on output): badge renders at end of L2 for `full` (`[CAVEMAN]`) and for a named mode (`[CAVEMAN:ULTRA]`). — case_l
- [x] 2.2 Hardening cases: symlinked `.caveman-active` → no badge; unrecognised/escape-laden flag value → no badge and no raw bytes emitted; oversized/control-laden content truncated and stripped. — case_m, case_n
- [x] 2.3 Savings cases: suffix present → appended after badge; suffix file absent → badge alone, no error; symlinked suffix → suffix omitted. — case_o
- [x] 2.4 Opt-out cases: `STATUSLINE_CAVEMAN=0` → no segment; `CAVEMAN_STATUSLINE_SAVINGS=0` → badge without savings. — case_p
- [x] 2.5 Fail-soft / regression cases: no `.caveman-active` → output byte-identical to the opted-out render; `lean` mode with an active flag → single line unchanged, no badge. — case_q, case_r
- [x] 2.6 Pin the recognised-mode whitelist with an explicit assertion so future caveman-mode drift is caught. — case_s

## 3. Validation

- [x] 3.1 `bash -n plugins/statusline/statusline-command.sh` and `shellcheck plugins/statusline/statusline-command.sh` clean.
- [x] 3.2 Run `plugins/statusline/tests/run.sh` — all 19 cases pass.
- [x] 3.3 `claude plugins validate plugins/statusline` passes; `jq empty` on `plugins/statusline/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.

## 4. Documentation

- [x] 4.1 Update `plugins/statusline/README.md`: new "Caveman badge" section — enriched-only end of L2, the `.caveman-active`/`.caveman-statusline-suffix` source, the `STATUSLINE_CAVEMAN` / `CAVEMAN_STATUSLINE_SAVINGS` opt-outs, the hardening, the cross-plugin coupling note, and the fail-soft behaviour.
- [x] 4.2 Mirror the badge note in the root `README.md` statusline entry.
- [x] 4.3 Record the cross-plugin coupling (paths, value whitelist, fail-soft). **Deviation:** folded into the statusline README's "Caveman badge" section rather than `docs/shell-safety.md` — that doc is scoped strictly to the dangerous-shell-command defense (git-guard/shell-guard/rtk-hook) and a statusline-rendering coupling does not belong in its map.
- [x] 4.4 Add a `CHANGELOG.md` entry (`[0.8.0]`) under the statusline plugin.

## 5. Release

- [x] 5.1 Minor-bump `plugins/statusline/.claude-plugin/plugin.json` (`0.5.1` → `0.6.0`) and the marketplace `metadata.version` in `.claude-plugin/marketplace.json` (`0.7.2` → `0.8.0`), per the repo release flow.
- [x] 5.2 Committed as 4 logical commits (docs:proposal → feat:script+tests → docs:READMEs → chore:version bump+CHANGELOG) on branch `worktree-statusline-caveman-badge` (98f61f3, 5751cc5, fa1cbfc, a469721). Not pushed; `develop` merge and `develop` → `main` fast-forward left to the user.
