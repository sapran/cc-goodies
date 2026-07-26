## MODIFIED Requirements

### Requirement: Context-subtype pool routing

The phrase pools SHALL be selected by the context of the event so that tone fits the
situation. For `Notification`, the cue SHALL be routed by the message subtype: a
permission request, an idle/waiting-for-input prompt, a background agent reporting that it has
completed, a background agent reporting that it needs input, or an unrecognised message
(neutral fallback). Routing SHALL prefer the payload's explicit notification type where one is
provided, falling back to matching the message wording, so that a payload without a type field
still routes correctly. For `Stop`, the cue SHALL be routed by turn length when that
information is available (short vs long).

#### Scenario: Permission request routing

- **WHEN** a `Notification` message indicates Claude needs permission
- **THEN** the cue uses the brisk garnish/core pool and speaks the specific reason in the
  first person (e.g. "Quick one — I need your permission to use Bash")

#### Scenario: Idle/waiting routing

- **WHEN** a `Notification` message indicates Claude is waiting for input
- **THEN** the cue uses the gentle pool (e.g. "Whenever you're ready — I'm waiting for your input")

#### Scenario: Background agent completion routing

- **WHEN** a `Notification` reports that a background agent has finished or failed
- **THEN** the cue announces that agent's completion rather than falling through to the generic
  attention phrase

#### Scenario: Background agent needs-input routing

- **WHEN** a `Notification` reports that a background agent needs input
- **THEN** the cue uses the brisk pool and announces which agent is asking, rather than falling
  through to the generic attention phrase

#### Scenario: Unrecognised message fallback

- **WHEN** a `Notification` message matches no known subtype, or `jq` is unavailable, or
  the message is empty
- **THEN** the cue falls back to a neutral attention phrase (e.g. "Hey — I need your attention")
