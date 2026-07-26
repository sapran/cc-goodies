# Trackers — detect, then adapt

Do not assume a fixed tracker or mechanism. Detect what's reachable *right now* by **capability**,
not by name: a task-tracker capability is an MCP tool or CLI that can read, comment on, label,
or change the status of a tracked item. Judge a tool by what it claims to do, not by matching
its name against a vendor list — a tracker vendor this file doesn't happen to name still counts
if it offers that capability; a tool that merely mentions "task" or "issue" without that
read/write surface doesn't.

- **Available tools:** scan currently-available tools for one offering that capability.
- **Project config:** check `.mcp.json` and `.claude/settings*.json` `enabledPlugins`.
- **CLIs:** `command -v gh` (and any other tracker CLI the project uses).

Then, for each tracker referenced this session:

- **Capability wired (MCP tool or CLI)** → propose the concrete updates (status, comment, close,
  link the commit/PR) and apply them through that integration, **confirming before each mutating
  call.**
- **Nothing wired** → emit a plain-text checklist of the exact changes for the user to apply
  manually, and note which MCP/CLI would automate it next time.

"Updating" a PR/issue/task means comment / label / status / link — it **never** includes
`git push`; pushing stays a separate confirmed action in Commit / stash.
