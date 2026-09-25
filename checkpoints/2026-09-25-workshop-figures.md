# Workshop paper figures complete (2026-09-25)

DR-004 task 5, pulled ahead of the October 6 figure gate: all four of the
memo's figures now have scripts in analysis/ and QA passes.

| The memo's figure | script | output | status |
|---|---|---|---|
| Fig. 1 goodput vs load | analysis/p1_figures.py | fig1 | Draft (QA pass 09-24) |
| Fig. 2 hidden share + model +/- correction | analysis/p1_fig_model.py | fig2-hiddenmodel | Draft (QA pass 09-25, 4 rounds) |
| Fig. 3 wake-delay distributions | analysis/p1_fig_wakedelay.py | fig3-wakedelay | Draft (QA pass 09-25, 4 rounds) |
| Fig. 4 wedge survival curves | analysis/p1_fig_wedge.py | fig-wedge-ab | Draft (QA pass 09-25) |

## Records established while building them

1. **Wake-delay column provenance.** perf sched timehist col 3 is the task's
   sleep time (means 374 us etc.), NOT the wake delay; col 4 (the scheduler
   wait after wakeup) reproduces every recorded anchor -- TCP P0 47.0 us
   mean / 791 us max (recorded 50 / 792), P0X 3.2 / 1088 (recorded 4 /
   1089), and all four UDP maxima to three significant figures (1242,
   3502, 906, 892 us vs the recorded 1.24, 3.50, 0.91, 0.89 ms). The
   figure's anchors check mean and max against the recorded pairs.
2. **Two instruments measure the hidden share.** rows-fig1-3 schedstat
   derivation at 390k: P0 reps 25.0-40.3%, mean 32.2% (n=3). C-006's
   independent measurement (/p1/pmudrain + /p1/softirq_poll): 26-42%,
   mean 33% -- the source of the re-grade's h = 0.33 calibration. Fig. 2a
   shows both: the agreement is the point.
3. **write_file partial-read refusals.** the outline v2 write was refused
   twice (silently, then explicitly) because read_file(limit=1) leaves a
   paged partial view; a full read_file() first makes the write land.
   One commit in between carried a stale v1 copy under a v2 message; the
   next commit corrects it (recorded in the outline header).

## Everything through this checkpoint (cumulative)

- W3 closed (kill criterion + 3 predictions recorded); kill narrative
  checked -- reproduces 169% at 2x knee and 42% at 3x exactly.
- Threaded group validated end to end (4/4 goodput checks, 130k); kernel
  build finishes 22:44 UTC (tree clean; v6.4 vmlinux+modules kept).
- Task 3 closed: AN-006A + both timelines (facts only; interpretation
  HELD for the PI; no public wedge mention).
- DR-004 claim promotions + the negative-results supplement committed
  verbatim / as supplemental; weekly memo updated before Friday noon.
- Workshop outline v2 (the memo's structure) + all four figures Draft.
- Open: r650 (user input), the netdev report (PI), C-004/C-006 ledger
  status at review, figs 5-10 of the skeleton (W4/fig 8 needs the
  suspended ladder + PI approval for the run).
