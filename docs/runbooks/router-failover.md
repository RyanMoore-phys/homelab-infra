# Router failover: node0 becomes the gateway

If the gateway is unplugged or moved away, node0 can route the lab instead.

## Hardware

node0 needs a second network interface: one to the home router (upstream),
one to the lab switch.

## Steps

1. In the inventory, move node0 into the `router` group and give it `lan_if`,
   `wan_if` and the same `firewall_rules` the gateway had.
2. Give node0 the gateway's lab address, or point every node's default route
   and DNS at node0's address (netplan).
3. Run `ansible-playbook playbooks/site.yml --limit node0 --check`, then apply.
   The router role turns on forwarding, NAT, the lab -> home block and dnsmasq.
4. Make node0 the subnet router (it already runs Tailscale):
   `sudo tailscale set --advertise-routes=<lab subnet>`, approve the route in
   the Tailscale admin console, and move `router_tailscale_serve` to node0 so
   the web UIs follow.
5. Test from a node: internet works, the home network is refused, the tailnet
   reaches the lab.

## Notes

* node0 also runs a public-facing game server; a router that also serves games
  is a weaker design. A small dedicated router is cleaner if one is available.
* Every node runs Tailscale, so this can be done **remotely even with the
  gateway down**: reach node0 by its own tailnet address (the fallback path).
