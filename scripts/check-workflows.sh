#!/usr/bin/env bash
# A public repository must never let a pull request (from a fork or anyone
# else) run on the self-hosted runner. Rule enforced here:
#   any workflow that uses a self-hosted runner may be triggered ONLY by
#   workflow_dispatch, and must name a protected environment.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$wf" ] || continue
  if grep -qE 'runs-on:.*self-hosted' "$wf"; then
    triggers=$(awk '/^on:/{f=1;next} f&&/^[a-z]/{f=0} f' "$wf" | grep -oE '^  [a-z_]+' | tr -d ' ' | sort -u | tr '\n' ' ')
    if [ "$triggers" != "workflow_dispatch " ]; then
      echo "UNSAFE: $wf uses a self-hosted runner but is triggered by: $triggers"; fail=1
    fi
    grep -qE '^\s+environment:' "$wf" || { echo "UNSAFE: $wf uses a self-hosted runner without a protected environment"; fail=1; }
  fi
  grep -qE 'pull_request_target' "$wf" && { echo "UNSAFE: $wf uses pull_request_target"; fail=1; }
  # Host-key options must go in --ssh-extra-args: inventory ssh COMMON args
  # override CLI ones, which would silently drop StrictHostKeyChecking.
  if grep -qE -- '--ssh-common-args' "$wf"; then
    echo "UNSAFE: $wf passes --ssh-common-args (overridden by the inventory; use --ssh-extra-args=)"; fail=1
  fi
done
[ $fail -eq 0 ] && echo "check-workflows: safe"
exit $fail
