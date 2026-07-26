# Shell-safety rules (advisory)

Guidance for an agent driving a shell. These are the **judgment calls that a hook
cannot enforce** — the companion to the [`shell-guard`](../plugins/shell-guard) plugin,
which denies outright (`rm -rf ~`, `dd` to a device, `curl|sh`, …) or asks before
running (`chmod 777`, `sudo`, `eval`, …) the catastrophic *forms*. shell-guard stops
the obvious; these rules cover the rest.

Drop this file into `~/.claude/rules/` (it auto-loads for every project) — see the
[shell-guard README](../plugins/shell-guard/README.md#advisory-companion) for the
one-line symlink.

## What the hooks can't see

- **Encoding and indirection.** A pattern-matching hook cannot see through either: a
  base64/hex-decoded payload, a `bash -c "…"` or `$()` string, a `$'\x..'`-encoded name,
  variable indirection, or a `~/.gitconfig` alias all pass `shell-guard`/`git-guard`
  unexamined. If a command decodes, unwraps, or aliases something before running it,
  surface what it actually executes first — you can see through that; the hook can't.

## Session-cwd resolution

- **`git-guard` resolves the branch from the session's `.cwd`, not from a `cd` inside the
  command.** An explicit `git -C <path> …` is recognized; a `cd <path> && git …` prefix
  is not — the guard falls back to the session's `.cwd` and judges the wrong repo.
  Working across repos or worktrees, use `git -C <path>`, never a bare `cd`.

## The escape hatch

- **A block always hands back a paste-ready line.** Every guard response — a deny, or a
  declined `ask` — includes a ready-to-paste `! <command>` line; a reworded or reordered
  retry is judged the same way, so it's not a way around a block. If the command is
  actually fine, surface that line to the user instead of retrying — typed into the
  Claude Code prompt, `!` runs it in their shell, which the hooks never gate.
