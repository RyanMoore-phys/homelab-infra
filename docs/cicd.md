# CI/CD

## Pipeline

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Contributor (anyone)
    actor Owner
    participant GH as GitHub
    participant Hosted as GitHub-hosted runner
    participant Env as Environment "homelab"
    participant Runner as Self-hosted runner<br/>node1 container · label homelab
    participant Lab as Lab hosts

    rect rgba(21, 101, 192, 0.10)
    Note over Dev,Hosted: ci.yml · every push and pull request, forks included
    Dev->>GH: push / open pull request
    GH->>Hosted: run ci.yml with a read-only token
    Hosted->>Hosted: gitleaks (full history) · private-data guard · workflow guard<br/>shellcheck · yamllint · ansible-lint · syntax check
    Hosted-->>GH: status checks
    opt a pull request adds its own workflow that targets the self-hosted runner
    GH->>Runner: that job
    Runner-->>GH: refused by the job-started hook, before checkout
    end
    end

    rect rgba(198, 40, 40, 0.08)
    Note over Owner,Lab: deploy.yml · manual · owner only · approved
    Owner->>GH: Run workflow on main (mode: check or apply)
    GH->>GH: job condition: ref is main and actor is the owner
    GH->>Env: deployment waits for review
    Owner->>Env: approve
    Env-->>GH: approved
    GH->>Runner: job (no secrets)
    Runner->>Runner: job-started hook: deploy.yml · main · owner, else refuse
    Note over Runner: Python installed per job (setup-python)
    Runner->>Runner: key, inventory, known_hosts: read-only mounts on node1<br/>::add-mask:: every address
    Runner->>Lab: ansible-playbook over SSH by lab address<br/>StrictHostKeyChecking=yes
    Lab-->>Runner: task results
    Runner-->>GH: PLAY RECAP only (full log stays on the runner host)
    end
```

## Why a public repository can safely have a self-hosted runner here

| Risk | Control |
|---|---|
| A pull request (from a fork or not) runs code on the runner | GitHub runs a pull request's own workflow files, so a rule inside this repository's workflows is not enough. The runner's job-started hook ([`runner/job-started.sh`](../runner/job-started.sh)) refuses every job except `deploy.yml` on `main` started by the owner, before checkout; tested with 11 cases. Fork pull requests also wait for approval (repository setting), and `scripts/check-workflows.sh` keeps this repository's own self-hosted workflows dispatch-only (tested with a planted unsafe workflow) |
| A job rewrites the hook | mounted read-only and owned by root inside the container |
| Someone else starts a deploy | `workflow_dispatch` needs write access; the job checks `actor == repository_owner` and `ref == main`, and the hook checks the same on the runner |
| A deploy runs unreviewed | environment with a required reviewer and `main`-only deployment branch |
| Secrets in logs (Actions logs of public repos are public) | nothing private comes from GitHub: the SSH key, inventory and known_hosts are mounted read-only into the runner on node1; every IP and tailnet name is masked; only the recap is printed |
| Token abuse from a workflow | `permissions: contents: read`; `persist-credentials: false` on checkout |
| Compromised third-party action | actions pinned to full commit SHAs; Dependabot proposes updates |
| Tool drift | Python, Ansible, linters and collections pinned; `make setup` builds the same environment everywhere |

See [ADR-0005](decisions/0005-self-hosted-runner-on-a-public-repo.md) and the
[runner runbook](runbooks/self-hosted-runner.md).

## Status

* `ci.yml` runs from the first push.
* `deploy.yml` runs on the runner `homelab-node1` (node1, label `homelab`,
  files in [`runner/`](../runner)). It deploys as the owner's admin account,
  which has password-free sudo on every machine, with a key accepted only from
  node1. The job's steps were rehearsed inside the runner container in check
  mode against all four machines ([verification](verification.md)). The lab
  can still be managed from the owner's laptop with `make check-host` /
  `make apply-host`.
