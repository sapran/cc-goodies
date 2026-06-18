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
- [ ] Every install verb has its documented inverse: `marketplace add` ⇄ `marketplace remove`,
      `/plugin install` ⇄ `/plugin uninstall`, `/<name>-install` ⇄ `/<name>-uninstall`.
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

- **`git-guard`** and **`shell-guard`** — a hook plus a `~/.claude/<plugin>.conf` config
  file, with a `/<name>-uninstall` that removes only that conf (after backup + confirm).
- **`statusline`** and **`rtk-hook`** — a `/<name>-install` / `/<name>-uninstall` pair that
  edits `~/.claude/settings.json` with `jq`: it backs up, merges/removes only its own key,
  verifies the result still parses (`jq empty`), and refuses to touch anything you didn't
  install.
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
