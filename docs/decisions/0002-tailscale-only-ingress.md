# ADR-0002: Tailscale is the only way in; the gateway is the normal path

**Status:** Accepted · 2026-11-21, revised 2026-11-22 (owner)

## Context
The owner needs SSH and web UIs from anywhere. Port forwarding puts a
service in front of every internet scanner. Tailscale runs on every machine,
which gives each node its own path in from the tailnet. Two things were found
on the way: Tailscale's `ts-input` chain accepts tailnet packets before ufw,
so a host firewall does not filter tailnet traffic; and every extra path is
one more thing to watch.

## Decision
* No port forwards and UPnP off on the ISP router. Tailscale is the only way in.
* **Every machine runs Tailscale.**
* **The gateway is the normal path.** It advertises the lab subnet and
  publishes lab web UIs with `tailscale serve`. Every configured way in goes
  through it: the owner's SSH config and the Ansible inventory reach nodes by
  their lab address over the subnet route, monitoring scrapes over the lab,
  and the web UIs are served by the gateway. The gateway masquerades this
  traffic, so nodes see sessions arrive from its lab address.
* **Each node's own tailnet address is a fallback**, for when the gateway is
  down or being changed.

## Consequences
* Remote access survives a gateway outage, through the fallback.
* Automation keys need only lab addresses in their `from=` limits.
* Node firewalls do not filter tailnet traffic (`ts-input` runs first).
  Accepted while the tailnet holds only the owner's devices; Tailscale ACLs
  close it (roadmap).
* The gateway's lab → home block keeps one narrow exception, UDP from
  Tailscale's port 41641, so nodes keep direct WireGuard paths to tailnet
  devices on the home network instead of falling back to relays.
* Tailscale's `ts-forward` accepts lab → tailnet traffic (known gap, closed by
  ACLs; roadmap).

## Alternatives considered
* **Tailscale on the gateway only (nodes leave the tailnet):** built and
  staged on 2026-11-21, not applied. Rejected by the owner on 2026-11-22: it
  makes the gateway a single point of failure for remote access, for a modest
  gain while the tailnet holds only the owner's devices.
* **SSH bastion with ProxyJump only, no subnet route:** narrower, but breaks
  lab web UIs and tooling that uses lab addresses. Still usable from a device
  without the subnet route (`ProxyJump admin@gateway`).
* **Port forwards, or plain WireGuard on the gateway:** a forwarded port and
  manual peers.
