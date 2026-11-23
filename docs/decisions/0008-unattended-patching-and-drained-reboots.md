# ADR-0008: Unattended patching, with reboots drained through Slurm

**Status:** Accepted · 2026-11-23

## Context
unattended-upgrades ran on every machine, with Ubuntu's stock settings: the
security pocket only, and no reboots. A survey on 2026-11-23 found:

* the three nodes had been up for 54 days, running a kernel three security
  updates old (two of them also with a libc update waiting);
* Tailscale, the program that carries every remote session, had never updated
  itself on any machine, and skybot's Docker CE was in the same position,
  because their repositories are outside Ubuntu's;
* the monitoring containers on node1 were pinned to versions nothing watched.

## Decision
* unattended-upgrades also installs updates from the Tailscale and Docker CE
  repositories (`auto_updates_extra_origins`).
* The nodes reboot themselves when an update needs it, through Slurm: a weekly
  timer asks `scontrol reboot ASAP nextstate=RESUME`, so a node is rebooted
  only after its running jobs end, and returns to service afterwards. A node
  someone drained on purpose is left alone.
* The gateway never reboots itself; `make patch-status` shows when it needs to.
* Dependabot watches the monitoring stack's images (patch and minor versions).

## Rationale
* Patching the packages without rebooting left the kernel unpatched for weeks:
  the reboot is the part that needs automating.
* Slurm already knows which jobs run where. Asking it to reboot "as soon as
  possible" keeps the one promise that matters on a compute node (running jobs
  finish) without a separate scheduler.
* The gateway routes the lab and runs real-time training outside Slurm, so a
  drain cannot protect its work; its owner chooses the moment.

## Rejected
* **`Unattended-Upgrade::Automatic-Reboot`** at a fixed time: kills any Slurm
  job running at that moment.
* **Canonical Livepatch**: needs Ubuntu Pro, covers only some kernel fixes,
  and libc still needs a reboot.
* **kured**: the same idea, but it drains Kubernetes nodes, not Slurm nodes.
* **Rebooting by hand**: what produced 54 days of uptime and three kernels.
* **Auto-updating the deadsnakes Python on the gateway**: it is the training
  interpreter, changed only between runs.

## Consequences
* `slurm.conf` gains `RebootProgram` and `ResumeTimeout=600`; Slurm's default
  of 60 s would mark a rebooting node down.
* A draining node takes no new jobs until its longest job ends, up to
  `MaxTime` (7 days).
* Services on the nodes are not drained: node1's dashboards and runners, and
  skybot's NFS share and Slurm controller, are briefly unavailable during
  their machine's reboot.
* A Tailscale update restarts `tailscaled`, which drops remote sessions for a
  few seconds; on the gateway that includes the subnet route.
