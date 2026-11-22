# Architecture

> Addresses are from the RFC 5737 documentation ranges. The real addressing
> plan lives only in the private inventory.

## Diagram conventions

| Color | Meaning |
|---|---|
| 🟥 red, thick border | security boundary (the gateway, anything that decides what passes) |
| 🟪 purple, dashed lines | Tailscale tailnet / WireGuard overlay |
| 🟩 green | trusted lab zone and lab links; accepted packets |
| 🟨 amber | untrusted home network and its links; approval gates |
| 🟦 blue | hosts and the services on them |
| ⬜ grey | third-party or passive infrastructure (ISP router, switch) |

Solid lines are physical or logical connections; dashed red lines with ✗ are
flows that are blocked.

## 1. Topology

The gateway is a **dedicated machine** with two physical interfaces: Wi-Fi to
the home network and Ethernet to the lab switch. It is the only machine on
both networks, the path every remote session takes into the lab, and since
[ADR-0007](decisions/0007-gateway-joins-slurm.md) also a Slurm compute node.

```mermaid
flowchart TB
    subgraph HOME["Home · 198.51.100.0/24"]
        isp["ISP router · .1 · to the Internet<br/>DHCP · NAT<br/>no port forwards · UPnP off"]
        personal["Personal devices"]
    end
    subgraph TAILNET["Tailnet · 100.64.0.0/10"]
        owner(["Owner devices<br/>laptop · phone"])
    end
    subgraph GW["gateway"]
        wan["wan_if · Wi-Fi<br/>DHCP address on the home network"]
        tsif["tailscale0 · the way in<br/>subnet router for the lab<br/>tailscale serve :443 · :8443"]
        nf["netfilter<br/>ts-input / ts-forward, then ufw<br/>default DROP for input and routed<br/>MASQUERADE out wan_if"]
        svc["local services<br/>dnsmasq :53 · exporters :9100 · :9835<br/>slurmd :6818 · RTX 5050 · NFS client"]
        lan["lan_if · Ethernet<br/>192.0.2.1/24 static"]
    end
    subgraph LAB[" "]
        sw{{"<b>Lab network · 192.0.2.0/24 · trusted</b><br/>Ethernet switch"}}
        n0["<b>node0</b> · .11<br/>NFS server · slurmctld · slurmd"]
        n1["<b>node1</b> · .12<br/>Grafana · Prometheus · wiki<br/>Actions runner · slurmd"]
        n2["<b>node2</b> · .13<br/>slurmd"]
    end

    isp --- personal
    isp ---|"Wi-Fi"| wan
    owner -.->|"WireGuard · UDP 41641<br/>enters on wan_if"| tsif
    wan --- nf
    tsif --- nf
    nf --- svc
    nf --- lan
    lan ---|"Ethernet · to the nodes"| sw
    sw --- n0
    sw --- n1
    sw --- n2

    classDef boundary fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#1a1a1a
    classDef iface fill:#ffffff,stroke:#c62828,color:#1a1a1a
    classDef host fill:#e3f2fd,stroke:#1565c0,color:#1a1a1a
    classDef infra fill:#eceff1,stroke:#607d8b,color:#1a1a1a
    classDef actor fill:#ede7f6,stroke:#5e35b1,color:#1a1a1a
    class nf boundary
    class wan,lan,tsif,svc iface
    class n0,n1,n2 host
    class isp,personal,sw infra
    class owner actor
    style GW fill:#fff5f5,stroke:#c62828,stroke-width:2px,color:#1a1a1a
    style LAB fill:#e8f5e9,stroke:#2e7d32,color:#1a1a1a
    style HOME fill:#fff8e1,stroke:#f9a825,color:#1a1a1a
    style TAILNET fill:#f3eefc,stroke:#5e35b1,stroke-dasharray:5 4,color:#1a1a1a
    linkStyle default interpolate linear
    linkStyle 0,1 stroke:#f9a825,stroke-width:2px
    linkStyle 2 stroke:#5e35b1,stroke-width:2.5px,stroke-dasharray:6 4
    linkStyle 3,4,5,6 stroke:#c62828,stroke-width:2px
    linkStyle 7,8,9,10 stroke:#2e7d32,stroke-width:2px
```

