# DR-004 task 5: workshop paper outline (v2, 2026-09-25)

v2 supersedes v1 (same day): v1 used the skeleton's structure and titles;
the memo's own section table and working title govern this paper and are
executed literally below. v1 remains in git history and the PI saw its
review items (carried forward at the bottom). (Record: v2's first write
attempt was refused because the file had only been paged-read; the commit
between the attempts carried a stale v1 copy under a v2 message.)

**Working title (the memo's): Invisible Receive Work: What Linux Pays for
It Under Overload.**

Rules (verbatim): Every sentence with a number cites a finding ID. Every
figure comes from a script in analysis/. Only Supported claims.
Dates (verbatim): Outline Sep 29; final figures Oct 6; full draft Oct 9;
PI review Oct 12; revision Oct 16.

## The memo's section table, with the evidence in hand

| Section | Content | Evidence (the memo's column) | Numbers ready |
|---|---|---|---|
| 1. Introduction | Receive work runs outside any thread, and three measured costs follow | C-004, C-007, C-012 | 0.20% of offered at 2x knee (95% CI 0.20-0.20, n=2) [F-p1-LADDER-1]; the corrected-cost model's 2.8%/6.2% knee miss [p1-LADDER.4]; wake wait 34-60 us vs 4 us UDP, 47 us vs 3 us TCP (means, 1.2M wake events) [p1-LADDER.2, p1-LADDER.6] |
| 2. Background | NAPI, softirq, and the 2016 and 2023 policy changes | Literature | Table text only |
| 3. Collapse and separation | Goodput against load, and the interrupt core as separation's ceiling | Fig. 1, C-013 | separated 97.5%/74.2% of offered at 1.5x/2x knee vs the default's 9.0%/0.2% [p1-LADDER.1]; the ceiling: core 8 100% busy at ~1.2 us/pkt while the app core runs ~85% [p1-LADDER.1, C-013] |
| 4. Invisibility makes models wrong | The standard metric is blind; corrected costs make the knee predictable; the model fails on TCP | Fig. 2, C-006, C-007 | /proc/stat sees 0.6% of receive work, a 166x undercount [AN-007, C-014]; thread accounting sees 43-55% [F-p1-LADDER-3, C-006]; corrected costs predict the UDP knee within 2.8% (P0: 451.0k vs 438.6k) and 6.2% (P0X: 767.0k vs 818.0k), no fitted constant [p1-LADDER.4]; on TCP the same form misses 3.06x/3.16x (62.0k/82.4k vs 190k/260k) -- cost depends on load [C-017] |
| 5. Invisibility makes wakeups wait | Wake-delay distributions, co-located against separated | Fig. 3, C-012 | means: UDP 59.2/33.8 us co-located vs 1.7/2.1 us separated (adaptive-rx on/off), TCP 47.0 us vs 3.2 us; tails to 1242/3502 us and 791/1088 us [p1-LADDER.2, p1-LADDER.6]; NAPI kthread 3 us in both placements |
| 6. The threaded-NAPI stall | Survival curves, what we ruled out, and its status | Fig. 4, C-008, C-011 | 25 of 48 cells plus 24 of 24 stall; unpinned fastest 8/8, onsets 9-19 s [p1-LADDER.2, AN-006]; ruled out: the mlx5 poll-affinity bailout (pre-registered A/B, C-010 Refuted); status: AN-006A timelines delivered, interpretation held for the PI (no public mention before the netdev report is approved) |
| 7. Agenda | Visibility-aware placement; upstream work | -- | no numbers |

Related work (the memo's five): Mogul and Ramakrishnan 1997; Iron
(NSDI'18); threaded NAPI's rationale (2021); Brouer 2023; Zuo et al.
(SIGCOMM'26). One sentence each.

## Figure audit (rule: every figure from a script in analysis/)

| The memo's figure | script | status |
|---|---|---|
| Fig. 1 goodput vs load | analysis/p1_figures.py (fig1) | Draft, QA pass |
| Fig. 2 the blind metric + corrected-cost knee model | analysis/p1_fig_model.py (fig2-metricmodel) | Draft, QA pass 2026-09-26 (v2 per DR-005: hidden-share framing retired; anchors reproduce: app 906-1407 ns, real 2026-2935 ns, thread 43-55%, /proc/stat 0.60%) |
| Fig. 3 wake-delay distributions co-located vs separated | analysis/p1_fig_wakedelay.py (fig3-wakedelay) | Draft, QA pass 2026-09-25 (anchors reproduce every recorded mean/max) |
| Fig. 4 wedge survival curves | analysis/p1_fig_wedge.py (fig-wedge-ab) | Draft, QA pass; the W39 figure of the week |

## Review items (Sep 29)

1. C-004 and C-006 are still Pending in the ledger although the memo's
   evidence column names them. The numbers are in findings (F-p1-LADDER-1,
   F-p1-LADDER-3) and the sentences cite findings per the rules -- promote
   the claims at review, or the paper cites findings only?
2. C-007 re-promotion (its revised numbers enter sections 1 and 4).
3. The W3 TCP outcomes (the kill criterion, three failed predictions) have
   no section in the plan. They currently surface only as section 5's TCP
   wake-delay numbers. Include a short "what TCP does not carry" note in
   section 5 or section 7, or drop? (Nothing outside the plan without
   approval.)
4. Confirm the working title; the controller name is not needed for this
   paper (section 7 is the agenda).
