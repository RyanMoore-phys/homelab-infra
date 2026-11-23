# Postmortems

Write-ups of things that went wrong in this lab: what happened, how it was
found, why it happened and what changed because of it. They are blameless:
they describe systems and decisions, not people, and every time in them comes
from a record (GitHub's run history, package logs, container and file
timestamps) unless it says it is an estimate.

| ID | Incident | Date | Severity | Status |
|---|---|---|---|---|
| [PM-001](pm-001-runner-reachable-from-pull-requests.md) | A pull request could have run code on the self-hosted runner | 2026-11-22 | High (no use found) | Fixed |
| [PM-002](pm-002-nodes-running-an-old-kernel.md) | Three nodes ran a kernel three security updates old for 45 days | 2026-11-23 | Medium | Fixed in code; first reboots due 2026-11-29 |
| [PM-003](pm-003-ci-blocked-by-actions-permissions.md) | CI and deploys could not start for 21 h 36 min | 2026-11-22 | Low | Fixed |
| [PM-004](pm-004-monitoring-exposed-past-the-firewall.md) | Grafana and an unauthenticated Prometheus reachable although the firewall denied them | 2026-11-21 | Medium (no use found) | Fixed |

**Severity:** *High*: a path to control of the lab. *Medium*: exposure of data
or a known vulnerability left unpatched. *Low*: the lab or its pipeline was
degraded, nothing exposed.

## Template

```markdown
# PM-NNN: <what happened, in one line>

**Date:** · **Severity:** · **Status:** · **Duration:**

## Summary
Two or three sentences: what broke or was exposed, for how long, and the fix.

## Impact
What actually happened, and what could have happened. Say so when there is
no evidence either way.

## Timeline (UTC)
| Time | Event |
|---|---|

## Detection
How it was found, how long after it started, and what should have found it.

## Root cause
The mechanism, then the decisions or gaps that let it happen
(contributing factors).

## What went well
## What went badly

## Action items
| Action | Status | Where |
|---|---|---|

## Lessons
```
