# Inventory

Only `hosts.example.yml` is committed. Your real inventory goes in
`hosts.yml` next to it; `.gitignore` keeps everything else in this folder out
of git, and `scripts/check-private-data.sh` fails the build if a real address,
tailnet name, key or email slips into any tracked file.

For the CI deploy job, a copy (`hosts.ci.yml`, with the gateway reached by its
lab address) and `known_hosts.ci` are kept on the runner host and mounted
read-only into the runner; they are never in this repository or in GitHub
([runner runbook](../docs/runbooks/self-hosted-runner.md)).
