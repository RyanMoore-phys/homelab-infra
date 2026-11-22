# Architecture decision records

Short records of decisions that shaped this lab: the context, what was
decided, what it costs, and what was rejected. Format after Michael Nygard.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-ansible-as-source-of-truth.md) | Ansible is the single source of truth for host configuration | Accepted |
| [0002](0002-tailscale-only-ingress.md) | Tailscale is the only way in; the gateway is the normal path, node clients are a fallback | Accepted |
| [0003](0003-explicit-binds-and-gateway-published-uis.md) | Bind container ports explicitly; publish web UIs from the gateway | Accepted |
| [0004](0004-flat-trusted-lab-segmented-at-the-gateway.md) | Lab nodes trust each other; segmentation is enforced at the gateway | Accepted |
| [0005](0005-self-hosted-runner-on-a-public-repo.md) | A self-hosted runner on a public repo, behind dispatch + environment gates | Accepted |
| [0006](0006-services-are-not-slurm-jobs.md) | Long-running services are not Slurm jobs | Accepted |
| [0007](0007-gateway-joins-slurm.md) | The gateway joins Slurm, uncapped, with its GPU and the NFS share | Accepted |
