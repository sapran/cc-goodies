## 1. Content — trim `rules/shell-safety.md`

- [x] 1.1 Kept and sharpened as "What the hooks can't see": folds in the concrete
      indirection forms from `docs/shell-safety.md`'s "Known gaps" (`bash -c "…"`,
      `$()`, `$'\x..'`-encoded names, variable indirection, `~/.gitconfig` alias) so the
      fact covers indirection, not just encoding.
- [x] 1.2 Dropped all 10 general-hygiene items per `proposal.md`'s classification
      (piping remote content, unnecessary escalation, confirm-before-delete, untrusted
      `/tmp`/downloads, the three credential bullets, the two prompt-injection/URL
      bullets, and the closing "stop and ask" paragraph); the 4 old section headings
      (Command execution / Credentials / Untrusted input & prompt injection / When in
      doubt) go with them — nothing else in the repo links to those anchors (checked).
- [x] 1.3 Added "Session-cwd resolution": re-verified against the current
      `plugins/git-guard/scripts/git-guard.sh` (post the two prior landings) — the
      `${cdir:-$cwd}` fallback at lines 207/284 is unchanged; `-C` is parsed at line
      167, a `cd` prefix is not recognized anywhere in the parser.
- [x] 1.4 Added "The escape hatch": every guard response — deny or a declined `ask` —
      hands back a ready-to-paste `! <command>` line (verified against the current
      `plugins/shell-guard/README.md` deny/ask examples, which already show this).
- [x] 1.5 Re-read top to bottom: 3 sections, each one fact about this system's hooks
      (blind spot, `.cwd` resolution, escape-hatch affordance) — no general hygiene
      left. 47→34 lines, 402→290 words.

## 2. Cross-references — keep other docs in sync

- [x] 2.1 Updated `docs/shell-safety.md`'s Layer 4 "Catches" column to name the 3
      surviving facts instead of the dropped bullets.
- [x] 2.2 Updated `plugins/shell-guard/README.md`'s "Advisory companion" section —
      replaced the restated dropped-bullet list with the 3 surviving facts.
- [x] 2.3 Grepped `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, and every
      plugin README for the dropped bullets. Found one more: root `README.md`'s "Shell
      safety" callout paraphrased "obfuscation, piping remote → shell, prompt
      injection" — updated it too (outside tasks.md's original 3-file list in 3.2, but
      required by this task and by the spec's "any document" sync requirement — see
      3.2 note). `CLAUDE.md`'s shell-guard row describes shell-guard's own block list,
      not the advisory file, so left as-is. `CHANGELOG.md` has historical release-note
      paraphrases; left untouched per the apply-step instruction not to edit it.

## 3. Verification

- [x] 3.1 Header's symlink command block (lines 9-11) untouched — confirmed unchanged
      and still correct.
- [x] 3.2 Diff touches `rules/shell-safety.md`, `docs/shell-safety.md`,
      `plugins/shell-guard/README.md`, **and** `README.md` (see 2.3) — one file beyond
      this task's original list, added because it paraphrased dropped content and the
      spec requires every such cross-reference to stay in sync. No file under
      `plugins/shell-guard/scripts/`, `plugins/git-guard/scripts/`, either plugin's
      `tests/`, either plugin's `.claude-plugin/plugin.json`, or `~/.claude/` appears in
      the diff (confirmed via `git diff --stat`: 4 files, all docs).
- [x] 3.3 Ran all three unchanged: `shell-guard: 53/53 passed, 0 failed`,
      `git-guard: 49/49 passed, 0 failed`, `git-guard routing: 8/8 passed, 0 failed` —
      zero effect on enforcement.

## 4. Sync, archive, release

- [ ] 4.1 Commit on the change branch (one logical commit; conventional `docs:` prefix).
- [ ] 4.2 Sync the `shell-safety-advisory` spec into `openspec/specs/` and archive the
      change per the repo's release flow, once reviewed.
- [ ] 4.3 Push, open a draft PR to `develop`.
