# Verification

Every control has a test that would fail if the control broke, run from both
sides where possible: the path that must work, and the path that must be
refused. Last full run: 2026-11-22.

## Configuration matches the code

| Test | Command | Expected | Result |
|---|---|---|---|
| Every machine matches the roles (incl. Slurm, GPU, patching) | check mode, all hosts, after the deploy `apply` of 2026-11-23 | `changed=0` | `changed=0` on 4/4 (gateway 31 ok, nodes 21-25 ok) |
| Ansible reaches nodes through the gateway | `ansible lab_nodes -m ping -e ansible_become=false` | `pong`, client address = gateway | pass, 3/3 |
| Patching change (ADR-0008), before apply | `make check`, all hosts | gateway: origins file, `slurm.conf`; nodes: also the reboot script and timer | as expected on 4/4, 0 failed (each node also shows the pending 41641/udp rule) |

## Patching

| Control | Test | Result |
|---|---|---|
| Outside repositories update unattended | the rendered origins file parses (`apt-config -c`), and unattended-upgrades' own matcher, run on node2, allows Tailscale's next version | pass |
| Drained reboot asks only when it should | the reboot script against node2's real `scontrol` output, with a stand-in that prints instead of acting: idle and busy → reboot requested after jobs; drained, down, already requested → left alone; unknown node → refused | pass, 6/6 |
| Runners survive a reboot | on a copy of the homelab runner, the shutdown de-register fails without a valid token and leaves `.runner` and `.credentials` in place | pass |
| Status report | `make patch-status` | pass: the three nodes show the waiting reboot and an enabled timer; the gateway shows none |
| First drained reboots | the three nodes (kernel three updates behind) reboot through Slurm and return to service | pending: on the first weekly run, or started by hand |

## Grounding pass, 2026-11-23

Every factual statement in the README and the nine diagrams was checked
against the code, this page, read-only reads of the four machines (`ss`,
`ufw status`, `iptables -S`, `docker ps`, `systemctl`, `exportfs`, `findmnt`,
`sshd -T`, `scontrol`, Prometheus' target list, `authorized_keys` options
and 30 days of root logins) and the GitHub API.

| Claim | Found | Now |
|---|---|---|
| Packet path through the gateway | jump order, `ts-input`, `ts-forward`, NAT match the diagram | unchanged |
| Slurm: four nodes, gateway 12 CPUs + GPU, 2 GB held back, cgroup v2, no swap | matches `scontrol` | unchanged |
| Prometheus: five targets every 10 s | 4 node exporters + GPU exporter, all up | unchanged |
| Grafana requires a login | `401` without one; sign-up off | unchanged |
| Deploy needs the owner's approval | environment `homelab`: required reviewers, branch policy | unchanged |
| Ansible badge 2.19 | 2.21.6 pinned | corrected |
| "Every host setting is an Ansible role" | Docker stacks, NFS client mounts, runners, game server are set up by hand | corrected; listed under Maintenance |
| node1 runs "a CI runner" | two runners, plus a wiki behind Caddy | corrected |
| node0 runs a game server | unit installed and enabled, not running | corrected |
| NFS share `/srv/data`; only the gateway mounts with `nofail` | `/srv/openmc`; all three clients use `nofail` | corrected |
| Port matrix complete | missing: the gateway's control service (8765, tailnet only), rpcbind (111), node0's game-server rule | rows added |
| Every automation key pinned with `from=` | the gateway's root has a second key without `from=`, unused for 30 days | **fixed** the same day: key files are exclusive, the key is gone |
| One NAT rule for the lab | the same `MASQUERADE` rule seven times in `POSTROUTING` (each reload appends a copy; the first match wins, so traffic is unaffected) | **fixed** the same day: NAT moved to its own nftables table |
| Firewalls hold only the roles' rules | node2 still allows DHCP, TFTP, HTTP, DNS and HTTPS from anywhere, and node0-2 carry a few malformed address rules; nothing listens on those ports | **fixed** the same day: 41 rules retired through the firewall role |
| `main` requires the `ci` checks | `main` is protected, with no required status checks | **open**: owner setting |
| ISP router: no port forwards, UPnP off | not readable from the lab | **open**: owner checks the router's admin page |

### Fixes applied, 2026-11-23

| Control | Allowed path (must work) | Refused or removed (must be gone) | Result |
|---|---|---|---|
| Exclusive key files | owner key on 4/4; CI key from the runner container with `sudo -n` on 4/4; the runner's root key from node1 | the unpinned root key: no longer in the gateway's root `authorized_keys`; a role run without the owner key in the inventory stops before writing (it did, once, on a quoting mistake) | pass |
| NAT in its own table | from node2: HTTPS 200, the security mirror 3/3, `apt-get update` with 0 errors | `MASQUERADE` copies in iptables: 0, and still 0 after two `ufw reload`s; Tailscale's own NAT rule kept | pass |
| Retired firewall rules | NFS readable on all three clients; a three-node `srun`; 5/5 Prometheus targets up; Grafana healthy | node0 12, node1 12, node2 17 rules gone; each node now holds only tailnet, SSH, lab trust and 41641/udp | pass |
| Code matches the machines | check mode, all hosts | | `changed=0` on 4/4 |

