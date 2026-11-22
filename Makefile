# One entry point for everything. `make help` lists the targets.
SHELL := /bin/bash
VENV  := .venv
BIN   := $(VENV)/bin
PY    ?= python3
INV   ?= inventory/hosts.yml
LIMIT ?= all

.DEFAULT_GOAL := help
.PHONY: help setup guards lint syntax test check check-nodes apply check-host apply-host clean

help: ## List targets
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

$(BIN)/ansible-playbook: requirements-dev.txt requirements.yml
	$(PY) -m venv $(VENV)
	$(BIN)/pip install -q --upgrade pip
	$(BIN)/pip install -q -r requirements-dev.txt
	$(BIN)/ansible-galaxy collection install -r requirements.yml -p .ansible/collections
	@touch $@

setup: $(BIN)/ansible-playbook ## Create .venv with pinned Ansible, linters and collections

guards: ## Private-data guard, workflow guard, shellcheck
	scripts/check-private-data.sh
	scripts/check-workflows.sh
	shellcheck scripts/*.sh

lint: setup ## yamllint + ansible-lint (production profile)
	$(BIN)/yamllint .
	$(BIN)/ansible-lint

syntax: setup ## Playbook syntax against the example inventory
	$(BIN)/ansible-playbook -i inventory/hosts.example.yml playbooks/site.yml --syntax-check

test: guards lint syntax ## Everything CI runs (no lab access needed)

check: setup ## Dry run against the real lab: shows what WOULD change (LIMIT=host|group)
	$(BIN)/ansible-playbook -i $(INV) playbooks/site.yml --check --diff --limit '$(LIMIT)'

check-nodes: setup ## Dry run on the lab nodes, asking for their sudo password
	$(BIN)/ansible-playbook -i $(INV) playbooks/site.yml --check --diff --limit lab_nodes --ask-become-pass

apply: setup ## Apply to the lab (run `make check` first)
	$(BIN)/ansible-playbook -i $(INV) playbooks/site.yml --diff --limit '$(LIMIT)'

check-host: setup ## Dry run on ONE machine, asking for THAT machine's sudo password (HOST=name)
	@test -n "$(HOST)" || { echo "usage: make check-host HOST=<inventory name>"; exit 2; }
	$(BIN)/ansible-playbook -i $(INV) playbooks/site.yml --check --diff --limit '$(HOST)' --ask-become-pass

apply-host: setup ## Apply to ONE machine, asking for THAT machine's sudo password (HOST=name; run check-host first)
	@test -n "$(HOST)" || { echo "usage: make apply-host HOST=<inventory name>"; exit 2; }
	$(BIN)/ansible-playbook -i $(INV) playbooks/site.yml --diff --limit '$(HOST)' --ask-become-pass

clean: ## Remove the local virtualenv and collections
	$(RM) -r $(VENV) .ansible
