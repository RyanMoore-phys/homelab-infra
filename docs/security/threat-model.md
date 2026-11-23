# Threat model

## Assets

The owner's personal devices, the lab's data (shared simulation data on
NFS), the hosts themselves, and the credentials that reach them: the owner's
SSH key, the automation keys, and the GitHub and Tailscale accounts.

## Protected against

| Threat | Control |
|---|---|
| Scanning and brute force from the internet | Nothing listens on the internet: no port forwards, UPnP off; SSH is keys only |
| Losing remote access when one machine fails | Remote traffic goes through the gateway first; each node's own tailnet address is a fallback ([ADR-0002](../decisions/0002-tailscale-only-ingress.md)) |
| A stolen automation key | `from=` limits: each key works only from the one lab address that uses it |
| Password guessing on SSH | Password and keyboard-interactive login are off on every machine |
| A compromised lab machine attacking the home network | The gateway drops new lab → home connections |
| Unauthenticated dashboards (Prometheus has no login) | Bound to localhost; Grafana (login) published by the gateway over HTTPS |
| A pull request running code on the self-hosted runner | The runner's job-started hook refuses every job except the owner's manual `deploy.yml` on main, including workflows a pull request adds; fork pull requests wait for approval; CI keeps this repository's self-hosted workflows dispatch-only |
| Secrets or addresses leaking through this public repo | Gitignored inventory, nothing private in GitHub (the runner's key and inventory are mounted on node1), gitleaks over full history, a private-data guard, masked deploy logs |
| Unpatched packages | Unattended security upgrades everywhere |
| A lab node reaching the boundary host's Slurm daemon | The gateway admits slurmd traffic from the controller only |
| A runaway Slurm job starving the router | `MemSpecLimit` keeps 2 GB for the gateway's own work; cgroups kill a job that outgrows its request |

## Accepted, knowingly

| Risk | Why accepted | What would close it |
|---|---|---|
| Lab machines trust each other completely | NFS, Slurm and MPI need many dynamic ports | VLANs / more trust zones |
| The lab can open connections to tailnet devices | Tailscale's `ts-forward` accepts them before ufw | Tailscale ACL (roadmap) |
| Tailnet devices reach every lab port through the subnet route | the tailnet holds only the owner's devices | ACL limiting the route to SSH and HTTPS (roadmap) |
| Each node is also directly reachable over the tailnet, and its firewall does not filter that traffic | the tailnet holds only the owner's devices; it keeps access when the gateway is down | Tailscale ACLs (roadmap) |
| The admin account has password-free sudo on every machine, and CI logs in as it | unattended deploys; owner's choice over a separate account (2026-11-22) | automation keys pinned with `from=`; a dedicated `deploy` user with limited sudo would narrow it |
| The boundary host runs batch jobs as the submitting user, and holds the munge key | the lab has one user, the owner ([ADR-0007](../decisions/0007-gateway-joins-slurm.md)) | revisit before anyone else gets Slurm access |
| Two schedulers share the gateway: work outside Slurm is invisible to it (an out-of-memory risk) | its training workload is not yet a Slurm job | drain the gateway before a large GPU stage; submit that work through Slurm |

## Out of scope

Physical access, the ISP router's firmware, and the Tailscale and GitHub
accounts themselves. Protect those accounts with MFA; for Tailscale also turn
on device approval and Tailnet Lock.
