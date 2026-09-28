# p1-WATCHDOG spec (DR-014 experiment 2) -- pre-registered before any run

## Question

Can an RX liveness watchdog in mlx5e bound every stall to ~T,
whatever the root cause?

## Background (DR-014, verbatim facts)

mlx5 has no steady-state RX watchdog: the RX recovery path
(mlx5e_health_channel_eq_recover) triggers only from
mlx5e_wait_for_min_rx_wqes at channel open; TX has timeout-driven
recovery; both poll the EVENT queue for missed events, and T1a shows
the event queue is empty during a stall -- even if they fired,
they'd find nothing.

## The patch

A per-channel check every T = 100 ms (delayed work per channel,
re-arming itself; stopped at channel close). Condition: the
completion queue has a ready entry at its consumer index AND the
poller has not run since the last check (a jiffies stamp updated in
mlx5e_napi_poll) -> napi_schedule. One cache-line read per channel
per period. Gated by an mlx5e module parameter rx_watchdog_ms
(default 0 = off).

## Pre-registration (DR-014, verbatim)

The pin46 arm, n = 8, with the watchdog at T = 100 ms.
- **Works if** the longest stranded gap is <= 2T in every cell, with
  no goodput loss against unstalled cells.
- **Works -> it goes upstream as an RFC with the report.** Users get
  bounded stalls now, and the vendor still owns the root cause.
- **Fails ->** the silence isn't recoverable by polling; that is
  itself decisive evidence for the vendor.

## Cell plan

- Same harness as p1-REARM (clnode323, IRQ on cpu 8, poller pinned
  cpu 46, single sender 10.10.1.10, 158 kpps / 45 s / plen 64, the
  W1 rules, preflight v2).
- Kernel: net-next HEAD + the rearm hook (inert) + the watchdog
  (rx_watchdog_ms=100 for these runs).
- Measurement: the probe's strand timeline (gap durations per cell)
  + the delivered rate per cell (the preflight counters).
- Run AFTER p1-REARM completes (DR-014's priority order).