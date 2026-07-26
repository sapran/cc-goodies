---
description: Run the end-of-session finalise checklist.
argument-hint: [optional notes — e.g. "skip cleanup" or "write a handoff"]
---

# /session-finalise

Use the **session-finalise** skill to wrap up the current work session. Follow its invariant —
nothing is destroyed or discarded before it is saved and confirmed — and its safety gates
(confirm before any commit, push, file deletion, or worktree removal; never commit to `main`);
propose only the phases this session needs rather than running a fixed step order.

Additional instructions from the user for this run (may be empty): **$ARGUMENTS**
