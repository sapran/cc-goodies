## ADDED Requirements

### Requirement: A push is judged against its effective destination branch

git-guard SHALL block a `git push` whose **effective destination** is a protected branch,
where the effective destination is the branch the push would update on the remote — not
merely the branch name appearing in the command. Resolution SHALL be best-effort: when the
effective destination cannot be determined, the guard SHALL fall back to allowing the command
(fail-open), consistent with the guard's convenience-not-sandbox stance.

#### Scenario: Explicit `src:dst` to a protected branch is blocked

- **WHEN** the command is `git push origin develop:main` and `main` is protected
- **THEN** the guard blocks it (the destination `dst` is `main`)

#### Scenario: Same-name upstream push to an unprotected branch is allowed

- **WHEN** `develop`'s push routing resolves to `origin/develop`, `develop` is not protected, and the command is `git push`
- **THEN** the guard allows it

#### Scenario: Unresolvable destination falls open

- **WHEN** the command is `git push`, the current branch has no upstream/push configuration, and the effective destination cannot be resolved
- **THEN** the guard allows the command rather than blocking

### Requirement: Destination-less pushes are resolved from git's push configuration

The guard SHALL resolve the destination of a destination-less push from git's push
configuration rather than assuming the destination equals the current branch name. For a push
that names no explicit refspec — the bare `git push`, `git push <remote>`, and the
remote-only forms — it SHALL determine the destination branch from configuration read against
the relevant repository directory (honouring an `-C <dir>` on the command, otherwise the
session cwd): when `push.default` is `upstream` (or its alias `tracking`) the destination is
the basename of the current branch's configured upstream (`branch.<src>.merge`); under the
other `push.default` modes the destination shares the source branch name and is judged as
today. Resolution SHALL read configuration (`push.default`, `branch.<src>.merge`) directly
rather than relying on a materialised remote-tracking ref, so it holds before any fetch. If
the resolved destination is a protected branch, the guard SHALL block.

#### Scenario: Upstream routed to a protected branch is blocked

- **WHEN** `push.default=upstream` and `branch.develop.merge=refs/heads/main`, the current branch is `develop`, and the command is `git push`
- **THEN** the guard resolves the destination to `main` and blocks the push

#### Scenario: Resolution holds without a materialised remote-tracking ref

- **WHEN** the routing configuration above is set but no `refs/remotes/origin/main` tracking ref has been fetched
- **THEN** the guard still resolves the destination to `main` from configuration alone and blocks the push

#### Scenario: Remote-only invocation is resolved, not treated as a target

- **WHEN** `push.default=upstream` with `branch.develop.merge=refs/heads/main`, `origin` is a configured remote, and the command is `git push origin`
- **THEN** the guard recognises `origin` as the remote (not a refspec), resolves the destination to `main`, and blocks

#### Scenario: A same-name upstream is allowed

- **WHEN** `push.default=upstream` and `branch.develop.merge=refs/heads/develop`, the current branch is `develop` (not protected), and the command is `git push`
- **THEN** the guard resolves the destination to `develop` and allows the push

#### Scenario: A push that git itself would refuse is not blocked

- **WHEN** `push.default=simple` and `branch.develop.merge=refs/heads/main` (a name mismatch git refuses to push), and the command is `git push`
- **THEN** the guard does not block, because git will refuse the push before it can reach a protected branch

#### Scenario: An explicit refspec overrides configured routing

- **WHEN** `push.default=upstream` routes `develop` to `main`, but the command names an explicit refspec, e.g. `git push origin develop`
- **THEN** the guard judges the explicit refspec (`develop`, allowed) and ignores the configured routing, matching git's own precedence

#### Scenario: Resolution is scoped to the targeted repository

- **WHEN** the command is `git -C /path/to/repo push` and that repo's push configuration resolves the current branch to a protected branch
- **THEN** the guard resolves the destination against `/path/to/repo` (not the session cwd) and blocks

### Requirement: Configured `remote.<remote>.push` refspecs are honoured

When a push's destination is not expressed on the command line, the guard SHALL also consider
the resolved remote's configured `remote.<remote>.push` refspecs. For each such refspec the
guard SHALL extract its destination (`src:dst → dst`, otherwise the refspec itself), and
SHALL block when any destination is a protected branch. This consideration SHALL be
best-effort: when the remote cannot be determined or its configuration cannot be read, the
guard SHALL fall open.

#### Scenario: Explicit push refspec to a protected branch is blocked

- **WHEN** `remote.origin.push=refs/heads/develop:refs/heads/main`, `main` is protected, and the command is `git push origin`
- **THEN** the guard extracts the refspec destination `main` and blocks the push

#### Scenario: Unreadable remote configuration falls open

- **WHEN** the resolved remote's push configuration cannot be determined
- **THEN** the guard does not block on that basis (it falls open)

### Requirement: Every positional refspec is judged, not only the last

When a push command carries more than one positional refspec, the guard SHALL evaluate the
resolved destination of **each** refspec and block if any one resolves to a protected branch,
rather than evaluating only the last positional token.

#### Scenario: A protected target among multiple refspecs is blocked

- **WHEN** the command is `git push origin main develop` and `main` is protected
- **THEN** the guard blocks the push because one of the refspecs targets `main`, even though it is not the last token

#### Scenario: All-unprotected multi-refspec push is allowed

- **WHEN** the command is `git push origin develop feature-x` and neither target is protected
- **THEN** the guard allows the push