## Access

| Control | Allowed path (must work) | Refused path (must fail) | Result |
|---|---|---|---|
| Keys only | `ssh admin@<host>` with the owner key | `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password admin@<host>` → `Permission denied (publickey)` | pass, 4/4 hosts |
| Through the gateway first | `ssh <node>` by lab address; `echo $SSH_CONNECTION` shows the gateway's lab address as client | | pass, 3/3 |
| Fallback path | SSH to a node's own tailnet address reaches it directly, without the gateway | | pass, 3/3 |
| `from=` on automation keys | gateway → nodes; runner → gateway root | gateway key from an unlisted source (`ssh -b <ipv6 link-local>`) → refused | pass |
| X11 off | `ssh -X <host> 'echo $DISPLAY'` prints nothing | | pass |
| CI runner key | from the runner container on node1: logs in on all four machines (node1 itself from its Docker network) | the same key from the gateway → `Permission denied (publickey)` | pass, 4/4 · refused: pass |
| Unattended sudo for CI | `sudo -n true` and `sudo.ws -n true` as the admin account on every machine | | pass, 4/4 |
| Runner job hook | the owner's manual `deploy.yml` on main → allowed | pull request event, another branch, another workflow file, `deploy.yml` from a pull request's merge ref, another actor or re-runner, another repository, no variables → refused | pass, 11/11 locally; allowed and refused cases also inside the container; first live run pending |
| CI deploy rehearsal | the job's steps inside the runner container: setup-python's 3.12 build, pinned Ansible, mounted key, inventory and known_hosts, strict host keys, check mode, all hosts | | exit 0; 4/4 reached |
| Owner key passphrase | | `ssh-keygen -y -P "" -f ~/.ssh/id_ed25519` fails (a passphrase is required) | pass |

## Network

| Control | Allowed path | Refused path | Result |
|---|---|---|---|
| No inbound from the internet | | ISP router: no port forwards, UPnP off (admin page); gateway's upstream interface accepts only 41641/udp | gateway: pass · router: manual check |
| Lab → home blocked | node → internet (HTTPS 200), DNS resolves | node → home router `:80` | pass (one narrow exception: UDP from port 41641, for Tailscale) |
| UIs via the gateway only | Grafana `https://<gateway>.<tailnet>.ts.net:8443/api/health` → 200; wiki on `:443` → 200 | Prometheus `:9090` from any other host → refused | pass |
| Scrapes over the LAN | Prometheus targets page: all `up` | | pass, 5/5 |
| NFS scoped | node1, node2 and the gateway mount `/srv/openmc` (NFS 4.2, `hard`, `nofail` on all three) | `exportfs -v` lists only those three clients, each `root_squash` | pass (2026-11-23) |

## Cluster

| Check | Command | Expected | Result |
|---|---|---|---|
| Identical config | `md5sum /etc/slurm/slurm.conf` on every node | same hash | pass, 4/4 |
| Nodes in service | `sinfo -N -o "%N %T %c %m %G"` | four nodes, none `down` or `drain`; gateway `12 15000 gpu:rtx5050:1` | pass |
| Memory kept for routing | `scontrol show node gateway` | `RealMemory=15000 MemSpecLimit=2048` | pass |
| munge across machines | `munge -n` on the controller, `unmunge` on the gateway | `STATUS: Success (0)` | pass |
| Gateway slurmd reachable only from the controller | TCP connect to the gateway's 6818 and 60001 from every node | controller: 6818 open; node1, node2: filtered; 60001 filtered from all | pass |
| Multi-node job | `srun -N4 hostname` on node0 | four host names | to run (cluster was busy) |
| Slurm job board | node1 crontab has the `slurm_board` line; push log is current | last push within minutes | pass |

## The repository itself

| Guard | Falsifier | Result |
|---|---|---|
| `scripts/check-private-data.sh` | plant the real inventory as a tracked file | caught addresses, tailnet IPs, email, 3 keys; exit 1 |
| `scripts/check-workflows.sh` | plant a workflow with `pull_request` + `runs-on: self-hosted` | refused on both rules; exit 1 |
| gitleaks / detect-secrets | full scan | no secrets (one false positive: a line naming the secret variables) |
| ansible-lint | `make lint` | production profile passes |
| Diagrams | render all 9 Mermaid blocks (Mermaid 11) in GitHub's light and dark themes; inspect for crossings and overlaps | all render; checked in both themes |
