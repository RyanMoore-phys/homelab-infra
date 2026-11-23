# PM-004: Grafana and an unauthenticated Prometheus reachable although the firewall denied them

**Date:** found 2026-11-21 · **Severity:** Medium (no use found) · **Status:** Fixed ·
**Duration:** from the stack's first deployment (not recorded) to 2026-11-21

## Summary
The monitoring stack on node1 published Grafana and Prometheus on all
addresses (`0.0.0.0:3000`, `0.0.0.0:9090`). Docker writes its own packet-filter
rules for published ports, and they act before ufw's, so both answered the
whole lab and the tailnet although ufw denied the ports. Prometheus has no
login. Every published port now names its address. Prometheus listens on
localhost only, and the web pages reach the tailnet through the gateway.

## Impact
* Any machine on the lab network or the owner's tailnet could read every
  metric in Prometheus and reach Grafana's login page.
* Neither was reachable from the internet: nothing is forwarded in from it.
* No evidence of misuse, and no way to rule it out: Prometheus keeps no
  access log.

## Timeline (UTC)
| Time | Event |
|---|---|
| Before 2026-11-21 | Stack deployed with ports published on all addresses (date not recorded; it predates this repository) |
| 2026-11-21 | Read-only audit compares listening sockets with firewall rules, then connects from another machine: both pages answer although ufw denies the ports |
| 2026-11-21 | Ports bound explicitly; the gateway publishes Grafana and the wiki on the tailnet with `tailscale serve`; Prometheus refused from the network ([ADR-0003](../decisions/0003-explicit-binds-and-gateway-published-uis.md)) |
| 2026-11-23 | Grounding pass re-reads every listening socket: Prometheus on localhost only, Grafana requires a login |

## Detection
By an audit, which compared what listens on each machine with what the firewall
allows, then tested both from another host. Reading the firewall rules alone
would have missed it: they looked correct.

## Root cause
Docker publishes container ports with its own NAT and forwarding rules, in
chains that run before ufw's. A ufw deny therefore does not apply to a
published port. The binding address in the compose file is the real access
control.

Contributing factors:
* **Defaults.** Compose's `ports: ["9090:9090"]` binds every address.
* **A service with no authentication.** Prometheus relies entirely on the
  network to protect it.
* **The firewall rules were trusted** without testing them from outside.

## What went well
* The audit tested the actual path, not the configuration.
* The fix removed the exposure instead of adding another filter that a future
  `ports:` entry could bypass again.

## What went badly
* The exposure existed from the first deployment and went unnoticed until an
  audit.

## Action items
| Action | Status | Where |
|---|---|---|
| Bind every published container port to a named address | Done | [ADR-0003](../decisions/0003-explicit-binds-and-gateway-published-uis.md) |
| Publish web pages from the gateway over HTTPS, tailnet only | Done | `router` role, `router_tailscale_serve` |
| Test: Prometheus refused from the network; Grafana healthy through the gateway | Done | [verification](../verification.md) |
| Port matrix read from the machines (`ss`), not from the configuration | Done (2026-11-23) | [network](../network.md#port-matrix) |
| Manage the Docker Compose stacks with Ansible, so their binds are code | Roadmap | [README](../../README.md#roadmap) |

## Lessons
* A firewall rule is a claim; a connection attempt from another machine is the test.
* With Docker, the published address is the access control.
