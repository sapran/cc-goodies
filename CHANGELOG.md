# Changelog

All notable changes to cc-goodies are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
