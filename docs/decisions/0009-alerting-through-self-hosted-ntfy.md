# ADR-0009: Alerts reach the phone through a self-hosted ntfy on the gateway

**Status:** Accepted · 2026-11-23

## Context
Prometheus on node1 collected metrics from every machine, but nothing looked
at them unless the owner opened Grafana. Each failure in the postmortems
(`docs/postmortems/`) was found by a person, hours or weeks late. The lab has
no mail server, no paging service and no second site. The owner has one
phone, and has no other machine to run monitoring on.

## Decision
* **Rules in the repository.** The alert rules live in
  `roles/alerting/files/rules/`. Every rule has a `promtool test rules` case,
  run in CI.
* **Alertmanager on node1** (`roles/alerting`). It runs next to Prometheus, in
  its own Compose project, with no published port. It groups alerts by name
  and machine, and repeats an unresolved alert every 12 h. It sends critical
  alerts at high priority.
* **ntfy on the gateway** (`roles/ntfy`), from ntfy's own apt repository.
  * It listens on the gateway's lab address, and ufw admits only node1 to it.
  * The phone reaches it through `tailscale serve` over HTTPS.
  * Every topic is deny-all. The owner reads with a login.
  * Two service accounts publish with tokens, which are kept root-only on the
    gateway.
  * Alertmanager's JSON is rendered by ntfy's built-in `alertmanager` template.
* **A watchdog for monitoring itself.** Prometheus keeps one alert always
  firing (`Watchdog`). Alertmanager forwards it every 5 minutes to a heartbeat
  topic that no phone follows. A timer on the gateway checks that topic every
  5 minutes. If nothing arrived in 15 minutes, it posts "Monitoring is down"
  straight to the alert topic. It posts "Monitoring is back" once heartbeats
  return.
* **iPhone wake-ups go through ntfy.sh, with the message ID only.** iOS
  delivers instant notifications only through Apple's push service, which a
  self-hosted server cannot use. The server sends ntfy.sh a poll request that
  carries the message ID. The phone then fetches the message itself from the
  gateway, so the alert text never leaves the lab (owner decision).

## Rationale
* **Why the gateway hosts ntfy.** It is the one always-on machine that is not
  the monitoring host. If node1 dies, the watchdog on the gateway still has a
  working server to say so. If ntfy ran on node1, the alert that node1 is down
  would have nowhere to go.
* **Why a heartbeat.** A silent pipeline and a healthy lab look the same on
  the phone. Checking that something does arrive catches the failures that no
  rule can see: Prometheus down, Alertmanager down, node1 off, a broken token.
* **Why test the rules in CI.** A rule that never fires looks exactly like a
  healthy lab. The unit tests feed each rule synthetic series and assert when
  it fires, with which labels, and when it must stay quiet. Examples: the
  gateway's NFS export is not a client, and `tmpfs` is not a disk.

## Rejected
* **Email.** It needs a mail relay or an outside account with stored
  credentials, and delivery to a phone is slow and easy to filter.
* **ntfy.sh, the public service, for everything.** Every alert's text, with
  machine names and states, would sit on a third party's server.
* **Grafana's own alerting.** It would put the rules in Grafana's database
  instead of the repository, and make Grafana a second alerting path to keep
  in step.
* **A paging service** (PagerDuty, Opsgenie): an outside account for one
  person's lab.
* **ntfy on node1.** It dies with the monitoring it should report on.

## Consequences
* **Two repositories.** The monitoring stack is defined in the training
  repository (`docker/monitor`). It needs the rules mount, the rule files'
  path and the Alertmanager target there too. The alerting role joins that
  stack's Docker network by name, `skybot-monitor_default`.
* **Pin ntfy's own build.** Ubuntu Pro's ESM Apps source carries ntfy 2.11
  at apt priority 510, above every normal source, so apt installed it instead
  of ntfy's 2.38.1. Version 2.11 has no `alertmanager` template, and the first
  live alert reached the phone as raw JSON (2026-11-23). The role now pins
  ntfy's repository for that one package, at priority 600. It checks the
  installed version against the oldest one whose template was tested
  (`ntfy_min_version`). The lesson is to test the version that is installed,
  not the version that was meant to be: the template had been tried in ntfy's
  own 2.38.1 container image.
* **ntfy's own package runs the service as `ntfy`.** Ubuntu's build ran it
  as `_ntfy`. The role makes the account and owns the databases before the
  package installs. The old `_ntfy` account remains and is unused.
* **The gateway is a single point.** If the gateway is down, ntfy and the
  watchdog are down with it, and the lab also loses its route to the
  internet. Nothing in the lab can report that. The owner notices because the
  tailnet path stops answering.
* **Things that cannot alert yet:**
  * the backup alerts, until phase 4 publishes backup metrics;
  * the gateway's own reboot: `RebootOverdue` fires there after 8 days, by
    design, because the owner reboots it.
