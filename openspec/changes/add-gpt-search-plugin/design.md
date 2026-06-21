## Context

`gpt-search` is a personal Claude Code skill at `~/.claude/skills/gpt-search/SKILL.md`: it runs deep web research through the Codex MCP and caches results per-project under `.claude/cache/search/`. It is not in the `cc-goodies` marketplace, so it is unversioned, undocumented, and only available on the one machine where the file exists.

The marketplace already has two reference migrations of personal skills into plugins — `session-finalise` and `project-scope` — both following the same pattern recorded in project memory: auto-activating `SKILL.md` + a thin `/<name>` command alias, registered in `marketplace.json` and mirrored across `README.md`, `CHANGELOG.md`, and the `CLAUDE.md` table, honoring install⇄uninstall symmetry.

The one way `gpt-search` differs from those two: it has a **hard runtime dependency on the Codex MCP** (`mcp__codex__codex` / `mcp__codex__codex-reply`), a server that lives in a *separate* plugin/marketplace. The prior two migrations were dependency-free.

## Goals / Non-Goals

**Goals:**
- Package `gpt-search` as a marketplace plugin using the validated skill+command-alias pattern, behavior-preserving.
- Document the Codex MCP as a prerequisite and degrade gracefully when it is absent.
- Keep the plugin portable and self-contained: no hook, no bundled MCP, no durable external state; `/plugin uninstall` is the full revert.
- Satisfy the existing `plugin-conformance` spec and the marketplace's documented conventions.

**Non-Goals:**
- Bundling or auto-wiring the Codex MCP (rejected — see Decisions).
- Changing the research/caching algorithm, the cache format, or the cache location.
- The publish→install→remove-local-duplicate steps (tracked as post-merge follow-up in the proposal; they are not repo edits in this change).
- Reconciling overlap with the separate `deep-research` skill.

## Decisions

**1. Document the Codex MCP as a prerequisite; ship no `.mcp.json`.** (User-selected.)
The plugin README states the Codex MCP requirement; the skill body gains a graceful-degradation note so a missing MCP yields a helpful message, not a crash. *Alternative considered:* bundle a `.mcp.json` declaring the Codex server so install auto-wires it. Rejected: it requires the `codex` CLI binary on PATH, makes the plugin non-portable, and risks duplicating or conflicting with the user's existing Codex MCP (already provided by their `codex` plugin). Prerequisite + graceful degradation matches the marketplace's "degrade gracefully, never hard-fail a workflow" convention.

**2. Skill + thin command alias (the session-finalise shape), not command-only.**
The artifact is already an auto-activating skill, so it stays a skill; the `/gpt-search` command is a thin alias that says "use the `gpt-search` skill" and forwards `$ARGUMENTS`. *Alternative:* fold everything into a single command. Rejected: loses auto-activation and breaks consistency with the two prior migrations and the recorded migration pattern.

**3. Carry behavior verbatim; only add two documentation notes.**
The keyword-relevance cache check, the AskUserQuestion reuse/re-search/new-query branch, the Codex MCP call shape, and the frontmatter cache write are preserved exactly. The only body additions are the graceful-degradation note and a pointer to the cache-teardown note. This minimizes review surface and risk.

**4. No `/<name>-install` or `/<name>-uninstall` command.**
The plugin writes nothing outside its own directory at install time (the cache is created on *use*, in the project, and is user-clearable). Per the marketplace's install⇄uninstall-symmetry rule, durable external state is what mandates a dedicated uninstall command; there is none here, so `/plugin uninstall` suffices — same as `session-finalise`. The README documents this explicitly and notes clearing `.claude/cache/search/` as an optional separate step.

**5. Fix command→skill self-references on migration.**
Per the migration pattern, ensure the command alias reads as a command (delegates to the skill) and the skill reads as a skill (no "this command" language left over), and the `$ARGUMENTS`→query bridge is wired in the command, mirroring the `/gpt-search <query>` usage.

## Risks / Trade-offs

- **[User installs the plugin without the Codex MCP and the skill silently does nothing useful.]** → README lists the prerequisite up front; the skill's graceful-degradation note makes the missing dependency explicit and actionable at run time.
- **[Name collision: the local `~/.claude/skills/gpt-search/` skill and the installed plugin skill both define `gpt-search`.]** → Resolved by ordering, outside this change: publish → install the plugin → only then remove the local duplicate, so there is never a capability gap (recorded migration pattern).
- **[Cache files accumulate in `.claude/cache/search/` and are not removed on uninstall.]** → Accepted and documented: the cache is on-demand, user-local, and self-explanatory; teardown is an optional, documented `rm` of the cache dir, consistent with the marketplace's ephemeral-cache exemption.
- **[Behavior drift while transcribing the skill body.]** → Carry the body verbatim and diff against the source `SKILL.md`; only the two documentation notes are intentional additions.

## Migration Plan

1. Create `plugins/gpt-search/` with `plugin.json`, `skills/gpt-search/SKILL.md` (verbatim body + the two notes), `commands/gpt-search.md` (thin alias), and `README.md` (Install/Uninstall + Codex MCP prerequisite).
2. Register in `.claude-plugin/marketplace.json` and bump the lineup description; mirror across root `README.md`, `CHANGELOG.md`, `CLAUDE.md`.
3. Validate: `jq empty` both JSON manifests; `claude plugins validate plugins/gpt-search`.
4. Commit on `develop`, conventional message.
5. **Post-merge (out of scope for these repo edits):** fast-forward `develop`→`main` and push `main` with raw git (rtk proxy bypasses git-guard); user runs `/plugin marketplace update` + `/plugin install gpt-search@cc-goodies`; then remove the local `~/.claude/skills/gpt-search/` duplicate.

**Rollback:** before publish, `git revert`/branch reset on `develop`. After install, `/plugin uninstall gpt-search@cc-goodies` is a complete revert (no hook, no shared-config edits).

## Open Questions

- None blocking. The Codex MCP handling (the only genuinely-open decision) is resolved as "document as prerequisite."
