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
| **2. git-guard** | Parses the git verb + resolves the branch | Plugin PreToolUse hook | **open** (allows if `jq` missing) | commit/merge/pull/rebase/push onto protected branches | exotic quoting; non-git destructive ops |
| **3. shell-guard** | Normalizes flags + resolves the target | Plugin PreToolUse hook | **open** (allows if `jq` missing) | a curated dangerous-command set (covers a typical shell deny list) | anything outside that set; heavy obfuscation |
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

A `PreToolUse`/`Bash` hook that **parses the git command** — walking past prefixes
(`sudo`, `env`, var-assignments), reading global options (`-C`, `-c`, …), extracting the
verb, and resolving the branch — then blocks (exit 2) when the active policy forbids it.

- **Guarded verbs:** `commit`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`,
  `am`, and a history-moving `reset --hard|--merge|--keep` (judged against the
  **current** branch); `branch -f`, `update-ref`, `checkout/switch -B` (judged against
  the **named** branch); and `push` (judged against the resolved target refspec,
  including the `+force` shorthand and `HEAD`). Inline `-c alias.*=` is resolved.
- **Policies** (`GIT_GUARD_POLICY`, default `2`):

  | Policy | Push → main | Commit/pull/rebase → main | Push → develop | …→ develop |
  |:------:|:-----------:|:-------------------------:|:--------------:|:----------:|
  | **1** | ⛔ | ✅ | ✅ | ✅ |
  | **2** (default) | ⛔ | ⛔ | ✅ | ✅ |
  | **3** | ⛔ | ⛔ | ⛔ *(all pushes)* | ✅ |

- **Config:** env → `~/.claude/git-guard.conf` → default. Protected/dev branch lists and
  the policy are all configurable; `GIT_GUARD_DISABLE=1` pauses it.
- **Fails open** if `jq` is missing (prints one line, allows the command) — a guard that
  blocked every Bash call on a missing dependency would be worse than none.

Full detail and the override paths: [git-guard README](../plugins/git-guard/README.md).

---

### Layer 3 — shell-guard (dangerous commands)

A `PreToolUse`/`Bash` hook that hard-blocks (exit 2) a **curated set** of dangerous
commands. Unlike Layer 1 it normalizes flags/spacing and resolves the target, catching the
obfuscated variants the string list misses. It splits compound commands on `&&`, `||`, `;`,
newlines, single pipes, background `&`, subshells `( )` and brace groups `{ }`, and judges
each piece, so `git pull && rm -rf /`, `true | rm -rf /` and `(rm -rf /)` are all caught.

**Blocks:**

- recursive delete of a protected path — `rm -rf`/`-fr`/`-r --force`/`--recursive --force`
  (any order) targeting `/`, `/*`, `~`, `$HOME`, a top-level system dir (`/usr`, `/etc`,
  `/System`, …), or — only when the session cwd **is** `$HOME` — a bare `*`/`.*`/`.`; and
  any `rm --no-preserve-root`;
- `dd … of=/dev/…`; `mkfs`/`mkfs.*`/`wipefs`/`newfs`; destructive `diskutil`
  (`eraseDisk`, `reformat`, `zeroDisk`, …);
- redirect onto a raw disk device (`> /dev/disk*`, `/dev/rdisk*`, `/dev/sd*`, … — **not**
  `/dev/null`/`zero`/tty);
- fork bombs (a function that pipes and backgrounds a call to itself);
- a network download fed to an interpreter (`curl`/`wget`/`fetch` → `sh`/`bash`/`zsh`/
  `dash`/`ksh`/`python`/`perl`/`ruby`/`node`/`php`) through one or more pipe stages, an
  `env`/`VAR=…`/`sudo` prefix, process substitution (`bash <(curl …)`, `source <(curl …)`)
  or command substitution (`bash -c "$(curl …)"`); plus `find … -delete`, `shred`,
  `cp`/`tee` and `diskutil apfs delete*` against a raw disk or protected path;
- truncate a file to empty — the `: > file` idiom and `truncate -s 0`/`--size=0` (but not
  a plain `> file` redirect or `: >>` append);
- `chmod 777`/`0777` (world-writable); `eval` (arbitrary code execution);
- `sudo` — blocked by default (opt out with `SHELL_GUARD_ALLOW_SUDO=1`);
- system halt/reboot — `reboot`, `shutdown`, `halt`, `poweroff`, `init 0`/`init 6`.

**Deliberately allows** (so it doesn't break normal work): `rm -rf ./build`,
`rm -rf node_modules`, deep paths under a system dir (`/usr/local/lib/...`),
`rm -rf *` *outside* `$HOME`, `dd … of=file`, `curl … | jq`, `curl … | ssh host`,
`echo "rm -rf /"`.

- **Config:** env → `~/.claude/shell-guard.conf` → default. `SHELL_GUARD_DISABLE=1`
  pauses it; `SHELL_GUARD_ALLOW_SUDO=1` permits `sudo`; `SHELL_GUARD_EXTRA_PATTERNS` adds
  your own ERE block patterns.
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

- Stricter git: `/git-guard` → policy 3 (no pushing anywhere from a session).
- Extra shell patterns: `/shell-guard` → add to `SHELL_GUARD_EXTRA_PATTERNS`.
- Pause without uninstalling: `GIT_GUARD_DISABLE=1` / `SHELL_GUARD_DISABLE=1`.

To **override** a block for one command, run it yourself in a terminal — the guards only
ever gate Claude's Bash tool, never your own shell.

---

## Known gaps & non-goals

- **String-matched deny rules are bypassable** by obfuscation; that's why Layer 3 exists,
  and why neither replaces plan mode.
- **The hook layers fail open** when `jq` is missing — by design. Install `jq`.
- **shell-guard is curated, not exhaustive.** It targets a high-confidence catastrophic
  set and stays out of the way of ordinary work; it will not catch every destructive
  command. Add your own via `SHELL_GUARD_EXTRA_PATTERNS`.
- **Best-effort shell parsing.** Pipes, `&`, subshells and brace groups are now split,
  but a command hidden behind a wrapper (`timeout`, `xargs`, `bash -c "…"`), backtick
  substitution, `eval`, a persistent `~/.gitconfig` alias, or variable indirection can
  still hide an operation from the hook layers.
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
