#!/usr/bin/env bash
# Job-started hook of the homelab runner (ACTIONS_RUNNER_HOOK_JOB_STARTED).
#
# The runner holds a key that is root on every lab machine, and it serves a
# PUBLIC repository. A pull request from a fork can add its own workflow that
# targets this runner, and GitHub runs the pull request's version of the
# workflows, so a guard inside this repository's workflows cannot stop it.
# Organisations can limit a runner to chosen workflows with runner groups;
# personal accounts cannot. This hook does the same job on the runner itself:
# it runs before checkout and before any step, and fails every job that is not
# deploy.yml on main, started by hand by the owner. A refused job never runs
# a line of its own code here.
#
# It is mounted read-only into the container, so a job cannot rewrite it.
set -u

want_repo="RyanMoore-phys/homelab-infra"
want_workflow="${want_repo}/.github/workflows/deploy.yml@refs/heads/main"
want_actor="RyanMoore-phys"

refuse() { echo "runner hook: job REFUSED: $1" >&2; exit 1; }

[ "${GITHUB_REPOSITORY:-}" = "$want_repo" ]       || refuse "repository is not ${want_repo}"
[ "${GITHUB_EVENT_NAME:-}" = "workflow_dispatch" ] || refuse "event '${GITHUB_EVENT_NAME:-unset}' (only workflow_dispatch)"
[ "${GITHUB_REF:-}" = "refs/heads/main" ]          || refuse "ref '${GITHUB_REF:-unset}' (only refs/heads/main)"
[ "${GITHUB_WORKFLOW_REF:-}" = "$want_workflow" ]  || refuse "workflow '${GITHUB_WORKFLOW_REF:-unset}' (only deploy.yml on main)"
[ "${GITHUB_ACTOR:-}" = "$want_actor" ]            || refuse "started by someone other than the owner"
[ "${GITHUB_TRIGGERING_ACTOR:-}" = "$want_actor" ] || refuse "re-run by someone other than the owner"

echo "runner hook: job allowed (deploy.yml on main, started by the owner)"
