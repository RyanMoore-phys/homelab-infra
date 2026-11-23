# homelab-infra

[![ci](https://github.com/RyanMoore-phys/homelab-infra/actions/workflows/ci.yml/badge.svg)](https://github.com/RyanMoore-phys/homelab-infra/actions/workflows/ci.yml)
![Ansible](https://img.shields.io/badge/Ansible-2.21-1A1918?logo=ansible)
![Ubuntu](https://img.shields.io/badge/Ubuntu-26.04_LTS-E95420?logo=ubuntu&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-WireGuard-242424?logo=tailscale)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

Infrastructure as code for a four-machine Ubuntu homelab: a Linux gateway
that routes and segments a private lab network, a four-node Slurm cluster
(the three lab nodes plus the gateway's CPUs and GPU)
with shared NFS storage, and a monitoring stack, with **nothing forwarded in
from the internet**. The host configuration (SSH, keys, sudo, firewall,
routing, NFS exports, Slurm, patching) is idempotent Ansible roles, checked by
CI on every push and deployed through a gated, owner-approved pipeline. What
is still set up by hand is listed under [Maintenance](#maintenance).

This repository is public, so it is built to hold **no addresses, keys,
logins or tailnet names**. CI fails the build if one appears, and the guards
that enforce this are themselves tested with planted leaks.

---

## Architecture

```mermaid
flowchart TB
    owner(["Owner devices<br/>Tailscale clients"])
    subgraph HOME["Home network · untrusted"]
        isp["ISP router<br/>no port forwards · UPnP off"]
        personal["Personal devices"]
    end
    gw["<b>gateway</b><br/>router · firewall · NAT · DNS<br/>Tailscale subnet router · blocks lab → home<br/>Slurm node · 12 CPUs · GPU"]
    subgraph LAB[" "]
        sw{{"<b>Lab network · trusted</b><br/>Ethernet switch"}}
        n0["<b>node0</b><br/>NFS server · Slurm controller"]
        n1["<b>node1</b><br/>monitoring · wiki · 2 CI runners · Slurm"]
        n2["<b>node2</b><br/>Slurm compute"]
    end

    owner ==>|"Tailscale · enters at the gateway"| gw
    isp ---|"Wi-Fi uplink"| gw
    isp --- personal
    gw ---|"Ethernet · then to the nodes"| sw
    sw --- n0
    sw --- n1
    sw --- n2

    classDef boundary fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#1a1a1a
    classDef host fill:#e3f2fd,stroke:#1565c0,color:#1a1a1a
    classDef infra fill:#eceff1,stroke:#607d8b,color:#1a1a1a
    classDef actor fill:#ede7f6,stroke:#5e35b1,color:#1a1a1a
    class gw boundary
    class n0,n1,n2 host
    class sw,isp,personal infra
    class owner actor
    style LAB fill:#e8f5e9,stroke:#2e7d32,color:#1a1a1a
    style HOME fill:#fff8e1,stroke:#f9a825,color:#1a1a1a
    linkStyle default interpolate linear
    linkStyle 0 stroke:#5e35b1,stroke-width:3px
    linkStyle 1,2 stroke:#f9a825,stroke-width:2px
    linkStyle 3,4,5,6 stroke:#2e7d32,stroke-width:2px
```

<sub>Colors used in every diagram: **red** security boundary · **purple** tailnet · **green** trusted lab · **amber** untrusted home network · **blue** hosts. See [diagram conventions](docs/architecture.md#diagram-conventions).</sub>

| Machine | Role |
|---|---|
| **gateway** | A dedicated machine between the home network and the lab: routing, NAT, dnsmasq, default-deny firewall, lab→home block, the Tailscale subnet router every remote session goes through, HTTPS for lab web UIs, and a Slurm compute node with 12 CPUs and the lab's only GPU ([ADR-0007](docs/decisions/0007-gateway-joins-slurm.md)). It is also the training project's host, which runs real-time training outside Slurm |
| **node0** | NFS v4.2 server for shared simulation data (`/srv/openmc`), Slurm controller, compute. A game server unit is installed but stopped |
| **node1** | Grafana + Prometheus and a wiki behind Caddy (Docker Compose), Slurm job board, two self-hosted Actions runners (one per repository), compute |
| **node2** | Compute |

Every machine runs Tailscale, but remote traffic is directed **through the gateway first**: SSH, Ansible, monitoring and the web UIs all reach the nodes by their lab address over its subnet route. Each node's own tailnet address is kept only as a fallback for when the gateway is down.

Deeper: [architecture](docs/architecture.md) · [network, packet path and port matrix](docs/network.md) ·
[access model](docs/security/access-model.md) · [CI/CD](docs/cicd.md)

## Security model

| Layer | Control | Verified by |
|---|---|---|
| Ingress | No port forwards, UPnP off. Tailscale is the only way in; remote traffic goes through the gateway first, with each node's own tailnet address as a fallback ([ADR-0002](docs/decisions/0002-tailscale-only-ingress.md)) | every node sees the owner's sessions arrive from the gateway's lab address; the gateway's upstream side accepts only Tailscale's WireGuard port; the ISP router's settings are checked by hand |
| SSH | Keys only, no passwords or keyboard-interactive, no X11, root by key only, `MaxAuthTries 3` | `sshd -T` on all four; password login refused |
| Credentials | Automation keys pinned with `from=` to the machine that uses it; the owner key has a passphrase. Key files are exclusive: a key not in the inventory is removed, and the role stops unless the owner's key stays | same key from an unlisted source refused; an unused, unpinned root key found on 2026-11-23 is gone; owner, CI and runner keys still log in |
| Segmentation | Lab reaches the internet but cannot open connections to the home network | from node2: home router times out; internet and DNS work (2026-11-23) |
| Services | Prometheus on `127.0.0.1`; Grafana and the wiki on node1's lab address, published on the tailnet by the gateway over HTTPS | Prometheus refused from the network; Grafana healthy through the gateway |
| Storage | NFS exports list each client (three, including the gateway), `root_squash` | exports reviewed; role refuses wildcard exports |
| Patching | Unattended upgrades everywhere, including Tailscale and Docker CE; nodes reboot through Slurm after their running jobs when an update needs it; Dependabot for actions, tools and monitoring images ([patching](docs/patching.md), [ADR-0008](docs/decisions/0008-unattended-patching-and-drained-reboots.md)) | `make patch-status`; reboot script tested on every Slurm state |
| Supply chain | Actions pinned to commit SHAs; Python, Ansible, linters, collections pinned; Dependabot | CI |
| Public repo | Private-data guard, gitleaks on full history, workflow guard, masked deploy logs | guards tested with planted leaks |

What it protects against, and what it knowingly accepts: [threat model](docs/security/threat-model.md).

## Engineering notes

Problems found during the hardening, and what they taught:

1. **Docker publishes around the firewall.** Grafana and an unauthenticated
   Prometheus were reachable from the whole network although ufw denied the
   ports: Docker's iptables chains run before ufw's. Prometheus now binds to
   localhost; web UIs are published by the gateway with `tailscale serve`.
   ([ADR-0003](docs/decisions/0003-explicit-binds-and-gateway-published-uis.md),
   [PM-004](docs/postmortems/pm-004-monitoring-exposed-past-the-firewall.md))
2. **So does Tailscale.** Per-port ufw denies on `tailscale0` did nothing:
   `tailscaled` jumps to its own `ts-input`/`ts-forward` chains first. Reading
   the gateway's real chains also showed `ts-forward` accepts lab → tailnet
   traffic, which only Tailscale ACLs can close (on the roadmap).
   ([packet path](docs/network.md#packet-path-through-the-gateway))
3. **Gateway first, with a fallback.** Everything that used the nodes'
   tailnet addresses (Prometheus scrapes, published UIs, SSH, Ansible) was
   moved to lab addresses behind the gateway, and each node was checked to see
   sessions arrive from the gateway's address. Taking the nodes off the tailnet
   entirely was built and then rejected: their own Tailscale clients stay as a
   fallback, so the gateway is never a single point of failure for access.
   ([ADR-0002](docs/decisions/0002-tailscale-only-ingress.md))
4. **`sshd` keeps the first value it reads.** Cloud-init's
   `50-cloud-init.conf` re-enabled password login over any later drop-in; the
   hardening drop-in is named `00-` for that reason. ([access model](docs/security/access-model.md))
5. **Public Actions logs are public.** Inventory values are not secrets to
   GitHub's masker; the deploy job masks every address itself and prints only
   the recap. ([CI/CD](docs/cicd.md))
6. **The router is also a compute node, on purpose.** The gateway has most of
   the lab's CPUs and its only GPU, so it joined Slurm with 2 GB held back for
   routing and its slurmd reachable from the controller only. The cost is
   written down: two schedulers share it, and multi-node steps that span it
   must start on the controller. ([ADR-0007](docs/decisions/0007-gateway-joins-slurm.md))
7. **Encode, then prove.** Hand fixes were turned into roles, and a check-mode
   run against all four machines reports `changed=0` (2026-11-23): code and
   reality agree.
8. **A pull request brings its own workflow.** GitHub runs a pull request's
   version of the workflow files, so no guard inside this repository's
   workflows can keep a fork off the self-hosted runner. The runner refuses
   every job except the owner's manual deploy from `main`, in a hook that runs
   before checkout. ([ADR-0005](docs/decisions/0005-self-hosted-runner-on-a-public-repo.md),
   [PM-001](docs/postmortems/pm-001-runner-reachable-from-pull-requests.md))
9. **A container reaches its own host from its bridge address.** The runner
   on node1 could log in everywhere except node1, where its connection arrived
   from the Docker bridge instead of node1's lab address and `from=` refused
   it. node1 alone also accepts that key from its Docker networks, which no
   other machine can send from. ([access model](docs/security/access-model.md))
10. **Installed is not running.** unattended-upgrades had kept the nodes'
    packages patched, yet they had been up 54 days on a kernel three security
    updates old: nothing rebooted them. They now reboot through Slurm, after
    their running jobs. ([ADR-0008](docs/decisions/0008-unattended-patching-and-drained-reboots.md),
    [PM-002](docs/postmortems/pm-002-nodes-running-an-old-kernel.md))
11. **Docs are claims too.** Checking every statement and diagram here against
    the live machines found a wrong NFS path, a stopped game server, listening
    ports missing from the port matrix, an unused root key without `from=`,
    one NAT rule repeated seven times and 41 leftover firewall rules. The last
    three were fixed the same day, in code: key files are now exclusive, NAT
    has its own nftables table, and retired rules are listed in the inventory.
    ([verification](docs/verification.md#grounding-pass-2026-11-23))
12. **An overlapping network beats the subnet route.** On a network that uses
    the lab's own address range, a laptop's local route wins over Tailscale's
    subnet route and the nodes time out. Jumping through the gateway by its
    tailnet name still works; renumbering the lab is on the roadmap.

Full log: [hardening log](docs/security/hardening-log.md). Decisions and their trade-offs: [ADRs](docs/decisions/README.md).
Incidents, written up blameless with timelines from the records: [postmortems](docs/postmortems/README.md)
(PM-001 to PM-004, including the 21-hour CI outage a settings change caused).

## CI/CD

```mermaid
flowchart LR
    pr(["push / pull request<br/>forks included"]) --> ci["<b>ci</b> · GitHub-hosted runner<br/>gitleaks · private-data guard · workflow guard<br/>shellcheck · yamllint · ansible-lint · syntax"]
    owner(["owner"]) -->|"Run workflow on main"| gate{"environment<br/>approval"}
    gate -->|"approved"| deploy["<b>deploy</b> · self-hosted runner in the lab<br/>check by default · apply on request<br/>masked output · recap only"]
    deploy -->|"SSH · pinned host keys"| lab[("lab hosts")]
    pr -.-x|"refused by the runner"| deploy

    classDef hosted fill:#e3f2fd,stroke:#1565c0,color:#1a1a1a
    classDef selfhosted fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#1a1a1a
    classDef actor fill:#ede7f6,stroke:#5e35b1,color:#1a1a1a
    classDef gate fill:#fff8e1,stroke:#f9a825,color:#1a1a1a
    classDef lab fill:#e8f5e9,stroke:#2e7d32,color:#1a1a1a
    class ci hosted
    class deploy selfhosted
    class pr,owner actor
    class gate gate
    class lab lab
    linkStyle default interpolate linear
    linkStyle 4 stroke:#c62828,stroke-width:2px,stroke-dasharray:5 4
```

A pull request cannot run on the self-hosted runner, even one that adds its
own workflow: the runner's job-started hook refuses every job except the
owner's manual deploy from `main`, before checkout. Nothing private is stored
in GitHub; the runner's key and inventory are mounted read-only on node1
([ADR-0005](docs/decisions/0005-self-hosted-runner-on-a-public-repo.md),
[sequence diagram](docs/cicd.md)).

## Maintenance

What runs by itself, and what is a person's job. Details and trade-offs:
[patching](docs/patching.md), [ADR-0008](docs/decisions/0008-unattended-patching-and-drained-reboots.md).

| When | What | How |
|---|---|---|
| Daily, automatic | Security updates on all four machines, plus Tailscale and Docker CE from their own repositories | unattended-upgrades (`auto_updates` role) |
| Weekly, automatic | A node whose update needs a reboot is drained, rebooted after its running jobs and returned to service; a node someone drained on purpose is left alone | `reboot-when-drained.timer` → `scontrol reboot ASAP nextstate=RESUME` |
| Weekly, review | Dependabot pull requests: the pinned actions and CI tools here; the monitoring images in the training project's repository (patch and minor only) | merge; for monitoring images, `docker compose pull && docker compose up -d` on node1 |
| Any time | What each machine still needs: a waiting reboot, pending and held updates, the last unattended run | `make patch-status` (read-only) |
| Any time | Drift: does every machine still match the code? | `make check`, or deploy in `check` mode: expect `changed=0` |
| By hand | Gateway reboots (it routes the lab and runs training outside Slurm); non-security updates (`apt upgrade`; 24 to 35 waiting per machine on 2026-11-23); the held NVIDIA and Kubernetes packages | owner |

Not managed by Ansible yet, so set up and updated by hand: the Docker Compose
stacks (monitoring and the wiki on node1, the exporters on node0 and node2),
the NFS client mounts, the two runner containers, the game server, and the
munge key (on purpose: it is a secret, copied node to node).

## Quick start

Requirements: Python 3.12+, `make`, SSH access to your hosts.

```bash
make setup                                          # pinned Ansible, linters, collections in .venv
cp inventory/hosts.example.yml inventory/hosts.yml  # your hosts (gitignored)
make test                                           # everything CI runs; no lab access needed
make check-host HOST=node2                          # dry run on one machine (asks for its sudo password)
make apply-host HOST=node2                          # apply to that machine
make patch-status                                   # read-only: reboots and updates waiting
```

The admin account has password-free sudo on every machine (CI deploys need
it), so `make check LIMIT=<host>` and `make apply LIMIT=<host>` run without a
prompt; `check-host` / `apply-host` ask for a sudo password, for a machine set
up without it. `make help` lists every target.

## Repository layout

```text
.
├── playbooks/
│   ├── site.yml                # baseline for all hosts, then router / NFS / Slurm plays
│   └── patch-status.yml        # read-only report: reboots, pending and held updates
├── roles/
│   ├── auto_updates/           # unattended upgrades (incl. Tailscale, Docker CE), drained reboots
│   ├── ssh_hardening/          # sshd drop-in, validated with `sshd -t` before install
│   ├── authorized_keys/        # keys with from= source pinning
│   ├── sudo_nopasswd/          # unattended sudo for the automation account, visudo-checked
│   ├── firewall/               # ufw defaults, tailnet, lab trust, host rules
│   ├── router/                 # forwarding, NAT, lab→home block, dnsmasq
│   ├── nfs_server/             # per-share exports, refuses wildcard clients
│   └── slurm/                  # slurm.conf, cgroup.conf, gres.conf (GPU) from inventory
├── inventory/hosts.example.yml # shape of the private inventory (RFC 5737 addresses)
├── group_vars/all.yml          # shared defaults, nothing identifying
├── scripts/                    # check-private-data.sh, check-workflows.sh
├── runner/                     # self-hosted runner: compose file, job-started hook, start script
├── docs/
│   ├── architecture.md · network.md · cicd.md · patching.md · verification.md
│   ├── security/               # threat model, access model, hardening log
│   ├── postmortems/            # PM-001 … 004, blameless incident write-ups
│   ├── decisions/              # ADR-0001 … 0008
│   └── runbooks/               # runner, router failover, Slurm, gateway in Slurm, job board, rollback
├── .github/workflows/          # ci.yml (hosted) · deploy.yml (self-hosted, gated)
└── Makefile                    # setup · test · check(-host) · apply(-host) · patch-status
```

## Verification

Each control has a test that fails if the control breaks, usually run from
both sides: the path that must work and the path that must be refused.
Commands and results: [verification](docs/verification.md).

## Roadmap

- [ ] Molecule scenarios to converge each role in a container in CI
- [ ] Tailscale ACLs as code (`policy.hujson` + GitOps action): limit the subnet route to SSH and HTTPS, and stop lab → tailnet traffic
- [ ] VLANs on a managed switch: separate trust zones for compute and services
- [ ] Alerting (Alertmanager) for disk, NFS and Slurm node state
- [ ] Encrypted off-host backups of node state
- [x] `authorized_keys` managed exclusively, so a key Ansible does not know about is removed instead of kept (2026-11-23)
- [ ] The NFS client mounts and the Docker Compose stacks as roles
- [ ] Renumber the lab off a common home address range, so a remote network can never overlap it

## License

[MIT](LICENSE)
