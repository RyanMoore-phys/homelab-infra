# PM-002: Three nodes ran a kernel three security updates old for 45 days

**Date:** found 2026-11-23 · **Severity:** Medium · **Status:** Fixed in code;
first reboots due 2026-11-29 · **Duration:** 45 days and counting

## Summary
unattended-upgrades installed every kernel and libc security update on the
three nodes, but nothing rebooted them, so the fixes never ran. They had
been up since 2026-09-30 on kernel 7.0.0-34 while -38, -42 and -43 sat on disk.
The nodes now reboot themselves through Slurm, after their running jobs, when
an update needs it.

## Impact
* The kernel fixes in three updates, and on node1 and node2 a libc fix, were
  installed but not in effect for up to 45 days.
* No evidence of exploitation. The nodes are reachable only from the lab and
  the owner's tailnet.

## Timeline (UTC)
Taken from node2's package log; node0 and node1 match within minutes.

| Time | Event |
|---|---|
| 2026-09-25 06:51 | Kernel 7.0.0-34 installed |
| 2026-09-30 05:19 | All three nodes boot (onto -34) |
| 2026-10-09 06:46 | Kernel -38 installed by unattended-upgrades: from here, a fix is on disk but not running |
| 2026-11-03 06:32 | Kernel -42 installed |
| 2026-11-12 06:11 | Kernel -43 installed |
| 2026-11-14 | libc6 security update installed (node1, node2) |
| 2026-11-23 | Survey for "what keeps each machine up to date" finds the pending reboots |
| 2026-11-23 | Drained-reboot timers, `RebootProgram` and `make patch-status` deployed ([ADR-0008](../decisions/0008-unattended-patching-and-drained-reboots.md)) |
| 2026-11-29 04:57-05:34 | First weekly checks; each node drains and reboots after its jobs |

## Detection
45 days late, by a person asking the right question during an unrelated
review. Every node had `/var/run/reboot-required` the whole time, but nothing
read it or showed it.

## Root cause
Ubuntu's unattended-upgrades installs updates but leaves rebooting to the
administrator (`Automatic-Reboot` is off by default). Turning it on was not an
option here: a reboot at a fixed time would kill Slurm jobs. So no one decided
how reboots should happen, and nothing measured that they did.

Contributing factors:
* **No view of patch state across machines.**
* **Alerting does not exist yet,** so nothing reports an overdue reboot.

## What went well
* The updates themselves were installed promptly every time.
* The fix fits the cluster: Slurm already knows what runs where, so "reboot as
  soon as possible" never kills a job.

## What went badly
* "Unattended upgrades: on" was recorded as patching done.
* 45 days passed with the evidence on disk on every node.

## Action items
| Action | Status | Where |
|---|---|---|
| Weekly drained reboot through Slurm on the nodes; the gateway's reboots stay the owner's | Done | [ADR-0008](../decisions/0008-unattended-patching-and-drained-reboots.md), [patching](../patching.md) |
| `make patch-status`: reboots, pending and held updates on every machine | Done | [patching](../patching.md) |
| Confirm the first drained reboots, timed, in verification | Due 2026-11-29 | [verification](../verification.md) |
| RebootOverdue alert after 8 days | Planned (alerting) | Plan phase 3 |

## Lessons
* Installed is not running. Patching ends when the new code runs.
* Every automatic process needs a measurement that shows it is working.
