# p1-T1C-fw-notes: the ConnectX-6 firmware release-note reading
# (DR-013 T1c, facts only)

Question (the memo, verbatim scope): "Read the ConnectX-6 firmware
release notes after 20.43.3608 for any EQ, CQ or event fix, and
record the result. Do not flash firmware."

Node fact (ethtool -i enp195s0np0, 2026-09-27): driver mlx5_core,
firmware-version 20.43.3608 (DEL0000000010) -- the memo's stated
environment version confirmed on the node.

## The release line after 20.43.3608 (ConnectX-6 family RN,
networking-docs.nvidia.com/connectx6fwrn/20438004lts, retrieved
2026-09-27)

| Version | Content (the family change-history page) |
|---|---|
| 20.43.8002 | "This release contains important reliability improvements and security hardening enhancements. NVIDIA recommends upgrading..." -- NO named EQ/CQ/event fix. The Bug Fixes History page states for this version: "This version does not include bug fixes." |
| 20.43.3608 | "This version does not include any changes to the firmware content of this adapter card. The version has been updated to align with the other adapter cards in the ConnectX family." |
| 20.43.2566 | Same wording: a re-versioning with no content change. |
| 20.43.2026 | TWO bug fixes (bug-fixes-history page): 4152492 "Fixed a linkup issue vs a 3rd party switch (BCM53405)"; 4055323 "Fixed a reference counter issue that resulted in the firmware assertion 0x889f with CQ reference counter underflow to solve a race condition." |

## The result (the memo's question)

- **After 20.43.3608 there is no EQ, CQ, or event fix.** The only
  later release (20.43.8002) lists no bug fixes at all.
- The only CQ-related fix anywhere in the visible window (the CQ
  reference-counter underflow race, fw assertion 0x8899... 0x889f,
  internal ref 4055323) is in 20.43.2026 -- BEFORE the running
  version, so the node already carries it.
- Recorded as facts only; no inference about our stall is made
  here. (The bug report will state the environment as 20.43.3608
  and that no later release claims an EQ/CQ/event fix.)

Sources:
- https://networking-docs.nvidia.com/connectx6fwrn/20438004lts/changes-and-new-feature-history
- https://networking-docs.nvidia.com/connectx6fwrn/20438004lts/bug-fixes-history