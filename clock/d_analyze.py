#!/usr/bin/env python3
"""d_analyze: D-matrix summary per PI spec D.

Prefers the cumulative `tokens` column (exact per-rep delivery by
diffing rep boundaries, staleness = zero diff); falls back to the
noisy 1s-window rate= field for pre-fix CSVs.

Per cell reports: delivered tok/s, offered, load (delivered/offered),
stall-seconds per stream, frozen reps excluded, and the emitter gate
(drops <= 0.1% of tokens).

Usage: d_analyze.py results/aligned.csv results/random.csv ...
"""
import csv
import sys
from statistics import median

TOK_PER_S = 40  # 25ms step period


def load(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            if r.get("rep") in (None, "connect_timeout", "master_complete", ""):
                continue
            try:
                r["_rep"] = int(r["rep"])
            except ValueError:
                continue
            rows.append(r)
    return rows


def has_tokens(rows):
    return rows and rows[0].get("tokens", "") not in ("", None)


def main(paths):
    for path in paths:
        mode = path.split("/")[-1].rsplit(".", 1)[0]
        rows = load(path)
        tok_mode = has_tokens(rows)
        print(f"\n=== mode={mode} ({len(rows)} reps; "
              f"delivery from {'tokens diff' if tok_mode else 'rate field'})")
        print(f"{'streams':>8} {'deliv Mtok/s':>12} {'offered':>8} {'load':>6} "
              f"{'stall_s/stream':>14} {'stalls/rep':>10} {'frozen':>6} {'gate':>6}")
        by_n = {}
        for r in rows:
            by_n.setdefault(int(r["streams"]), []).append(r)
        for n in sorted(by_n):
            rs = sorted(by_n[n], key=lambda r: r["_rep"])
            deliv, stallps, stalls_rep, frozen, drops = [], [], [], 0, 0
            prev_tok = prev_stall_s = None
            for r in rs:
                drops = max(drops, int(r["drops"]))
                if tok_mode:
                    tok = float(r["tokens"])
                    ss = float(r["stall_s"])
                    if prev_tok is not None:
                        dtok = tok - prev_tok
                        if dtok <= 0:
                            frozen += 1
                            prev_tok, prev_stall_s = tok, ss
                            continue
                        deliv.append(dtok / 75.0)  # 15s discard + 60s measure
                        stallps.append((ss - (prev_stall_s or 0)) /
                                       max(int(r["live"]), 1))
                    prev_tok, prev_stall_s = tok, ss
                else:
                    if prev_tok is not None and r["rate_tok_s"] == prev_tok:
                        frozen += 1
                    else:
                        deliv.append(float(r["rate_tok_s"]))
                        stallps.append(float(r["stall_s"]) /
                                       max(int(r["live"]), 1))
                    prev_tok = r["rate_tok_s"]
                stalls_rep.append(float(r["stalls"]))
            offered = n * TOK_PER_S
            if not deliv:
                print(f"{n:8d} {'-':>12} {offered/1e6:8.2f} {'-':>6} "
                      f"{'-':>14} {'-':>10} {frozen:6d} {'?':>6}")
                continue
            d = median(deliv)
            est_tok = sum(deliv) * 75
            gate = "pass" if drops <= 0.001 * max(est_tok, 1) else "drops"
            print(f"{n:8d} {d/1e6:12.3f} {offered/1e6:8.2f} {d/offered:6.2f} "
                  f"{median(stallps):14.1f} {median(stalls_rep):10.0f} "
                  f"{frozen:6d} {gate:>6}")


if __name__ == "__main__":
    main(sys.argv[1:] or ["results/aligned.csv", "results/random.csv",
                          "results/per-engine.csv"])
