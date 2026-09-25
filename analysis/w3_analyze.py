#!/usr/bin/env python3
"""W3 analysis (spec p1-W3MEMC.md v3): cell stats + pre-registered verdicts P1-P4."""
import numpy as np, re, os, glob, json, csv

SLO_US = 1050.0
OUT = "/mnt/davidlin-personal/cloudlab-profile/analysis"

def cell_stats(d):
    achieved = 0.0; miss = None; skip = None; opq = None
    for o in (10, 11, 12, 13, 14):
        p = f"{d}/load-{o}.txt"
        if not os.path.exists(p): continue
        t = open(p).read()
        m = re.search(r"Total QPS = ([\d.]+)", t)
        if m: achieved += float(m.group(1))
        m = re.search(r"Misses = \d+ \(([\d.]+)%\)", t)
        if m and miss is None: miss = float(m.group(1))
        m = re.search(r"Skipped TXs = \d+ \(([\d.]+)%\)", t)
        if m and skip is None: skip = float(m.group(1))
        if o == 10:
            for line in t.splitlines():
                f = line.split()
                if f and f[0] == "op_q": opq = float(f[-1])
    le = tot = 0; pcts = []
    for o in (10, 11, 12, 13, 14):
        p = f"{d}/samples-{o}.txt"
        if not os.path.exists(p): continue
        x = np.fromfile(p, sep=" ")
        if x.size == 0: continue
        le += int((x <= SLO_US).sum()); tot += int(x.size)
        pcts.append((np.percentile(x, 50), np.percentile(x, 99), np.percentile(x, 99.9)))
    st = dict(achieved=achieved, miss=miss, skip=skip, opq=opq, n=tot,
              slo_frac=(le / tot if tot else None))
    if pcts:
        a = np.array(pcts)
        st.update(p50=float(a[:,0].mean()), p99=float(a[:,1].mean()), p999=float(a[:,2].mean()))
    pp = f"{d}/perf.txt"
    if os.path.exists(pp):
        rc = {c: int(v.replace(",", "")) for c, v in re.findall(r"(CPU\d)\s+([\d,]+)\s+ref-cycles", open(pp).read())}
        st["rc8"], st["rc9"] = rc.get("CPU8", 0), rc.get("CPU9", 0)
    return st

rows = []
pat = re.compile(r"(P0X|P0|BP)-(\d+)(?:-(\d))?$")
for base, tag in ((f"{OUT}/w3main", "main"), (f"{OUT}/w3knee/w3knee", "k1"), (f"{OUT}/w3knee/w3knee2", "k2")):
    if not os.path.isdir(base): continue
    for d in sorted(glob.glob(f"{base}/*-*")):
        m = pat.match(os.path.basename(d))
        if not m: continue
        s = cell_stats(d)
        rows.append(dict(src=tag, arm=m.group(1), target=int(m.group(2)), rep=int(m.group(3) or 0), **s))

fields = ["src","arm","target","rep","achieved","miss","skip","opq","n","slo_frac","p50","p99","p999","rc8","rc9"]
with open(f"{OUT}/rows-w3-full.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore"); w.writeheader(); w.writerows(rows)
print(f"{len(rows)} rows -> rows-w3-full.csv")

print("\n=== MAIN MATRIX (3 reps; achieved / slo_frac / p50 p99 p999 us) ===")
for arm in ("P0", "P0X", "BP"):
    for target in (47500, 95000, 190000, 285000, 380000):
        rs = [r for r in rows if r["src"] == "main" and r["arm"] == arm and r["target"] == target]
        if not rs: continue
        ach = np.mean([r["achieved"] for r in rs])
        sl = np.mean([r["slo_frac"] for r in rs])
        p99 = np.mean([r.get("p99", 0) for r in rs])
        p50 = np.mean([r.get("p50", 0) for r in rs])
        p999 = np.mean([r.get("p999", 0) for r in rs])
        print(f"{arm:3} {target:>6} ach={ach:>8.0f} ({ach/target:.3f}) slo={sl:.3f} p50={p50:.0f} p99={p99:.0f} p999={p999:.0f} n={sum(r['n'] for r in rs)}")
