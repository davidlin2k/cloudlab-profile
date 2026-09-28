# Confound-breaker candidate: Utah xl170 (mlx5 on an Intel platform)

DR-015 requires this check only if every T1B arm comes back clean
(<=1/8).  Pre-verified 2026-09-28 from the CloudLab hardware docs so
the decision can be made same-day:

- xl170 = HPE ProLiant XL170r, Intel Xeon E5-2640 v4 (Broadwell,
  10c, 2.4 GHz), 200 nodes at Utah.
- NIC: dual-port **Mellanox ConnectX-4 Lx** (MT27710), 25 Gb,
  PCIe v3.0 x8 -- the mlx5 driver.  (Also one 10G port usable per
  the docs; the experimental LAN = 25G to Mellanox 2410 switches.)
- So xl170 gives the Intel-CPU + mlx5-driver cell that neither the
  r6615 (AMD + mlx5) nor the c6420 (Intel + i40e) provides.

The three-way logic if T1B is clean (all arms <= 1/8):
  - r6615 (AMD+mlx5) stalls; c6420 (Intel+i40e) clean -> the confound
    is NIC *and* CPU both changed.  A stall on xl170 (Intel+mlx5)
    would isolate the NIC (mlx5) as the differing factor; a clean
    xl170 would leave the confound unbroken.

Caveats to check at reservation time, not from the docs: the ConnectX-4
Lx's firmware version (the T1a suspect = firmware stuck), whether the
25G link changes the 158k pps 64 B protocol's meaning (it does not --
same pps), and SMT/sibling layout for the arm mapping (Broadwell =
(2k, 2k+10) sibling pairs on this 2x10c part -- arms A/B/C remap).
