# Rollback

Every manual change of 2026-11-21 left a backup next to it.

| Change | Undo |
|---|---|
| SSH hardening | `sudo rm /etc/ssh/sshd_config.d/00-hardening.conf && sudo systemctl reload ssh` |
| `from=` key limits | restore `~/.ssh/authorized_keys.bak-from-20261121` (root's on the gateway) |
| Removed keys | restore `~/.ssh/authorized_keys.bak-20261121` |
| Gateway firewall | `sudo ufw status numbered`, then `sudo ufw delete <n>` for the rule with the matching comment; full copy in `/root/ufw.bak-20261121` |
| Node firewall (lab trust) | `sudo ufw delete` the rule commented `lab trust 2026-11-21` |
| Slurm | restore `/etc/slurm/slurm.conf.bak-20261121`, then `sudo scontrol reconfigure` on the controller |
| Monitoring ports | restore `docker-compose.yml.bak-20261121b` (or `...-20261121` for the first change), then `docker compose up -d grafana prometheus` |
| Prometheus targets | restore `prometheus.yml.bak-20261121b`, then `docker compose restart prometheus` |
| Wiki binding | restore `~/stack/compose.yml.bak-20261121b`, then `docker compose up -d caddy` |
| Gateway publishing | `sudo tailscale serve --https=443 off`, `sudo tailscale serve --https=8443 off` |
| Owner SSH config | restore `~/.ssh/config.bak-20261121b` |
| Gateway in Slurm and the NFS export | the Undo section of [add-gateway-to-slurm.md](add-gateway-to-slurm.md) |
| Any file the `slurm` role wrote | Ansible keeps a timestamped copy next to it (`slurm.conf.<date>~`) |

With Ansible, a rollback is a revert commit followed by a deploy in `apply`
mode; use `--check` first to see exactly what will change back.
