# Self-hosted runner for a public repository

GitHub warns against self-hosted runners on public repositories: a pull
request can add its own workflow that targets the runner, and GitHub runs the
pull request's version of the workflows. A rule inside this repository's
workflows cannot stop that. Here the runner refuses those jobs itself; keep all
of the layers below.

## On the runner host (node1)

Everything is in [`runner/`](../../runner), copied to `~/homelab-runner` on
node1.

1. **A separate registration.** Its own runner for this repository, label
   `homelab`, as a non-root user in a container: the same image as the other
   repository's runner on node1, with its own registration and its own work
   volume. Do not reuse a runner that another repository can target: jobs
   would run next to that repository's credentials. `./start.sh` asks for the
   one-time registration token (Settings -> Actions -> Runners -> New
   self-hosted runner), starts the container, waits for "Listening for Jobs"
   and then blanks the token in `.env`. A restart or reboot keeps the
   registration; recreating the container (`docker compose down`, a changed
   compose file) needs a new token.
2. **The job-started hook** ([`runner/job-started.sh`](../../runner/job-started.sh)),
   set with `ACTIONS_RUNNER_HOOK_JOB_STARTED`. It runs before checkout and
   before any step, and fails every job that is not `deploy.yml` on `main`,
   started (and re-run) by the owner. Organisations get the same limit from
   runner groups; personal accounts do not have them. It is mounted read-only
   and owned by root in the container, so a job cannot rewrite it. Tested with
   11 cases: the owner's manual deploy is allowed; a pull request event, another
   branch, another workflow file, `deploy.yml` from a pull request's merge ref,
   another actor or re-runner, another repository, and no variables at all are
   refused.
3. **The runner's key.** One dedicated key on node1
   (`ssh-keygen -t ed25519 -N "" -f ~/.ssh/homelab_deploy`), mounted
   read-only at `/home/runner/.ssh/homelab_deploy`. Never uploaded to GitHub.
4. **Private files**, in `~/homelab-runner/private/` (mode 700, gitignored as
   `runner/private/`), mounted read-only at `/home/runner/homelab`:
   * `hosts.yml`: a copy of `inventory/hosts.ci.yml`, the inventory with the
     gateway's `ansible_host` set to its lab address (MagicDNS names do not
     resolve inside the container).
   * `known_hosts`: a copy of `inventory/known_hosts.ci`, the host key of
     every machine, checked against the fingerprints shown on each console.
     Nodes are looked up by their inventory name (`HostKeyAlias`), the gateway
     by the address in `ansible_host`, so the entries are written under those
     names.

   After changing the inventory:
   ```bash
   scp inventory/hosts.ci.yml <admin>@node1:homelab-runner/private/hosts.yml
   ```
   **Until the container is next recreated** it holds copies placed with
   `docker cp` (2026-11-22, to avoid a new registration), not the mounts, so
   also run on node1:
   `docker cp ~/homelab-runner/private/hosts.yml homelab-runner:/home/runner/homelab/hosts.yml`.
   After the next `./start.sh` the mounts take over and the `scp` alone is
   enough.
5. **Who it logs in as.** The owner's admin account on every machine (owner
   decision 2026-11-22, [ADR-0005](../decisions/0005-self-hosted-runner-on-a-public-repo.md)).
   The `authorized_keys` role installs the runner's public key there, limited
   with `from=` (`ci_runner_from`: the runner host's lab address; on the
   runner host itself also its Docker networks, because the container reaches
   its own host from its bridge address), and the `sudo_nopasswd` role gives that
   account password-free sudo, so Ansible runs unattended. A dedicated
   `deploy` user with sudo limited to the commands Ansible needs is the
   stricter option.
6. **Python and host keys.** The image has no Python and no `make`, so
   `deploy.yml` installs the repository's Python version with
   `actions/setup-python` and runs the `make setup` steps directly. The
   image's SSH config turns host-key checking off for its other job;
   `deploy.yml` turns it back on with `StrictHostKeyChecking=yes` and the
   mounted `known_hosts`, passed as `--ssh-extra-args=` (not
   `--ssh-common-args`, which the inventory's own common args override).
   Tested: an empty known-hosts file is refused, the real one is accepted.

## In GitHub (Settings)

1. **Actions -> General -> Fork pull request workflows**: "Require approval
   for all external contributors" (a second layer behind the hook).
2. **Actions -> General -> Workflow permissions**: "Read repository contents".
3. **Environments -> `homelab`** (created by the first deploy run, or by hand):
   required reviewer yourself, "Prevent self-review" off, deployment branches
   `main` only. It holds no secrets.
4. **Code security**: secret scanning, push protection and private
   vulnerability reporting on.
5. **Branches -> protect `main`**: require the `ci` checks to pass.

## Running it

Actions -> deploy -> Run workflow on `main`, mode `check` first. Approve the
environment if a reviewer is set. The "Set up runner" step shows
`runner hook: job allowed`. Read the recap; run again with `apply` only if
the check showed what you expected. Full logs stay in the runner's work
volume:
```bash
docker exec homelab-runner ls /home/runner/_work/_homelab-deploy-logs
```
