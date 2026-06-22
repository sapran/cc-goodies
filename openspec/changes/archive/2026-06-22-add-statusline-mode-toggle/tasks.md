## 1. Mode resolution in the statusline script

- [x] 1.1 In `plugins/statusline/statusline-command.sh`, after the single `jq` field-parse block (around line 34), resolve the active mode: default `mode=enriched`; if `$HOME/.claude/statusline.conf` exists, read the last `STATUSLINE_MODE=` line with `grep` + parameter expansion / `cut` (read only — **never** `source` the file), then `case`-validate the value to `enriched|lean`, falling back to `enriched` for anything else
- [x] 1.2 Confirm mode resolution adds no `jq` call and no subprocess beyond the single `grep`/read, preserving the one-`jq`-parse-per-render budget; bash 3.2 / BSD safe (only `grep`, `cut`/parameter expansion, `case`)

## 2. Gate the enriched-only work behind enriched mode

- [x] 2.1 Wrap the effort-from-settings fallback (the `$HOME/.claude/settings.json` read and the `effort="auto"` default) so it runs only when `mode = enriched` (lean drops the effort suffix)
- [x] 2.2 Wrap the rate-limit gauge + reset-epoch cache block (the `rl_cache` recover/persist and percentage recovery) so it runs only when `mode = enriched`
- [x] 2.3 Wrap the time-readout block (duration `c_dur`, `s_reset`, `w_reset` via `humanize_secs`) so it runs only when `mode = enriched`
- [x] 2.4 Wrap the `task` and `latest` transcript reads (the `head -n 500` / `tail -n 500 | tail -r` + `first_real` lookups and their caches) so they run only when `mode = enriched` — these are the script's heaviest per-render cost
- [x] 2.5 Keep the shared cheap fields unconditional: cwd compression, the cached branch lookup, and worktree shortening (lean uses cwd + branch/worktree)

## 3. Lean-mode render path

- [x] 3.1 Branch the final render on `$mode`: keep the existing two-line `printf` block as the `enriched` path unchanged
- [x] 3.2 Add the `lean` path: a single line of compressed cwd (`\033[34m`), the `[branch]` or `wt:` worktree token (`\033[33m`) when present, the model display name (`\033[36m`), and — when `used` is present — the `c:NN%` gauge coloured by `gauge_sgr "$used_int" 25:'38;5;178' 50:'38;5;208' 75:'1;38;5;196'` (compute `used_int=$(printf '%.0f' "$used")` in this path), terminated by a single `\n`
- [x] 3.3 Confirm the lean path emits no `user@host`, no `task → latest`, no `(effort)`, no `s:`/`w:` gauge, and no `⧗`/`⟲` suffix, and that it is exactly one line

## 4. `/statusline-toggle` command

- [x] 4.1 Create `plugins/statusline/commands/statusline-toggle.md` with YAML frontmatter (`description`, `allowed-tools` scoped to the `grep`/`cut`/`mkdir`/`mv`/`test` + `Read`/`Edit` it needs, `disable-model-invocation: true` to match the other statusline commands)
- [x] 4.2 Command body: determine the target mode — an `enriched`/`lean` argument sets it explicitly; with no argument, read the current `STATUSLINE_MODE` from `$HOME/.claude/statusline.conf` (treat absent/invalid as `enriched`) and flip it
- [x] 4.3 Command body: persist the value by writing `STATUSLINE_MODE=<mode>` to `$HOME/.claude/statusline.conf` (`mkdir -p "$HOME/.claude"` first), **updating only that key** — rewrite the existing `STATUSLINE_MODE=` line if present (e.g. `grep -v` into a temp file then append), append it if not, and preserve every other line
- [x] 4.4 Command body: report the resulting mode and that it takes effect on the next render (no restart); no confirmation prompt (the change is local, display-only, and trivially reversible)

## 5. Extend `/statusline-uninstall` to remove the conf

- [x] 5.1 In `plugins/statusline/commands/statusline-uninstall.md`, add a step to delete `$HOME/.claude/statusline.conf` (`rm -f`) as part of reverting durable state — completing the install ⇄ uninstall symmetry for the mode toggle
- [x] 5.2 Ensure the new step is no-op-clean when the conf is absent and is described in the command's final "what was removed" report; the existing `statusLine`-ownership guard is unchanged

## 6. Documentation

- [x] 6.1 Update `plugins/statusline/README.md`: document the two modes, the lean single-line layout (`~/cab/claude.ai  [main]  Opus 4.8  c:42%`) and exactly what it drops, the `enriched` default, the `/statusline-toggle` command (bare flips, optional `enriched`/`lean` argument), and the `~/.claude/statusline.conf` / `STATUSLINE_MODE` mechanism read each render
- [x] 6.2 Note in the README Uninstall section that `/statusline-uninstall` now also removes `~/.claude/statusline.conf`, and add `/statusline-toggle` to the command list
- [x] 6.3 Mirror the statusline entry update in the marketplace root `README.md` (mode toggle mentioned); leave `plugin.json` keywords as-is unless a `version` bump is part of release

## 7. Verify

- [x] 7.1 `bash -n plugins/statusline/statusline-command.sh` and `shellcheck plugins/statusline/statusline-command.sh` pass
- [x] 7.2 With `HOME` pointed at a temp dir and **no** conf, pipe synthetic stdin and assert the output is the unchanged two-line enriched statusline (default = enriched)
- [x] 7.3 With a temp `HOME` whose `.claude/statusline.conf` has `STATUSLINE_MODE=lean`, pipe the same stdin and assert the output is exactly one line containing cwd, `[branch]`, model, and `c:NN%`, and containing no `user@host`, no `task → latest`, no `(effort)`, no `s:`/`w:` gauge, and no `⧗`/`⟲`
- [x] 7.4 Assert lean keeps the `c:` severity colour: a lean render with a red-band context value emits the bold-red SGR on the `c:` token
- [x] 7.5 Assert fail-soft: a conf with `STATUSLINE_MODE=bogus` (and one with no `STATUSLINE_MODE` key) renders enriched without error
- [x] 7.6 Assert the conf is never executed: a conf containing a side-effecting shell line (e.g. one that would `touch` a sentinel file) alongside `STATUSLINE_MODE=lean` renders lean and the sentinel file is **not** created
- [x] 7.7 Assert lean does not read the transcript: with `STATUSLINE_MODE=lean` and a transcript path whose contents would otherwise surface a task, the lean output contains no task snippet and is identical to the lean output with the transcript path omitted
- [x] 7.8 Assert mode is re-read per render (runtime): two consecutive renders with the same stdin but the conf flipped between them produce enriched then lean (or vice versa), with no other state carried over
- [x] 7.9 Confirm `jq` is still invoked exactly once for field extraction in both modes and the only files written remain those in the `$TMPDIR` cache (the script itself writes no conf)
- [x] 7.10 Toggle command round-trip: from a conf containing an unrelated key, run the documented toggle write and assert `STATUSLINE_MODE` flips while the unrelated key is preserved; run `/statusline-uninstall`'s conf-removal step and assert the conf is gone and the step is clean when re-run
