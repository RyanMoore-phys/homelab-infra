# Verification

Every control has a test that would fail if the control broke, run from both
sides where possible: the path that must work, and the path that must be
refused. Last full run: 2026-11-22.

## Configuration matches the code

| Test | Command | Expected | Result |
|---|---|---|---|
| Gateway matches the roles (incl. Slurm, GPU) | `make check LIMIT=gateway` | `changed=0` | 27 ok, `changed=0` |
| Nodes match the roles | `make check-host HOST=<node>` (asks for that node's sudo password) | `changed=0` | to run by the owner |
| Ansible reaches nodes through the gateway | `ansible lab_nodes -m ping -e ansible_become=false` | `pong`, client address = gateway | pass, 3/3 |

## Access

| Control | Allowed path (must work) | Refused path (must fail) | Result |
|---|---|---|---|
| Keys only | `ssh admin@<host>` with the owner key | `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password admin@<host>` → `Permission denied (publickey)` | pass, 4/4 hosts |
| Through the gateway first | `ssh <node>` by lab address; `echo $SSH_CONNECTION` shows the gateway's lab address as client | | pass, 3/3 |
| Fallback path | SSH to a node's own tailnet address reaches it directly, without the gateway | | pass, 3/3 |
| `from=` on automation keys | gateway → nodes; runner → gateway root | gateway key from an unlisted source (`ssh -b <ipv6 link-local>`) → refused | pass |
| X11 off | `ssh -X <host> 'echo $DISPLAY'` prints nothing | | pass |
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
