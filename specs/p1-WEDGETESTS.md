# Spec p1-WEDGETESTS: the four wedge-separation tests

Pre-registered 2026-09-25 (UTC), BEFORE any run, per DR-005 ("Four tests
separate them. Pre-register each"). The two alternatives and the four
tests are the PI's verbatim (DR-005); the outcome mappings below restate
the PI's discrimination logic without adding predictions the PI did not
make.

## The alternatives (DR-005, verbatim)

- (A) Pending work, no event. Completions were already pending when the
  queue was re-armed, and re-arming produced no event for them.
- (B) Nothing to complete. The receive ring held no posted buffers after
  the last poll, so no new completion could occur, and only NAPI reposts
  buffers.

Both are "no event source while the ring is starved".

## The four tests and their discriminating outcomes

1. State dump during a wedge: `devlink health diagnose <pci-dev> reporter
   rx` (list reporters first with `devlink health` -- the earlier failure
   was syntax). Reports the receive queue's posted-buffer counts, the
   completion-queue consumer and producer indices, and the buffer-refill
   (ICOSQ) state.
   -> Under A, completions are pending. Under B, zero buffers are posted.
2. Ring size 1024 against 8192, unpinned arm, 8 cells each.
   Prediction (PI, verbatim): if starvation is necessary, the hazard
   falls at least 4x with the larger ring.
3. Striding receive queue off (ethtool --set-priv-flags <dev>
   rx_striding_rq off): removes the multi-packet refill path.
   -> A change in wedge behavior localizes the starvation to the
   striding/refill path; no change moves suspicion to the re-arm path.
4. Recovery interrupt's source: a kprobe on mlx5e_completion_event
   recording the completion-queue number shows whether the receive queue
   or the refill queue restarts it.

## Run protocol

- Cells follow the AN-006 matrix conditions (W1 flood, threaded-NAPI
  arm, unpinned sender unless the test says otherwise); 8 cells per ring
  size for test 2.
- Onset/recovery timeline capture stays as in AN-006A (the established
  instrument); the state dump is taken while a wedge is active (facts:
  the same timestamps as the timeline).
- Facts only in the note; the PI reads the timelines (the AN-006A
  convention continues). The netdev report is drafted after these tests
  (DR-005 order item 3) and goes for the PI's review; DR-005 lifts the
  embargo ("it's a performance bug, so there's no embargo") and the
  report is cc'd to the mlx5 maintainers.
