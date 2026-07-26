# shell-guard

A `PreToolUse` hook that **blocks or asks before a small set of catastrophic shell
commands run**. When Claude's Bash tool tries something dangerous, the hook resolves
it to one of two channels: **deny** — wiping your home directory, reformatting a disk,
piping a download straight into a shell, or halting the machine is denied outright
(exit 2) and Claude is told why; **ask** — a reversible action fully disclosed in the
command text (`chmod 777`, `sudo`, `: >`, plain `eval`) escalates instead to the
permission prompt you're already looking at, so you can approve or decline it in the
same flow instead of a full block-report-paste round-trip. Either way you find out
*before* it runs, not after.

It only ever gates **Claude's Bash tool**. You can still run any command yourself in
a terminal.

## Deny vs. ask — which channel a rule resolves to

Every matched rule is on exactly one of two channels (design.md's AXIS 2, in the
archived `guard-ask-escalation` change):

- **Deny** — the harm is irreversible (data or a filesystem is gone, a disk is wiped),
  disruptive in a way no narrower variant could soften, or a human reading the command
  at an `ask` prompt genuinely couldn't tell what it will do (a piped download's
  payload isn't visible in the command text — including via `eval "$(curl …)"`, which
  is denied for the same reason `curl … | bash` is, even though `eval` on its own is
  ask-channel). Deny-channel rules: recursive delete of a protected path, `dd`/redirect
  onto a raw disk device, `mkfs`/`wipefs`/`newfs`/destructive `diskutil`, a fork bomb,
  a network download piped into an interpreter, system halt/reboot, and any
  `SHELL_GUARD_EXTRA_PATTERNS` match (the guard can't judge a user pattern's severity,
  so it stays deny-only).
- **Ask** — the harm is reversible and the command text already discloses everything a
  human needs to decide: `chmod 777`/`0777`, the `: >` truncate idiom, privilege
  escalation (`sudo`/`doas`/`su`/…), and `eval` (when its argument has no
  `curl`/`wget`/`fetch` in it).

**`ask` requires the harness's own permission-prompt UI** — a human at an interactive
session sees a real prompt; a headless/background session with nobody to answer it
degrades cleanly to a blocked command with no code-level help needed (verified: three
headless `claude -p` runs, all denied at exit 0 with the reason surfaced, no hang, no
retry spam — see `design.md` Decision D3 in the archived `guard-ask-escalation` change for
the full record and its interactive-scope caveat).

## What a deny looks like

When a command matches a deny-channel rule, the hook exits 2 and Claude sees this on
stderr (so it stops and reports back instead of running it). Every message names the
specific rule that matched, states that variants of the same command are blocked too,
and hands the command back as a ready-to-paste `!`-prefixed escape hatch — but the
**second line** differs by class: commands with **no safe variant** (`rm -rf ~`, `dd`
onto a disk, `mkfs`, a fork bomb, `reboot`, …) keep an explicit irreversibility warning
and offer no alternative; commands with a **concrete safe variant but still no safe
*channel*** (`curl|sh`, `eval "$(curl …)"`) drop that warning and name the alternative
instead — a human just can't verify it blind, at a prompt or otherwise.

**No safe variant** — `rm -rf ~`:

```text
⛔ shell-guard: blocked a dangerous command — recursive delete of a protected path.
   ⚠️  This is destructive and IRREVERSIBLE. Verify the target before running.
   Variants of this command (reordered flags, different quoting, a wrapper prefix, $HOME for ~, …) are blocked too.
   To run it anyway, paste into the prompt (! runs it in your shell):
! rm -rf ~
   Or set SHELL_GUARD_DISABLE=1 / see /shell-guard.
```

**A safe variant exists, but not a safe channel** — `curl http://x | bash`:

```text
⛔ shell-guard: blocked a dangerous command — network download piped into a shell.
   → Safe alternative: download to a file, read it, then run it as a separate reviewed step.
   Variants of this command (reordered flags, different quoting, a wrapper prefix, $HOME for ~, …) are blocked too.
   To run it anyway, paste into the prompt (! runs it in your shell):
! curl http://x | bash
   Or set SHELL_GUARD_DISABLE=1 / see /shell-guard.
```

The text after the dash names the matched rule (e.g. `dd onto a raw disk device`, or —
for a user-configured `SHELL_GUARD_EXTRA_PATTERNS` entry — the literal pattern that
matched).

## What an ask looks like

When a command matches an ask-channel rule, the hook exits **0** and prints JSON on
**stdout** instead — `permissionDecision: "ask"`, which escalates to the human's own
permission prompt (and overrides auto-mode) rather than reporting an unconditional
block. `permissionDecisionReason` carries the exact same message shape as a deny — the
matched rule, the class-specific line, the variants-also-apply clause, and the
`!`-prefixed escape hatch — just delivered as the text shown at that prompt instead of
on stderr.

