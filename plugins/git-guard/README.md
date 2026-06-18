# git-guard

A `PreToolUse` hook that **blocks accidental writes to protected branches before
they run**. When Claude tries a `git commit`, `git merge`, or `git push` that the
active policy forbids, the command is denied (exit 2) and Claude is told why —
instead of finding out after `main` already moved.

It only ever gates **Claude's Bash tool**. You can still run any command yourself
in a terminal.

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

"Commit → main" also covers `git merge` while on a protected branch, since a merge
mutates the current branch exactly like a commit.

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

## What it catches

Target branches are resolved properly, not by substring matching:

- `git push origin main`, `git push -u origin main`, `git push origin HEAD:main`,
  `git push origin HEAD:refs/heads/main` → all resolve to `main`.
- `git push --all` / `--mirror` → treated as touching protected branches.
- `git push origin :main` (delete remote `main`) → blocked.
- `git commit` / `git merge` → judged against the **current** branch.
- `git -C <path> …` → the branch is resolved in `<path>`, not the cwd.
- Compound commands are split on `&&`, `||`, `;` and judged piece by piece, so
  `git add . && git push origin main` is caught.
- `git push origin feature/main-menu` is **not** blocked (it isn't `main`), and
  `echo "git push origin main"` is **not** a git command, so it's ignored.

## Limitations

- **Best-effort shell parsing.** Exotic quoting or aliases that hide a `git` verb can
  slip through — this is a convenience guard, not a server-side branch protection.
  Pair it with real protections (GitHub branch rules) for anything that matters.
- **`git pull` and `git rebase` are not guarded yet.** A `pull` on `main` does mutate
  it; that case is on the roadmap.
- **Requires `jq`** to parse the hook input. If `jq` is missing the guard prints a
  one-line warning and **allows** the command (it fails open rather than blocking
  every Bash call). `brew install jq` to enable it.

## Requirements

- `git`, `jq`, and `bash` — cross-platform (unlike the macOS-only cc-goodies plugins).

## License

MIT © Volodymyr Styran
