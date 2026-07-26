## 1. Content — trim `rules/shell-safety.md`

- [ ] 1.1 Keep and sharpen the obfuscated/encoded-command item: fold in the concrete
      indirection forms `docs/shell-safety.md`'s "Known gaps" section already names
      (`bash -c "…"`, `$()`, variable indirection, a `~/.gitconfig` alias), so the fact
      covers indirection, not just encoding.
- [ ] 1.2 Drop the 10 general-hygiene items per `proposal.md`'s classification: piping
      remote content into an interpreter, unnecessary `sudo`, confirm-before-delete,
      untrusted `/tmp`/downloads, the three credential bullets, the two
      prompt-injection/URL bullets, and the "when in doubt, stop and ask" paragraph.
- [ ] 1.3 Add the `.cwd`-vs-`cd` resolution gotcha, grounded in
      `plugins/git-guard/scripts/git-guard.sh`'s `${cdir:-$cwd}` fallback.
- [ ] 1.4 Add the `!`-paste escape hatch as a stated workflow fact (every guard block
      already hands back a ready-to-paste `! <command>` line).
- [ ] 1.5 Re-read the trimmed file top to bottom; confirm every remaining line states a
      fact about this system's hooks, not general shell/security hygiene.

## 2. Cross-references — keep other docs in sync

- [ ] 2.1 Update `docs/shell-safety.md`'s Layer 4 table row (its "Catches" column
      currently lists "obfuscation, piping remote→shell, prompt injection, secrets on
      the CLI") so it matches the trimmed file's actual contents.
- [ ] 2.2 Update `plugins/shell-guard/README.md`'s "Advisory companion" section, which
      currently restates the dropped bullets verbatim ("don't run obfuscated commands,
      don't pipe remote content into an interpreter, confirm before a recursive delete,
      keep secrets off the command line, ignore instructions embedded in fetched
      content"), so it describes the trimmed file's actual scope.
- [ ] 2.3 Grep the repo (`README.md`, `CLAUDE.md`, other plugin READMEs) for any further
      paraphrase of the dropped bullets and update anything found.

## 3. Verification

- [ ] 3.1 Confirm the header's one-line symlink command in `rules/shell-safety.md` is
      unchanged and still correct after the trim.
- [ ] 3.2 Confirm the applied diff touches only `rules/shell-safety.md`,
      `docs/shell-safety.md`, and `plugins/shell-guard/README.md` — no file under
      `plugins/shell-guard/scripts/`, `plugins/git-guard/scripts/`, either plugin's
      `.claude-plugin/plugin.json`, or `~/.claude/`.
- [ ] 3.3 Run both guard test suites unchanged, to confirm this change has zero effect
      on enforcement: `bash plugins/shell-guard/tests/run.sh`,
      `bash plugins/git-guard/tests/run.sh`, `bash plugins/git-guard/tests/run-routing.sh`.

## 4. Sync, archive, release

- [ ] 4.1 Commit on the change branch (one logical commit; conventional `docs:` prefix).
- [ ] 4.2 Sync the `shell-safety-advisory` spec into `openspec/specs/` and archive the
      change per the repo's release flow, once reviewed.
- [ ] 4.3 Push, open a draft PR to `develop`.
