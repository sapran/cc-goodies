# git-guard

A `PreToolUse` hook that **blocks an aligned agent from accidentally writing a
protected branch before it happens**. When Claude tries a `git commit`, `git merge`,
`git pull`, `git rebase`, or `git push` that would land on `main` (or `master`), the
command is denied (exit 2) and Claude is told why — instead of finding out after
`main` already moved.

It only ever gates **Claude's Bash tool**. You can still run any command yourself
in a terminal.

## What a block looks like

When a command would write a protected branch, the hook exits 2 and Claude sees this
on stderr (so it stops and tells you, instead of `main` moving). For
`git push origin main`:

```text
⛔ git-guard: blocked push to protected branch 'main'.
   Protected: main master. Use a feature branch or 'develop'.
   To run it yourself, paste into the prompt (! runs it in your shell):
! git push origin main
   Or set GIT_GUARD_DISABLE=1 / see /git-guard.
```

The blocked command is always handed back as a ready-to-paste `!`-prefixed line.
Typed into the Claude Code prompt, the `!` prefix runs it in **your** shell — which
this hook never gates — so overriding a one-off block is a single copy-paste.

## Behavior

One built-in behaviour, one optional toggle:

- **Default** — keep protected branches clean: block a local write (`commit`, `merge`,
  `pull`, `rebase`, `cherry-pick`, `revert`, history-moving `reset`) while you are **on**
  a protected branch, and block any **push** whose resolved target is a protected
  branch. Everything on `develop` and feature branches is unrestricted.
- **`GIT_GUARD_BLOCK_ALL_PUSH=1`** — additionally block **every** push, regardless of
  target (useful for a strictly local-only workflow).

A local write is judged against the current branch because `git merge`, `git pull`,
`git rebase` (and a history-moving `reset --hard|--merge|--keep`) each mutate it exactly
like a commit. The protected-branch list is `GIT_GUARD_MAIN_BRANCHES` (default
`main master`).

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install git-guard@cc-goodies
```

Installing the plugin is the whole install — the hook is declared inline in the plugin
manifest, so it activates on install (restart or `/hooks` to load it the first time) and
stays active across plugin updates. There is no separate hook-install step and nothing is
written to `settings.json`. Run `/git-guard` any time to view, pause/resume, or change its
settings.

## Configure

Settings resolve **environment variable → `~/.claude/git-guard.conf` → built-in
default** (env wins). The conf file is a plain `KEY=VALUE` list and is read fresh on
every command, so changes take effect immediately — no restart.

| Key | Default | Meaning |
|-----|---------|---------|
| `GIT_GUARD_MAIN_BRANCHES` | `main master` | Space-separated protected branches |
| `GIT_GUARD_BLOCK_ALL_PUSH` | *(unset)* | Set to `1` to block **every** push, not just pushes to a protected branch |
| `GIT_GUARD_DISABLE` | *(unset)* | Set to `1` to pause the guard without uninstalling |

Example `~/.claude/git-guard.conf`:

```sh
GIT_GUARD_MAIN_BRANCHES="main master release"
GIT_GUARD_BLOCK_ALL_PUSH=1
```

The easiest way to edit it is the `/git-guard` command, which shows the current
state and writes the file for you.

## Pause / resume

To turn the guard off without uninstalling, **pause** it — set `GIT_GUARD_DISABLE=1` (via
`/git-guard`, or as a line in `~/.claude/git-guard.conf`): the hook no-ops but stays
installed. **Resume** by clearing it (remove the line or set `GIT_GUARD_DISABLE=0`).
`/git-guard` offers pause and resume as explicit choices.

## Uninstall

```text
/git-guard-uninstall
/plugin uninstall git-guard@cc-goodies
```

`/git-guard-uninstall` deletes the `~/.claude/git-guard.conf` it created (after confirmation); `/plugin uninstall` then removes the plugin and its hook. To turn the guard off **without** removing it, see [Pause / resume](#pause--resume) above.

## What it catches

Target branches are resolved properly, not by substring matching:

- `git push origin main`, `git push -u origin main`, `git push origin HEAD:main`,
  `git push origin HEAD:refs/heads/main`, the force shorthand `git push origin +main`,
  the quoted `git push origin "main"`, and `git push origin HEAD` (current branch)
  → all resolve to `main`.
- Common non-evasive wrappers are unwrapped to reach the real `git` —
  `timeout 60 git push …`, `nice git push …`, `sudo git push …`, `env … git push …`,
  plus `rtk proxy git push …` (and `rtk git push …`) — so the wrapped command is still
  judged. A flat skip, not a per-wrapper flag parser: a misparse just fails open.
- `git push --all` / `--mirror` → treated as touching protected branches.
- `git push origin :main` (delete remote `main`) → blocked.
- `git push -o <v>` / `--push-option <v>` / `--receive-pack <v>` / `--exec <v>` →
  the flag's value can't masquerade as the remote or refspec.
- `git commit` / `merge` / `pull` / `rebase` / `cherry-pick` / `revert` / `am`, and
  a history-moving `git reset --hard|--merge|--keep` → judged against the **current**
  branch (each mutates it like a commit).
- `git branch -f|-D|-M <protected>` (force-reset / delete / force-rename onto a
  protected branch) → blocked.
- `git -C <path> …` → the branch is resolved in `<path>`, not the cwd.
- Compound commands are split on `&&`, `||`, `;`, newlines, single pipes, background
  `&`, subshells `( )` and brace groups `{ }`, so `git add . && git push origin main`,
  `true | git push origin main` and `(git push origin main)` are all caught.
- `git push origin feature/main-menu` is **not** blocked (it isn't `main`), and
  `echo "git push origin main"` is **not** a git command, so it's ignored.

## Limitations

- **Branch is resolved from the session's working directory.** The guard reads the
  branch of the directory Claude is running in — not a `cd /other/repo &&` target
  inside the command. So a command that `cd`s into a *different* repo is judged
  against the session repo's branch, which can both over-block (harmless) and, if the
  session sits on an unprotected branch, miss a write to another repo's `main`. Use
  the `git -C /path …` form for another repo — that **is** resolved correctly. Working
  normally inside the repo is fully covered.
- **Deliberately hidden git is out of scope by design.** This guard stops the *plain
  accident* (`git push origin main`, a commit while on `main`), not an agent that is
  actively trying to evade it. A `git` verb buried in a `bash -c "…"` string,
  backtick/`$()` command substitution, a `sudo -u USER git …` identity switch, or a
  persistent `~/.gitconfig` alias will **not** be caught — and the guard does not try.
  Plan mode is the backstop for intent; this is a convenience guard, not a server-side
  branch protection. Pair it with real protections (GitHub branch rules) for anything
  that matters.
- **Requires `jq`** to parse the hook input. If `jq` is missing the guard prints a
  one-line warning and **allows** the command (it fails open rather than blocking
  every Bash call). `brew install jq` to enable it.

## Requirements

- `git`, `jq`, and `bash` — cross-platform (unlike the macOS-only cc-goodies plugins).

## License

MIT © Volodymyr Styran
