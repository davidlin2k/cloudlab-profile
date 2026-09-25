# W3: memcached TCP knee, co-location cost, and the kill test (DR-004 task 4)

Status: v3 FROZEN 2026-09-25T10:15Z (definition amendment only; P1-P4
numbers unchanged). v2's scan stop rule fired at 300k with no delivered-ratio
crossing on either arm (AN-008 extension): TCP flow control holds delivered =
offered past saturation, so the v1/v2 knee definition cannot fire before
client throttling. v3 knee definition: the smallest offered load with
bottleneck CPU >= 95% (P0: CPU 8; P0X: CPU 9) -- the saturation knee, which
is also the UDP knee's nature. From the scan: P0 knee = 190k, P0X = 260k.
The delivered-ratio rule is retained as P2's collapse check. Everything else
is v2 (09:50Z), which is v1 (09:15Z) plus the gate split and scan extension. v1 froze 09:15Z before any cell; the
first 14 knee-pass cells (09:16-09:36Z) revealed two v1 defects (see AN-008):
(1) no knee to 130k so the scan range extends (160k-300k added; the 30-130k
cells stand as valid data); (2) the Skipped=0%/op_q<=16 gates assume pre-knee
cells while P2 requires overload cells -- gates are now split below/above the
knee (below: open-loop as v1; above: backpressure is the knee signal, client
CPU < 80% on all five senders is the validity check). P1-P4 numbers UNCHANGED.
A spec change after runs start is a new version (DR-004 standing rule).

## Question

Does the receive/worker co-location cost (C-005, C-012) survive TCP, and does
the collapse survive TCP flow control? Memcached decides the paper's TCP claims
(the Oct 16 gate).

## Setup (fixed)

- rx: memcached 1.6.24 (`-t 1 -c 32768 -p 11211 -l 10.10.1.1 -u root -m 256`),
  worker pinned per arm. tx0-tx4 (10.10.1.10-14): five INDEPENDENT mutilate
  masters (agent mode was built and tested end-to-end but is restart-fragile:
  a killed master leaves its ZMQ agents unresponsive; see notes/p1-CAL2.md).
- Steering: `ethtool -N enp195s0np0 flow-type tcp4 dst-port 11211 action 7`
  (ntuple on; old rules deleted first). Landing gate per run: rx7 purity
  >= 99% over a gated burst (cal-3/3b measured 99.93-99.95%).
- Queue 7: IRQ 312 effective-affinity CPU 8; threaded-NAPI kthread PID 1594438
  pinned to CPU 8 in BOTH arms (W1/W2 placement semantics: the receive side is
  CPU 8; the arm difference is the worker's CPU). Provenance: AN-006A.
- DB: 100,000 records, 30 B keys, 32 B values, keyspace -r 100000;
  90% GETs (`--update 0.1`, pinned from Connection.cc:127). `--loadonly` per
  cell before the measure; `Misses` must be 0.0% (validity gate).
- Load model: open-loop Poisson arrivals (`-i exponential:1`, rescaled by
  mutilate to the --qps target). Per master: `-T 2 -c 8 -d 32 -K 30 -V 32
  -u 0.1 -r 100000 -i exponential:1 -w 5 -t 65 -C 1 -Q 200 -D 4 --save`.
  PACING LAW (cal-3b, 10 masters, ±0.2%): achieved QPS per master = q / c.
  The runner sets q = (target/5) * c and records achieved per cell.
- Instrument: `perf stat -A -a -C 8,9 -e ref-cycles` bracketing [t0+6, t0+70]
  of the 65 s measure window (basis per C-014/AN-007; 3.250 GHz TSC).

## Arms

| arm | worker | receive (IRQ+kthread) | busy_poll |
|-----|--------|-----------------------|-----------|
| P0  | CPU 8  | CPU 8 (co-located)    | off       |
| P0X | CPU 9  | CPU 8 (separated)     | off       |
| BP  | CPU 8  | CPU 8; worker busy-polls in its own epoll context | on (busy_poll=50, busy_read=50) |

## Calibration (cal-3b, 20,000 aggregate QPS = 0.32x predicted knee)

Requests in bracket: 1,278,596 (P0), 1,278,952 (P0X).

| arm | per-CPU cost (ref-cycles / ns per request) | predicted knee |
|-----|--------------------------------------------|----------------|
| P0  | total 52,424 rc = 16,130 ns (CPU8+9)       | 1e9/16,130 = **62.0k QPS** |
| P0X | receive (CPU8) 19,714 rc = 6,066 ns; app (CPU9) 39,448 rc = 12,138 ns | min(1e9/6066, 1e9/12138) = **82.4k QPS** |

Sensitivity form (P0 from P0X's parts summed): 1e9/18,204 = 54.9k QPS.
Idle p99 (200 QPS trickle): P0 104.1 us, P0X 105.5 us; SLO = 10x = 1.05 ms.

## Predictions (pre-registered before any W3 cell)

- **P1 (knee).** F_P0 = 62.0k QPS; F_P0X = 82.4k QPS. Miss bar +/-25%
  (P0: 46.5-77.5k; P0X: 61.8-103.0k). A miss outside the bar = the cost model
  fails for TCP and the model's claim scope shrinks (recorded, not bent).
- **P2 (kill criterion).** At 2.0x the measured knee, offered load verified
  open-loop (Skipped TXs = 0.0%, op_q p99 <= 16 of depth 32): if delivered
  goodput >= 90% of the knee goodput (plateau), the collapse does NOT survive
  TCP -- the transport-independence claim dies (Refuted, recorded). If
  delivered goodput < 70% of the knee goodput (fall), the collapse survives
  TCP (claim stands). 70-90%: inconclusive, add reps.
- **P3 (wake-delay x5).** At the knee load, p99(P0) / p99(P0X) >= 5 (the
  C-012 mechanism: the worker's wake wait sits behind receive processing).
- **P4 (SLO direction).** P0 violates the 1.05 ms SLO at some load <= knee;
  P0X holds the SLO through the knee. Numbers fill the abstract's TCP slot.

## Run order (literal)

1. Knee-pass: loads 30k, 45k, 60k, 75k, 90k, 110k, 130k QPS (v1, done) plus
   160k, 190k, 220k, 260k, 300k QPS (v2 extension) x 1 rep x {P0, P0X}
   (24 cells). The measured knee = the largest offered load with delivered
   >= 95% of offered, per arm; the load table scales to P0's knee. The scan
   stops when both arms have crossed (delivered < 95% of offered) or 300k.
2. Main matrix: 0.25, 0.5, 1.0, 1.5, 2.0x P0's measured knee (190k) =
   47.5k, 95k, 190k, 285k, 380k QPS x 3 reps x {P0, P0X, BP} (45 cells).
3. Mechanism: perf sched on the 0.25x pair {P0, P0X} (2 captures).

## Validity gates (per cell; v2 split)

All cells: Misses = 0.0%; landing purity >= 99%; bracket inside the measure
window; achieved recorded per cell (offered axis = achieved). A failed gate
voids the cell.

At or below the knee (v1): Skipped TXs = 0.0%; op_q p99 <= 16.

Above the knee (v2): Skipped TXs and op_q are the backpressure/knee SIGNALS
(recorded, not gates); validity = all five sender nodes' CPU < 80% during the
window (senders not bottlenecked) and every master's samples file non-empty.

## Known gaps

- CONFIG_IRQ_TIME_ACCOUNTING is not set: /proc/stat partitioning remains
  broken (AN-007); PMU ref-cycles is the accounting basis.
- The knee-pass uses 1 rep per point (scale-finding only; the 3-rep rule
  applies to the main matrix).