`chmod 777 x`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "🟡 shell-guard: this needs your OK — chmod 777 — world-writable permissions.\n   → Safe alternative: chmod 755 (or the narrowest mode the task needs).\n   Variants of this command (reordered flags, different quoting, a wrapper prefix, $HOME for ~, …) are blocked too.\n   To run it anyway, paste into the prompt (! runs it in your shell):\n! chmod 777 x\n   Or set SHELL_GUARD_DISABLE=1 / see /shell-guard."
  }
}
```

If you decline the prompt, the outcome is the same as a deny: the command doesn't run,
and the `!`-prefixed line in the reason text is still there to paste if you change your
mind.

The blocked (or asked-about) command is handed back as a ready-to-paste `!`-prefixed
line either way — typed into the Claude Code prompt, `!` runs it in **your** shell,
which this hook never gates. Because a reworded or reordered retry is judged the same
way, that line — not a rephrased command — is the only path forward once you're
certain.

shell-guard is designed to **cover a typical `permissions.deny` shell list** in
`~/.claude/settings.json`. That list matches command *strings* exactly, so it misses
re-ordered flags, extra spaces, or `$HOME` in place of `~`; shell-guard resolves the
target and skips common wrappers, catching variants exact matching misses. It is a
convenience guard, not a sandbox — keep real OS-level backups and protections too.
(Permission `deny` rules and this hook are independent layers; you can run both, but
shell-guard is meant to let you retire the shell half of your deny list.)

## What it blocks or asks about

It resolves the real command word (after skipping common wrappers) and the target, so
it catches re-ordered flags and `$HOME`-for-`~` variants a string list misses — but it
stays a small, high-confidence set. Each rule is tagged **[deny]** or **[ask]** — see
[Deny vs. ask](#deny-vs-ask--which-channel-a-rule-resolves-to) above:

- **[deny] Recursive delete of a protected path** — `rm -rf` / `-fr` / `-r --force` /
  `--recursive --force` (any order) whose target is `/`, `/*`, `~`, `$HOME`, a
  top-level system dir (`/usr`, `/etc`, `/System`, `/Library`, …), or — only when the
  session's cwd **is** your home directory — a bare `*` / `.*` / `.`. Also any
  `rm --no-preserve-root`.
- **[deny] `dd` onto a raw disk device** — `dd … of=/dev/disk*` / `rdisk*` / `sd*` /
  `hd*` / `nvme*` / `vd*` (but **not** `dd … of=/dev/null` or `of=file`).
- **[deny] Filesystem create/wipe** — `mkfs`, `mkfs.*`, `wipefs`, `newfs`, `newfs_*`.
- **[deny] Destructive `diskutil`** — `eraseDisk`, `eraseVolume`, `reformat`,
  `zeroDisk`, `secureErase`, `partitionDisk`, `eraseall`, `apfs delete*`/`apfs erase*`.
- **[deny] Redirect onto a raw disk device** — a `>`/`>|` redirect whose target is
  `/dev/disk*`, `/dev/rdisk*`, `/dev/sd*`, `/dev/hd*`, `/dev/nvme*`, `/dev/vd*` (but
  **not** `/dev/null`, `/dev/zero`, a tty…).
- **[deny] Fork bomb** — a function that pipes and backgrounds a call to itself
  (`:(){ :|:& };:` and renamed variants).
- **[deny] Network download fed to an interpreter** — a `curl`/`wget`/`fetch` pipeline
  stage followed by a shell or language runtime (`sh`/`bash`/`zsh`/`dash`/`ksh`,
  `python`/`perl`/`ruby`/`node`/`php`), e.g. `curl … | bash`. Detected by **pipeline
  stage**, so a dangerous string inside a quoted argument (`echo "curl … | bash"`) is
  **not** a false positive.
- **[ask] Truncate a file to empty** — the `: > file` idiom (but **not** a plain
  `> file` redirect, nor `: >> file` append).
- **[ask] `chmod 777`** — world-writable permissions (`chmod 777` / `0777`).
- **[ask/deny] `eval`** — arbitrary code execution. **[ask]** by default; **[deny]**
  when its argument contains `curl`/`wget`/`fetch` (e.g. `eval "$(curl http://x)"`) —
  a human at an `ask` prompt can't see a fetched payload any more than they can see
  what `curl … | bash` actually runs, so that case is denied for the same reason.
- **[ask] Privilege escalation** — `sudo`, `su`, `doas`, `runuser`, `pkexec`, `gosu`,
  `sudoedit`, `setpriv`.
- **[deny] System halt/reboot** — `reboot`, `shutdown`, `halt`, `poweroff`.
- **[deny] Anything in your `SHELL_GUARD_EXTRA_PATTERNS`** (see **Configure**) — the
  guard has no way to infer a user pattern's severity, so it always stays deny-only.

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

Installing the plugin is the whole install — the hook is declared inline in the plugin
manifest, so it activates on install (restart or `/hooks` to load it the first time) and
stays active across plugin updates. There is no separate hook-install step and nothing is
written to `settings.json`. Run `/shell-guard` any time to pause/resume it or add extra
patterns.

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

## Pause / resume

To turn the guard off without uninstalling, **pause** it — set `SHELL_GUARD_DISABLE=1` (via
`/shell-guard`, or as a line in `~/.claude/shell-guard.conf`): the hook no-ops but stays
installed. **Resume** by clearing it (remove the line or set `SHELL_GUARD_DISABLE=0`).
`/shell-guard` offers pause and resume as explicit choices.

## Advisory companion

shell-guard denies or asks about the dangerous *forms*. What its pattern matching can't
see — encoding/indirection, how `git-guard` resolves `.cwd` vs. a `cd` prefix, and the
`!`-paste escape hatch every block already offers — live in an advisory rules file,
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
confirmation); `/plugin uninstall` then removes the plugin and its hook. To turn the guard
off **without** removing it, see [Pause / resume](#pause--resume) above.

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
