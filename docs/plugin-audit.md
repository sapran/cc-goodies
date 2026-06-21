# cc-goodies plugin best-practice audit

**Audit date:** 2026-06-21 · **Standard:** `plugin-dev` skills + `plugin-validator` agent
(primary) cross-checked against Anthropic's official plugin/marketplace docs (validation
layer, retrieved live 2026-06-21, Claude Code v2.1.x) and this repo's `CLAUDE.md` house
rules (layered source). **Rubric:** 86 items / 12 dimensions — full machine-readable list
in [`../openspec/changes/audit-plugin-best-practices/rubric.json`](../openspec/changes/audit-plugin-best-practices/rubric.json),
abbreviated in [Appendix A](#appendix-a--full-rubric). Full per-item verdicts (8 targets ×
86 items) in [`verdicts.json`](../openspec/changes/audit-plugin-best-practices/verdicts.json).

> This is a **measurement, not a migration.** No plugin file or `marketplace.json` entry was
> modified. Findings are triaged into proposed follow-up changes (§6); those are *listed*,
> not scaffolded.

## 1. Executive summary

The marketplace is in **good structural health**. All 8 targets (7 plugins + the marketplace
manifest) pass `claude plugins validate`. There are **no blocker or major findings** — nothing
fails validation, no required schema field is missing, no install⇄uninstall contract is broken,
no durable external state lacks a revert.

The 25 candidate gaps the assessors raised were put through an adversarial verification pass;
**10 were refuted** as false positives (§5) and **15 confirmed**: **11 minor** (convention /
documentation drift) and **4 nit** (cosmetic). Every confirmed finding is a *convention or
documentation* item, and most are **marketplace-wide patterns** rather than per-plugin defects
(§4) — which means they're better closed by a few small sweeping changes than plugin by plugin.

| Severity | Count | Nature |
|---|---|---|
| blocker | 0 | — |
| major | 0 | — |
| minor | 11 | convention / doc drift (CMD-6 ×4, CMD-2 ×2, CMD-3, SKILL-2, SKILL-5, VAL-6, HOOK-8) |
| nit | 4 | cosmetic (VAL-6 ×2, CMD-12, SKILL-3) |

## 2. Method

1. **Rubric build** (workflow, 11 agents): 7 `plugin-dev` skills + the `plugin-validator`
   agent + `CLAUDE.md` extracted in parallel; the official docs fetched as the validation
   layer; one synthesis pass merged them, assigned IDs, and recorded conflict resolutions where
   sources diverge (MAN-1, HOOK-1, HOOK-10, SET-1).
2. **Assessment** (workflow, 8 agents): each target read in full, `claude plugins validate`
   run against it, and a verdict (`pass`/`gap`/`n-a`) recorded for every one of the 86 items
   with file:line evidence.
3. **Adversarial verification** (workflow, 25 agents): every claimed gap independently
   re-checked by a skeptic prompted to *refute* unless the evidence held — re-reading the cited
   file, confirming applicability, and correcting severity.
4. **Synthesis** (this session): reconciled cross-target inconsistencies (§5), filled 2
   verdicts the `project-scope` assessor skipped (CMD-8/CMD-9 → pass), and triaged.

**Severity scale.** `blocker` = validation fails / install-uninstall asymmetry / breaks a
documented contract · `major` = missing required schema field / undocumented durable external
state · `minor` = convention drift / doc omission · `nit` = cosmetic.

## 3. Coverage matrix

Targets × dimensions. Cell shows confirmed gaps (**NG**), passes (P) and not-applicable (n/a).
Refuted candidates are folded into P. AGT and MCP are n/a everywhere — no plugin ships an
`agents/` dir or an MCP server.

