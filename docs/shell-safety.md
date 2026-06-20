# Shell-safety manual

How cc-goodies defends against **dangerous shell commands** when Claude Code drives the
Bash tool, and how the pieces fit together.

This is the companion manual to three of the plugins —
[`git-guard`](../plugins/git-guard), [`shell-guard`](../plugins/shell-guard), and
[`rtk-hook`](../plugins/rtk-hook) — plus the harness-level settings you configure
yourself. Each plugin's own README is the reference for its options; this document is
the **map**: the threat model, the layered defenses, what each layer catches and misses,
and how to set the whole thing up.

> **Scope and honesty up front.** These are *convenience guards*, not a sandbox. They
> stop accidents and obvious mistakes from an agent driving your shell. A determined
> bypass (obfuscation, `eval`, indirection) can get through any of them. Keep real
> protections too: backups, least-privilege accounts, and server-side branch rules.

---

## Threat model

When Claude runs Bash, a wrong or hallucinated command executes with **your** shell,
your environment, and your filesystem permissions. The realistic failure modes:

1. **Catastrophic filesystem / device ops** — `rm -rf ~`, `dd` onto a disk, `mkfs`, a
   fork bomb, piping a download straight into a shell.
2. **Accidental writes to protected git branches** — a commit, merge, pull, rebase, or
   push that moves `main`/`master` when it shouldn't.
3. **The long tail** — a novel destructive command none of the static rules anticipated.

The defenses below address each, with deliberate overlap (defense in depth) so a gap in
one layer is covered by another.

---

## The layers

| Layer | Mechanism | Enforced by | Fails | Catches | Misses |
|------|-----------|-------------|-------|---------|--------|
| **0. Plan mode** | Human confirmation before any tool runs | Harness (`defaultMode`) | closed (asks) | *everything*, incl. the long tail | nothing — but relies on you reading the command |
| **1. Deny list** | Exact string match on the command | Harness (`permissions.deny`) | closed (blocks) | a fixed, enumerated set | re-ordered flags, quoting, variables, anything not listed |
| **2. git-guard** | Parses the git verb + resolves the branch | Plugin PreToolUse hook | **open** (allows if `jq` missing) | commit/merge/pull/rebase/reset/push that lands on a protected branch (plain forms) | deliberately hidden git (`bash -c`, `$()`, `sudo -u USER`, gitconfig aliases); non-git ops |
| **3. shell-guard** | Resolves the target + skips common wrappers | Plugin PreToolUse hook | **open** (allows if `jq` missing) | a small catastrophic-command set (covers a typical shell deny list) | deliberately hidden forms (option-value wrapping, `bash -c`, encoding, stdin targets) |
| **4. Advisory rules** | Reasoning from `~/.claude/rules/*.md` | The agent (not enforced) | n/a | judgment calls: obfuscation, piping remote→shell, prompt injection, secrets on the CLI | anything the agent overlooks or is told to ignore |

> `rtk-hook` is **not** a security layer — it is a token optimizer that rewrites
> commands. It is listed in this repo's lineup but does not gate anything dangerous.

**Key property:** any single layer blocking is enough to stop the command. They are
independent — losing one (e.g. `jq` missing disables the two hook layers) still leaves
the deny list and plan mode.

---

### Layer 0 — Plan mode (`defaultMode`)

Set `"defaultMode": "plan"` (or `"acceptEdits"` selectively) in `~/.claude/settings.json`.
In plan mode nothing executes without you confirming, so it is the backstop for the
**long tail** — the destructive command no static rule predicted. It is the only layer
that covers "unknown unknowns," and the only one that depends on a human actually reading
what's proposed.

If you turn default mode off (full auto), Layers 1–3 become your entire net, and they
only cover the enumerated/curated sets. That is a deliberate trade-off — make it
knowingly.

---

### Layer 1 — The static deny list (`permissions.deny`)

A list of `Bash(...)` patterns in `~/.claude/settings.json` that the harness **hard-blocks
before the tool runs** (fail-closed; it cannot silently degrade). It is the cheapest and
most reliable layer for the exact strings it lists — and the dumbest: it matches the
command *text*, so it is blind to re-ordered flags, extra spaces, quotes, or variables.

A reasonable baseline:

```json
"permissions": {
  "defaultMode": "plan",
  "deny": [
    "Bash(rm -rf /)",
    "Bash(rm -rf ~*)",
    "Bash(rm -rf .*)",
    "Bash(sudo *)",
    "Bash(chmod 777 *)",
    "Bash(curl * | bash)",
    "Bash(wget * | bash)",
    "Bash(eval *)",
    "Bash(: > *)",
    "Bash(mkfs*)",
    "Bash(dd if=*)",
    "Bash(reboot*)",
    "Bash(shutdown*)"
  ]
}
```

