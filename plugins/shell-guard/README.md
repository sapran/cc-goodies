# shell-guard

A `PreToolUse` hook that **blocks a curated set of dangerous shell commands before
they run**. When Claude's Bash tool tries something that would wipe your home
directory, reformat a disk, pipe a download straight into a shell, truncate a file to
nothing, escalate with `sudo`, or halt the machine, the command is denied (exit 2) and
Claude is told why — instead of finding out afterwards.

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
shell`, `dd onto a device node`, `sudo — privilege escalation`).

shell-guard is designed to **cover — and improve on — a typical `permissions.deny`
shell list** in `~/.claude/settings.json`. That list matches command *strings* exactly,
so it misses re-ordered flags, extra spaces, or `$HOME` in place of `~`; shell-guard
normalises the flags and resolves the target, catching the obfuscated variants string
matching misses. It is a convenience guard, not a sandbox — keep real OS-level backups
and protections too. (Permission `deny` rules and this hook are independent layers; you
can run both, but shell-guard is meant to let you retire the shell half of your deny
list.)

## What it blocks

Each is matched after normalising flags/spacing, not by naïve substring match:

- **Recursive delete of a protected path** — `rm -rf` / `-fr` / `-r --force` /
  `--recursive --force` (any order) whose target is `/`, `/*`, `~`, `$HOME`, a
  top-level system dir (`/usr`, `/etc`, `/System`, `/Library`, …), or — only when the
  session's cwd **is** your home directory — a bare `*` / `.*` / `.`. Also any
  `rm --no-preserve-root`.
- **`dd` onto a device** — `dd … of=/dev/…`.
- **Filesystem create/wipe** — `mkfs`, `mkfs.*`, `wipefs`, `newfs`, `newfs_*`.
- **Destructive `diskutil`** — `eraseDisk`, `eraseVolume`, `reformat`, `zeroDisk`,
  `secureErase`, `partitionDisk`, `eraseall`, `apfs delete*`/`apfs erase*`.
- **Overwrite a raw disk device** — a `>` redirect, or `dd of=`, `cp`, or `tee`
  whose target is `/dev/disk*`, `/dev/rdisk*`, `/dev/sd*`, `/dev/hd*`, `/dev/nvme*`,
  `/dev/vd*` (but **not** `/dev/null`, `/dev/zero`, a tty…).
- **Recursive unlink without `rm`** — `find <protected path> … -delete`, or
  `find <protected path> … -exec` running a *mutating* command (rm/mv/chmod/shred/…);
  a read-only `-exec grep/cat/ls/…` over a system dir is allowed. Also `shred` of a
  raw disk device or a protected path.
- **Fork bomb** — a function that pipes and backgrounds a call to itself
  (`:(){ :|:& };:` and renamed variants).
- **Network download fed to an interpreter** — `curl`/`wget`/`fetch` reaching a
  shell or language runtime (`sh`/`bash`/`zsh`/`dash`/`ksh`/`pwsh`, `python`/`perl`/
  `ruby`/`node`/`php`/`deno`/`bun`/`Rscript`/`lua`/`tclsh`/`osascript`) through one or
  more pipe stages (incl. via `sudo`/`env`/`xargs`/a `VAR=…` prefix), process
  substitution (`bash <(curl …)`, `source <(curl …)`), or command substitution
  (`bash -c "$(curl …)"`).
- **Truncate a file to empty** — the `: > file` idiom and `truncate -s 0` /
  `--size=0` (but **not** a plain `> file` redirect, nor `: >> file` append).
- **`chmod 777`** — world-writable permissions (`chmod 777` / `0777`, recursive or not).
- **`eval`** — arbitrary code execution.
- **Privilege escalation** — `sudo`, `su`, `doas`, `runuser`, `pkexec`, `gosu`,
  `sudoedit`, `setpriv`, blocked by default (opt out with `SHELL_GUARD_ALLOW_SUDO=1`;
  see **Configure**). Also `find -exec`/`-ok` of a mutating command through a wrapper.
- **System halt/reboot** — `reboot`, `shutdown`, `halt`, `poweroff`, `init 0`/`init 6`.
- Anything in your `SHELL_GUARD_EXTRA_PATTERNS` (see **Configure**).

Compound commands are split on `&&`, `||`, `;`, newlines, and — for the per-command
checks — single pipes, background `&`, subshells `( )`, brace groups `{ }` and
backtick substitution, so `git pull && rm -rf /`, `true | rm -rf /`, `(rm -rf /)` and
`echo \`rm -rf /\`` are all caught. Common wrappers are unwrapped too — with their
options and option *values*, so `timeout -s KILL 5 rm -rf /` and `xargs -n 1 rm -rf /`
don't hide the command: `timeout`, `setsid`, `nice`/`chrt`/`ionice`/`taskset`,
`env`/`env -i`, `xargs`, `stdbuf`, and `bash -c "<script>"` (the `-c` string is
re-checked). Best-effort, not a sandbox — a target supplied at runtime via stdin
(`echo / | xargs rm -rf`), a two-step download-then-run, a hex/`$'\x..'`-encoded
command name, or variable indirection can still hide a command.

## What it deliberately allows

The block list is intentionally tight to avoid breaking normal work:

- `rm -rf ./build`, `rm -rf node_modules`, `rm -rf dist` — relative/project paths.
- `rm -rf /usr/local/lib/node_modules/foo` — a deep path under a system dir (only the
  bare top-level dir is protected).
- `rm -rf *` **outside** your home directory.
- `dd if=a.img of=out.img` — `dd` to a regular file.
- `curl … | jq`, `curl … | ssh host`, `curl … -o file` — downloads that don't feed a shell.
- `echo "rm -rf /"` — the dangerous text is an argument, not the command.
- `git init`, `terraform init`, `npm run reboot-staging` — the trigger word is a
  subcommand or substring, not the command being run.
- `> file`, `echo x > log`, `: >> append.log` — ordinary redirects and appends.
- `truncate -s 100M img`, `chmod 755 x`, `chmod +x x`, `chmod -R 755 ./app` — non-destructive forms.

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
| `SHELL_GUARD_ALLOW_SUDO` | *(unset)* | Set to `1` to permit privilege escalation — `sudo`/`su`/`doas`/`runuser` (blocked by default) |
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

- **Best-effort shell parsing.** Common wrappers, pipes, subshells, backticks and
  `bash -c` strings are handled, but a few classes are irreducible for a static
  text guard and still pass: a destructive target supplied at **runtime via stdin**
  (`echo / | xargs rm -rf`, `find / … | xargs rm`), a **two-step** download-then-run
  (`curl -o /tmp/x …; bash /tmp/x`), a **hex/`$'\x..'`-encoded** command name,
  `eval`/variable indirection, and a rare value-taking wrapper option outside the
  table (`exec -a NAME`, `/usr/bin/time -o FILE`). This is a convenience guard, not a
  sandbox — pair it with real backups and OS-level protections for anything that matters.
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
