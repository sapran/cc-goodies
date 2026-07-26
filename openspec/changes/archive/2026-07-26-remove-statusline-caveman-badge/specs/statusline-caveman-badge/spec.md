## REMOVED Requirements

### Requirement: Caveman badge rendered at the end of the enriched second line

**Reason**: The badge only ever rendered when the caveman plugin's mode flag was
present; caveman is uninstalled, so the segment is unreachable. The enriched second
line now ends with the `c:`/`s:`/`w:` gauges.

**Migration**: None for installs without a caveman flag — output is byte-identical.
Users still running caveman wire the caveman plugin's own `caveman-statusline.sh` into
Claude Code's `statusLine` slot instead of this statusline.

### Requirement: Badge sourced from the caveman plugin's state files

**Reason**: Removes this repo's only cross-plugin coupling — a fixed-path read of
`.caveman-active` and `.caveman-statusline-suffix`, files another marketplace owns and
whose format it may change at will.

**Migration**: None. No other capability reads those files.

### Requirement: Mode-specific badge label

**Reason**: The `[CAVEMAN]` / `[CAVEMAN:<MODE>]` label and its pinned mode whitelist
exist only to render the removed badge.

**Migration**: None.

### Requirement: Badge content hardened against terminal-escape injection

**Reason**: The hardening (symlink refusal, 64-byte read cap, case-folding, charset
strip, mode whitelist) defended a read that no longer happens. Deleting the read is
strictly safer than keeping the defense.

**Migration**: None.

### Requirement: Optional savings suffix beside the badge

**Reason**: The `~NN% saved` token came from a caveman-written file and rendered only
alongside the removed badge.

**Migration**: None.

### Requirement: Opt-out via environment variables

**Reason**: `STATUSLINE_CAVEMAN` and `CAVEMAN_STATUSLINE_SAVINGS` gated a segment that
no longer exists.

**Migration**: Both variables are now ignored. Nothing breaks if they remain set in a
shell profile; they can be deleted at leisure.

### Requirement: Fail-soft when caveman is absent

**Reason**: "Absent" is now the only state, and it is expressed by the code not
existing rather than by a guarded early return.

**Migration**: None — this was already the rendered behaviour for every install
without an active flag.
