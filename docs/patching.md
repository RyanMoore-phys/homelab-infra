# Patching

What keeps each part of the lab up to date, and what is still done by hand.
The decision and its trade-offs: [ADR-0008](decisions/0008-unattended-patching-and-drained-reboots.md).

| What | Kept current by | How it lands |
|---|---|---|
| Ubuntu packages from the security pocket on all four machines: OpenSSH, sudo, kernel, libc, Slurm, munge, NFS, ufw, Ubuntu's `docker.io`, Java | unattended-upgrades (`auto_updates` role) | daily, installed without asking |
| Tailscale (all four machines), Docker CE (skybot), ntfy (gateway) | unattended-upgrades; their repositories are added as `Origins-Pattern` entries (ntfy also pinned above Ubuntu Pro's older build, [ADR-0009](decisions/0009-alerting-through-self-hosted-ntfy.md)) | daily, installed without asking |
| Reboots that kernel and libc updates need, on the three nodes | `reboot-when-drained.timer` asks Slurm to reboot the node after its running jobs | weekly check (below) |
| Reboots of the gateway | the owner | `make patch-status` shows when one is waiting |
| GitHub Actions and the CI's Python tools in this repository | Dependabot ([`.github/dependabot.yml`](../.github/dependabot.yml)) | weekly pull requests; nothing changes until one is merged |
| Monitoring containers on node1 (Grafana, Prometheus, node exporter) and the base images of the training project's Dockerfiles | Dependabot in that project's repository, patch and minor versions only | weekly pull requests; after merging, `docker compose pull && docker compose up -d` on node1 |
| The Actions runner program | the runner itself | updates itself when GitHub releases a new version |
| Held on purpose | NVIDIA driver (gateway), Kubernetes packages | `apt-mark hold`; upgraded by hand after testing |
| By hand | the deadsnakes Python on the gateway (the training interpreter, changed between runs), node1's reverse proxy and wiki stack (`~/stack`), the exporter stacks on skybot and node2, the runner image's base OS (a rebuild), the Paper server and its plugins, the ISP router's firmware | — |

## Drained reboots

A kernel or libc fix only takes effect after a reboot, and unattended-upgrades
does not reboot (`Automatic-Reboot` is off). Rebooting a Slurm node at a fixed
time would kill whatever is running on it, so the reboot goes through Slurm:

1. An update leaves `/var/run/reboot-required` behind.
2. Every Sunday at 04:30, plus a fixed delay of up to two hours that differs per
   machine, `reboot-when-drained.timer` runs `/usr/local/sbin/reboot-when-drained`.
3. The script asks Slurm to reboot the node when it is free:
   `scontrol reboot ASAP nextstate=RESUME reason="OS update: <packages>" <node>`.
   Slurm stops placing new jobs there, waits for the running ones to end, runs
   `RebootProgram` (`/usr/sbin/reboot`) and returns the node to service when
   its slurmd registers again. A node not back within `ResumeTimeout` (600 s)
   is marked down for a person to look at.
4. A node someone already drained, downed or put in maintenance is left alone,
   because `nextstate=RESUME` would undo that decision.

What it costs and what it does not cover:

* A draining node takes no new jobs until its longest running job ends, which
  can be days (`MaxTime` is 7 days).
* The drain protects Slurm jobs only. node1's services (Grafana, the wiki, both
  runners) are down for the reboot and come back through their restart policy.
  skybot is the NFS server and the Slurm controller: clients' NFS reads and
  writes wait until it is back, and slurmctld restarts from its saved state.
* The runners keep their registration through a reboot: tested on a copy of
  the homelab runner, a failed de-register at shutdown leaves `.runner` in place.

Tested against node2's real `scontrol` output with a stand-in that prints
instead of acting: idle and busy nodes are asked to reboot; drained, down and
already-requested nodes are left alone; an unknown node is refused (6 of 6).

Per machine: `auto_updates_reboot: never` in the inventory turns it off (the
gateway's default). To reboot a node now, through the same path:
`sudo systemctl start reboot-when-drained.service`.

## Checking

```bash
make patch-status                 # every machine; LIMIT=node2 for one
```

It changes nothing and prints, per machine: whether a reboot is waiting and
for which packages, the running kernel and uptime, pending and held packages,
the last unattended-upgrades run, the drained-reboot timer and the Tailscale
version.

The same facts are also metrics in Prometheus, from every machine's node
exporter: `apt_upgrades_pending`, `apt_upgrades_held` and
`node_reboot_required` (Ubuntu's apt collector), and
`homelab_unattended_upgrades_last_run_seconds`. Alerts on them are the next
step.

## In GitHub

Settings -> Code security, in both repositories: **Dependabot alerts** and
**Dependabot security updates** on. Alerts cover packages that are not listed
in `dependabot.yml` too, such as the training project's Python packages, which
move only through its test campaign.
