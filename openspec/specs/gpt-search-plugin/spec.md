# gpt-search-plugin Specification

## Purpose
TBD - created by archiving change add-gpt-search-plugin. Update Purpose after archive.
## Requirements
### Requirement: Plugin packaging

The marketplace SHALL ship `gpt-search` as a self-contained plugin under `plugins/gpt-search/`, packaged with the established skill→plugin migration pattern: an auto-activating skill at `skills/gpt-search/SKILL.md` carrying the full research-and-cache body, and a thin command alias at `commands/gpt-search.md` that delegates to that skill and forwards `$ARGUMENTS`. The plugin SHALL declare a `.claude-plugin/plugin.json` manifest with `name`, `version`, `description`, `author`, SPDX `license`, and `keywords`. The plugin SHALL declare no hooks and SHALL write no durable state outside its own directory.

#### Scenario: Plugin directory is complete and valid

- **WHEN** `claude plugins validate plugins/gpt-search` is run
- **THEN** it reports the plugin valid, with the manifest, the `skills/gpt-search/SKILL.md` skill, and the `commands/gpt-search.md` command all present and parseable

#### Scenario: Command alias delegates to the skill

- **WHEN** a user invokes `/gpt-search <query>`
- **THEN** the command body instructs Claude to use the `gpt-search` skill and forwards the query via `$ARGUMENTS`, rather than re-implementing the research logic

### Requirement: Codex MCP prerequisite and graceful degradation

The plugin SHALL depend on the Codex MCP server (`mcp__codex__codex`, `mcp__codex__codex-reply`) at runtime and SHALL NOT bundle a `.mcp.json`; the user supplies their own Codex MCP. The plugin README SHALL document this prerequisite. When the Codex MCP tools are absent, the skill SHALL degrade gracefully — informing the user that the Codex MCP must be installed — and SHALL NOT hard-fail the session.

#### Scenario: Codex MCP available

- **WHEN** the Codex MCP tools are present and the user runs a search with no relevant cache hit
- **THEN** the skill calls the Codex MCP to perform the research and returns a formatted result

#### Scenario: Codex MCP missing

- **WHEN** the Codex MCP tools are absent and the user runs a search
- **THEN** the skill tells the user the Codex MCP is required and how to install it, and does not raise an unhandled error

#### Scenario: No bundled MCP config

- **WHEN** the `plugins/gpt-search/` directory is inspected
- **THEN** it contains no `.mcp.json` file

### Requirement: Research, cache reuse, and caching behavior

The skill SHALL preserve the existing behavior: before calling the Codex MCP it SHALL check the project-local cache at `.claude/cache/search/*.md` by comparing query keywords against each cached file's YAML frontmatter keywords, and on a sufficiently relevant match it SHALL offer the user the choice to reuse, re-search, or treat as a new query. After a fresh search it SHALL format the result (summary, key facts, sourced links) and SHALL persist it to `.claude/cache/search/YYYY-MM-DD_<topic>.md` with YAML frontmatter (`query`, `date`, `keywords`). The cache SHALL be created on use, not on install.

#### Scenario: Relevant cache hit offers reuse

- **WHEN** a new query's keywords overlap a cached file's keywords above the relevance threshold
- **THEN** the skill asks the user whether to reuse the cached result, re-search, or treat it as a new query

#### Scenario: Fresh result is cached with frontmatter

- **WHEN** a fresh Codex MCP search completes
- **THEN** the skill writes a self-contained Markdown file under `.claude/cache/search/` with YAML frontmatter containing the original query, date, and extracted keywords, and returns the summary plus the cache file path

### Requirement: Marketplace registration and documentation mirroring

The change SHALL register the plugin in `.claude-plugin/marketplace.json` with a `name`, `source`, and `description`, and SHALL update the marketplace `metadata.description` lineup to include it. The plugin SHALL be mirrored across the root `README.md`, the `CHANGELOG.md`, and the `CLAUDE.md` plugin table.

#### Scenario: Marketplace manifest parses and lists the plugin

- **WHEN** `jq empty .claude-plugin/marketplace.json` is run after the change
- **THEN** it succeeds and the `plugins` array contains a `gpt-search` entry whose `source` is `./plugins/gpt-search`

#### Scenario: Docs mention the plugin

- **WHEN** the root `README.md`, `CHANGELOG.md`, and `CLAUDE.md` are inspected after the change
- **THEN** each references the `gpt-search` plugin

### Requirement: Install and uninstall symmetry

The plugin SHALL document both an Install and an Uninstall path in its README, mirrored in the root `README.md`. Because the plugin ships no hook and writes no durable external state, `/plugin uninstall gpt-search@cc-goodies` SHALL be the full revert; the docs SHALL state this and SHALL document how to clear the project-local `.claude/cache/search/` cache as an optional separate step.

#### Scenario: Uninstall is fully documented and complete

- **WHEN** a user reads the plugin README Uninstall section
- **THEN** it states that `/plugin uninstall` removes the plugin entirely (no leftover hooks or shared-config edits) and explains that clearing `.claude/cache/search/` is an optional, user-driven cleanup
