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
  and only after approval in the `homelab` environment.
* **The runner enforces this itself** (amended 2026-11-22). A pull request can
  add its own workflow that targets the runner, and GitHub runs the pull
  request's version of the workflows, so the rules above cannot stop it alone.
  A job-started hook (`runner/job-started.sh`, read-only and root-owned in the
  container) fails every job that is not `deploy.yml` on `main` started by the
  owner, before checkout. It stands in for runner groups, which personal
  accounts do not have.
* Nothing private is stored in GitHub: the SSH key, the inventory and
  known_hosts are mounted read-only into the runner container on node1.
* `scripts/check-workflows.sh` fails CI if one of this repository's workflows
  could put a pull request on the self-hosted runner, or targets it without an
  environment.
* Output is masked and reduced to the recap; full logs stay on the runner host.

* The runner is its own registration on node1 (label `homelab`), sharing the
  machine and the container image with another repository's runner but
  nothing else: separate work volume, its own key, no access to the other
  runner's.

## Consequences
* The runner can still be abused by someone holding the owner's GitHub
  account; MFA on that account is part of the control.
* Deploys run as the owner's admin account, which has password-free sudo on
  every machine (owner decision 2026-11-22: no separate `deploy` user). The
  runner's key is accepted only from node1's lab address. A copy of that key
  used anywhere else is refused; used from node1 it is root on every machine.

## Alternatives considered
* **A dedicated `deploy` user** with password-free sudo (planned first):
  keeps automation apart from the owner's login and can be narrowed to the
  commands Ansible needs. Not chosen for now; the stricter option.
* **Private repository:** removes the risk, but also the showcase.
* **Push-based deploys from the laptop only:** fine, and still supported
  (`make apply`), but loses the reviewed, logged path.
