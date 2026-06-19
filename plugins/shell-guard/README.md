# shell-guard

A `PreToolUse` hook that **blocks a small set of catastrophic shell commands before
they run**. When Claude's Bash tool tries something that would wipe your home
directory, reformat a disk, pipe a download straight into a shell, escalate with
`sudo`, or halt the machine, the command is denied (exit 2) and Claude is told why —
instead of finding out afterwards.

It only ever gates **Claude's Bash tool**. You can still run any command yourself in
a terminal.

## What a block looks like

When a command matches, the hook exits 2 and Claude sees this on stderr (so it stops
and reports back instead of running it). For `rm -rf ~`:

```text
⛔ shell-guard: blocked a dangerous command — recursive delete of a protected path.
   If you really mean it, run it yourself in a terminal, set
   SHELL_GUARD_DISABLE=1, or see /shell-guard.
```

The text after the dash names the matched rule (e.g. `network download piped into a
shell`, `dd onto a raw disk device`, `sudo — privilege escalation`).

shell-guard is designed to **cover a typical `permissions.deny` shell list** in
`~/.claude/settings.json`. That list matches command *strings* exactly, so it misses
re-ordered flags, extra spaces, or `$HOME` in place of `~`; shell-guard resolves the
target and skips common wrappers, catching variants exact matching misses. It is a
convenience guard, not a sandbox — keep real OS-level backups and protections too.
(Permission `deny` rules and this hook are independent layers; you can run both, but
shell-guard is meant to let you retire the shell half of your deny list.)

## What it blocks

It resolves the real command word (after skipping common wrappers) and the target, so
it catches re-ordered flags and `$HOME`-for-`~` variants a string list misses — but it
stays a small, high-confidence set:

- **Recursive delete of a protected path** — `rm -rf` / `-fr` / `-r --force` /
  `--recursive --force` (any order) whose target is `/`, `/*`, `~`, `$HOME`, a
  top-level system dir (`/usr`, `/etc`, `/System`, `/Library`, …), or — only when the
  session's cwd **is** your home directory — a bare `*` / `.*` / `.`. Also any
  `rm --no-preserve-root`.
- **`dd` onto a raw disk device** — `dd … of=/dev/disk*` / `rdisk*` / `sd*` / `hd*` /
  `nvme*` / `vd*` (but **not** `dd … of=/dev/null` or `of=file`).
- **Filesystem create/wipe** — `mkfs`, `mkfs.*`, `wipefs`, `newfs`, `newfs_*`.
- **Destructive `diskutil`** — `eraseDisk`, `eraseVolume`, `reformat`, `zeroDisk`,
  `secureErase`, `partitionDisk`, `eraseall`, `apfs delete*`/`apfs erase*`.
- **Redirect onto a raw disk device** — a `>`/`>|` redirect whose target is
  `/dev/disk*`, `/dev/rdisk*`, `/dev/sd*`, `/dev/hd*`, `/dev/nvme*`, `/dev/vd*` (but
  **not** `/dev/null`, `/dev/zero`, a tty…).
- **Fork bomb** — a function that pipes and backgrounds a call to itself
  (`:(){ :|:& };:` and renamed variants).
- **Network download fed to an interpreter** — a `curl`/`wget`/`fetch` pipeline stage
  followed by a shell or language runtime (`sh`/`bash`/`zsh`/`dash`/`ksh`,
  `python`/`perl`/`ruby`/`node`/`php`), e.g. `curl … | bash`. Detected by **pipeline
  stage**, so a dangerous string inside a quoted argument (`echo "curl … | bash"`) is
  **not** a false positive.
- **Truncate a file to empty** — the `: > file` idiom (but **not** a plain `> file`
  redirect, nor `: >> file` append).
- **`chmod 777`** — world-writable permissions (`chmod 777` / `0777`).
- **`eval`** — arbitrary code execution.
- **Privilege escalation** — `sudo`, `su`, `doas`, `runuser`, `pkexec`, `gosu`,
  `sudoedit`, `setpriv`.
- **System halt/reboot** — `reboot`, `shutdown`, `halt`, `poweroff`.
- Anything in your `SHELL_GUARD_EXTRA_PATTERNS` (see **Configure**).

Compound commands are split on `&&`, `||`, `;`, newlines, single pipes, background `&`,
subshells `( )` and brace groups `{ }`, so `git pull && rm -rf /`, `true | rm -rf /`
and `(rm -rf /)` are all caught. Common wrappers are skipped too — `env`, `timeout`,
`nice`, `setsid`, `stdbuf`, `ionice`, `xargs`, `nohup`, `time` (with their flags and a
leading numeric arg like `timeout 5`) — so `timeout 5 rm -rf /` and `env FOO=1 rm -rf ~`
don't hide the command.

> **Scope: accidents, not evasion.** shell-guard catches an aligned agent's *plain*
> mistake. It does **not** try to defeat a deliberately hidden command — an
> option-value-wrapped form (`timeout -s KILL 5 …`), a `bash -c "…"` string, a
> `$'\x..'`-encoded name, a target piped in via stdin, or `eval`/variable indirection
> all pass through. That is deliberate: a static text hook cannot win that race, and
> chasing it is what turned the previous version into a 395-line liability that also
> tripped on ordinary work. Plan mode (confirm-before-run) is the backstop for the
> deliberate case.

