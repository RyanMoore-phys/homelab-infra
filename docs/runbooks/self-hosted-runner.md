# Self-hosted runner for a public repository

GitHub warns against self-hosted runners on public repositories because a pull
request can run code on them. This setup makes that impossible; keep all of it.

## In GitHub (Settings)

1. **Actions -> General -> Fork pull request workflows**: "Require approval for
   all external contributors".
2. **Actions -> General -> Workflow permissions**: "Read repository contents".
3. **Environments -> New environment `homelab`**:
   * Required reviewers: yourself; "Prevent self-review" off (you are the only reviewer).
   * Deployment branches: `main` only.
   * Secrets: `HOMELAB_INVENTORY`, `HOMELAB_SSH_KEY`, `HOMELAB_KNOWN_HOSTS` (below).
4. **Code security**: turn on secret scanning, push protection and private
   vulnerability reporting.
5. **Branches -> protect `main`**: require the `ci` checks to pass.

## On the runner host

1. Register a **separate** runner for this repository with the label `homelab`,
   as a non-root user (a container is fine). Do not reuse a runner that other
   repositories can target: on a personal account a runner serves exactly one
   repository anyway, and sharing one would put every job next to the other
   repository's credentials.

   In this lab it is a second container on node1, `~/homelab-runner`, built
   from the **same image** as the runner of another repository but with its
   own registration (`homelab-node1`, label `homelab`), its own work volume
   and **no host keys mounted**. `./start.sh` asks for the one-time
   registration token (Settings -> Actions -> Runners -> New self-hosted
   runner), starts the container, waits for "Listening for Jobs" and then
   blanks the token in `.env`. A restart or reboot keeps the registration; a
   `docker compose down` needs a new token.

   That image has no Python and no `make`, and its distro Python is too old
   for the pinned Ansible, so `deploy.yml` installs the repository's Python
   version with `actions/setup-python` and runs the `make setup` steps
   directly. (Verified in a throwaway container from the same image.) The
   image's SSH config turns host-key checking off for its other job;
   `deploy.yml` turns it back on with `StrictHostKeyChecking=yes` and the
   `HOMELAB_KNOWN_HOSTS` file, passed as `--ssh-extra-args=` (not
   `--ssh-common-args`, which the inventory's own common args override).
   Tested: an empty known-hosts file is refused, the real key is accepted.
2. Create a dedicated deploy key **on the runner host** (it never leaves it,
   apart from the environment secret):
   `ssh-keygen -t ed25519 -f ~/.ssh/homelab_deploy -C homelab-deploy`
3. Create a dedicated `deploy` user on every machine (not your own login),
   install the public key for it limited to the runner host's lab address
   (`from="<runner lab IP>" ssh-ed25519 ...`), and give it password-free sudo
   (`/etc/sudoers.d/deploy`). Ansible cannot type a sudo password in CI, so
   this is the price of unattended deploys: the deploy key is root-equivalent,
   which is why it is pinned to one source address and lives only on the
   runner host and in the environment secret. Set `ansible_user: deploy` in the
   CI copy of the inventory.
4. Secrets for the `homelab` environment:
   * `HOMELAB_SSH_KEY`: the private deploy key.
   * `HOMELAB_KNOWN_HOSTS`: the host key of every machine, checked against
     the fingerprints shown on each console. Nodes are looked up by their
     inventory name (`HostKeyAlias`), the gateway by the address in
     `ansible_host`, so the entries must be written under those names.
   * `HOMELAB_INVENTORY`: `base64 < inventory/hosts.yml`, with two changes
     for a runner inside the lab: `ansible_user: deploy`, and the gateway's
     `ansible_host` set to its lab address (MagicDNS names do not resolve
     inside the runner's container).

## Running it

Actions -> deploy -> Run workflow on `main`, mode `check` first. Approve the
environment. Read the recap; run again with `apply` only if the check showed
what you expected. Full logs are in `~/homelab-deploy-logs` on the runner host.
