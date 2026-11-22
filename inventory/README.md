# Inventory

Only `hosts.example.yml` is committed. Your real inventory goes in
`hosts.yml` next to it; `.gitignore` keeps everything else in this folder out
of git, and `scripts/check-private-data.sh` fails the build if a real address,
tailnet name, key or email slips into any tracked file.

For the CI deploy job, the real inventory is stored as the `HOMELAB_INVENTORY`
secret of the protected `homelab` environment (base64), never in the repo.