**Why it is not enough on its own:** `Bash(rm -rf /)` does not stop `rm -fr /`,
`rm -r --force /`, or `rm -rf $HOME`. That gap is exactly what **shell-guard** (Layer 3)
closes by normalizing the flags and resolving the target instead of matching a string.

> **You can retire the shell half of this list once shell-guard is installed.**
> shell-guard (Layer 3) is designed to cover every pattern in the baseline above —
> `rm -rf`, `sudo`, `chmod 777`, `curl|sh`, `wget|sh`, `eval`, `: >`, `mkfs`, `dd`,
> `reboot`, `shutdown` — and more, with flag/spacing normalization the deny list can't
> do. Keep `permissions.deny` only for non-shell rules or as a belt-and-suspenders second
> layer; the two are independent and a deny match still wins.

---

### Layer 2 — git-guard (protected branches)

A `PreToolUse`/`Bash` hook that **parses the git command** — walking past common prefixes
(`sudo`, `env`, var-assignments, `rtk proxy`), reading global options (`-C`, …),
extracting the verb, and resolving the branch — then blocks (exit 2) when the action would
land on a protected branch.

- **Guarded verbs:** `commit`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `am`,
  and a history-moving `reset --hard|--merge|--keep` (judged against the **current**
  branch); `branch -D|-f|-M` (judged against the **named** branch); and `push` (judged
  against the resolved target refspec, including the `+force` shorthand, `HEAD`, and a
  `:branch` delete).
- **Behaviour:** by default, block a local write while on a protected branch and any push
  whose target is protected; `GIT_GUARD_BLOCK_ALL_PUSH=1` additionally blocks **every**
  push (for a strictly local-only workflow). The protected-branch list
  `GIT_GUARD_MAIN_BRANCHES` (default `main master`) is configurable.
- **Config:** env → `~/.claude/git-guard.conf` → default; `GIT_GUARD_DISABLE=1` pauses it.
- **Fails open** if `jq` is missing (prints one line, allows the command) — a guard that
  blocked every Bash call on a missing dependency would be worse than none.

Full detail and the override paths: [git-guard README](../plugins/git-guard/README.md).

---

### Layer 3 — shell-guard (dangerous commands)

A `PreToolUse`/`Bash` hook that hard-blocks (exit 2) a **small catastrophic set** of
commands. Unlike Layer 1 it resolves the target and skips common wrappers, catching
re-ordered-flag variants the string list misses. It splits compound commands on `&&`, `||`, `;`,
newlines, single pipes, background `&`, subshells `( )` and brace groups `{ }`, and judges
each piece, so `git pull && rm -rf /`, `true | rm -rf /` and `(rm -rf /)` are all caught.

**Blocks:**

- recursive delete of a protected path — `rm -rf`/`-fr`/`-r --force`/`--recursive --force`
  (any order) targeting `/`, `/*`, `~`, `$HOME`, a top-level system dir (`/usr`, `/etc`,
  `/System`, …), or — only when the session cwd **is** `$HOME` — a bare `*`/`.*`/`.`; and
  any `rm --no-preserve-root`;
- `dd … of=/dev/disk*` (a raw disk device, **not** `/dev/null`); `mkfs`/`mkfs.*`/`wipefs`/
  `newfs`; destructive `diskutil` (`eraseDisk`, `reformat`, `zeroDisk`, …);
- a `>` redirect onto a raw disk device (`/dev/disk*`, `/dev/rdisk*`, `/dev/sd*`, … —
  **not** `/dev/null`/`zero`/tty);
- fork bombs (a function that pipes and backgrounds a call to itself);
- a network download fed to an interpreter — a `curl`/`wget`/`fetch` pipeline stage
  followed by `sh`/`bash`/`zsh`/`dash`/`ksh`/`python`/`perl`/`ruby`/`node`/`php`, e.g.
  `curl … | bash` (matched by pipeline stage, so a quoted `echo "curl … | bash"` is not a
  false positive);
- the `: > file` truncate-to-empty idiom (but not a plain `> file` redirect or `: >>`
  append);
- `chmod 777`/`0777` (world-writable); `eval` (arbitrary code execution);
- privilege escalation — `sudo`/`su`/`doas`/`runuser`/`pkexec`/…;
- system halt/reboot — `reboot`, `shutdown`, `halt`, `poweroff`.

