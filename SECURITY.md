# Security policy

## Reporting a problem

Please use GitHub's **private vulnerability reporting** (Security tab ->
"Report a vulnerability"). Do not open a public issue for anything that could
help someone reach the lab.

## What is deliberately not in this repository

* the real inventory (addresses, interface names, login, public keys)
* any private key, the Slurm munge key, tokens or passwords
* the tailnet name and anything from the Tailscale admin console

They live in a gitignored `inventory/hosts.yml` on the owner's machine and,
for CI, in a folder on the runner host that is mounted read-only into the
runner. Nothing private is stored in GitHub.

## Checks that keep it that way

* `scripts/check-private-data.sh`: private and Tailscale addresses, tailnet
  names, emails, MAC addresses, SSH keys (CI and pre-commit)
* gitleaks over the full git history (CI and pre-commit)
* `scripts/check-workflows.sh`: none of this repository's workflows can run a
  pull request on the self-hosted runner (CI and pre-commit)
* `runner/job-started.sh`: the runner itself refuses every job except the
  owner's manual deploy from `main`, including workflows a pull request adds

If a secret is ever committed, treat it as exposed: rotate it first, then
rewrite history. Deleting the commit is not enough once it has been pushed.
