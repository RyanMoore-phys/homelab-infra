# PM-001: A pull request could have run code on the self-hosted runner

**Date:** 2026-11-22 · **Severity:** High (no use found) · **Status:** Fixed ·
**Duration:** 14 h 22 min (key at risk for at most 2 h 35 min)

## Summary
The homelab runner on node1 was registered to this public repository before
anything on the runner itself limited which jobs it would take. A pull
request can add its own workflow file that targets a self-hosted runner, and
GitHub runs the pull request's version of the workflows, so the repository's
own guards did not protect it. A job-started hook on the runner now refuses
every job except the owner's manual deploy from `main`.

## Impact
* **Observed:** none. In the window there were no pull-request runs at all
  (GitHub's run history), and the runner's log shows no job until the owner's
  deploys the next morning.
* **Possible:** a pull request from anyone could have run code in the runner
  container. From 20:32 the container also held the deploy key, which logs in
  as the admin account, with password-free sudo, on all four machines: control
  of the whole lab.

## Timeline (UTC)
| Time | Event |
|---|---|
| 2026-11-22 08:26 | Last pull-request run before the runner existed (CI on GitHub's own runners) |
| 08:45 | Homelab runner registered on node1 (`.runner` created) |
| 20:32 | Deploy key created on node1; copied into the runner container after this |
| Evening | While reviewing whether the deploy was safe, GitHub's documentation is read against the design: the docs' claim that a pull request "can never reach" the runner is wrong |
| 23:07 | Job-started hook in place (root-owned, read-only); runner back to "Listening for Jobs" |
| 2026-11-23 06:27 | First deploy through the hook: allowed and succeeded |

## Detection
By review, not by an alarm: the question "is this safe enough to run?" led to
reading how GitHub schedules pull-request workflows. Nothing would have
reported a pull-request job on the runner: the runner keeps a log, but no one
watched it.

## Root cause
GitHub runs the workflow files of the pull request itself, so guards written
into this repository's workflows (dispatch-only triggers, an owner check, a
protected environment) only bind the repository's own files. A pull request
can add a new workflow with `runs-on: [self-hosted, homelab]`.

Contributing factors:
* **No platform control.** Organisations limit runners with runner groups;
  personal accounts do not have them.
* **Repository guards gave false confidence.** `check-workflows.sh` checks the
  repository's own workflows, and the documentation claimed more than that.
* **Approval of fork pull requests was left at GitHub's default,** which
  approves returning contributors automatically.

## What went well
* Found before any pull request arrived, and before the deploy key was ever used.
* The fix lives on the runner, where a pull request cannot change it, and was
  tested with 11 cases before going live.
* Nothing private is stored in GitHub, so there was no secret to rotate.

## What went badly
* The runner was registered and given a powerful key before its limits were
  in place.
* Documentation stated a guarantee nobody had tested.

## Action items
| Action | Status | Where |
|---|---|---|
| Job-started hook: only `deploy.yml` on `main`, started and re-run by the owner | Done | [`runner/job-started.sh`](../../runner/job-started.sh) |
| Test the hook: 1 allowed, 10 refused cases | Done | [verification](../verification.md) |
| Correct the docs; amend the decision record | Done | [ADR-0005](../decisions/0005-self-hosted-runner-on-a-public-repo.md), [CI/CD](../cicd.md) |
| "Require approval for all external contributors" | Owner setting; not readable without admin access | [runner runbook](../runbooks/self-hosted-runner.md) |

## Lessons
* A runner on a public repository must refuse work by itself; the repository
  cannot protect it.
* Give a component its limits before its credentials.
* A security claim in the docs needs a test that would fail if it were false.
