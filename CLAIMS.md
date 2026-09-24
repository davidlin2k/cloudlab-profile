# Claims ledger

| ID | Claim | Evidence | Level | Status | Last reviewed |
| --- | --- | --- | --- | --- | --- |
| C-001 | Phase alignment (aligned vs random vs per-engine) does not change delivered throughput through a proxy at 25k-75k streams under one-token-one-segment emission. | C1-CLOCK.1 | H | Pending | 2026-09-24 |
| C-002 | The decode step clock is smeared at the wire above a few thousand streams; the arrival signature is a 25ms sawtooth, not instant incast. | C1-CLOCK.2 | H | Pending | 2026-09-24 |
| C-003 | The host stack fails on per-token user-space work before kernel receive limits at this scale (HAProxy 13.2 cores at 1.88M tok/s; softnet drops 0.002%, squeeze 0). | K-series, AN-001 | H | Contested | 2026-09-24 |

