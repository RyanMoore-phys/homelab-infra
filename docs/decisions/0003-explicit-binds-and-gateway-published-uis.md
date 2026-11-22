# ADR-0003: Bind container ports explicitly; publish web UIs from the gateway

**Status:** Accepted · 2026-11-21

## Context
Grafana and Prometheus were published as `0.0.0.0:3000` and `0.0.0.0:9090`.
Docker inserts its own iptables rules for published ports, ahead of ufw, so
both were reachable from the whole lab and tailnet regardless of the host
firewall. Prometheus has no authentication.

## Decision
* Every published container port names the address it binds to.
* **Prometheus:** `127.0.0.1` only. Grafana reaches it over the Compose network.
* **Grafana and the wiki:** node1's lab address, inside the trusted lab zone.
* The **gateway** publishes them on the tailnet with `tailscale serve`
  (HTTPS with the tailnet certificate, tailnet only): Grafana on `:8443`, the
  wiki on `:443`. Managed by the `router` role (`router_tailscale_serve`).

## Consequences
* Verified: Prometheus refused from the network; Grafana and the wiki answer
  through the gateway; all scrape targets up.
* No certificates to manage and no extra proxy container.
* A tailnet device can also reach Grafana by plain HTTP on node1's lab
  address through the subnet route. Acceptable while the tailnet holds only
  the owner's devices; an ACL limiting the subnet route closes it.

## Alternatives considered
* **ufw rules in the `DOCKER-USER` chain:** workable, but silently bypassed by
  the next `ports:` entry someone adds.
* **Caddy/Traefik with SSO:** worth it if a UI is ever exposed beyond the tailnet.
