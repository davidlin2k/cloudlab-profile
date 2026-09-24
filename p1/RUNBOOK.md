# p1 session runbook -- what runs when fig1-3 finishes (2026-09-24)

Binaries are FROZEN until Fig 4 + the P1 arms complete (one
implementation across the arms of Figs 1-4): the wp50 k2_rx and the
profile k5blast exist only in the repo until then.

## A. fig1-3 rest batch ends (poll batch-fig1-3r.log for BATCH DONE)
1. `sudo python3 /root/k2/p1_analyze.py fig1-3 > /root/p1/rows-fig1-3.csv`
   and pull it; run analysis/p1_figures.py (Figs 1-3 drafts).
2. Gate audit: every manifest's 4 gates; failures = diagnostic only.
3. Prediction check against spec v1 (numbers); write
   notes/p1-LADDER-1.md + FINDINGS entry + checkpoint 2026-09-24-fig1-3
   (both dirs), commit + push.

## B. P1 kernel session (t6) -- batched per the skeleton
1. `sudo bash /root/k2/p1-kernel.sh install` (debs already in
   /root/p1/kdeb) -- verify grub entries printed.
2. `sudo bash /root/k2/p1-kernel.sh arm-p1` then `sudo reboot`.
3. After boot: verify `uname -r` == 6.4.0-060400-generic; run
   `sudo bash /root/k2/p1prep.sh` (re-sets RSS key, re-pins IRQs,
   rebuilds nothing -- binaries are user-space) + lp.sh landing check.
   If mlx5 refuses to bind on 6.4 (fw compat), stop and record AN.
4. Run P1 arms: `sudo bash -c 'SPEC_VERSION=1 nohup bash /root/k2/
   p1batch.sh /root/k2/p1arms.txt fig1-3 > /root/p1/batch-p1.log 2>&1 &'
   -- 21 cells (~30 min at mux speed).
5. `sudo bash /root/k2/p1-kernel.sh arm-restore`, reboot, verify
   6.17.8-061708-generic, p1prep + lp.sh again.
6. Note + checkpoint: the deferral's CPU profile (ksoftirqd/8 share)
   is part of Fig 3's accounting story.

## C. fig4 batch (t7) -- same frozen binaries
`sudo bash -c 'SPEC_VERSION=2 nohup bash /root/k2/p1batch.sh
/root/k2/fig4.txt fig4 > /root/p1/batch-fig4.log 2>&1 &'`
162 cells (~4 h at mux speed). Then form-F validation per placement
and size; prediction check (within +/-25% or Dropped).

## D. Fig 5+ (t8) -- NOW deploy the new binaries
rx: k2_rx (wp50) + p1ctl.py + p1w5.sh + costs.env; txs: k5blast
(profile). Verify one W5 smoke (P0 ramp 30 s), then the 36-cell Fig 5
matrix (W5 x P0/P2/P4/P7 x 3 patterns x 3 reps) and Fig 6 (t9).
