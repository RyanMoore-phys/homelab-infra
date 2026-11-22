# ADR-0005: A self-hosted runner on a public repo, behind dispatch and environment gates

**Status:** Accepted · 2026-11-21

## Context
Deploying to a private lab needs a runner inside it. GitHub advises against
self-hosted runners on public repositories because a pull request from a fork
can run arbitrary code on them. This repository is public to showcase the work.

## Decision
* `ci.yml` (lint, scans, syntax) runs on GitHub-hosted runners for every push
  and pull request.
* `deploy.yml` is the only workflow that targets the self-hosted runner. It is
  `workflow_dispatch` only, runs only on `main`, only for the repository owner,
  and only after approval in the protected `homelab` environment, which holds
  the inventory, deploy key and known_hosts as secrets.
* `scripts/check-workflows.sh` fails CI if any workflow could put a pull
  request on the self-hosted runner, or targets it without an environment.
* Output is masked and reduced to the recap; full logs stay on the runner host.

## Consequences
* The runner can still be abused by someone holding the owner's GitHub
  account; MFA on that account is part of the control.
* Unattended deploys need a `deploy` user with password-free sudo; its key is
  pinned to the runner's address.

## Alternatives considered
* **Private repository:** removes the risk, but also the showcase.
* **Push-based deploys from the laptop only:** fine, and still supported
  (`make apply`), but loses the reviewed, logged path.