| Target | MKT | MAN | NAME | HOOK | CMD | SKILL | AGT | MCP | CONV | DOC | SYM | VAL |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `marketplace` | 9P·2n/a | 9n/a | 1P·5n/a | 17n/a | 12n/a | 7n/a | 3n/a | 4n/a | 1n/a | 1P·3n/a | 6n/a | 4P·2n/a |
| `voice-notify` | 9P·2n/a | 9P | 6P | **1G**·10P·6n/a | 12n/a | 7n/a | 3n/a | 4n/a | 1n/a | 4P | 4P·2n/a | **1G**·4P·1n/a |
| `statusline` | 10P·1n/a | 8P·1n/a | 6P | 17n/a | **2G**·6P·4n/a | 7n/a | 3n/a | 4n/a | 1n/a | 2P·2n/a | 5P·1n/a | 5P·1n/a † |
| `git-guard` | 9P·2n/a | 9P | 6P | 15P·2n/a | **1G**·9P·2n/a | 7n/a | 3n/a | 4n/a | 1n/a | 4P | 5P·1n/a | **1G**·5P |
| `shell-guard` | 9P·2n/a | 8P·1n/a | 6P | 15P·2n/a | **1G**·9P·2n/a | 7n/a | 3n/a | 4n/a | 1n/a | 4P | 5P·1n/a | **1G**·5P |
| `rtk-hook` | 9P·2n/a | 9P | 6P | 12P·5n/a | **2G**·8P·2n/a | 7n/a | 3n/a | 4n/a | 1n/a | 4P | 5P·1n/a | 6P |
| `session-finalise` | 9P·2n/a | 8P·1n/a | 5P·1n/a | 17n/a | **1G**·5P·6n/a | **1G**·4P·2n/a | 3n/a | 4n/a | 1n/a | 3P·1n/a | 5P·1n/a | 5P·1n/a |
| `project-scope` | 9P·2n/a | 8P·1n/a | 5P·1n/a | 17n/a | **1G**·7P·4n/a | **2G**·3P·2n/a | 3n/a | 4n/a | 1n/a | 3P·1n/a | 4P·2n/a | 5P·1n/a |

† `statusline` VAL-6 reads as a pass here because its verifier misfired (§5); the per-plugin
LICENSE finding is actually uniform across all 7 plugins — see §4.

## 4. Cross-cutting findings

Most confirmed gaps are the *same* item repeating across plugins. Treat these as the real units
of work:

- **CMD-6 — destructive control commands omit `disable-model-invocation: true`** (minor).
  *Zero* command files in the marketplace set the flag (`grep` confirmed). It matters on the 5
  mutating control commands — `statusline-install`, `statusline-uninstall`,
  `git-guard-uninstall`, `shell-guard-uninstall`, `rtk-hook-uninstall` — which delete files
  and/or edit `~/.claude/settings.json`. The flag stops the model auto-invoking them via the
  SlashCommand tool; bodies already gate with backup + per-step confirmation, so this is
  defense-in-depth, not a hole.
- **VAL-6 — no per-plugin `LICENSE` file** (nit/minor). All 7 plugins declare `"license":
  "MIT"` (SPDX field present) and the repo root ships a `LICENSE` that covers the monorepo, but
  no plugin dir ships its own. SHOULD-level; only relevant if plugins are distributed
  standalone. Uniform and deliberate-looking.
- **CMD-12 — no HTML-comment maintainer docs in commands** (nit, borderline). *Zero* command
  files use `<!-- -->`. Verifiers split on whether this is even a gap (the command body *is* the
  prompt, so maintainer-note-hiding has little force); confirmed nit on `rtk-hook`, refuted to
  n-a/pass elsewhere. Low priority; arguably document-as-intentional.
