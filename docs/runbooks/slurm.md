# Slurm

* `slurm.conf` is generated from the inventory and must be identical on every
  node; the role writes it everywhere and reconfigures the controller.
* The **munge key** (`/etc/munge/munge.key`) is a shared secret and is never in
  this repository. Copy it from the controller to a new node over SSH, owned by
  `munge:munge`, mode `0400`, then restart `munge`.
* node0, node1 and node2 trust each other in the firewall, which covers
  slurmd (6818), slurmctld (6817), srun callbacks (`SrunPortRange`) and MPI.
  The gateway admits slurmd (6818) from the controller only: start multi-node
  steps that include it on node0, and keep MPI on node0-2.
* After an outage nodes can stay `down*`; `ReturnToService=1` brings them back
  when they register, or `scontrol update nodename=<nodes> state=resume`.
* Test, from node0: `srun -N4 hostname` prints all four machines;
  `srun -w gateway --gres=gpu:1 nvidia-smi -L` shows the GPU.
* The gateway (`gateway`) as a fourth, uncapped node with its GPU:
  [add-gateway-to-slurm.md](add-gateway-to-slurm.md), [ADR-0007](../decisions/0007-gateway-joins-slurm.md).
  Before a large GPU or real-time job that is NOT a Slurm job, drain it:
  `scontrol update nodename=gateway state=drain reason="gpu stage"`; `state=resume` after.
* A GPU job asks for it: `srun --gres=gpu:1 ...` (`sinfo -o "%N %G"` shows it).
* Jobs per machine are on the project dashboard, with a System selector for
  every node:
  [slurm-dashboard.md](slurm-dashboard.md).
