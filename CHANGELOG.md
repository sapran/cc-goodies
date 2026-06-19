# Changelog

All notable changes to cc-goodies are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`shell-guard` plugin** — a `PreToolUse`/`Bash` hook that hard-blocks (exit 2) a
  curated set of dangerous shell commands before they run: recursive deletes of `/`,
  `$HOME`/`~`, or a top-level system directory (and any `--no-preserve-root`); `dd` onto
  a `/dev` device; `mkfs`/`wipefs`/`newfs`; destructive `diskutil`; redirects onto a raw
  disk device; fork bombs; network downloads piped into a shell (`curl|sh`); truncating a
  file to empty (`: >`, `truncate -s0`); `chmod 777`; `eval`; `sudo` (default-on, opt out
  with `SHELL_GUARD_ALLOW_SUDO=1`); and system halt/reboot
  (`reboot`/`shutdown`/`halt`/`poweroff`/`init 0|6`). Designed to cover — and improve on —
  a typical shell `permissions.deny` list: it normalizes flags/spacing and resolves the
  target, catching obfuscated variants string-matching misses, while deliberately allowing
  ordinary work (`rm -rf ./build`, `dd … of=file`, `curl|jq`, `git init`, plain `> file`
  redirects, `chmod 755`). Configurable via `~/.claude/shell-guard.conf`
  (`SHELL_GUARD_DISABLE`, `SHELL_GUARD_ALLOW_SUDO`, `SHELL_GUARD_EXTRA_PATTERNS`) through
  `/shell-guard`, with a matching `/shell-guard-uninstall`. Fails open if `jq` is missing.
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

- **`git-guard`** now guards `git pull` and `git rebase` in addition to
  `commit`/`merge`/`push`. Both mutate the current branch like a commit, so they are
  treated as local writes: blocked on protected branches under policy 2 (default) and 3,
  allowed on dev/feature branches, and never blocked under policy 1.

## [0.1.0]

### Added

- Initial marketplace with three plugins: **`voice-notify`** (spoken macOS
  notifications), **`statusline`** (enriched two-line statusline), and **`git-guard`**
  (protected-branch guard for `commit`/`merge`/`push`).
