# p1-STRIDING -- striding receive queue off (DR-005 task 4)

**Version:** 1 (2026-09-25; frozen before any run.)
**Question.** Does the striding RQ (multi-packet WQE) participate in
the wedge? (DR-005 task 4, "Striding receive queue off".)

## Design (the memo's, with fixed definitions)

- 8 cells after `ethtool --set-priv-flags enp195s0np0 rx_striding_rq
  off`; flag name confirmed with `ethtool --show-priv-flags` first
  (recorded in the batch log; if the name differs, supersede this spec
  before running).
- Arm/wiring/cell = the task 1 `unpin` arm and flood exactly as in
  specs/p1-RINGSIZE.md (790k pps, 64 B; wedge detector unchanged;
  120 s NO-WEDGE censoring).
- Baseline for comparison: the default-configuration unpin rate
  (AN-006: 8/8, onsets 9-19 s) and this batch's default-size cells.
- After the flag change: the full pre-flight (RSS key, port map,
  IRQ re-pin) and the queue-7 NAPI-thread rediscovery as in
  specs/p1-RINGSIZE.md. Step 4 recovery between cells as needed.

## Prediction

None supplied by the memo for this arm. Pre-registered rule: report
x/8 with the exact 95% binomial interval against the default-
configuration rate; any difference is descriptive only (no confirmatory
claim) unless the PI pre-registers a direction before these cells run.

## Outcome classes (pre-registered)

- **Striding off still wedges:** >= 7/8 cells wedged.
- **Striding off removes the wedge:** <= 1/8 cells wedged.
- **Intermediate:** 2/8 to 6/8 -- report the distribution and the
  onsets; make no claim.
- **Invalid:** as in specs/p1-RINGSIZE.md (wire gate / post-reset probe
  < 90% of 10k pps); re-run and report.
