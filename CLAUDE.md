# CLAUDE.md

Guidance for Claude Code when developing in this repository.

## What this is

`cc-goodies` is a **plugin marketplace** — a small collection of independent, opt-in
Claude Code plugins. Each lives under `plugins/<name>/` and is installable on its own.

> **Dev source vs. installed copy.** This repository is the development source — edit it here.
> The copy under `~/.claude/plugins/marketplaces/<marketplace>/` is the *installed* clone that
> `/plugin marketplace add` manages and **overwrites on update**; never edit that one. `git fetch`
> before working — the dev clone can lag what's already published.

| Plugin | Kind | Notes |
|--------|------|-------|
| `statusline` | statusline + install command | macOS-oriented; needs `/statusline-install` to wire `statusLine` into settings (a plugin can't set that key itself) |
| `voice-notify` | hooks | macOS `say`; Notification + Stop hooks |
| `git-guard` | hook + commands | cross-platform; PreToolUse/Bash guard against writes to protected branches |
| `shell-guard` | hook + commands | cross-platform; PreToolUse/Bash guard that hard-blocks a curated catastrophic-command set (`rm -rf ~`, `dd` to device, `mkfs`, fork bombs, `curl\|sh`). Defence in depth over the `settings.json` deny list |

## Install ⇄ uninstall symmetry (required)

Every plugin ships a documented, **symmetric install and uninstall path**. A change that
adds an install or setup step without its documented inverse is incomplete.

- **Both directions documented:** the plugin README has an **Install** and an **Uninstall**
  section, and the root `README.md` mirrors both.
- **Every install verb has its inverse:** `marketplace add` ⇄ `marketplace remove`,
  `/plugin install` ⇄ `/plugin uninstall`, `/<name>-install` ⇄ `/<name>-uninstall`.
- **Durable external state needs a dedicated, ownership-guarded revert.** If install writes
  durable state outside the plugin dir (`~/.claude/settings.json`, `~/.claude/<plugin>.conf`,
  files under `$HOME`), ship a `/<name>-uninstall` that reverts exactly what install added,
  backs up shared config before editing, verifies it still parses, and **refuses to touch
  state the user configured themselves**. `statusline` and `git-guard` are the reference
  implementations; pure-hook plugins like `voice-notify` rely on `/plugin uninstall` and say so.
- **Ephemeral `$TMPDIR` caches are exempt** — they self-clear and need no teardown.

## Layout

```
.claude-plugin/marketplace.json   # registers every plugin (name, source, description)
README.md                          # top-level marketplace overview
plugins/<name>/
  .claude-plugin/plugin.json       # manifest; hooks declared INLINE here
  scripts/*.sh                     # hook/statusline scripts
  commands/*.md                    # slash commands
  README.md                        # per-plugin docs
```

Adding a plugin = create `plugins/<name>/` **and** add an entry to
`.claude-plugin/marketplace.json`. Bump `metadata.description` there if the lineup changes.

## Conventions

- **Hooks are declared inline in `plugin.json`** under a `hooks` key — this repo does
  *not* use a separate `hooks/hooks.json`. Reference scripts as
  `${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh`. Use `"async": true` only for fire-and-forget
  hooks (e.g. notifications); a blocking guard must stay synchronous.
- **Shell scripts**: `#!/bin/bash`, `set -u`, must degrade gracefully (no-op cleanly
  when a dependency or platform feature is missing — never hard-fail a user's workflow).
  Comments explain *why*, not what. Target macOS's bash 3.2 (avoid named-array features
  that break there). Keep scripts `chmod +x`.
- **Config pattern**: precedence is **env var → `~/.claude/<plugin>.conf` → built-in
  default**. Parse the conf file *safely* (read `KEY=VALUE` with grep/parameter
  expansion — never `source` it; a stray/untrusted conf must not execute shell).
- **Commands** are markdown with YAML frontmatter (`description`, `allowed-tools`) whose
  body instructs Claude. Anything a plugin can't do declaratively (e.g. writing the
  `statusLine` key) is done via a command that reads, shows the diff, confirms, and
  merges with `jq` — never clobbering unrelated keys. Every such command has a matching
  `/<name>-uninstall` (see **Install ⇄ uninstall symmetry** above).
- **`jq` is the parsing dependency.** Statusline requires it; hooks that need it should
  no-op (fail open) with a one-line warning if it's missing, rather than blocking.

## Hook authoring — the input contract (important)

Hooks receive their event as **JSON on stdin**, not via environment variables. For a
PreToolUse/Bash hook:

```bash
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')          # the SESSION cwd
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
```

- There is **no `$CLAUDE_TOOL_INPUT`** env var. (A previous external hook read it, got
  empty input, and silently passed everything — a fail-open bug. Don't repeat it.)
- **Block with `exit 2`** (stderr is fed back to Claude). `exit 1` is a *non-blocking*
  error — the tool still runs. `exit 0` allows.
- Env vars that *do* exist in command hooks: `$CLAUDE_PROJECT_DIR`, `$CLAUDE_PLUGIN_ROOT`,
  `$CLAUDE_ENV_FILE` (SessionStart only), `$CLAUDE_CODE_REMOTE`.
- `.cwd` is the session working directory, not a `cd` target inside the command — resolve
  other repos with `git -C <path>` if it matters.
- Hooks load at session start; test changes with `/hooks` reload or a restart.

## Testing

No test framework — verify scripts by piping synthetic stdin and asserting exit codes,
in real temp git repos where branch state matters. Before committing a script change run:

```bash
bash -n plugins/<name>/scripts/<script>.sh      # syntax
shellcheck plugins/<name>/scripts/<script>.sh    # lint
jq empty plugins/<name>/.claude-plugin/plugin.json && jq empty .claude-plugin/marketplace.json
```

git-guard's policy matrix is the reference example: one harness builds temp repos on
`main`/`develop`/`feature`, pipes crafted tool-call JSON, and checks allow (0) vs block (2)
across every policy, refspec form, compound command, and false-positive case.

## Git workflow

- Branches: do work on **`develop`**; `main` is the release branch.
- This repo eats its own dog food — `git-guard` (policy 2) blocks commits/pushes to
  `main` from a Claude session. That's intentional. Push `main` from a terminal, or
  fast-forward `develop` → `main` with explicit user confirmation.
- Conventional commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`),
  one logical change per commit. Confirm before pushing.

## Common commands

```bash
claude plugins validate plugins/<name>
/plugin marketplace add sapran/cc-goodies
/plugin install <name>@cc-goodies
```
