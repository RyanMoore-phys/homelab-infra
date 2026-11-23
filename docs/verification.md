# Verification

Every control has a test that would fail if the control broke, run from both
sides where possible: the path that must work, and the path that must be
refused. Last full run: 2026-11-22.

## Configuration matches the code

| Test | Command | Expected | Result |
|---|---|---|---|
| Gateway matches the roles (incl. Slurm, GPU) | `make check LIMIT=gateway` | `changed=0` | 27 ok, `changed=0` |
| Nodes match the roles | the deploy job's steps inside the runner container, check mode, all hosts | `changed=0` | each node `changed=1`: the Tailscale port rule (41641/udp) the code now sets on every machine; added by the first `apply` |
| Ansible reaches nodes through the gateway | `ansible lab_nodes -m ping -e ansible_become=false` | `pong`, client address = gateway | pass, 3/3 |
| Patching change (ADR-0008), before apply | `make check`, all hosts | gateway: origins file, `slurm.conf`; nodes: also the reboot script and timer | as expected on 4/4, 0 failed (each node also shows the pending 41641/udp rule) |

## Patching

| Control | Test | Result |
|---|---|---|
| Outside repositories update unattended | the rendered origins file parses (`apt-config -c`), and unattended-upgrades' own matcher, run on node2, allows Tailscale's next version | pass |
| Drained reboot asks only when it should | the reboot script against node2's real `scontrol` output, with a stand-in that prints instead of acting: idle and busy → reboot requested after jobs; drained, down, already requested → left alone; unknown node → refused | pass, 6/6 |
| Runners survive a reboot | on a copy of the homelab runner, the shutdown de-register fails without a valid token and leaves `.runner` and `.credentials` in place | pass |
| Status report | `make patch-status` | to run after apply |
| First drained reboots | the three nodes (kernel three updates behind) reboot through Slurm and return to service | pending: after apply, on the first weekly run or by hand |

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
| NFS scoped | node1, node2 and the gateway mount `/srv/data` (the gateway with `nofail`) | exports list only those three clients | pass |

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
