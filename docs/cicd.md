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
    end

    rect rgba(198, 40, 40, 0.08)
    Note over Owner,Lab: deploy.yml · manual · owner only · approved
    Owner->>GH: Run workflow on main (mode: check or apply)
    GH->>GH: job condition: ref is main and actor is the owner
    GH->>Env: deployment waits for review
    Owner->>Env: approve
    Env-->>GH: approved
    GH->>Runner: job and environment secrets
    Note over Runner: Python installed per job (setup-python)
    Runner->>Runner: write inventory, key, known_hosts (mode 0600)<br/>::add-mask:: every address
    Runner->>Lab: ansible-playbook over SSH by lab address<br/>StrictHostKeyChecking=yes
    Lab-->>Runner: task results
    Runner-->>GH: PLAY RECAP only (full log stays on the runner host)
    Runner->>Runner: always: delete the private files
    end
```

## Why a public repository can safely have a self-hosted runner here

| Risk | Control |
|---|---|
| A pull request (from a fork or not) runs code on the runner | No workflow that targets the runner has a PR trigger. `scripts/check-workflows.sh` fails CI if one ever does; tested with a planted unsafe workflow |
| Someone else starts a deploy | `workflow_dispatch` needs write access; the job also checks `actor == repository_owner` and `ref == main` |
| A deploy runs unreviewed | protected environment with a required reviewer and `main`-only deployment branch |
| Secrets in logs (Actions logs of public repos are public) | inventory and keys arrive as environment secrets; every IP and tailnet name is masked; only the recap is printed |
| Token abuse from a workflow | `permissions: contents: read`; `persist-credentials: false` on checkout |
| Compromised third-party action | actions pinned to full commit SHAs; Dependabot proposes updates |
| Tool drift | Python, Ansible, linters and collections pinned; `make setup` builds the same environment everywhere |

See [ADR-0005](decisions/0005-self-hosted-runner-on-a-public-repo.md) and the
[runner runbook](runbooks/self-hosted-runner.md).

## Status

* `ci.yml` runs from the first push.
* `deploy.yml` is ready. Its runner is staged on node1 (`~/homelab-runner`,
  label `homelab`) and registers with a one-time token; the `deploy` user and
  the `homelab` environment's secrets follow the
  [runner runbook](runbooks/self-hosted-runner.md). Until all three exist, the
  lab is managed from the owner's laptop with `make check-host` / `make apply-host`.
