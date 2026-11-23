# Slurm jobs per machine on the project dashboard

The training project's dashboard (Grafana on node1) has a
**System** menu at the top, like the host menu of the Node Exporter dashboard:
every machine in the cluster (`gateway`, `node0`, `node1`, `node2` in this repository's names). The section under the campaign controls
then shows that machine:

| Panel | What it reads |
|---|---|
| `<system>` in Slurm | the node's Slurm state (idle, mixed, allocated, drained, down); the gateway reads *not in Slurm* until [it joins](add-gateway-to-slurm.md) |
| CPUs in use | CPUs Slurm has given to jobs, of the node's total |
| Free memory | free memory as Slurm last read it (everything on the machine) |
| Slurm jobs running here | running Slurm jobs on that node |
| Waiting in Slurm | jobs not yet placed on any node, with the reason |
| Jobs on `<system>` | every Slurm job that ran there, newest first, kept permanently; on the gateway also its training campaign's tasks |

## How the data gets there

```
node1 crontab, every 2 min
  slurm_board_collect.py   squeue -t all + sinfo -N  ->  ~/.slurm_board/slurm_snapshot.json   (times converted to UTC)
  slurm_board_push.sh      docker cp into the ingest container, then slurm_board_merge.py
                           ->  /data/campaign_history.db  tables slurm_jobs (never deleted), slurm_nodes, slurm_meta
Grafana (frser-sqlite, uid campaign-board)  reads that database, filtered by $system
```

* node1 runs both steps because it is a Slurm node with the client commands
  and the monitor host; the controller has no cron. Nothing is installed: the
  merge is standard-library Python piped into the existing ingest container.
* The scripts live on the NFS share in `/srv/openmc/<project>/tools/`; their
  source and contracts are in the SkyBot repository (`tools/slurm_board_*.py`,
  `scripts/slurm_board_push.sh`, `tests/campaign/_slurm_board_smoke.py`).
* The controller keeps a finished job for `MinJobAge` (300 s), so a 2-minute
  poll sees every end. A job that vanished between polls is recorded as
  `ENDED (not seen)` with its last-seen time, never an invented end.

## Checks and repair

```bash
ssh <login>@node1 'crontab -l | grep slurm_board; tail -3 ~/.slurm_board_push.log; tail -2 ~/.slurm_board/collect.log'
```
A stale "Slurm data as of" time means the cron line is missing or a step
fails; the logs say which. To rebuild the Slurm tables from scratch is not
possible (Slurm accounting is off: `AccountingStorageType=accounting_storage/none`),
so the history table is never dropped. Enabling `slurmdbd` would give a full
job history independent of this board.