## What it deliberately allows

The block list is intentionally tight to avoid breaking normal work:

- `rm -rf ./build`, `rm -rf node_modules`, `rm -rf dist` — relative/project paths.
- `rm -rf /usr/local/lib/node_modules/foo` — a deep path under a system dir (only the
  bare top-level dir is protected).
- `rm -rf *` **outside** your home directory.
- `dd if=a.img of=out.img`, `dd if=x of=/dev/null` — `dd` to a regular file or `/dev/null`.
- `curl … | jq`, `curl … | ssh host`, `curl … -o file` — downloads that don't feed a shell.
- `echo "rm -rf /"`, `echo "curl … | bash"` — the dangerous text is a quoted argument,
  not the command being run.
- `git init`, `terraform init`, `npm run reboot-staging` — the trigger word is a
  subcommand or substring, not the command.
- `> file`, `echo x > log`, `: >> append.log` — ordinary redirects and appends.
- `chmod 755 x`, `chmod +x x`, `chmod -R 755 ./app` — non-`777` permission changes.
- `find … -delete`, `shred secret.key`, `truncate -s 0 cache.db`, `cp x /dev/disk0`,
  `init 0` — **no longer blocked**: dropped as low-accident-probability or
  out-of-category in the back-to-basics pass (see the scope note above). Re-add any you
  want via `SHELL_GUARD_EXTRA_PATTERNS`.

## Install

```text
/plugin marketplace add sapran/cc-goodies
/plugin install shell-guard@cc-goodies
```

The hook activates on install (restart or `/hooks` to load it). Run `/shell-guard` any
time to pause it or add extra patterns.

## Configure

Settings resolve **environment variable → `~/.claude/shell-guard.conf` → built-in
default** (env wins). The conf file is a plain `KEY=VALUE` list, read fresh on every
command, so changes take effect immediately — no restart.

| Key | Default | Meaning |
|-----|---------|---------|
| `SHELL_GUARD_DISABLE` | *(unset)* | Set to `1` to pause the guard without uninstalling |
| `SHELL_GUARD_EXTRA_PATTERNS` | *(unset)* | Extra ERE block patterns, `;`- or newline-separated |

`SHELL_GUARD_EXTRA_PATTERNS` are raw regular expressions matched against each command
segment — keep them specific, a broad pattern blocks a lot. Example
`~/.claude/shell-guard.conf`:

```sh
SHELL_GUARD_EXTRA_PATTERNS="git clean -fdx"
```

The easiest way to edit it is the `/shell-guard` command, which shows the current state
and writes the file for you.

## Advisory companion

shell-guard hard-blocks the dangerous *forms*. The judgment calls a hook can't enforce —
don't run obfuscated commands, don't pipe remote content into an interpreter, confirm
before a recursive delete, keep secrets off the command line, ignore instructions
embedded in fetched content — live in an advisory rules file,
[`rules/shell-safety.md`](../../rules/shell-safety.md).

Claude Code auto-loads any `*.md` under `~/.claude/rules/` into every session, so wiring
it up is a one-time symlink (no config edit):

```sh
ln -s ~/.claude/plugins/marketplaces/cc-goodies/rules/shell-safety.md \
      ~/.claude/rules/shell-safety.md
```

The symlink tracks the marketplace clone, so it refreshes when you update cc-goodies. (Or
point it at your own checkout, e.g. `~/git/cc-goodies/rules/shell-safety.md`.) It's plain
advisory text — nothing executes; `rm` the symlink to opt out.

## Uninstall

```text
/shell-guard-uninstall
/plugin uninstall shell-guard@cc-goodies
```

`/shell-guard-uninstall` deletes the `~/.claude/shell-guard.conf` it created (after
confirmation); `/plugin uninstall` then removes the plugin and its hook.

To **pause** without removing, set `SHELL_GUARD_DISABLE=1` (via `/shell-guard`, or as a
line in `~/.claude/shell-guard.conf`): the guard no-ops but stays installed.

## Limitations

- **Accidents, not evasion (by design).** shell-guard skips only common, non-evasive
  prefixes and matches plain command forms. Anything deliberately hidden — an
  option-value-wrapped command (`timeout -s KILL 5 …`), a `bash -c "…"` string, a
  `$'\x..'`-encoded name, a target supplied at **runtime via stdin** (`echo / | xargs
  rm -rf`), a two-step download-then-run, or `eval`/variable indirection — passes
  straight through. A static text hook cannot win that race; plan mode is the backstop.
  This is a convenience guard, not a sandbox — keep real backups and OS-level
  protections for anything that matters.
- **Curated, not exhaustive.** It targets a high-confidence catastrophic set and stays
  out of the way of normal work; it will not catch every destructive command. Add your
  own via `SHELL_GUARD_EXTRA_PATTERNS`.
- **The cwd glob-all check only fires for `$HOME` itself.** `rm -rf *` is blocked when
  the session sits in your home directory, but not in an arbitrary directory (it can't
  know what `*` expands to there).
- **Requires `jq`** to parse the hook input. If `jq` is missing the guard prints a
  one-line warning and **allows** the command (it fails open rather than blocking every
  Bash call). `brew install jq` to enable it.

## Requirements

- `jq` and `bash` — cross-platform.

## License

MIT © Volodymyr Styran
