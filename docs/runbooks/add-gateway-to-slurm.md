# Add the gateway (`gateway`) to Slurm and to the NFS export

Decision: [ADR-0007](../decisions/0007-gateway-joins-slurm.md). The inventory
(`inventory/hosts.yml`, private) already carries the change: `gateway` in
`slurm_nodes` with 12 CPUs, `RealMemory=15000`, `MemSpecLimit=2048` and its GPU
as `gpu:rtx5050:1`; no cluster-wide per-job memory cap; one firewall rule on
`gateway` (6818/tcp from the controller only); `gateway` added to the `/srv/data`
export. Values in angle brackets are in that inventory, never here.

Run the steps in order; continue only when a step's **check** passes.

## 1. Versions match
```bash
ssh <login>@node0 'sinfo -V'                       # slurm-wlm 25.11.2
ssh <login>@gateway 'apt-cache policy slurmd | head -3' # Candidate: 25.11.2-...
```
**Check:** the same 25.11 release on both.

## 2. Packages on `gateway`
```bash
ssh <login>@gateway
sudo apt update
sudo apt install -y slurmd munge nfs-common
```
**Check:** `slurmd -V` prints `slurm-wlm 25.11.2`.

## 3. The munge key (a secret: never into this repository, never onto a laptop)
Needs step 2 first: installing `munge` creates the `munge` user that owns the key.
```bash
# on node0: a copy only your login can read (0600, so shred can overwrite it afterwards)
ssh -t <login>@node0 'sudo install -m 0600 -o <login> /etc/munge/munge.key /tmp/munge.key'
# on the gateway: fetch it from node0, install it for munge, destroy the copy
ssh -t <login>@gateway 'scp node0:/tmp/munge.key /tmp/munge.key \
  && sudo install -m 0400 -o munge -g munge /tmp/munge.key /etc/munge/munge.key \
  && shred -u /tmp/munge.key \
  && sudo systemctl enable --now munge && sudo systemctl restart munge'
# on node0: destroy its copy
ssh <login>@node0 'shred -u /tmp/munge.key'
```
**Check:** `ssh <login>@node0 'munge -n' | ssh <login>@gateway unmunge | grep STATUS`
prints `STATUS: Success (0)`. (Paste commands without trailing `# ...` comments: zsh on a Mac
hands them to the command as arguments.) If any command in the chain fails, destroy both copies:
`ssh <login>@gateway 'shred -u /tmp/munge.key'; ssh <login>@node0 'shred -u /tmp/munge.key'`.

## 4. Dry run, one machine at a time (shows every change; changes nothing)
Ansible's "BECOME password" is the machine's **sudo password**. One
`--ask-become-pass` gives the SAME answer to every machine, so with a different
password on each machine, run one machine at a time; each run asks for that
machine's password. (`gateway` has passwordless sudo: just press Enter.) The lab
nodes' default `sudo` is sudo-rs, which Ansible cannot prompt through; the
inventory sets `ansible_become_exe: sudo.ws` (the classic sudo, still
installed), otherwise every lab node fails with "Timeout (12s) waiting for
privilege escalation prompt".
```bash
cd homelab-infra
make test
make check-host HOST=node1
make check-host HOST=node2
make check-host HOST=gateway
make check-host HOST=node0
```
**Check:** each run ends `unreachable=0 failed=0`. Expected differences:
node1 and node2 a new `slurm.conf`; `gateway` six (the 6818/tcp rule from the
controller, `slurm.conf`, `cgroup.conf`, `gres.conf`, starting and restarting
slurmd); `node0` a new `slurm.conf` and the `data` export gaining `gateway`.
Anything else: stop and read it.

## 5. Apply, in the same order (the controller last)
```bash
make apply-host HOST=node1
make apply-host HOST=node2
make apply-host HOST=gateway
make apply-host HOST=node0
```
`node0` goes last: its run re-exports the share and runs `scontrol
reconfigure`, after which the controller knows `gateway`. Until then `gateway`'s
slurmd is refused by the controller; that is expected and clears itself
(`ReturnToService=1`). Running jobs are not affected.
**Check:** `ssh <login>@node0 'sinfo -N -o "%N %T %c %m %G"'` lists
`gateway idle 12 15000 gpu:rtx5050:1` (if it says `down`, run
`ssh <login>@node0 'scontrol update nodename=gateway state=resume'`).

Permanent alternative (later, optional): store each machine's sudo password in
an encrypted Ansible Vault file per host (`inventory/host_vars/<host>/vault.yml`,
gitignored, `ansible_become_password`) and run with `--ask-vault-pass`: one
vault password, each machine still uses its own sudo password.

## 6. Mount the share on `gateway`
```bash
ssh -t <login>@gateway 'sudo mkdir -p /srv/data \
  && echo "<node0 lab address>:/srv/data /srv/data nfs vers=4.2,proto=tcp,hard,_netdev,nofail 0 0" | sudo tee -a /etc/fstab \
  && sudo mount /srv/data && ls /srv/data/<project>'
```
`nofail` matters on the gateway: a missing share must never stop it booting.
**Check:** the listing shows `code runs venv`.

## 7. Test jobs
```bash
ssh <login>@node0
srun -w gateway hostname                            # gateway
srun -w gateway --gres=gpu:1 nvidia-smi -L             # the RTX 5050
srun -w gateway ls /srv/data/<project>                  # the share, from a job
srun -N4 hostname                                   # all four machines
```

## 8. Keep CI in step
The deploy job reads its own copy of the inventory on the runner host. Make the
same change in `inventory/hosts.ci.yml` and copy it there, or the next deploy
removes `gateway` from Slurm again (see the
[runner runbook](self-hosted-runner.md) for the `docker cp` still needed
until the runner container is next recreated):
```bash
scp inventory/hosts.ci.yml <admin>@node1:homelab-runner/private/hosts.yml
```

## Running GPU or memory-heavy work outside Slurm on `gateway`
Slurm cannot see processes it did not start. Before a large GPU or real-time
stage of the SkyBot campaign:
```bash
ssh <login>@node0 'scontrol update nodename=gateway state=drain reason="gpu stage"'
# ... the stage runs ...
ssh <login>@node0 'scontrol update nodename=gateway state=resume'
```
Draining lets running jobs finish and starts none.

## Fast local disk
Jobs work in node-local scratch (`~/.skybot_slurm_scratch/` on `gateway`'s NVMe)
and copy only their results to the share; SkyBot's `slurm_wave.py` also copies
the code tree to that scratch before a run, so nothing touches NFS during it.
Write large trees on `node0`'s own disk or with `srun -w <node> tar cf - ... | tar xf -`;
small-file writes through the NFS mount are slow (about 0.4 MB/s measured).

## Undo
```bash
ssh -t <login>@gateway 'sudo systemctl disable --now slurmd'
# remove the gateway from slurm_nodes, its slurm_* lines, its export client and its 6818 rule in inventory/hosts.yml, then:
.venv/bin/ansible-playbook -i inventory/hosts.yml playbooks/site.yml --diff --limit 'slurm_nodes:nfs_server' --ask-become-pass
ssh -t <login>@gateway 'sudo umount /srv/data && sudo sed -i "\|/srv/data|d" /etc/fstab'
```
