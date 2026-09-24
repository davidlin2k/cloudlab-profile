# 2026-09-24 — AN-003 wedge A/B verdict: all placements wedge at 790k

Status: wedge-m0/m1 matrix complete (24 cells, placement P2/P3/P4 x
PIN_IDLE 0/1 x 4 reps at 790k, interleaved). Verdict in AN-003.

## Verdict

ALL 24 cells wedged. What varies is the onset time (t=2..68 of the 71 s
budget), not whether the wedge happens:

| Placement | wedged / cells | onset range |
| --- | --- | --- |
| P2 (thread, app core) | 8/8 | t=2..3 (early) |
| P3 (thread, SMT sibling) | 8/8 | t=2..20 |
| P4 (thread, other core) | 8/8 | t=2..68 (latest onsets) |

- C-state pinning (PIN_IDLE=1, /dev/cpu_dma_latency=0) does NOT change
  the outcome: both halves 12/12 wedged. AN-003's C-state hypothesis is
  REFUTED (this was the A/B's design question).
- "P2 immune" (first matrix) is REFUTED: it was onset luck within the
  measurement window.
- Mechanism resolved to the last observable layer: the queue delivers
  seconds of traffic, then falls silent to a ~0 trickle for the rest of
  the budget (win-emitter gaps of 60+ s), socket drops ~0 (the loss is
  at/below the ring). Trigger candidates narrowed: NOT C-states, NOT
  pause frames (diag round), NOT sender-side (5/5 clean budgets where
  observed). Open: affinity/power history; the napi_schedule -> kthread
  wakeup path under sustained full-ring pressure.

## Consequences for the figures and claims

- Fig. 1 at >=790k: per-placement goodput there is TIME-TO-WEDGE, not
  capacity. Curves need onset-variance error bars + wedge markers
  (already designed into analysis/p1_figures.py).
- Fig. 4: the measured knee at 64 B is wedge-limited for the threaded
  placements -- the form-F falsification pressure (42-91% misses) is
  partly this: the model has no wedge term. Grading on fig4's own cells;
  if the miss holds, rule 4 applies with AN-003 as the mechanism.
- Fig. 5's ladder must treat "wedge onset" as a failure the controller
  detects and re-arms around (open design item for p1ctl v2).

## Instrument note (AN-004, corrected same day)

20/24 cells carry launch-delayed senders (throttled ssh; logs truncate
at the next cell's kill). Their offered-rate axes are excluded from
curves via the analyzer's new snd_full column; the wedge verdict is
denominator-independent and holds for all 24. The first AN-004 draft's
clock-step mechanism is struck (k2_rx's span clock is monotonic).

## Data locations

- rows: analysis/rows-wedge-m{0,1}.csv (regenerating with snd_full).
- raw: rx:/root/p1/results/wedge-m{0,1}/ + classification output in this
  checkpoint's tables (classifier: analysis/p1_wedge_ab.py).
- records: anomalies/AN-003.md (verdict), anomalies/AN-004.md (corrected).
