# Contributing to cc-goodies

Thanks for adding to the marketplace. Plugins here are small, **independent, and opt-in**.
See [CLAUDE.md](CLAUDE.md) for the full development conventions; this file is the short
checklist contributors must satisfy.

## The install ⇄ uninstall rule

**Every feature ships a documented, symmetric install and uninstall path.** This is the one
hard rule — a pull request that adds an install or setup step without its documented inverse
is incomplete.

Checklist for a new or changed plugin:

- [ ] The plugin README has an **Install** section and an **Uninstall** section.
- [ ] The root `README.md` mirrors both (Install and Uninstall).
- [ ] Each install verb you ship has its documented inverse: `marketplace add` ⇄ `marketplace
      remove`, `/plugin install` ⇄ `/plugin uninstall`, and — only if the plugin has one —
      `/<name>-install` ⇄ `/<name>-uninstall`. Inline hooks self-activate on `/plugin install`,
      so a `/<name>-install` is the exception (durable-state setup like `statusline`), not the rule.
- [ ] If install writes **durable** state outside the plugin directory
      (`~/.claude/settings.json`, `~/.claude/<plugin>.conf`, files under `$HOME`), there is a
      dedicated `/<name>-uninstall` command that:
  - reverts exactly what install added, and nothing else;
  - is **ownership-guarded** — refuses to remove or overwrite state the user set up themselves;
  - backs up shared config before editing and verifies it still parses.
- [ ] Self-contained plugins (pure hooks/commands, no external writes) rely on
      `/plugin uninstall` — and the README says so.
- [ ] Ephemeral `$TMPDIR` caches are fine to leave (they self-clear); don't write durable
      state you won't clean up.

Reference implementations to copy from:

- **`git-guard`**, **`shell-guard`** and **`rtk-hook`** — a hook plus a `~/.claude/<plugin>.conf`
  config file and a `/<name>` control command (pause/resume etc.), with a `/<name>-uninstall`
  that removes only that conf (after backup + confirm) — and **no** `/<name>-install`. `rtk-hook`
  additionally edits `~/.claude/settings.json` with `jq` (its `/rtk-hook` offers to remove a
  hand-wired duplicate; `/rtk-hook-uninstall` offers to restore it), backing up, verifying
  `jq empty`, and touching only its own entry.
- **`statusline`** — a `/<name>-install` / `/<name>-uninstall` pair that edits
  `~/.claude/settings.json` with `jq` (it can't set the `statusLine` key declaratively): it backs
  up, merges/removes only its own key, verifies the result still parses (`jq empty`), and refuses
  to touch anything you didn't install.
- **`voice-notify`** — a self-contained plugin (pure hooks, no external writes) that just
  relies on `/plugin uninstall`.

## Workflow

- Do work on **`develop`**; `main` is the release branch (and `git-guard` blocks commits to it
  from a Claude session — that's intentional).
- One logical change per commit; conventional prefixes (`feat:`, `fix:`, `docs:`, …).
- Validate before committing: `bash -n` + `shellcheck` any changed script, and `jq empty` the
  touched `plugin.json` / `marketplace.json`. See [CLAUDE.md](CLAUDE.md#testing).
- Test guard behavior by piping synthetic tool-call JSON to the hook script and asserting
  exit codes (`0` = allow, `2` = block) — in real temp git repos where branch state matters.
  Always include false-positive cases (the ordinary commands that must still be allowed), not
  just the ones that should block.
- If you change what a guard catches, update [docs/shell-safety.md](docs/shell-safety.md) too.
- Keep plugins independent — no cross-plugin dependencies.
