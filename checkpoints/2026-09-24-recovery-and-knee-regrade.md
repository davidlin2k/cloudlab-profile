# 2026-09-24: wedge recovery verdict + inline knee re-grade (DR-003 #4, #9)

## 1. Recovery test (decision 4) -- VERDICT: SELF-RECOVERING (performance bug)

Run: `wdiag.sh recovery mis-P4 20` at 15:21Z, immediately after the
first confirmed wedge (run order step 2). Flood 20 s at 790k, kill
senders, 5 s quiet, then a 60 s probe at 10k pps.

- Probe windows: `pkts=10048 rate=10000 drops=0 wp50_us=11-12` every
  second -- the probe delivered IN FULL.
- Counter deltas post-flood -> post-probe: rx_packets +605,263 (~= the
  probe's whole 600k budget), ch7_poll +18,474 (polling resumed),
  ch7_arm +18,268, ch7_aff_change +1,313, ch7_eq_rearm unchanged.
- The queue recovered ON ITS OWN after the flood stopped. Per DR-003
  decision 4 this is a PERFORMANCE BUG, not remote denial of service:
  no security@kernel.org embargo; the route is the netdev patch with a
  Fixes: tag and the evidence (student is the patch author).
- Gap: the devlink rx health reporter was not captured (this build's
  devlink rejected `health show ... rx`; "Reporter's name is expected"
  on the bare form). The probe verdict does not depend on it.

## 2. A/B interim (pre-registered in DR-002; grades at matrix end ~18:10Z)

- mis arms: wedge at onset t~0-2 s (WEDGE-CLASS: wire full ~790k pps,
  driver processing ~33/s).
- ali-P4 rep1/rep2 (IRQ 312 moved onto the kthread's CPU 9): CENSORED
  at 202/201 s -- no wedge under full flood (wire 156.4M pkts/202 s),
  aff_active = 314/687 per s (~0, the predicted positive control).
- Consistent with the pre-registration so far (ali: <=1/8 wedge, aff
  near zero). Final grades from wdiageval --summary at WDIAG-DONE.

## 3. Inline knee re-grade (decision 9, analysis-only on existing rows)

Model forms (spec v2/v4): co-located P0: F = 1e9/(c_app+c_net), and
F' = (1-h)F with h = the hidden softirq share; split P0X: F =
1e9/max(c_app,c_net) (its app core is clean, so the h correction does
not apply -- h is a co-location artifact by construction).

| Placement | Measured knee | Form | Predicted | Miss | +/-25% |
| --- | --- | --- | --- | --- | --- |
| P0 64 B (12 cost cells: c_app=1212 ns, c_net=283 ns) | 438.6 k (raw grid; 436.6 k recomputed on the filtered dataset) | F | 669.0 k | 53% | FAIL |
| P0 64 B | 438.6 k | F' = (1-0.33)F | 448.2 k | 2% | PASS |
| P0X 64 B (c_app=1118 ns, c_net=321 ns) | ~818 k (filtered crossing 790-1050k) | F = 1e9/max() | 894.3 k | ~9% | PASS |
| P0X 64 B | ~818 k | F' | 599.2 k | ~27% | (wrong form for split) |

h = 0.33 is C-006's independently measured hidden share (Fig 3, 26-42%
at 390k), NOT a fitted constant. The miss ratio of plain F at 64 B is
0.656 ~= (1-h): the model's error is exactly the invisible softirq time.

VERDICT (decision 9's bar): the two-cost model as F' + the split-core
form fits the existing inline rows within 25% (2% / 9%). Rule 4 stands
DOWN for now: the claim's shape is "predictable from per-packet costs
plus one calibration constant (the measured hidden share)" per spec
v4's pre-registered fallback. LIMITS: 64 B is the only complete grid;
512/1400 B rows were not collected (chain6 stopped per decision 1) and
the multi-size falsification bar (spec v4) remains OPEN until those
sizes land post-patch. "Predictive" is not claimed beyond 64 B.

## Data
rows-fig4.csv (22 rows, P0/P3/P4 64 B), rows-fig1-3*.csv (filtered
111-row dataset), /root/p1/wdiag/ (recovery + cell dirs), live-wdiag.log.