**Deliberately allows** (so it doesn't break normal work): `rm -rf ./build`,
`rm -rf node_modules`, deep paths under a system dir (`/usr/local/lib/...`),
`rm -rf *` *outside* `$HOME`, `dd … of=file`, `dd … of=/dev/null`, `curl … | jq`,
`curl … | ssh host`, `echo "rm -rf /"`, and the dropped arms `find … -delete`, `shred`,
`truncate -s 0`, `cp … /dev/disk*`, `init 0`.

- **Config:** env → `~/.claude/shell-guard.conf` → default. `SHELL_GUARD_DISABLE=1`
  pauses it; `SHELL_GUARD_EXTRA_PATTERNS` adds your own ERE block patterns.
- **Fails open** if `jq` is missing.

Full list, allow-cases, and limitations: [shell-guard README](../plugins/shell-guard/README.md).

---

## Recommended setup

```text
/plugin marketplace add sapran/cc-goodies
/plugin install git-guard@cc-goodies
/plugin install shell-guard@cc-goodies
```

Then symlink the advisory companion so it auto-loads in every session (Layer 4 — the
judgment calls the hooks can't enforce):

```sh
ln -s ~/.claude/plugins/marketplaces/cc-goodies/rules/shell-safety.md \
      ~/.claude/rules/shell-safety.md
```

Keep `"defaultMode": "plan"` in `~/.claude/settings.json`. Once shell-guard is installed
you can **retire the shell half of `permissions.deny`** (it covers that ground); keep the
deny list only for non-shell rules or as a belt-and-suspenders second layer. Both hook
plugins need `jq` (`brew install jq`) — without it they fail open and you're back to plan
mode + the deny list.

Tune to taste:

- Stricter git: `/git-guard` → set `GIT_GUARD_BLOCK_ALL_PUSH=1` (no pushing anywhere from a session).
- Extra shell patterns: `/shell-guard` → add to `SHELL_GUARD_EXTRA_PATTERNS`.
- Pause without uninstalling: `GIT_GUARD_DISABLE=1` / `SHELL_GUARD_DISABLE=1`.

To **override** a block for one command, run it yourself — the guards only ever gate
Claude's Bash tool, never your own shell. Every block hands the command back as a
ready-to-paste `!`-prefixed line; typed into the Claude Code prompt, `!` runs it in your
shell, bypassing the hook. shell-guard fronts that line with an irreversibility warning,
since the commands it blocks are catastrophic by design.

---

## Known gaps & non-goals

- **String-matched deny rules are bypassable** by obfuscation; that's why Layer 3 exists,
  and why neither replaces plan mode.
- **The hook layers fail open** when `jq` is missing — by design. Install `jq`.
- **shell-guard is curated, not exhaustive.** It targets a high-confidence catastrophic
  set and stays out of the way of ordinary work; it will not catch every destructive
  command. Add your own via `SHELL_GUARD_EXTRA_PATTERNS`.
- **Accidents, not evasion — by design.** The hooks split compound commands and skip
  common, non-evasive wrappers, but they match *plain* command forms only. Anything
  deliberately hidden — an option-value-wrapped command (`timeout -s KILL 5 …`), a
  `bash -c "…"`/`$()` string, a `$'\x..'`-encoded name, a target piped in via **stdin**,
  a two-step download-then-run, `eval`/variable indirection, or a `~/.gitconfig` alias —
  passes through. A static text hook cannot win that race; chasing it is what bloated the
  previous versions. Layer 0 (plan mode) is the backstop.
- **`rm -rf *` is only caught in `$HOME`.** Elsewhere the guard can't know what `*`
  expands to, so it allows it (blocking every `rm -rf *` would break normal build work).
- **Not a sandbox, not server-side.** Pair with backups and GitHub/GitLab branch
  protection for anything that matters.

---

## Verifying it works

There is no test framework — the guards are verified by piping synthetic tool-call JSON
to the hook scripts and asserting exit codes (`0` = allow, `2` = block), in real temp git
repos where branch state matters. See [CLAUDE.md](../CLAUDE.md#testing) and the
[hook input contract](../CLAUDE.md#hook-authoring--the-input-contract-important).

Quick manual smoke after install (`/hooks` reload first):

```text
git status            # allowed
rm -rf ./tmp          # allowed (relative path)
rm -rf ~              # blocked by shell-guard
git rebase main       # blocked by git-guard while on main
```

---

## See also

- [git-guard](../plugins/git-guard/README.md) — protected-branch guard
- [shell-guard](../plugins/shell-guard/README.md) — dangerous-command guard
- [rules/shell-safety.md](../rules/shell-safety.md) — the advisory companion (symlink into `~/.claude/rules/`)
- [rtk-hook](../plugins/rtk-hook/README.md) — token optimizer (not a security control)
- [CLAUDE.md](../CLAUDE.md) — development conventions and the hook input contract
- [CONTRIBUTING.md](../CONTRIBUTING.md) — the install ⇄ uninstall rule
