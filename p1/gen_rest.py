#!/usr/bin/env python3
"""gen_rest.py LISTFILE RESULTSDIR OUTFILE -- emit the list rows that
have no manifest yet (used for safe batch relaunch)."""
import json, glob, sys
lst, res, outp = sys.argv[1], sys.argv[2], sys.argv[3]
done = set()
for m in glob.glob(res + "/*/rep*/manifest.json"):
    try:
        c = json.load(open(m))["cell"]
        done.add((c["policy"], c["workload"], int(c["rate"]), int(c["plen"]), int(c["rep"])))
    except Exception:
        pass
out = open(outp, "w")
out.write("# remainder after ssh-mux relaunch (generated, do not edit)\n")
n = 0
for ln in open(lst):
    if ln.startswith("#") or not ln.strip():
        continue
    pol, work, rate, plen, rep, warm, meas = ln.split()
    if (pol, work, int(rate), int(plen), int(rep)) not in done:
        out.write(ln)
        n += 1
out.close()
print(f"rest rows: {n} (done: {len(done)})")
