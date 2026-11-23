#!/bin/bash
# Register and start the homelab-infra runner.
# Asks for the ONE-TIME registration token: GitHub -> homelab-infra -> Settings
# -> Actions -> Runners -> New self-hosted runner (the value after --token; it
# expires after about an hour). The token is written to .env (mode 600) only
# for this start and then blanked: a running or restarted container no longer
# needs it. A full rebuild (docker compose down) needs a new token.
set -euo pipefail
cd "$(dirname "$0")"
umask 077
read -rsp "Registration token: " tok; echo
[ ${#tok} -ge 20 ] || { echo "That does not look like a registration token."; exit 1; }
printf "%s\n" "GITHUB_URL=https://github.com/RyanMoore-phys/homelab-infra" \
  "RUNNER_NAME=homelab-node1" "RUNNER_LABELS=homelab" "RUNNER_TOKEN=$tok" > .env
unset tok
docker compose up -d
ok=0
for _ in $(seq 1 45); do
  if docker logs homelab-runner 2>&1 | grep -q "Listening for Jobs"; then ok=1; break; fi
  sleep 2
done
sed -i "s/^RUNNER_TOKEN=.*/RUNNER_TOKEN=used-get-a-new-one-to-re-register/" .env
docker logs homelab-runner 2>&1 | grep -E "registering|Connected to GitHub|Listening for Jobs|rror" | tail -5
if [ "$ok" = 1 ]; then echo "homelab-runner is online"; else echo "Not online yet: docker logs homelab-runner"; exit 1; fi
