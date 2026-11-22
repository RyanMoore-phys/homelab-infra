# ADR-0001: Ansible is the single source of truth for host configuration

**Status:** Accepted · 2026-11-21

## Context
The lab was configured by hand over SSH: drop-in files, ufw rules, exports,
`slurm.conf` copied between nodes. Hand edits drift, are hard to review, and
cannot be rebuilt after a disk failure. `slurm.conf` in particular must be
byte-identical on every node.

## Decision
Every setting that matters is an idempotent Ansible role, driven by one
inventory. Changes go through a pull request, CI, and a `--check` dry run
before `apply`. Hand changes made during the initial hardening were encoded
afterwards and verified with a check-mode run reporting `changed=0`.

## Consequences
* Rebuilding a node is `make apply LIMIT=<node>`.
* Roles respect pre-existing hand configuration where rewriting it would be
  churn (the router role detects an existing NAT rule before adding one).
* Roles are additive for firewall rules and keys: removing access is still a
  deliberate manual step, recorded in the hardening log.

## Alternatives considered
* **Shell scripts:** not idempotent, no dry run, no diff.
* **NixOS / immutable images:** stronger guarantees, but a rebuild of four
  working Ubuntu machines for little gain at this size.
