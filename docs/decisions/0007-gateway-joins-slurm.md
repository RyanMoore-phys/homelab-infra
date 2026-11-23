# ADR-0007: The gateway joins Slurm as an uncapped compute node with its GPU

**Status:** Accepted · 2026-11-21 (owner)

## Context
The three lab nodes are 4-CPU, 6 GB machines. The gateway has 12
threads, 15 GB of memory, a fast NVMe disk and the lab's only GPU, and it also
runs a GPU training workload outside Slurm. The owner asked for CPU work to be divided
across all four machines through Slurm, with the gateway **not capped**, and
for the shared-storage export to include the gateway. Earlier campaign runs on
the gateway were killed by the kernel's OOM killer when too much ran at once.

## Decision
* The gateway is a Slurm node with its full size (12 CPUs, `RealMemory=15000`)
  and its GPU as a schedulable resource (`Gres=gpu:rtx5050:1`).
* `MemSpecLimit=2048`: 2 GB is held back for the gateway's own work (routing,
  DNS, Tailscale, exporters), so Slurm jobs can never take the memory the
  boundary host needs to keep the lab online.
* No cluster-wide per-job memory cap (`MaxMemPerNode` empty); a job on a 6 GB
  node is still bounded by that node's `RealMemory`.
* Every Slurm job is fenced by cgroups (`ConstrainRAMSpace`, no swap): a job
  that outgrows its request is killed alone and cannot take another process's
  memory.
* Only the controller may reach the gateway's slurmd (port 6818); the gateway
  keeps `firewall_trust_lab: false`. It mounts the NFS share with `nofail`.

## Consequences
* **Two schedulers share the gateway.** The gateway's own training workload is not a Slurm job,
  so Slurm cannot see its memory. Slurm may fill the gateway (up to 13 GB of
  jobs) while a large GPU stage runs, which is the pattern that caused the OOM
  kills. Until that workload is submitted to Slurm itself (then Slurm
  arbitrates the GPU and the memory), drain the gateway before a large GPU or
  real-time stage and resume it after:
  `scontrol update nodename=gateway state=drain reason="gpu stage"` /
  `state=resume`. Jobs already running finish; none start.
* **The boundary host runs batch work.** A job runs with the submitting
  user's rights on the router. Accepted because the lab has one user (the
  owner) and jobs are the owner's own code; revisit before any other user gets
  Slurm access. The munge key now also lives on the gateway.
* **Multi-node steps that span the gateway must start on the controller.**
  Measured with TCP connects from every node: only the controller reaches the
  gateway's slurmd (6818), and nothing reaches its srun ports (60001-60100).
  Single-node jobs (including GPU jobs) and steps launched on node0 work; a
  multi-node step started on node1, node2 or the gateway, or MPI spanning the
  gateway, is blocked. Opening 6818 and the srun range to `lab_cidr` on the
  gateway would lift this, at the cost of more lab → boundary-host access.
* The CI deploy reads its own copy of the inventory on the runner host: update
  it after the inventory change, or a deploy would remove the gateway again.

## Rejected
* **Capping the gateway at 4 CPUs / 6 GB** (proposed first): protects that
  workload but wastes most of the machine; the owner chose no cap.
* **A separate gateway-only partition:** adds a second queue to choose between
  for no gain while one user submits everything.
