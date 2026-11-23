# Hardening log

## 2026-11-21, part 1: audit and first fixes

Starting point: ufw on every machine, Tailscale on every machine, nothing
forwarded from the internet. The audit was read-only first; every change was
then tested from the allowed and the refused side.

| Finding | Risk | Fix |
|---|---|---|
| Password SSH still on (gateway, two nodes) | Brute force from anything that reaches port 22 | `00-hardening.conf` drop-in; keys only |
| Cloud-init's `50-cloud-init.conf` sets `PasswordAuthentication yes` | Any later drop-in loses to it | sshd keeps the FIRST value it reads, so the drop-in is named `00-` |
| Grafana and Prometheus published as `0.0.0.0` ports | Prometheus (no login) readable from the whole lab and tailnet, despite ufw | Docker ports bypass ufw: explicit binds ([ADR-0003](../decisions/0003-explicit-binds-and-gateway-published-uis.md)) |
| rpcbind, NFS, slurmd reachable from the tailnet | Larger attack surface | ufw denies on `tailscale0` were tried and did nothing: Tailscale's `ts-input` runs first. Accepted while the tailnet holds only the owner's devices; ACLs on the roadmap |
| Lab could open connections to the home network | A compromised node reaches personal devices | Gateway route rule: deny lab → home |
| One automation key opens every node; the CI runner's key gives root on the gateway | A copied key works from anywhere | `from=` limits to each key's real source, taken from 14 days of SSH logs |
| Unknown and stale SSH keys, an unused firewall port | Forgotten access | Removed, with backups |
| Slurm: firewall blocked srun callbacks and node-to-node traffic; one node excluded | Multi-node jobs failed | Lab nodes trust each other; the node returned to the partition |

## 2026-11-21, part 2: gateway first

Goal: every remote session reaches the lab through the gateway
([ADR-0002](../decisions/0002-tailscale-only-ingress.md)).

| Step | Detail | Check |
|---|---|---|
| 1. Map dependencies on node tailnet addresses | live connections, serve configs, config files, cron, timers, CI and bridge settings | only Prometheus scrapes and node1's `tailscale serve` used them |
| 2. Prometheus scrapes over the LAN | two targets moved from tailnet to lab addresses | all 5 targets `up` |
| 3. Web UIs published by the gateway | Grafana and wiki bound to node1's lab address; gateway `tailscale serve` :8443 / :443 | both answer through the gateway |
| 4. SSH to nodes through the gateway | owner's SSH config uses lab addresses (`HostKeyAlias` keeps the trusted host keys) | each node sees sessions from the gateway's address |
| 5. Key limits tightened | `from=` lists reduced to lab addresses only | gateway → nodes and runner → gateway still log in |
| 6. Nodes leave the tailnet | a script that stops `tailscaled` and refuses to run over a tailnet session | **not applied**: on 2026-11-22 the owner kept Tailscale on every node as a fallback; the script was deleted |
| 7. Gateway exception kept | the UDP 41641 exception stays, so nodes keep direct WireGuard paths | encoded in the `router` role |

Found while reading the gateway's live rules: Tailscale's `ts-forward` also
accepts lab → tailnet traffic. Documented as a known gap; the fix is an ACL.

## 2026-11-21, part 3: the gateway joins Slurm

Decision: [ADR-0007](../decisions/0007-gateway-joins-slurm.md). Security-relevant parts:

| Change | Control | Check |
|---|---|---|
| The boundary host runs slurmd | firewall admits 6818 from the controller only; `firewall_trust_lab` stays off on the gateway | TCP connect: controller open; node1, node2 filtered |
| Slurm jobs on the router | `MemSpecLimit=2048`; cgroup memory confinement, no swap | `scontrol show node`: 15000 MB, 2048 held back |
| The munge key on one more machine | copied node to node over SSH, never through a laptop or this repository | `munge -n | unmunge` succeeds |
| The gateway mounts the share | NFS export names it; mounted with `nofail` so a missing share never blocks boot | `/etc/fstab`, `findmnt` |
| sudo-rs on the nodes broke Ansible's become prompt | `ansible_become_exe: sudo.ws` for the lab nodes | `make check-host` reaches every node |

## 2026-11-22: the CI deploy identity

| Change | Control | Check |
|---|---|---|
| A second runner on node1 for this repository | own registration, own work volume, label `homelab` | registered and listening |
| Its SSH key | created on node1, mounted read-only into the container, never uploaded to GitHub | `test -r` in the deploy job |
| Who it logs in as | the owner's admin account, `from=` node1's lab address only | accepted from node1 on 4/4, refused from the gateway |
| Unattended sudo | `sudo_nopasswd` role on the nodes (the gateway already had it), validated with `visudo` | `sudo -n true` and `sudo.ws -n true`: 4/4 |
| Host-key checking in CI | `--ssh-extra-args=` (inventory SSH args override CLI common args); guard rule in `check-workflows.sh` | empty known_hosts refused, real key accepted |
| A pull request could add a workflow that targets the runner | job-started hook on the runner: only `deploy.yml` on main, started by the owner; read-only and root-owned in the container | 11 cases: 1 allowed, 10 refused |
| Private CI files in GitHub | none: key, inventory and known_hosts mounted read-only from node1; the environment secrets were never created | deploy job checks they are readable |
| The runner could not log in to node1, its own host | the container reaches node1 from its Docker bridge address, so node1 also accepts the CI key from its own Docker networks (`ci_runner_from`, node1 only) | check mode from the container: 4/4 reached |

## 2026-11-23: patching gaps

Decision: [ADR-0008](../decisions/0008-unattended-patching-and-drained-reboots.md); how it works: [patching](../patching.md).

| Finding | Risk | Fix |
|---|---|---|
| The three nodes up 54 days, three kernel updates behind (two with a libc update too) | Patched packages on disk, unpatched kernel in memory | Weekly drained reboot through Slurm (`scontrol reboot ASAP nextstate=RESUME`), after running jobs; `RebootProgram`, `ResumeTimeout=600` |
| Tailscale never updated itself on any machine; skybot's Docker CE neither | The program carrying every remote session stays on old versions | Their repositories added to unattended-upgrades (`Origins-Pattern`) |
| Monitoring containers pinned to versions nothing watched | Known vulnerabilities in Grafana or Prometheus go unnoticed | Dependabot on the monitoring stack's images, patch and minor versions |
| No single view of what each machine still needs | Pending reboots and held packages found by accident | `make patch-status`, read-only |

## Traps worth knowing

1. **Docker publishes around ufw.** Bind every published port to an address.
2. **Tailscale accepts on `tailscale0` before ufw**, for input and forwarding.
   Control tailnet access with ACLs, or keep Tailscale off hosts whose
   firewall must decide.
3. **sshd: first value wins**, so a drop-in that must win needs a low number.
4. **Actions logs of a public repo are public.** Values from a `.env` or an
   inventory are not masked unless you mask them.
5. **NFS v4.2 clients do not need rpcbind**; only the server's port 2049 matters.
6. **Move dependencies before removing a path**, and make the change script
   refuse to run over the path it removes.
7. **Ubuntu 26.04 ships sudo-rs as `sudo`**, which does not honour Ansible's
   prompt option; point `ansible_become_exe` at the classic `sudo.ws`.
