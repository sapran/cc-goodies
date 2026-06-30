## ADDED Requirements

### Requirement: Caveman badge rendered at the end of the enriched second line

When the caveman mode flag is present and active, the statusline SHALL render a caveman
badge as the final segment of the enriched second line, after the model, effort, and the
`c:`/`s:`/`w:` gauges and their time suffixes. The badge SHALL be the last thing on that
line, separated from the preceding segment by the statusline's normal segment spacing, and
SHALL be rendered in the caveman badge colour (256-colour index 172) to match the caveman
plugin's own badge. The badge SHALL appear only in `enriched` mode; `lean` mode SHALL NOT
render it.

#### Scenario: Badge trails the gauges in enriched mode

- **WHEN** the statusline renders in `enriched` mode and the caveman flag reports an active mode
- **THEN** the second line ends with the caveman badge after the `c:`/`s:`/`w:` gauges — for example `Opus 4.8 (high)  c:42% s:10% w:5%  [CAVEMAN]`

#### Scenario: Lean mode never shows the badge

- **WHEN** the statusline renders in `lean` mode and the caveman flag reports an active mode
- **THEN** the lean single line is unchanged and contains no caveman badge

### Requirement: Badge sourced from the caveman plugin's state files

The badge SHALL be derived from the caveman plugin's existing state files, resolved under
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}`: the mode flag `.caveman-active` and the pre-rendered
savings token `.caveman-statusline-suffix`. The statusline SHALL read these files directly;
it SHALL NOT invoke the caveman plugin, spawn `node`, or shell out to compute the values.

#### Scenario: Mode read from the flag file

- **WHEN** `.caveman-active` exists under the resolved config directory and holds a recognised mode value
- **THEN** the badge reflects that mode value on the next render

#### Scenario: Config directory override is honoured

- **WHEN** `CLAUDE_CONFIG_DIR` is set and `.caveman-active` lives under that directory
- **THEN** the statusline reads the flag from `$CLAUDE_CONFIG_DIR/.caveman-active`, not from `$HOME/.claude`

### Requirement: Mode-specific badge label

The badge label SHALL be derived from the flag value: a value of `full` or an empty value
SHALL render `[CAVEMAN]`; any other recognised mode SHALL render `[CAVEMAN:<MODE>]` with the
mode upper-cased. The set of recognised modes SHALL match the caveman plugin's whitelist
(`off`, `lite`, `full`, `ultra`, `wenyan-lite`, `wenyan`, `wenyan-full`, `wenyan-ultra`,
`commit`, `review`, `compress`).

#### Scenario: Full mode renders the bare badge

- **WHEN** the flag value is `full` (or empty)
- **THEN** the badge renders as `[CAVEMAN]` with no suffix

#### Scenario: Named mode renders an upper-cased suffix

- **WHEN** the flag value is `ultra`
- **THEN** the badge renders as `[CAVEMAN:ULTRA]`

### Requirement: Badge content hardened against terminal-escape injection

The statusline SHALL apply the same hardening to the caveman state files that the caveman
plugin's own statusline script applies, because the files are rendered to the terminal on
every keystroke. It SHALL refuse a flag or suffix file that is a symbolic link; it SHALL cap
the bytes read from each file; it SHALL lower-case the flag value and strip it to the
character set `[a-z0-9-]`; it SHALL strip control bytes from the savings suffix; and it SHALL
validate the resulting mode against the recognised-mode whitelist. A flag value outside the
whitelist SHALL render no badge at all rather than echo the file's bytes.

#### Scenario: Symlinked flag file renders nothing

- **WHEN** `.caveman-active` is a symbolic link
- **THEN** no badge is rendered and the statusline does not read through the link

#### Scenario: Unrecognised flag value renders nothing

- **WHEN** `.caveman-active` contains a value outside the recognised-mode whitelist (including embedded escape sequences)
- **THEN** no badge is rendered and none of the file's bytes are emitted to the terminal

#### Scenario: Oversized or control-laden content is neutralised

- **WHEN** the flag or suffix file contains content longer than the read cap or containing control or escape bytes
- **THEN** the read is truncated to the cap and stripped to the safe character set before any rendering, so no control or escape byte reaches the terminal

### Requirement: Optional savings suffix beside the badge

The statusline SHALL append the sanitised caveman savings token after the badge, in the badge
colour, when the badge renders and the savings file `.caveman-statusline-suffix` is present, is
not a symbolic link, and the savings readout is not opted out. When the suffix file is absent the
statusline SHALL render the badge alone, without error.

#### Scenario: Suffix appended when present

- **WHEN** the badge renders and `.caveman-statusline-suffix` holds a sanitised savings token
- **THEN** the line ends with the badge followed by the savings token — for example `[CAVEMAN] ~38% saved`

#### Scenario: Badge renders alone when the suffix file is absent

- **WHEN** the badge renders and `.caveman-statusline-suffix` does not exist
- **THEN** only the `[CAVEMAN]` badge is rendered and no error occurs

### Requirement: Opt-out via environment variables

The badge segment SHALL be suppressible without uninstalling anything. Setting
`STATUSLINE_CAVEMAN=0` SHALL suppress the entire caveman segment (badge and savings). Setting
`CAVEMAN_STATUSLINE_SAVINGS=0` SHALL suppress only the savings suffix while leaving the badge,
mirroring the caveman plugin's own knob so a user's existing setting carries over. Any value
other than `0`, or an unset variable, SHALL leave the corresponding output enabled (default
on).

#### Scenario: Whole segment suppressed

- **WHEN** `STATUSLINE_CAVEMAN=0` is set and the caveman flag is active
- **THEN** neither the badge nor the savings suffix is rendered, and the rest of the statusline is unchanged

#### Scenario: Savings suppressed but badge kept

- **WHEN** `CAVEMAN_STATUSLINE_SAVINGS=0` is set and the caveman flag is active
- **THEN** the `[CAVEMAN]` badge renders but the savings suffix is omitted

### Requirement: Fail-soft when caveman is absent

The statusline SHALL render exactly as it did before this capability existed — no badge, no
extra output, and no error — when the caveman flag file is absent, which is the common case
because the caveman plugin is in a separate marketplace and is neither required nor installed by
this one. The badge segment SHALL add no `jq` invocation, preserving the script's single-`jq`
performance budget; it SHALL use plain-bash file reads only.

#### Scenario: No flag file renders the pre-existing output

- **WHEN** `.caveman-active` does not exist under the resolved config directory
- **THEN** the statusline output is byte-identical to its output before this capability, with no badge segment and no error

#### Scenario: Badge path adds no jq parse

- **WHEN** the badge segment is evaluated, whether or not the flag is present
- **THEN** it performs no `jq` invocation, reading any caveman state with plain-bash file operations