* **Routing.** Lab nodes use static addresses with the gateway as default
  route and DNS server (dnsmasq; no DHCP in the lab). The gateway NATs the lab
  out of `wan_if`.
* **Remote access goes through the gateway first.** It advertises the lab
  subnet on the tailnet, so a tailnet device reaches a node by its lab
  address; the gateway masquerades that traffic, and nodes see every session
  arrive from `192.0.2.1`. SSH, Ansible, monitoring and the web UIs (published
  with `tailscale serve`) all use this path.
* **Fallback.** Every node also runs Tailscale. Its own tailnet address is
  used only when the gateway is down or being changed
  ([ADR-0002](decisions/0002-tailscale-only-ingress.md)), and makes the
  [router failover](runbooks/router-failover.md) possible remotely.

## 2. Host roles

| Host | Inventory groups | Services | Ansible roles |
|---|---|---|---|
| gateway | `router`, `slurm_nodes` | routing, NAT, dnsmasq, Tailscale subnet router + `tailscale serve`, node and GPU exporters, slurmd with the GPU, NFS client | baseline + `router` + `slurm` |
| node0 | `lab_nodes`, `nfs_server`, `slurm_nodes` | NFS v4.2 server, slurmctld, slurmd, node_exporter, game server | baseline + `nfs_server` + `slurm` |
| node1 | `lab_nodes`, `slurm_nodes` | Grafana, Prometheus, wiki (Docker Compose), Slurm job board, Actions runner, slurmd, NFS client | baseline + `slurm` |
| node2 | `lab_nodes`, `slurm_nodes` | slurmd, node_exporter, NFS client | baseline + `slurm` |

*Baseline* = `auto_updates`, `ssh_hardening`, `authorized_keys`, `firewall`.

## 3. Compute and storage

One Slurm partition spans four machines. node1 and node2 are identical 4-CPU
compute nodes; node0 is also the storage server and the scheduler; the
gateway adds 12 CPUs and the GPU.

### Storage

```mermaid
flowchart TB
    nfsd["<b>node0</b> · nfsd · TCP 2049<br/>/srv/data on local disk<br/>per-client exports · root_squash"]
    m1["<b>node1</b><br/>NFS v4.2 client"]
    m2["<b>node2</b><br/>NFS v4.2 client"]
    mg["<b>gateway</b><br/>NFS v4.2 client · nofail"]

    nfsd -->|"NFS v4.2 · 2049"| m1
    nfsd -->|"NFS v4.2 · 2049"| m2
    nfsd -->|"NFS v4.2 · 2049"| mg

    classDef srv fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:#1a1a1a
    classDef client fill:#e8f5e9,stroke:#2e7d32,color:#1a1a1a
    classDef gw fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#1a1a1a
    class nfsd srv
    class m1,m2 client
    class mg gw
    linkStyle default interpolate linear
    linkStyle 0,1,2 stroke:#1565c0,stroke-width:2px
```

### Scheduling

```mermaid
flowchart TB
    ctld["<b>node0</b> · slurmctld · TCP 6817<br/>one partition · cons_tres · cgroup v2"]
    d0["<b>node0</b> · slurmd<br/>4 CPUs"]
    d1["<b>node1</b> · slurmd<br/>4 CPUs"]
    d2["<b>node2</b> · slurmd<br/>4 CPUs"]
    dg["<b>gateway</b> · slurmd<br/>12 CPUs · GPU rtx5050 × 1<br/>2 GB held back · firewall: controller only"]
    peer["<b>node ↔ node among node0-2</b><br/>step fan-out 6818 · srun 60001-60100 · MPI<br/>lab trust · the gateway is not included"]

    ctld <-->|"6817 / 6818"| d0
    ctld <-->|"6817 / 6818"| d1
    ctld <-->|"6817 / 6818"| d2
    ctld <-->|"6818 · controller only"| dg
    d0 -.- peer
    d1 -.- peer
    d2 -.- peer

    classDef ctl fill:#e3f2fd,stroke:#1565c0,stroke-width:2px,color:#1a1a1a
    classDef node fill:#e8f5e9,stroke:#2e7d32,color:#1a1a1a
    classDef gw fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#1a1a1a
    classDef note fill:#ffffff,stroke:#2e7d32,stroke-dasharray:4 3,color:#1a1a1a
    class ctld ctl
    class d0,d1,d2 node
    class dg gw
    class peer note
    linkStyle default interpolate linear
    linkStyle 0,1,2 stroke:#2e7d32,stroke-width:2px
    linkStyle 3 stroke:#c62828,stroke-width:2px
    linkStyle 4,5,6 stroke:#2e7d32,stroke-width:1.5px,stroke-dasharray:5 4
```

