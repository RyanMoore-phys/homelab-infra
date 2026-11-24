# Alerting

How an alert reaches the phone, what each alert means, and what to do. The
design and its trade-offs are in
[ADR-0009](../decisions/0009-alerting-through-self-hosted-ntfy.md).

```
Prometheus (node1) ──rules──► Alertmanager (node1) ──webhook + token──► ntfy (gateway, lab address)
                                                                          │
   homelab-watchdog.timer (gateway) ── reads homelab-heartbeat ───────────┤
                                     └─ posts to homelab-alerts ──────────┤
                                                                          ▼
                              phone ◄── tailscale serve, HTTPS 8444 ── ntfy
                                ▲
                  ntfy.sh (wake-up only: message ID, no text)
```

## Where things are

| What | Where |
|---|---|
| Alert rules and their tests | `roles/alerting/files/rules/` (deployed to `/srv/monitoring/rules/` on node1) |
| Alertmanager config | `roles/alerting/templates/alertmanager.yml.j2` (rendered to `/srv/monitoring/alertmanager/` on node1) |
| ntfy config and accounts | `roles/ntfy` (gateway: `/etc/ntfy/server.yml`, `/var/lib/ntfy/user.db`) |
| Service tokens | `/etc/ntfy/alertmanager.token`, `/etc/ntfy/watchdog.token` on the gateway, root-only; Alertmanager's copy is `/srv/monitoring/alertmanager/ntfy_token` on node1 |
| Watchdog | `/usr/local/sbin/homelab-watchdog`, `homelab-watchdog.timer`, state in `/var/lib/homelab-watchdog/state` (gateway) |

## Phone setup (once)
1. Install the ntfy app. In its settings, add the server
   `https://<gateway's tailnet name>:8444`. The phone must be on the tailnet.
2. Make the owner's read login on the gateway, then type its password:
   `sudo ntfy user add <name>`, then
   `sudo ntfy access <name> homelab-alerts read-only`.
3. In the app, sign in to that server and subscribe to `homelab-alerts`.
   Do not subscribe to `homelab-heartbeat`: it carries a message every 5
   minutes.

## The alerts

Critical alerts arrive at high priority. Every alert is sent again every 12 h
while it lasts, and a "Resolved" message follows when it clears.

| Alert | Fires when | First look |
|---|---|---|
| ExporterDown | a machine's node exporter has not answered for 5 min (critical) | Is the machine up (`ping`, `ssh`)? If it is, `systemctl status prometheus-node-exporter` |
| DiskAlmostFull | a real file system is under 10 % free for 15 min (critical) | `df -h`, then `du -xh --max-depth=1 <mount> \| sort -h` |
| DiskWillFill | under 15 % free and on course to fill within 24 h | the same; look for a growing log or run directory |
| RebootOverdue | an update has needed a reboot for 8 days | Nodes: is the node drained for a long job, or did the weekly reboot fail (`journalctl -u reboot-when-drained`)? Gateway: the owner reboots it |
| SecurityUpdatesStuck | security updates pending for 3 days | `sudo unattended-upgrade --dry-run -d`; a held package or a dpkg prompt |
| UnattendedUpgradesNotRunning | no unattended-upgrades run for 2 days | `systemctl list-timers apt-daily-upgrade.timer` |
| SlurmNodeDown | Slurm sees a node down, failing or not responding for 15 min (critical) | `sinfo -R`; `systemctl status slurmd` on the node |
| SlurmDrainStuck | a node has been unavailable to Slurm for 3 days | `sinfo -R` for the reason; `scontrol update nodename=<n> state=resume` once fixed |
| NFSShareMissing | a client of the NFS export does not have it mounted, for 10 min (critical) | `findmnt /srv/openmc`; `sudo mount /srv/openmc`; is skybot up? |
| CertificateExpiring | a tailnet HTTPS certificate has under 14 days left | `tailscale serve status`; renewal is automatic, so look at `tailscaled`'s log |
| CertificateUnreadable | the gateway could not read a certificate for 2 days | `systemctl status homelab-tls-metrics` |
| GPUHot | the gateway's GPU is above 85 °C for 10 min | `nvidia-smi`; fans, airflow, a stuck process |
| Monitoring is down | no heartbeat reached the gateway in 15 min (sent by the watchdog, not by Alertmanager) | Is node1 up? `docker ps` there: are `prometheus` and `alertmanager` running? |

## Everyday tasks

**Silence an alert** (planned work): on node1,
`docker exec alertmanager amtool --alertmanager.url=http://localhost:9093 silence add alertname=<name> instance=<instance> --duration=2h --comment="<why>"`.
List silences with `silence query`, and end one with `silence expire <id>`.

**See what is firing:** on node1,
`docker exec alertmanager amtool --alertmanager.url=http://localhost:9093 alert query`.

**Add or change a rule:**
1. Edit `roles/alerting/files/rules/homelab.yml`.
2. Add a case to `homelab_test.yml` that fires and one that stays quiet.
3. Run `make rules`.
4. Deploy. Prometheus reloads the rules itself.

**Rotate a service token:**
1. On the gateway, `sudo ntfy token list <account>` and
   `sudo ntfy token remove <account> <token>`.
2. Delete `/etc/ntfy/<account>.token`.
3. Deploy. The role makes a new token and copies Alertmanager's to node1.

## When alerts do not arrive

1. **Did Alertmanager send it?** On node1,
   `docker exec alertmanager wget -qO- http://localhost:9093/metrics | grep alertmanager_notifications`.
   `failed_total` should be 0. `docker logs alertmanager` gives the reason.
2. **Did ntfy accept it?** On the gateway, `journalctl -u ntfy`. A 401 or 403
   means a token or access grant is wrong: deploy again.
3. **The message arrived but reads as raw JSON.** The installed ntfy does not
   have the `alertmanager` template. Run `apt-cache policy ntfy`: the
   installed version must come from `archive.ntfy.sh` and be at least
   `ntfy_min_version`. See the pin in `/etc/apt/preferences.d/ntfy`.
4. **Nothing on the phone at all.** Check that the phone is on the tailnet and
   signed in to the server, and that it is subscribed to `homelab-alerts`.
   "Not authorized to read this topic" means the login has no password or no
   read access (Phone setup, step 2).
