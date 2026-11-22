# Access model: who can log in where

```mermaid
flowchart TB
    kr["Runner key<br/>runner container on node1"]
    ko["Owner key · ed25519<br/>passphrase in macOS Keychain"]
    kg["Gateway automation key<br/>on the gateway"]
    kd["Deploy key · planned<br/>on the runner host"]
    gr["<b>gateway</b> · root"]
    ga["<b>gateway</b> · admin<br/>sudo without password"]
    na["<b>node0-2</b> · admin<br/>sudo with password"]
    nd["<b>node0-2</b> · deploy · planned<br/>sudo without password"]

    kr -->|"from= node1 lab address"| gr
    ko ==>|"over the tailnet"| ga
    ko ==>|"via the gateway's subnet route<br/>arrives from the gateway's address"| na
    kg -->|"from= gateway lab address"| na
    kd -.->|"from= runner lab address"| nd

    classDef owner fill:#ede7f6,stroke:#5e35b1,color:#1a1a1a
    classDef auto fill:#fff8e1,stroke:#f9a825,color:#1a1a1a
    classDef planned fill:#ffffff,stroke:#90a4ae,stroke-dasharray:4 3,color:#1a1a1a
    classDef gwacct fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#1a1a1a
    classDef nodeacct fill:#e3f2fd,stroke:#1565c0,color:#1a1a1a
    class ko owner
    class kg,kr auto
    class kd,nd planned
    class ga,gr gwacct
    class na nodeacct
    linkStyle default interpolate linear
    linkStyle 0 stroke:#f9a825,stroke-width:2px
    linkStyle 1,2 stroke:#5e35b1,stroke-width:2.5px
    linkStyle 3 stroke:#f9a825,stroke-width:2px
    linkStyle 4 stroke:#90a4ae,stroke-width:2px,stroke-dasharray:5 4
```

Purple: the owner's key. Amber: automation keys, each pinned with `from=`.
Dashed grey: planned for CI deploys.

## Controls

| Control | Setting | Why |
|---|---|---|
| Authentication | public key only; `PasswordAuthentication no`, `KbdInteractiveAuthentication no` | nothing to brute-force |
| Root | `PermitRootLogin prohibit-password` | root only by key, only for the CI runner |
| Source pinning | `from="<lab address>"` on every automation key | a copied key is useless anywhere else |
| Normal path | nodes are reached through the gateway; sessions arrive from its lab address. Each node's own tailnet address is a fallback | one place to watch, without losing access if it fails |
| Slurm | munge key on all four machines; a job runs as its submitting user wherever it lands, including the gateway | one user today; revisit before sharing |
| Attempts | `MaxAuthTries 3` | limits key enumeration per connection |
| Forwarding | `X11Forwarding no` | no reason to expose a display channel |
| Owner key | passphrase, held by the macOS Keychain | a copied key file alone is not enough |

`from=` sources were taken from 14 days of `sshd` logs before being applied,
then tested both ways: allowed sources still log in, and an unlisted source
(the same key over an IPv6 link-local address) is refused.

## Why the drop-in is called `00-hardening.conf`

`sshd` keeps the **first** value it reads for each keyword, and
`sshd_config.d/*.conf` is read in lexical order. Ubuntu cloud images ship
`50-cloud-init.conf` with `PasswordAuthentication yes`, which silently beats
any drop-in sorted after it. `00-` sorts first.
