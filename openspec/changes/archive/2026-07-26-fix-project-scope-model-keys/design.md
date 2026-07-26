# Design — fix-project-scope-model-keys

## Context

`references/mechanism.md` currently hard-codes `.tokens` keys (`claude-opus-4-7`,
`claude-sonnet-4-6`) and a silent fallback ("current model's key if present, else any opus key,
else any key"). `SKILL.md`'s Phase 1B jq query doesn't even implement that fallback — it reads
`to_entries[0].value`, an arbitrary first key. Fixing this requires the skill to know, at
resolution time, what the session's own model actually is. That turns out to be the one non-
trivial question in an otherwise small change, so it's recorded here rather than left implicit in
`tasks.md`.

## Verified facts

- The live catalog cache (`~/.claude/plugins/plugin-catalog-cache.json`, confirmed present and
  readable, 397.1 KB) carries exactly two `.tokens` keys across every entry today:
  `claude-opus-4-7` and `claude-sonnet-4-6`. No Claude-5-generation key exists in the file as of
  this writing.
- `project-scope` is a **skill** (prompt-resident `SKILL.md` instructions the model follows),
  not a **hook** or the **statusLine** command. Those two mechanisms are the only places this
  repo has found where Claude Code *injects* structured session metadata into a script's stdin:
  hooks receive event JSON on stdin (`CLAUDE.md`'s documented contract: `.tool_input`, `.cwd`,
  `.tool_name`, …, and env vars `$CLAUDE_PROJECT_DIR` / `$CLAUDE_PLUGIN_ROOT` /
  `$CLAUDE_ENV_FILE` / `$CLAUDE_CODE_REMOTE`); the statusLine command receives a separate JSON
  payload that includes `.model.display_name` (`plugins/statusline/statusline-command.sh:25`,
  e.g. `"Opus 4.8"`). **Neither list includes a model identifier available to a skill's own Bash
  tool calls.** A skill's `jq`/bash invocations get no injected payload at all — they're plain
  tool calls the model writes and runs itself.
- Even where the platform *does* expose a model identifier (statusLine), it's a human-readable
  `display_name` ("Opus 4.8"), not the catalog's slug format (`claude-opus-4-7`) — i.e. even the
  one confirmed channel doesn't hand over a string that's guaranteed to match `.tokens` keys
  verbatim.
- What the model *does* reliably have is first-person self-knowledge of its own identity — this
  session's own system context states "You are powered by the model named Sonnet 5. The exact
  model ID is `claude-sonnet-5`." That knowledge lives in the model's reasoning, not in anything
  a subprocess can read from disk or environment.

## Decision: resolution key comes from the model's self-report, not a script

Because no documented, script-visible channel carries the session's model id into a skill's
Bash/jq calls, the skill **cannot** shell out to "detect" the model — there is nothing on disk or
in the environment for it to detect. The only reliable source is the model's own self-knowledge.
`SKILL.md` must therefore instruct the model to state its own known model id as a literal value
*before* constructing the jq query, and pass that value in as a `--arg` — the resolution key is
supplied by the model's reasoning step, not discovered by the script.

This is a real constraint, not a preference: it means the fix cannot be "read `$SOME_ENV_VAR`
instead of hard-coding two strings" — there is no such variable. The fix is "ask the model what it
knows about itself, then look that up," with the lookup honest about not finding an exact hit.

## Decision: three-step match, never a silent substitution

Because the model's self-reported id is not guaranteed to match the catalog's key spelling
character-for-character (the display-name vs. slug mismatch above is existing precedent for that
gap), resolution is a three-step procedure, each step explicitly disclosed if it's the one that
resolves:

1. **Exact match.** The self-reported model id equals a `.tokens` key verbatim. Report the figure
   with no caveat — this is the session's own cost.
2. **Family match.** No exact key exists, but a key shares the model's family word (`opus`,
   `sonnet`, `fable`, `haiku`) — e.g. self-report `claude-sonnet-5`, cache has
   `claude-sonnet-4-6`. Report the figure, but name the key actually used, so the reader knows
   it's a different generation's cost, not this session's.
3. **No match.** Neither an exact nor a family key exists. Report the cost as unavailable — never
   substitute an unrelated family's number, and never fall back to "any key" the way the current
   text does.

This replaces "else any opus key, else any key" (which can hand back a *different family's*
number, e.g. Opus's cost mislabelled as Sonnet's) with a chain that degrades in relevance
(exact → same family, older generation → unavailable) and is honest at every step that isn't
step 1.

## Non-goals

- This change does not add a `$CLAUDE_MODEL`-style env var to the platform, or ask Claude Code to
  add one — that's outside the plugin's control and outside a "small, surgical" fix. If such a
  channel is ever added, the family-match step becomes unnecessary and step 1 becomes reliable by
  construction; the disclosure requirement in the spec still holds regardless.
- This change does not alter how `always_on`/`on_invoke` figures are used downstream (budget
  comparisons, install/skip decisions) — only how the figure is selected and disclosed.