- **Skill frontmatter (SKILL-2 / SKILL-3)** — both skills (`session-finalise`, `project-scope`)
  omit a `version` key (versioning lives in `plugin.json` by convention) and open their
  descriptions in imperative mood ("Use when…") rather than the prescribed third person ("This
  skill should be used when…"). Consistent across both; the load-critical `name` field is
  present in both, so the basename-fallback risk SKILL-2 guards against is already avoided.
- **Thin alias commands omit `allowed-tools` (CMD-3) and run long descriptions (CMD-2)** — the
  two delegate-to-skill commands (`project-scope`, `session-finalise`) both omit `allowed-tools`
  (defensibly — they execute nothing; the skill runs under its own permissions) and carry
  ~220–230-char descriptions, well over the ~60-char guideline.

## 5. Reconciliations & refuted candidates (transparency)

The adversarial pass refuted **10 of 25** raw candidates. Distributed assessment also produced a
few cross-target inconsistencies that synthesis reconciled:

**Refuted (false positives, corrected verdict):**

| Target | Item | → | Why refuted |
|---|---|---|---|
| statusline, git-guard, shell-guard | MKT-11 | pass | Rule fires only if `version` is set in *both* `plugin.json` AND the marketplace entry. Entries carry no version — no double-declaration. |
| statusline, git-guard, shell-guard | CMD-12 | n-a/pass | Command bodies are self-documenting; HTML-comment item judged non-applicable / not a defect here. |
| shell-guard | CMD-2 | pass | Description (129 chars) flagged, but verifier judged it acceptable given the pattern; folded to pass. |
| session-finalise | CMD-3 | pass | Alias command runs no tools itself — `allowed-tools` not needed (delegated skill carries its own perms). |
| session-finalise | SKILL-2 | pass | Verifier accepted `version`-in-`plugin.json` convention as satisfying intent (cf. project-scope where it was kept as a minor — see note). |
| statusline | VAL-6 | n-a | **Unreliable refutation** — this verifier reported it couldn't read the rubric (an arg-glitch passed it `"undefined"`) and bailed. Overridden in synthesis: VAL-6 applies to statusline exactly as to the other 6 plugins (no per-plugin LICENSE). Counted as the marketplace-wide §4 finding, not as a statusline pass. |

**Synthesis fills:** `project-scope` CMD-8 and CMD-9 (assessor stopped at 84/86) → both `pass`
(single-responsibility alias; empty-arg handled by delegating to the skill).

**Note on SKILL-2/CMD-12 divergence:** identical items landed `pass`/`n-a` on one plugin and
`gap` on another depending on the verifier. §4 states the reconciled marketplace-wide reading;
the per-target `verdicts.json` preserves the raw record.

## 6. Triage — proposed follow-up changes (list-only)

Grouped by the work unit, not the plugin. None scaffolded; each is a candidate
`/opsx:propose`.

**Minor (worth doing):**

1. **`harden-control-command-invocation`** — add `disable-model-invocation: true` to the 5
   mutating control commands (CMD-6). One sweep, highest-value finding.
2. **`trim-command-descriptions`** — shorten over-cap command descriptions to ≤~60 chars,
   moving detail into the body: `statusline-install`, `statusline-uninstall`,
   `session-finalise` (CMD-2).
3. **`align-skill-frontmatter`** — add `version` to both `SKILL.md` files and reword their
   descriptions to third person (SKILL-2, SKILL-3).
4. **`decide-alias-command-allowed-tools`** — either add tightly-scoped `allowed-tools` to the
   two alias commands or document the intentional omission as a house rule (CMD-3).
5. **`voice-notify-hook-timeouts`** — add explicit `"timeout"` to voice-notify's two hooks to
   match the sibling pattern (git-guard 10 / shell-guard 10 / rtk-hook 15) (HOOK-8).
6. **`split-project-scope-skill`** *(optional)* — move the Mechanism reference tables and the
   Phase-3 menu tables in `project-scope/SKILL.md` (3,996 words) into `references/` to get the
   always-loaded body under the 3,000-word guideline (SKILL-5).

**Nit (decide & document, likely WONTFIX):**

7. **`per-plugin-license-policy`** — add per-plugin `LICENSE` files/symlinks *or* document that
   the root `LICENSE` covers the monorepo (VAL-6). Recommend: document the convention.
8. **`command-html-comment-policy`** — decide whether maintainer notes belong in `<!-- -->`
   blocks; given self-documenting bodies, recommend documenting the intentional omission
   (CMD-12).

A natural first follow-up bundles 1–5 (all `CLAUDE.md`-convention alignment) into one small
change, then optionally 6, and folds 7–8 into a `CLAUDE.md` "documented exceptions" note.

## 7. Spec cross-check

Against `specs/plugin-best-practice-audit/spec.md`:

- ✅ **Rubric from cross-checked sources, each item sourced, conflicts explicit** — 86 items,
  every item carries `sources`; conflict notes on MAN-1/HOOK-1/HOOK-10/SET-1.
- ✅ **Rubric covers every used dimension** — MKT/MAN/NAME/HOOK/CMD/SKILL/DOC/SYM/CONV/VAL all
  populated; AGT/MCP included for completeness (n-a here).
- ✅ **Every plugin × every applicable item has a verdict; gaps evidenced + severity-rated;
  n-a justified** — 8 × 86 = 688 verdicts in `verdicts.json`; the 2 skipped fills closed.
- ✅ **`claude plugins validate` run and recorded per target** — all 8 pass (marketplace: pass
  with 1 ignorable warning on `metadata.repository`).
- ✅ **Triaged report, no plugin mutation** — see §6; no-mutation gate result recorded with the
  change tasks.

## Appendix A — full rubric

Abbreviated; canonical machine-readable form in
[`rubric.json`](../openspec/changes/audit-plugin-best-practices/rubric.json). `docs:` = Anthropic
official documentation.

| ID | Dim | Rule (abbrev) | Applies to | Sources | Conflict resolution |
|---|---|---|---|---|---|
| MKT-1 | MKT | The marketplace catalog MUST exist at .claude-plugin/marketplace.json in the repo root; missing → fails to load. | repo marketplace.json | docs:plugin-marketplaces, CLAUDE.md |  |
| MKT-2 | MKT | marketplace.json MUST be valid JSON. | repo marketplace.json | docs:plugin-marketplaces, CLAUDE.md, plugin-validator |  |
| MKT-3 | MKT | Required top-level fields: name (kebab), owner (object), plugins (array). | repo marketplace.json | docs:plugin-marketplaces |  |
| MKT-4 | MKT | owner object MUST have name (string); email optional. | owner field | docs:plugin-marketplaces |  |
| MKT-5 | MKT | name MUST NOT be a reserved/official Anthropic marketplace name. | name field | docs:plugin-marketplaces |  |
| MKT-6 | MKT | Each plugins[] entry MUST have a unique kebab name and a source. | plugins[] entries | docs:plugin-marketplaces, CLAUDE.md |  |
| MKT-7 | MKT | Relative-path source MUST start ./, resolve from marketplace root, no '..'. | string-form sources | docs:plugin-marketplaces |  |
| MKT-8 | MKT | Object source MUST set a valid type discriminator + required sub-fields. | object-form sources | docs:plugin-marketplaces |  |
| MKT-9 | MKT | strict:true (default) → plugin.json authoritative; declaring components in both is a load failure. | strict + plugin.json | docs:plugin-marketplaces |  |
| MKT-10 | MKT | Adding a plugin requires dir AND marketplace entry; bump metadata.description on lineup change. | plugin add/remove | CLAUDE.md |  |
| MKT-11 | MKT | Avoid version in BOTH plugin.json and the marketplace entry (plugin.json silently wins). | version fields | docs:plugin-marketplaces |  |
| MAN-1 | MAN | When present, manifest MUST be at .claude-plugin/plugin.json. | every plugin | plugin-structure, plugin-validator, docs:plugins-reference | docs: manifest optional (auto-discovery); house convention: every plugin ships one. |
| MAN-2 | MAN | plugin.json MUST be valid JSON with correct field types. | every plugin.json | plugin-structure, plugin-validator, docs:plugins-reference |  |
| MAN-3 | MAN | plugin.json MUST include a non-empty name (the only required field). | every plugin.json | plugin-structure, plugin-validator, docs:plugins-reference |  |
| MAN-4 | MAN | If version present it MUST be semver and bumped per release. | plugins with version | plugin-structure, plugin-validator, docs:plugins-reference |  |
| MAN-5 | MAN | description MUST explain the plugin in active voice (~50-200 chars). | distributed plugins | plugin-structure, plugin-validator |  |
| MAN-6 | MAN | Optional metadata fields MUST use documented types (author/homepage/repository/license/keywords…). | plugins declaring them | plugin-structure, plugin-validator, docs:plugins-reference |  |
| MAN-7 | MAN | Custom component paths MUST be ./-relative, forward-slash, no '..', and exist. | custom-path plugins | plugin-structure, docs:plugins-reference |  |
| MAN-8 | MAN | Keep the manifest lean; mind replace-vs-add path semantics. | all plugins | plugin-structure, docs:plugins-reference |  |
| MAN-9 | MAN | Keep manifest metadata current (version/description/keywords). | maintained plugins | plugin-structure |  |
| NAME-1 | NAME | plugin name MUST match kebab regex and be unique. | plugin + marketplace name | plugin-structure, plugin-validator, docs:plugins-reference, docs:plugin-marketplaces |  |
| NAME-2 | NAME | kebab-case ALL dir/file names (commands, agents, skills, scripts, docs). | per shipped component | plugin-structure |  |
| NAME-3 | NAME | Only plugin.json in .claude-plugin/; component dirs at plugin root. | every dir tree | plugin-structure, plugin-validator, docs:plugins-reference |  |
| NAME-4 | NAME | Descriptive, non-vague, non-colliding component names; shallow nesting. | components | plugin-structure |  |
| NAME-5 | NAME | Reference intra-plugin files via ${CLAUDE_PLUGIN_ROOT}; never hardcode/persist there. | bundled-file refs | plugin-structure, command-development, mcp-integration, plugin-validator, docs:plugins-reference |  |
| NAME-6 | NAME | Don't reference files outside the plugin dir; share within a marketplace via symlink. | bundled-file refs | docs:plugins-reference |  |
| HOOK-1 | HOOK | Hooks MUST be declared INLINE in plugin.json (no hooks/hooks.json). | hook plugins | CLAUDE.md, plugin-structure, hook-development, docs:plugins-reference | docs allow either; CLAUDE.md house rule mandates inline. |
| HOOK-2 | HOOK | Each hook entry: valid event, matcher where applicable, hooks array, type command, non-empty command; valid JSON. | hook plugins | plugin-structure, hook-development, plugin-validator, docs:plugins-reference, CLAUDE.md |  |
| HOOK-3 | HOOK | Event names from the supported set, exactly cased. | hook plugins | plugin-structure, hook-development, plugin-validator, docs:hooks |  |
| HOOK-4 | HOOK | Command hooks read event JSON on STDIN + jq; no $CLAUDE_TOOL_INPUT. | command-hook scripts | hook-development, CLAUDE.md, docs:hooks |  |
| HOOK-5 | HOOK | Block with exit 2; exit 0 allows; exit 1 is non-blocking. | gating hooks | hook-development, CLAUDE.md, docs:hooks |  |
| HOOK-6 | HOOK | Denials to stderr; structured JSON well-formed. | blocking hooks | hook-development |  |
| HOOK-7 | HOOK | Blocking guards MUST be synchronous; async only for fire-and-forget. | hook declarations | CLAUDE.md, docs:hooks |  |
| HOOK-8 | HOOK | Set an explicit numeric timeout per hook. | hook plugins | hook-development, plugin-validator |  |
| HOOK-9 | HOOK | Prompt-type hooks only on supported events, non-empty prompt. | prompt-hook plugins (n-a here) | hook-development, plugin-validator |  |
| HOOK-10 | HOOK | Scripts: shebang, chmod +x, bash 3.2, set -u, quote expansions, why-comments. | command-hook scripts | hook-development, CLAUDE.md, docs:plugins-reference | skill: set -euo pipefail; CLAUDE.md: only set -u + fail-open (governs). |
| HOOK-11 | HOOK | Degrade gracefully (jq missing → no-op + warn; handle missing fields/files). | command-hook scripts | CLAUDE.md, hook-development |  |
| HOOK-12 | HOOK | Validate/sanitize input; reject '..' and system-dir writes; never log secrets. | command-hook scripts | hook-development, plugin-validator |  |
| HOOK-13 | HOOK | Treat .cwd as session cwd (git -C for other repos); design hooks independent/parallel-safe. | location-aware hooks | CLAUDE.md, hook-development |  |
| HOOK-14 | HOOK | Persist env only via $CLAUDE_ENV_FILE from SessionStart; cross-event temp state sequential only. | env/state hooks (n-a here) | hook-development |  |
| HOOK-15 | HOOK | Verify hooks: bash -n, shellcheck, jq, synthetic-stdin exit-code tests in temp repos. | command-hook scripts | hook-development, CLAUDE.md, plugin-validator |  |
| HOOK-16 | HOOK | args array → exec form; without args → shell form (quote ${CLAUDE_PLUGIN_ROOT}). | hook command handlers | docs:hooks, docs:plugins-reference |  |
| HOOK-17 | HOOK | Config precedence env → ~/.claude/<plugin>.conf → default; parse conf safely, never source. | config-reading plugins | CLAUDE.md |  |
| CMD-1 | CMD | Commands: .md in commands/, valid YAML frontmatter + non-empty imperative body. | command plugins | command-development, plugin-structure, plugin-validator, CLAUDE.md |  |
| CMD-2 | CMD | Frontmatter MUST have description; keep ≤~60 chars, verb-first, no filler; repo also declares allowed-tools. | command plugins | command-development, plugin-validator, CLAUDE.md |  |
| CMD-3 | CMD | Declare allowed-tools tightly scoped (filter Bash; avoid bare/*). | tool-using commands | command-development |  |
| CMD-4 | CMD | argument-hint for arg-consuming commands; $ARGUMENTS/$1 matching invocation. | arg commands | command-development |  |
| CMD-5 | CMD | model field, if set, MUST be a valid Claude model. | model-setting commands | command-development |  |
| CMD-6 | CMD | disable-model-invocation:true for manual-only/destructive commands. | *-uninstall / destructive | command-development |  |
| CMD-7 | CMD | @ for file includes, !`cmd` for dynamic context; keep inline bash fast/read-only. | context-gathering commands | command-development |  |
| CMD-8 | CMD | Single responsibility, verb-noun name, hyphens, non-colliding; namespace at 5+. | command plugins | command-development |  |
| CMD-9 | CMD | Validate args/resources in body before acting (usage fallback, test -f). | arg/script commands | command-development |  |
| CMD-10 | CMD | Config-writing command: gather/validate, show diff, confirm, jq-merge (no clobber). | config-writing commands | CLAUDE.md, command-development |  |
| CMD-11 | CMD | Referenced agent/skill MUST exist; document hook interaction. | delegating commands | command-development |  |
| CMD-12 | CMD | Document non-obvious logic/usage/examples in HTML comments. | non-trivial commands | command-development |  |
| SKILL-1 | SKILL | Each skill in its own kebab dir with SKILL.md (or root SKILL.md for single-skill). | skill plugins | skill-development, plugin-structure, plugin-validator, docs:plugins-reference |  |
| SKILL-2 | SKILL | SKILL.md valid frontmatter with name + description (plugin skills should carry version); set name explicitly. | skill plugins | skill-development, plugin-structure, plugin-validator, docs:plugins-reference |  |
| SKILL-3 | SKILL | Description in THIRD person with specific triggers/scenarios; never vague. | skill plugins | skill-development |  |
| SKILL-4 | SKILL | Substantial imperative/objective body (not 2nd person / actor-narration). | skill plugins | skill-development |  |
| SKILL-5 | SKILL | Keep body lean (~1,500-2,000 words, <3,000 ideal, <5,000 cap); move detail to references/. | skill plugins | skill-development |  |
| SKILL-6 | SKILL | Reference every bundled resource from SKILL.md; referenced files MUST exist. | skills with resources | skill-development, plugin-validator |  |
| SKILL-7 | SKILL | scripts/ runnable, references/ docs, assets/ media, examples/ runnable; create only what's used. | skills with extras | skill-development |  |
| AGT-1 | AGT | Agents: .md in agents/, --- frontmatter, non-empty system-prompt body. | agent plugins (n-a here) | agent-development, plugin-structure, plugin-validator |  |
| AGT-2 | AGT | Agent frontmatter: name, description (triggers), model, color. | agent plugins (n-a here) | agent-development, plugin-validator |  |
| AGT-3 | AGT | Least-privilege tools; "When to invoke"; documented; no hooks/mcpServers/permissionMode. | agent plugins (n-a here) | agent-development, docs:plugins-reference |  |
| MCP-1 | MCP | MCP servers in .mcp.json (or inline mcpServers); valid JSON + type-specific fields. | MCP plugins (n-a here) | mcp-integration, plugin-structure, plugin-validator, docs:plugins-reference |  |
| MCP-2 | MCP | ${CLAUDE_PLUGIN_ROOT} for paths, env-var for secrets; HTTPS/WSS; document setup. | MCP plugins (n-a here) | mcp-integration, plugin-validator, docs:plugins-reference |  |
| MCP-3 | MCP | stdio: creds via env/args, PYTHONUNBUFFERED=1, stdout = protocol only. | stdio MCP (n-a here) | mcp-integration |  |
| MCP-4 | MCP | Invoke MCP tools by exact prefixed name; pre-allow specific tools; validate/confirm. | MCP-invoking (n-a here) | mcp-integration |  |
| SET-1 | CONV | Per-project state in .claude/<plugin>.local.md (chmod 600, gitignored, atomic writes). | project-local-settings plugins | plugin-settings | cc-goodies guards use ~/.claude/<plugin>.conf (HOOK-17) instead; HOOK-17 governs here. |
| DOC-1 | DOC | Ship a comprehensive root README.md; Claude-context instructions via skill/agent/hook (not plugin CLAUDE.md). | every plugin | plugin-structure, plugin-validator, docs:plugins-reference |  |
| DOC-2 | DOC | README has Install + Uninstall; root README mirrors both per plugin. | every README + root | CLAUDE.md |  |
| DOC-3 | DOC | Hook plugins document install/uninstall round-trip; self-contained say /plugin uninstall is full revert. | hook/self-contained plugins | CLAUDE.md, hook-development |  |
| DOC-4 | DOC | Toggleable hooks document an opt-out and the restart requirement. | toggleable-hook plugins | hook-development, plugin-settings |  |
| SYM-1 | SYM | Every setup step has a documented inverse teardown. | every plugin | CLAUDE.md |  |
| SYM-2 | SYM | Every install verb has its inverse (marketplace/plugin/<name>-install). | every plugin | CLAUDE.md |  |
| SYM-3 | SYM | No /<name>-install just to activate a hook; only for declaratively-unsettable durable state. | every plugin | CLAUDE.md |  |
| SYM-4 | SYM | Durable state outside the plugin dir → ship /<name>-uninstall (or fold revert into control cmd). | external-state plugins | CLAUDE.md |  |
| SYM-5 | SYM | Revert cmd: back up shared config, verify it parses, refuse user-configured state. | config-editing revert cmds | CLAUDE.md |  |
| SYM-6 | SYM | Self-contained plugins rely on /plugin uninstall and say so; $TMPDIR caches exempt. | self-contained plugins | CLAUDE.md |  |
| VAL-1 | VAL | Validate with `claude plugin validate` before publishing; --strict in CI. | marketplace + every plugin | docs:plugins-reference, plugin-validator, CLAUDE.md |  |
| VAL-2 | VAL | Malformed hooks config fails the whole plugin; validate hook JSON before shipping. | hook plugins | plugin-validator, docs:plugins-reference, hook-development |  |
| VAL-3 | VAL | Pre-commit gate: bash -n + shellcheck on scripts, jq empty on plugin.json + marketplace.json. | script/manifest changes | CLAUDE.md, plugin-validator |  |
| VAL-4 | VAL | No hardcoded secrets, no junk files (node_modules/.DS_Store); hook scripts secure. | all plugins | plugin-validator, mcp-integration |  |
| VAL-5 | VAL | Component frontmatter validates (command desc/allowed-tools array/body; SKILL name+desc). | command/skill plugins | plugin-validator, command-development, skill-development, agent-development |  |
| VAL-6 | VAL | SHOULD ship a LICENSE file + SPDX field; .gitignore when generated artifacts exist. | distributed plugins | plugin-structure, plugin-validator |  |
