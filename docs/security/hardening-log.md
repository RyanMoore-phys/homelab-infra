# Hardening log

The incidents behind several entries are written up as blameless
[postmortems](../postmortems/README.md), with timelines taken from the records.

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

## 2026-11-23: grounding pass

Every statement in the README and the diagrams was checked against the live
machines ([verification](../verification.md#grounding-pass-2026-11-23)). The
documentation was corrected where it was wrong. Found on the machines, and
fixed the same day:

| Finding | Risk | Fix |
|---|---|---|
| A second root key on the gateway, without `from=`, unused for 30 days | A copy of it opens root on the router from anywhere that reaches SSH | Key files are now exclusive (`authorized_keys_exclusive`): a key not in the inventory is removed. A guard stops the role unless the admin account keeps the owner's key; it caught a quoting mistake in the inventory before anything was written |
| The lab's `MASQUERADE` rule seven times in `POSTROUTING` | None today (the first match wins), but the table grows with every firewall reload | The rule was hand-written into ufw's `before.rules`, which ufw re-applies without flushing. NAT now lives in its own nftables table (`homelab_nat`), loaded by `homelab-nat.service`, masquerading only the lab range; the old copies were deleted and stay at 0 across reloads |
| Leftover firewall rules: node2 allows DHCP, TFTP, HTTP, DNS and HTTPS from anywhere; malformed address rules on node0-2 | Any service later started on those ports is open beyond the lab | `firewall_rules_absent` retires exact rules: 41 removed across the three nodes. Kept on purpose: node1's SSH from anywhere, which the runner container needs to reach its own host |

## 2026-11-23: one exporter per machine

| Finding | Risk | Fix |
|---|---|---|
| Three hand-made node exporters: a binary on the gateway, containers on node0 and node2, plus one in node1's monitoring stack | No updates; each set up differently; nothing recorded how | Ubuntu's packaged exporter on every machine, on the lab address, with security updates through unattended-upgrades (`node_exporter` role) |
| `group_vars/all.yml` sat at the repository root, where Ansible never reads it | Shared settings silently ignored; it only worked because the SSH role's defaults matched | Moved to `playbooks/group_vars/`, which every inventory loads |
| node1's live monitoring stack had drifted from the training repository: Prometheus kept 15 days instead of 120, and scraped by address, so the dashboards' `main:9100` filters matched nothing | History lost after two weeks; dashboard panels empty | Retention restored to 120 days with a 20 GB cap; targets generated from the inventory and named after the machines; the same edits made in the training repository |
| Scraping node1's own exporter from the Prometheus container | Arrives from the Docker bridge, which node1's firewall refused | node1 admits 9100 from Docker's networks only (same reasoning as the runner's key) |

## 2026-11-23/24: alerting

| Finding | Risk | Fix |
|---|---|---|
| Nothing watched the metrics: every failure in the postmortems was found by a person | Outages, full disks and stuck patching go unnoticed for days | 13 alert rules in the repository, each unit-tested in CI; Alertmanager on node1; ntfy on the gateway; a watchdog for the monitoring itself ([ADR-0009](../decisions/0009-alerting-through-self-hosted-ntfy.md)) |
| apt installed Ubuntu Pro's ntfy 2.11 instead of ntfy's own 2.38.1: the ESM Apps source is pinned at priority 510, above every other repository | The first live alert reached the phone as raw JSON: 2.11 has no `alertmanager` template | `/etc/apt/preferences.d/ntfy` pins ntfy's repository for that one package; the role checks the installed version against the one that was tested |
| ntfy's own package runs as `ntfy`, Ubuntu's as `_ntfy`, and neither package makes the data directories that ntfy needs before its first start | The service fails at start, or the new build cannot open the old databases | The role makes the account and directories and owns the databases before the package installs |
| `get_url` reported a change in every check-mode run for a key file that was already in place (ansible-core 2.21 fetches it again and, in check mode, compares against nothing) | A drift check that never reads `changed=0` hides real drift | The key file's SHA-256 is pinned; an existing, matching key is not fetched at all |
| The owner's ntfy login had no password, so the phone app reported "not authorized to read this topic" | No alerts on the phone, with the server working | Runbook: the login is made and its password typed by the owner (`ntfy user add`), with read access to the alert topic only |

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
8. **Ubuntu Pro's ESM sources outrank every other repository** (apt priority
   510). A package that also comes from its vendor's repository installs from
   ESM, often years older, unless that repository is pinned higher.
9. **`get_url` reports a change in check mode** for a file already in place,
   unless it is given the file's checksum.