* `cons_tres` with CPU and memory as consumable resources, cgroup v2
  confinement and no swap: a job that outgrows its request is killed alone.
  `slurm.conf` is generated from the inventory and identical on every node,
  so adding a node is an inventory change.
* **The gateway** ([ADR-0007](decisions/0007-gateway-joins-slurm.md),
  [runbook](runbooks/add-gateway-to-slurm.md)) is uncapped apart from
  `MemSpecLimit=2048` (2 GB kept for routing) and offers its GPU as a GRES
  (`srun --gres=gpu:1`). Its firewall admits Slurm traffic **from the
  controller only**, so single-node jobs and steps launched on node0 run there,
  while a multi-node step started on node1, node2 or the gateway, or MPI
  spanning the gateway, is blocked. It also runs work outside Slurm; drain it
  before a large GPU stage.
* NFS v4.2 uses one TCP port; clients need neither rpcbind nor mountd.
  Exports name each client and always squash root.
* Long-running services are **not** Slurm jobs:
  [ADR-0006](decisions/0006-services-are-not-slurm-jobs.md).

## 4. Observability

```mermaid
flowchart TB
    owner(["Owner browser · on the tailnet"])
    serve["<b>gateway</b> · tailscale serve<br/>HTTPS :8443 · tailnet certificate"]
    graf["<b>node1</b> · Grafana<br/>lab address :3000 · login required"]
    prom["<b>node1</b> · Prometheus<br/>127.0.0.1:9090 · scrape every 10 s"]
    db[("<b>node1</b> · SQLite job history<br/>in the ingest container")]
    cron["<b>node1</b> · cron, every 2 min<br/>slurm_board collect + push"]
    ctld["<b>node0</b> · slurmctld<br/>squeue · sinfo"]
    ne_gw["<b>gateway</b><br/>node_exporter :9100"]
    gpu["<b>gateway</b><br/>NVIDIA GPU exporter :9835"]
    ne1["<b>node1</b><br/>node-exporter container"]
    ne0["<b>node0</b><br/>node_exporter :9100"]
    ne2["<b>node2</b><br/>node_exporter :9100"]

    owner -->|"HTTPS"| serve
    serve -->|"HTTP over the lab"| graf
    graf -->|"PromQL · compose network"| prom
    graf -->|"SQLite datasource"| db
    prom --> ne_gw
    prom --> gpu
    prom --> ne1
    prom --> ne0
    prom --> ne2
    cron -->|"merge"| db
    cron -->|"poll"| ctld

    classDef gw fill:#ffebee,stroke:#c62828,stroke-width:2px,color:#1a1a1a
    classDef svc fill:#e3f2fd,stroke:#1565c0,color:#1a1a1a
    classDef target fill:#e8f5e9,stroke:#2e7d32,color:#1a1a1a
    classDef actor fill:#ede7f6,stroke:#5e35b1,color:#1a1a1a
    class serve gw
    class graf,prom,db,cron svc
    class ne_gw,gpu,ne1,ne0,ne2,ctld target
    class owner actor
    linkStyle default interpolate linear
    linkStyle 0 stroke:#5e35b1,stroke-width:2.5px,stroke-dasharray:6 4
    linkStyle 1,2,3,9 stroke:#1565c0,stroke-width:2px
    linkStyle 4,5,6,7,8,10 stroke:#2e7d32,stroke-width:1.5px
```

Red: on the gateway. Blue: the monitoring stack on node1. Green: what it
reads: scrape targets (pulled every 10 s over the lab) and the Slurm
controller, polled every 2 minutes for the job board
([slurm-dashboard.md](runbooks/slurm-dashboard.md)).

Prometheus has no authentication, so it listens on localhost only; Grafana
reaches it over the Compose network. Docker-published ports bypass ufw, so
port bindings are the real access control:
[ADR-0003](decisions/0003-explicit-binds-and-gateway-published-uis.md).
