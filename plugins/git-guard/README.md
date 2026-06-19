# git-guard

A `PreToolUse` hook that **blocks accidental writes to protected branches before
they run**. When Claude tries a `git commit`, `git merge`, `git pull`, `git rebase`,
or `git push` that the active policy forbids, the command is denied (exit 2) and
Claude is told why — instead of finding out after `main` already moved.

It only ever gates **Claude's Bash tool**. You can still run any command yourself
in a terminal.

## What a block looks like

When the active policy forbids a command, the hook exits 2 and Claude sees this on
stderr (so it stops and tells you, instead of `main` moving). For `git push origin main`
under the default policy 2:

```text
⛔ git-guard (policy 2): blocked push to protected branch 'main'.
   Protected: main master. Use a feature branch or 'develop'.
   Override: run it yourself in a terminal, set GIT_GUARD_DISABLE=1, or see /git-guard.
```

## Policies

Pick how strict you want it with `GIT_GUARD_POLICY` (default **2**):

| Policy | Push → main | Commit → main | Push → develop | Commit → develop |
|:------:|:-----------:|:-------------:|:--------------:|:----------------:|
| **1** | ⛔ block | ✅ allow | ✅ allow | ✅ allow |
| **2** (default) | ⛔ block | ⛔ block | ✅ allow | ✅ allow |
| **3** | ⛔ block | ⛔ block | ⛔ block *(all pushes)* | ✅ allow |

- **Policy 1** — lenient: only stop pushes that land on `main`. Local commits to
  `main` are fine.
- **Policy 2** — default: keep `main` clean entirely — no commits *and* no pushes to
  it. `develop` (and feature branches) are unrestricted.
- **Policy 3** — local-only on `develop`: no pushing **anywhere**, and no commits to
  `main`. Commits to `develop` and feature branches are still allowed.

"Commit → main" also covers `git merge`, `git pull`, and `git rebase` while on a
protected branch, since each mutates the current branch exactly like a commit.

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install git-guard@cc-goodies
```

The hook activates on install (restart or `/hooks` to load it). Run `/git-guard` any
time to view or change the policy.

## Configure

Settings resolve **environment variable → `~/.claude/git-guard.conf` → built-in
default** (env wins). The conf file is a plain `KEY=VALUE` list and is read fresh on
every command, so changes take effect immediately — no restart.

| Key | Default | Meaning |
|-----|---------|---------|
| `GIT_GUARD_POLICY` | `2` | `1`, `2`, or `3` (see table above) |
| `GIT_GUARD_MAIN_BRANCHES` | `main master` | Space-separated protected branches |
| `GIT_GUARD_DEV_BRANCHES` | `develop` | Space-separated "dev" branches |
| `GIT_GUARD_DISABLE` | *(unset)* | Set to `1` to pause the guard without uninstalling |

Example `~/.claude/git-guard.conf`:

```sh
GIT_GUARD_POLICY=3
GIT_GUARD_MAIN_BRANCHES="main master release"
```

The easiest way to edit it is the `/git-guard` command, which shows the current
state and writes the file for you.

## Uninstall

```text
/git-guard-uninstall
/plugin uninstall git-guard@cc-goodies
```

`/git-guard-uninstall` deletes the `~/.claude/git-guard.conf` it created (after confirmation); `/plugin uninstall` then removes the plugin and its hook.

To **pause** without removing, set `GIT_GUARD_DISABLE=1` (via `/git-guard`, or as a
line in `~/.claude/git-guard.conf`): the guard no-ops but stays installed.

## What it catches

Target branches are resolved properly, not by substring matching:

- `git push origin main`, `git push -u origin main`, `git push origin HEAD:main`,
  `git push origin HEAD:refs/heads/main`, the force shorthand `git push origin +main`,
  the quoted `git push origin "main"`, and `git push origin HEAD` (current branch)
  → all resolve to `main`.
- Command wrappers are unwrapped, **including their options and option values** —
  `timeout -s KILL 60 git push …`, `nice -n 5 git push …`, `sudo -u alice git push …`,
  `env -i git push …`, plus `chrt` / `ionice` / `taskset` / `xargs` / `stdbuf` /
  `setsid` — so a wrapper flag's value is never mistaken for the command and the
  wrapped `git` is still judged.
- `git push --all` / `--mirror` → treated as touching protected branches.
- `git push origin :main` (delete remote `main`) → blocked.
- `git push -o <v>` / `--push-option <v>` / `--receive-pack <v>` / `--exec <v>` →
  the flag's value can't masquerade as the remote or refspec.
- `git commit` / `merge` / `pull` / `rebase` / `cherry-pick` / `revert` / `am`, and
  a history-moving `git reset --hard|--merge|--keep` → judged against the **current**
  branch (each mutates it like a commit).
- `git branch -f|-D|-M|-C <b>` and `git branch -m|-c` (rename/copy onto **or** off a
  protected branch), `git update-ref [-m <msg>] refs/heads/<b>`,
  `git checkout/switch -B <b>` → judged against the **named** branch `<b>` (direct
  ref rewrites).
- `git -c alias.x=push x …` → the inline alias is resolved to its real verb.
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
- **Best-effort shell parsing.** Common wrappers (`timeout`, `nice`, `sudo`, `env`,
  `xargs`, `setsid`, …) — with their options and option values — and inline
  `-c alias.*=` definitions are resolved, but a `git` verb hidden inside a
  `bash -c "…"`/`su -c "…"` string, backtick/`$()` command substitution, a **persistent**
  or **shell (`!cmd`)** alias from `~/.gitconfig`, or a rare value-taking wrapper option
  outside the table (`exec -a NAME`, `/usr/bin/time -o FILE`) can still slip through —
  this is a convenience guard, not a server-side branch protection. Pair it with real
  protections (GitHub branch rules) for anything that matters.
- **Requires `jq`** to parse the hook input. If `jq` is missing the guard prints a
  one-line warning and **allows** the command (it fails open rather than blocking
  every Bash call). `brew install jq` to enable it.

## Requirements

- `git`, `jq`, and `bash` — cross-platform (unlike the macOS-only cc-goodies plugins).

## License

MIT © Volodymyr Styran
