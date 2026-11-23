# PM-003: CI and deploys could not start for 21 h 36 min

**Date:** 2026-11-22 to 2026-11-23 · **Severity:** Low · **Status:** Fixed ·
**Duration:** 21 h 36 min

## Summary
The repository's Actions permissions were changed to allow only actions owned
by the repository's account. Both workflows use GitHub's own `actions/checkout`
and `actions/setup-python`, so every run was rejected before its first job:
six runs, five of them on pushes to `main`. The setting now allows actions
created by GitHub and requires every action to be pinned to a full commit SHA.

## Impact
* Five pushes reached `main` with no test results.
* One deploy was delayed.
* Nothing broken shipped: the first run after the fix tested the latest
  commit, which contained all five, and passed.

## Timeline (UTC)
| Time | Event |
|---|---|
| 2026-11-22 08:26 | Last successful run (CI on a Dependabot pull request) |
| Between 08:26 and 08:47 | Actions permissions changed to "the account's actions only" (exact time not in the public record) |
| 08:47 | First `startup_failure`: CI on push 3a97371 |
| 08:47, 08:47, 09:08 | Three more pushes, three more startup failures |
| 2026-11-23 06:18 | CI on push acd0c6a fails at startup |
| 06:19 | Deploy fails at startup; the owner reads the error: the two actions "are not allowed" |
| About 06:20 | Setting changed: allow actions created by GitHub; require full-SHA pinning |
| 06:23 | CI re-run on acd0c6a: success |
| 06:25 | Deploy: success |

## Detection
21 h 36 min late, when a deploy failed in front of the owner. A run that fails
at startup has no jobs and no logs, so the failures were easy to miss. And
because `main` does not require the CI checks, the pushes went through anyway.

## Root cause
A security setting was tightened without checking what the workflows depend
on. "Only my own actions" is safe in principle, but this repository uses
GitHub's checkout and Python setup actions.

Contributing factors:
* **Branch protection without required status checks.** `main` accepted
  pushes whose CI never ran.
* **Startup failures are quiet.** The badge turned red, but nothing reached
  the owner.
* **The setting change was not followed by a test run.**

## What went well
* The error message named the exact actions, so diagnosis took minutes.
* The fix kept a strict policy: GitHub's own actions only, pinned by SHA.

## What went badly
* Nearly a day without CI went unnoticed.
* The repository's documentation did not list the setting, so its right value
  was not written down anywhere.

## Action items
| Action | Status | Where |
|---|---|---|
| Document the Actions permissions setting and why | Done | [runner runbook](../runbooks/self-hosted-runner.md) |
| Require the `ci` checks on `main` | Open (owner setting) | GitHub branch protection |
| Re-run CI after any change to Actions or repository settings | Practice | This postmortem |

## Lessons
* A settings change is a change: test it the way code is tested, right away.
* A check that is not required can fail in silence.
