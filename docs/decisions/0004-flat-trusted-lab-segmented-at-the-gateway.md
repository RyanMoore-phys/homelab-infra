# ADR-0004: Lab nodes trust each other; segmentation is enforced at the gateway

**Status:** Accepted · 2026-11-21

## Context
NFS, Slurm (6817/6818), srun callbacks (`SrunPortRange`) and MPI between
nodes need many ports between the compute nodes. Per-port host rules were
blocking srun callbacks and node-to-node traffic. Meanwhile the lab could open
connections to the owner's personal devices on the home network.

## Decision
* On every lab node: allow everything from the lab subnet on the lab
  interface; keep default-deny for everything else.
* On the gateway: forward lab traffic to the internet, but deny new
  connections from the lab to the home network, with one narrow exception:
  UDP from Tailscale's port 41641, so the nodes (which also run Tailscale,
  ADR-0002) keep direct WireGuard paths to tailnet devices on the home network.

## Consequences
* A compromised node can reach the other nodes. Accepted: they share data
  and a scheduler, so they share a trust zone.
* A compromised node cannot reach devices on the home network. Verified from
  a node: home router refused; internet and DNS still work.
* ICMP echo still crosses (ufw's default forward rules); acceptable.
* It **can** still open connections to the owner's devices over the tailnet:
  Tailscale's `ts-forward` accepts traffic leaving through `tailscale0` before
  ufw runs. Closed by a Tailscale ACL that does not grant the lab subnet access
  to devices (roadmap).

## Alternatives considered
* **Per-port allow lists between nodes:** brittle with MPI's dynamic ports.
* **VLANs on a managed switch:** the right next step for more trust zones;
  not needed for one zone.
