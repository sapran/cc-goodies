# Commit / stash (CONFIRM)

Do this before Cleanup runs, so cleanup can never destroy uncommitted work.

- Surface uncommitted changes. Group them into **separate logical commits** with conventional
  messages (`feat:`/`fix:`/`chore:`/`docs:`/`refactor:`/`test:`), or offer to `git stash`.
- **Never commit to `main`** — use `develop` or an existing dev branch; create one if needed.
- **Exclude scratch/throwaway files** from commits — they are removed in Cleanup, not committed.
- **Never `git push` without explicit confirmation.** State exactly what will be pushed where.
