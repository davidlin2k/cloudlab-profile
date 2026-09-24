# 2026-09-24 — fig1–3 visual QA round 3 (figures4papers-style skill)

Verdict: NOT clean — each of the three rendered figures carries one real
defect, all three matching known gotchas in the figures4papers-style skill.
Figures are structurally sound (style, dpi, no data clipping except the
fig1 reference line) but need one fix + re-render round before Draft is
re-affirmed. Checked visually (full-image pass + zoomed crop per defect).

## Style conformance (pass)

- PNG 300 dpi confirmed (299.99 dpi metadata), PNG+PDF pairs for all 3.
- Top/right spines off, frameless legends — confirmed visually.
- figstyle.py shared module => fonttype 42 by construction.

## Defects (confirmed at zoom)

| Fig | Defect | Skill gotcha |
| --- | --- | --- |
| fig1 | Frameless legend collides with x-label "offered rate / knee" (right-column "thread" entries + "inline, app elsewhere" sit under the label text) | legend placement |
| fig1 | "offered" reference line clipped at top-right (exits y-range at x=2) | data clipped at edge |
| fig2 | First x category labels collide: "inline sep.app" overlaps "thr app-core" | two-token category labels need ~9in width or tick fontsize 13 (fig2 is ~3.8in) |
| fig3 | Red "+0 hidden" annotations overlap the white in-bar values 1113 / 1466 / 1451 (bars 2, 4, 5) | annotations must sit where data provably doesn't reach |

Minor (data-inherent, no fix needed): fig1 marker/error-bar stacking at
x=1 (3 series converge on the offered line); fig3 "2064" total label sits
close to the legend but does not touch it.

## Recommended fixes

1. fig1: move legend below the x-label (or inside bottom-right dead zone
   where series sit at 0); keep offered line — clip is acceptable for a
   reference line, or extend y-limit to 800k.
2. fig2: widen figure to >=9in or drop tick fontsize to 13 for the
   rotated category labels; re-check the first label after render.
3. fig3: move "+0 hidden" above the bar next to the total label (or drop
   the annotation and note "0 hidden" in the caption).

## Note

fig1–3 were previously "accepted through two vision-QA rounds" (09:54Z
checkpoint); round 3 with zoomed crops still found the 3 collisions above
— the earlier rounds missed them. fig4–6: scripts written (p1_fig4/5/6.py),
no renders on disk yet; rows-fig4.csv updated 12:00.

Data locations unchanged: analysis/out/fig{1,2,3}.{png,pdf}.
