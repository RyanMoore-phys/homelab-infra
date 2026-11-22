# ADR-0006: Long-running services are not Slurm jobs

**Status:** Accepted · 2026-11-21

## Context
It was proposed to run every service (Grafana, Prometheus, a game server) as a
containerised Slurm job, so compute would be shared across all nodes.

## Decision
Keep Slurm for batch work (OpenMC simulations) and run services with Docker
Compose on a fixed host.

## Rationale
* Slurm enforces `MaxTime` and kills jobs at the limit; services must not stop.
* Jobs land on any node; services need stable addresses for scrapes, bridges
  and bookmarks.
* With `OverSubscribe=NO`, an idle dashboard job would hold a whole CPU away
  from simulations.
* Pooling does not make one process faster; a game server's main loop runs on
  one thread on one machine.
* Docker inside jobs gives every Slurm user root-equivalent access; HPC sites
  use Apptainer or rootless Podman instead.
* State (game world, TSDB, Grafana database) would need shared storage; a
  game world on NFS performs badly and risks corruption.

## Consequences
* If failover for services is ever needed, the step is an orchestrator
  (Docker Swarm or k3s) with a storage plan, not Slurm.
* Slurm can reserve CPU and memory for services on shared nodes with
  `CoreSpecCount` / `MemSpecLimit`.
