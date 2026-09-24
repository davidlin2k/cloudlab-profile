# p1-LADDER-2: knee model validation (Fig 4) + the P1 deferral arm
Draft skeleton. Spec: p1-LADDER v2 (model form F). Evidence: H.

## The model in one line
knee = 1e9/(c_app+c_net) (P0/P2), (2/s)*1e9/(c_app+c_net) (P3, SMT
capacity factor m = 2/s), 1e9/max(c_app,c_net) (P4), costs in ns/pkt
measured in-situ per placement; s = 1.24 (calsmt matched pairs).

## Prediction table (fill measured + residual)
| placement | plen | c_app | c_net | knee_pred | knee_meas | err | verdict |
|---|---|---|---|---|---|---|---|
| P0 | 64 | 1060 | 517 | 634k | | | |
| P3 | 64 | 1456 | 1383 | (2/1.24)*1e9/2839 = 567k | | | |
| P4 | 64 | 1133 | 1138 | 880k | | | |
| P0 | 512 | | | | | | |
| P3 | 512 | | | | | | |
| P4 | 512 | | | | | | |
| P0 | 1400 | | | | | | |
| P3 | 1400 | | | | | | |
| P4 | 1400 | | | | | | |

Verdict rule (spec v2): any placement x size missing by >25% drops the
claim for that placement (skeleton contract: mark Dropped, record a
decision, change the claim list -- no post-hoc re-fit).

## P1 arm (pre-6.5 ksoftirqd deferral, mainline 6.4.0)
- deferral CPU profile (ksoftirqd/8 share of the core at each load)
- where P1 sits in the Fig 1 curves (caps near half a core?)
- low-load latency tax vs P2 (the "deferral" experience)

## Caveats
