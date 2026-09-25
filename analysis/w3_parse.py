#!/usr/bin/env python3
"""W3 analysis (spec p1-W3MEMC.md v3): parse cells, compute the four
pre-registered verdicts P1-P4. Verdict rules come from the frozen spec.
Usage: python3 w3_parse.py <rows_out.csv> <report_out.md>
"""
import re, sys, csv, glob, os, statistics

BASES = [("knee1", "/mnt/davidlin-personal/cloudlab-profile/analysis/w3knee/w3knee"),
         ("knee2", "/mnt/davidlin-personal/cloudlab-profile/analysis/w3knee/w3knee2"),
         ("main", "/root/p1/w3main")]  # main pulled locally first

def parse_cell(d):
    rec = {"dir": os.path.basename(d)}
    achieved = 0.0
    for o in (10, 11, 12, 13, 14):
        p = f"{d}/load-{o}.txt"
        if not os.path.exists(p): continue
        t = open(p).read()
        m = re.search(r"Total QPS = ([\d.]+)", t)
        if m: achieved += float(m.group(1))
        for key, pat in (("miss_pct", r"Misses = \d+ \(([\d.]+)%\)"),
                         ("skip_pct", r"Skipped TXs = \d+ \(([\d.]+)%\)")):
            m = re.search(pat, t)
            if m and key not in rec: rec[key] = float(m.group(1))
        if o == 10:
            for line in t.splitlines():
                f = line.split()
                if not f: continue
                if f[0] == "op_q": rec["opq99"] = float(f[-1])
                if f[0] == "read":
                    rec["t50_us"] = float(f[4]); rec["t99_us"] = float(f[-1])
    rec["achieved"] = round(achieved, 1)
    pp = f"{d}/perf.txt"
    if os.path.exists(pp):
        rc = {c: int(v.replace(",", "")) for c, v in
              re.findall(r"(CPU\d)\s+([\d,]+)\s+ref-cycles", open(pp).read())}
        rec["rc8"], rec["rc9"] = rc.get("CPU8", 0), rc.get("CPU9", 0)
    # latency samples (measure client) for p99.9 + SLO under-count
    samps = []
    for o in (10, 11, 12, 13, 14):
        p = f"{d}/samples-{o}.txt"
        if os.path.exists(p):
            try:
                samps += [float(x) for x in open(p).read().split()]
            except ValueError:
                pass
    if samps:
        samps.sort()
        rec["n_samples"] = len(samps)
        rec["p50_us"] = samps[len(samps)//2]
        rec["p99_us"] = samps[int(len(samps)*0.99)]
        rec["p999_us"] = samps[int(len(samps)*0.999)]
    return rec

def parse_name(n):
    m = re.match(r"(P0X|P0|BP)-(\d+)(?:-(\d))?$", n)
    if not m: return None
    return m.group(1), int(m.group(2)), int(m.group(3) or 0)

def main():
    rows = []
    for tag, base in BASES:
        if not os.path.isdir(base): continue
        for d in sorted(glob.glob(f"{base}/*-*")):
            nm = parse_name(os.path.basename(d))
            if not nm: continue
            rec = parse_cell(d)
            rec.update(arm=nm[0], target=nm[1], rep=nm[2], src=tag)
            rows.append(rec)
    rows.sort(key=lambda r: (r["arm"], r["target"], r["rep"]))
    fields = ["src", "arm", "target", "rep", "achieved", "miss_pct", "skip_pct",
              "opq99", "t50_us", "t99_us", "p50_us", "p99_us", "p999_us",
              "n_samples", "rc8", "rc9", "dir"]
    with open(sys.argv[1], "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader(); w.writerows(rows)
    print(f"wrote {len(rows)} rows -> {sys.argv[1]}")

if __name__ == "__main__":
    main()
