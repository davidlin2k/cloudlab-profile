# Topology of @clnode366 (the locality map, DR-012 step 1)

Collected 2026-09-27 from /sys and lscpu. `lstopo` is not installed
on the node; the /sys cache map below carries the same substance.

## The machine

- AMD EPYC 9354P 32-Core, 1 socket, 64 threads (SMT2), 4 NUMA nodes
  (NPS4).
- node0 = 0-7,32-39; **node1 = 8-15,40-47**; node2 = 16-23,48-55;
  node3 = 24-31,56-63.
- **The NIC under test (0000:c3:00.0, mlx5, ConnectX-6 MT28908) is
  NUMA node 1.**
- The second port is a ConnectX-6 Lx (0000:c4) on the same node.
- lscpu's L3 domains (index3, shared_cpu_list):
  - cpu 8: L3 shared 8-11,40-43 (32 MiB); SMT sibling 40.
  - cpu 10: L3 shared 8-11,40-43 (the SAME L3 as cpu 8); SMT
    sibling 42.
  - cpu 46: L3 shared 12-15,44-47 (a DIFFERENT L3 from cpu 8, the
    adjacent CCX in the same NUMA node); SMT sibling 14.

## The map that matters

| cpu | NUMA | L3 domain | same L3 as the IRQ core 8? |
|---|---|---|---|
| 8 (IRQ 312's core) | node1 | {8-11,40-43} | -- |
| 10 | node1 | {8-11,40-43} | **YES** |
| 46 | node1 | {12-15,44-47} | **NO (adjacent CCX)** |

All three are in the NIC's NUMA node; all three are off the IRQ's
affinity mask. The asymmetry (pin10 0/8 vs pin46 5/8) sits exactly
on the L3/CCX boundary between the poll and the event handler, not
on the NUMA boundary and not on the mask.

## Consequence for the stale-arm hypothesis (DR-012)

With the poll on 10, the arm doorbell and the event handler's
arm_sn increment share one L3 -- the read-modify interleave window
is L3-coherent-short. With the poll on 46 (or roaming), the
interleave crosses the CCX boundary -- the window widens. This is
consistent with every count to date (pin10 0/8, pin46 5/8, unpinned
8/8, the at-hop-onset enrichment) and is the DR-012 step 3 curve's
prediction basis: stall probability rises with L3 distance from
cpu 8.

The full per-cpu cache map (all 64 cpus, index0-3) is archived on
the node at /root/p1/topo-cache-dump.txt and in the repo at
analysis/dr012/topology/.
