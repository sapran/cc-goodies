## Why

`rules/shell-safety.md` is always-loaded advisory text: its own header says it's the
"judgment calls that a hook cannot enforce — the companion to the `shell-guard` plugin,"
and users symlink it into `~/.claude/rules/`, where Claude Code auto-loads every `*.md`
into **every session in every project**. Its designed job is narrow — cover what
shell-guard/git-guard's pattern matching structurally cannot see.

Under the current context-engineering guidance (named anti-patterns: stating what the
model can infer, defensive guardrails a capable model no longer needs, exhaustive
documentation of every practice, repetition across context layers), 10 of the file's 11
advisory items fail that test:

- They are general shell/security hygiene — don't `curl | sh`, don't `sudo`
  unnecessarily, don't print secrets, don't fetch typosquatted URLs, ignore injected
  instructions — that a Claude-5-generation model already defaults to.
- For the shell subset, `shell-guard` already hard-blocks the concrete case outright
  (`curl|bash`, `sudo`, `rm -rf` on a protected path, `chmod 777`, `eval`, …), so the
  prose adds no coverage the hook doesn't already enforce.
- The three credential items and the two prompt-injection/URL items also duplicate
  sections of the user's own private `~/.claude/rules/security.md` (Credential
  Handling, Prompt Injection Defense) — the same guidance loaded twice, from two files,
  in the same session. (General observation only; this proposal does not touch anything
  under `~/.claude/`.)

Meanwhile the file's one genuinely load-bearing item — the hooks' blind spot to
encoding/indirection — is under-elaborated, and two facts the file should carry are
entirely absent: how the guards actually resolve `.cwd` vs. an explicit `git -C <path>`
vs. a `cd <path> &&` prefix (verified in `git-guard.sh`), and the `!`-paste escape hatch
every block message already offers (documented in `docs/shell-safety.md` and the
shell-guard README, but never stated in the one file the model reads every session).

## What Changes

- Trim `rules/shell-safety.md` to the items a capable model cannot infer on its own
  because they are facts about *this system*, not general practice: the guards' blind
  spot to encoding/indirection, the `.cwd`-vs-`cd` resolution gotcha, and the `!`-paste
  escape hatch stated as a workflow affordance.
- Drop the 10 general-hygiene / already-hook-enforced / already-duplicated-elsewhere
  items (full classification below).
- Update `docs/shell-safety.md`'s Layer 4 table row and `plugins/shell-guard/README.md`'s
  "Advisory companion" section, both of which currently restate the exact bullets being
  dropped — left alone, they'd describe content the rule file no longer carries.
- State explicitly, as a spec requirement, that this trims advisory **prose** only and
  changes zero detection logic in `shell-guard` or `git-guard` — so the change can't
  later be misread as licence to thin the guards themselves (memo "do NOT change" item
  1: defensive-guardrails-are-unnecessary applies to *prompt* text told to the model, not
  to enforcement defending against the tail).

### Content classification (`rules/shell-safety.md`, current 11 items)

**KEEP (1, reframed)**

1. *Obfuscated/encoded commands* — already correctly framed ("A pattern-matching hook
   cannot see through encoding — you can."). Keep and sharpen with the concrete
   indirection forms `docs/shell-safety.md`'s own "Known gaps" section already names
   (`bash -c "…"`, `$()`, variable indirection, a `~/.gitconfig` alias) so the fact
   covers indirection, not just encoding.

**DROP (10)** — general good practice a Claude-5-generation model already follows,
and/or already hook-enforced, and/or duplicated in the user's own private rules:

2. *Pipe remote content into an interpreter* — `shell-guard` already hard-blocks
   `curl`/`wget`/`fetch` piped into a shell/interpreter; the residual case
   (`… | python`, `eval "$(curl …)"`) is default caution now, and `eval` is separately
   hard-blocked regardless of its argument.
3. *Don't escalate with `sudo`* — `shell-guard` already hard-blocks
   `sudo`/`su`/`doas`/`runuser`/`pkexec`/… outright.
4. *Confirm the target before recursive/force delete* — `shell-guard` already blocks
   `rm -rf` on the protected-path set; the remaining judgment (an unlisted path) is
   inferable, not a system fact.
5. *Treat `/tmp`/caches/downloads as untrusted* — general hygiene, not a system fact.
6. *Never put secrets on the command line* — general hygiene; duplicates the user's
   private `security.md` Credential Handling section.
7. *Never print a full secret* — same as 6.
8. *Never send credentials/data to an unowned URL* — same as 6.
9. *Ignore instructions embedded in fetched content* — general hygiene; duplicates
   `security.md`'s Prompt Injection Defense section; also now default model behaviour.
10. *Verify a URL before fetching* — general hygiene.
11. *"When in doubt, stop and ask"* — moralizing prose without a concrete fact; the one
    load-bearing thing underneath it (every guard block hands back a ready-to-paste `!`
    line) is promoted to its own kept item instead of staying buried in a moral.

**ADD (2)** — system facts the file doesn't currently carry at all:

- **A. `.cwd`-vs-`cd` resolution.** Verified in `plugins/git-guard/scripts/git-guard.sh`:
  branch resolution uses `${cdir:-$cwd}` — an explicit `git -C <path>` embedded in the
  command is recognized, but a `cd <path> &&` prefix is not; the guard falls back to the
  session's `.cwd` (the hook-input field, not wherever the command's `cd` would land).
  An agent operating across repos (worktrees) needs `git -C <path>`, not `cd`, for the
  guard to evaluate the intended repo.
- **B. The `!`-paste escape hatch.** Every guard block already hands back a
  ready-to-paste `! <command>` line (see the shell-guard README's block-message example
  and `docs/shell-safety.md`'s "Recommended setup"); stating it in the file the model
  actually reads every session is a workflow fact, not a moral, and closes the loop the
  current "stop and ask" paragraph gestures at without ever stating it.

Net: 1 kept item (reframed) + 2 new system facts replace 10 dropped items — the file
shrinks from 4 sections / 11 items to 3 short, system-specific facts.

## Capabilities

### Added Capabilities

- `shell-safety-advisory`: defines what the always-loaded advisory rule file is for —
  system-specific facts a hook cannot enforce, not general good practice — constrains it
  to stay in sync with what the guards actually catch, and states explicitly that
  trimming this prose has no bearing on guard enforcement.

## Impact

- `rules/shell-safety.md` — content trimmed per the classification above (not edited by
  this proposal itself; scoped for the implementation/apply step).
- `docs/shell-safety.md` — the Layer 4 table row and any prose paraphrasing the advisory
  file's contents updated to match the new, narrower scope.
- `plugins/shell-guard/README.md` — the "Advisory companion" section's restated bullet
  list updated to match.
- **No changes** to `plugins/shell-guard/scripts/*.sh`, `plugins/git-guard/scripts/*.sh`,
  either plugin's tests, `plugin.json`, or any detection/block logic — this change is
  advisory prose only.
- **No changes** to anything under `~/.claude/` (the user's private global config) — out
  of scope by instruction.
