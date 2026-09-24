# 2026-09-24 — Plan alignment check: the 7-item plain-language program

Status: verdict on the plain-language list (item 1 arithmetic + items 2–6
hypotheses + item 7 scope + the HAProxy bonus), checked against
paper1-skeleton.md, DR-001/DR-002/DR-003, CLAIMS.md C-001..C-011,
AN-003/AN-004 and the 2026-09-24 checkpoints. Verdict: YES on substance —
items 1, 3, 4, 5, 6, 7 and the bonus map onto existing records; item 2 is
NEW and gated; three corrections below.

## Mapping

| Item | Record of record | Verdict |
| --- | --- | --- |
| 1. Fig. 1 follows from two numbers (S ~780k pps, r = 1.77) | C-007 (form F, Contested) + DR-003 decision 9 (inline-only knee re-grade, analysis only) | YES as C-007's replacement form; one open input (below) |
| 2. Flood freezes host management (netns/interface ops hang) | none found in either tree | NEW — needs a PI call (DR-003: no experiments beyond the list); first step is a rows/log entry in anomalies/collisions.md (decision 10) |
| 3. Wedge = affinity-bailout race, bad luck at high handoff rate | AN-003, C-010/C-011, DR-003 decisions 1–6 (wdiag v2 running; patch = skip the affinity bailout when NAPI is threaded; patched comparison = the verification) | YES; the rate-doubling discriminant is beyond DR-002's frozen pre-registration (aff_change-based) — a follow-up test, not a replacement |
| 4. Official guidance steers into the collapsing setup | DR-003 decision 8 fallback claim ("co-location, which RFS and aRFS do by design, is harmful"); collisions.md rows 1–2 (logged, untested); DR-003 decision 5 docs fix | YES as motivation; the by-design part is citable from kernel docs, the measured harm rows are still Pending |
| 5. Big packets may reverse the result (boundary ~1400 B) | Fig. 4 knee cells at 64/512/1400 B (chain6; stopped per DR-003 decision 1, partial rows kept) | YES; "reversal boundary" is sharper than the skeleton's "validated across packet sizes"; needs patched driver or inline placements (threaded rungs at flood are wedge-limited, C-008) |
| 6. 108 µs = adaptive interrupt moderation feedback | DR-003 decision 8 (perf sched + adaptive-rx-off cells), C-005 Pending a mechanism | YES, but "checking needs no new runs" is WRONG — the adaptive-rx-off pair is a scheduled new run |
| 7. Scope: moderate overload, not line rate | W4 (4 flood rates), DR-002 severity/DoS framing | YES as the scope paragraph |
| Bonus: HAProxy ~7 µs CPU/token, mostly user space | C-003 (Contested), h1h2-verdict checkpoint H4 -> Reins host paper | YES, keep as a nugget for paper 2 |

## Arithmetic (computed this checkpoint)

- P0X saturation S: 790k x 0.975 = 770k, 1050k x 0.742 = 779k,
  1300k x 0.605 = 786k pps delivered. Three flood rates agree within 2%
  -> S ~ 780k pps. Solid.
- Two-number law: softirq fills the core at S; per-packet costs
  c_soft = r x c_app. Shared-core goodput G(l) = min(l, r(S - l));
  peak at l = rS/(1+r). With r = 1.77, S = 780k -> peak 498k pps
  (measured P0 knee bracket 450–525k ✓), zero at 780k (measured P0:
  9.0% share at 790k, 0.2% at 1050k — the measured zero is bracketed,
  the 780k zero is the model's line), 50/50 split kernel: its network
  half fills at S/2 = 390k ✓.
- 100 Gb/s at 64 B: 100e9 / (84 x 8) = 148.8 Mpps ~ the cited 149M ✓.
- HAProxy tax: 13.24 core-s/s / 1.88M tok/s = 7.0 µs/token ✓ (C-003).

## Open input before item 1 is a claim

r = 1.77 looks back-derived: r = peak/(S - peak) = 500/280 = 1.79 from our
own curve. If the model's "two numbers" come from the curve it explains, the
"no tuning" claim is circular. What is owed is the INDEPENDENT per-core cycle
counts (Fig. 3 / perf): c_soft / c_app = 1.77. Only with that does the law
earn the right to replace form F (C-007) under skeleton rule 4. Also note
form F's 64-B miss (42–91%) is partly the missing wedge term on the threaded
rungs (C-008), per the wedge-ab-verdict checkpoint — re-grade on inline
placements is exactly DR-003 decision 9.

## Gates in force (unchanged)

DR-003 run order stands: wdiag v2 first (running), recovery test at the first
confirmed wedge, disclosure rule decides the venue, patch + patched comparison
next, decisions 9–10 analysis/log only. Item 2 and the rate-doubling test
wait for the PI. Every result supersedes; nothing edited or deleted.
