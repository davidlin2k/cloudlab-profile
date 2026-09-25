#!/usr/bin/env python3
"""metastab_eval.py -- DR-005 task 1 step 5: rows + the pre-registered class.

usage: .venv/bin/python p1/metastab_eval.py [CELLS_ROOT]

Default CELLS_ROOT: a directory whose subdirectories are the cell
directories produced by p1/metastab.sh (e.g. a pulled copy of
/root/p1/metastab). For every cell it reads cell.env and counters.log and
writes analysis/rows-metastab.csv (columns: cell, rep, mode, keep,
t_flood, t_wedge, t_reduce, recovered, t_recover_s, rx7_rate_reduced,
oob_rate_reduced, probe). Then it prints the pre-registered class per
reduced level (specs/p1-METASTABLE.md, DR-005 verbatim):

  Metastable     >=4 of 5 M cells not recovered within 120 s, and the
                 matching B cells healthy in 5 of 5
  Not metastable >=4 of 5 M cells recover within 2 s of the reduction
  Intermediate   anything else (report the distribution; 5 more reps; no claim)
  Invalid        any B cell wedges (the M result at that level cannot be
                 interpreted; use the other level)

Recovery time is computed offline from counters.log (1 Hz): the first
2 s sample after REDUCE that begins 3 consecutive qualifying samples
(delta rx7_packets >= 90% of the kept offered rate).
"""
import os, re, sys, csv

def parse_env(path):
    env = {}
    for ln in open(path, errors="replace"):
        m = re.match(r"(\S+) mono=(\S+)", ln.strip())
        if m:
            env[m.group(1)] = m.group(2)
        m2 = re.match(r"(WEDGE) mono=(\S+)", ln.strip())
        if m2:
            env["WEDGE"] = m2.group(2)
        m3 = re.match(r"(PROBE-\w+) adv=(\d+)", ln.strip())
        if m3:
            env["probe"] = m3.group(1)
            env["probe_adv"] = m3.group(2)
    return env

def parse_counters(path):
    out = []  # (mono, rx7, oob)
    t = rx7 = oob = None
    for ln in open(path, errors="replace"):
        m = re.match(r"@ (\S+)", ln.strip())
        if m:
            t = float(m.group(1))
            continue
        m = re.search(r"rx7_packets:\s+(\d+)", ln)
        if m and t is not None:
            rx7 = int(m.group(1))
        m = re.search(r"rx_out_of_buffer:\s+(\d+)", ln)
        if m and t is not None:
            oob = int(m.group(1))
            out.append((t, rx7, oob))
    return out

def recovery_time(samples, t_reduce, need):
    """first 2 s sample at/after t_reduce starting 3 consecutive
    qualifying samples; returns (recovered, t_recover_s)"""
    ts = [(t, w) for (t, w, _) in samples]
    ok_run = 0
    for i in range(2, len(ts)):
        t, w = ts[i]
        if t < t_reduce:
            continue
        if t > t_reduce + 120:
            break   # the verdict window is 120 s (the monitor's), not later
        d = w - ts[i - 2][1]
        if d >= need:
            ok_run += 1
        else:
            ok_run = 0
        if ok_run >= 3:
            return 1, ts[i - 2][0] - t_reduce
    return 0, ""

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "/root/p1/metastab"
    rows = []
    for cell in sorted(os.listdir(root)):
        d = os.path.join(root, cell)
        if not os.path.isdir(d):
            continue
        envp, cntp = os.path.join(d, "cell.env"), os.path.join(d, "counters.log")
        if not (os.path.exists(envp) and os.path.exists(cntp)):
            print(f"skip {cell}: missing cell.env or counters.log")
            continue
        env = parse_env(envp)
        samples = parse_counters(cntp)
        m = re.match(r"([MB])(\d+)-(\d+)$", cell)
        if not m:
            print(f"skip {cell}: name not MODE$NKEEP-REP")
            continue
        mode, nkeep, rep = m.group(1), int(m.group(2)), m.group(3)
        keep = "10" if nkeep == 1 else "10 11"
        need = nkeep * 158000 * 2 * 9 // 10
        t_red = float(env.get("REDUCE", 0) or 0)
        rec, t_rec = recovery_time(samples, t_red, need) if t_red else (0, "")
        if not env.get("RECOVERED") and not env.get("NOT-RECOVERED-120s"):
            verdict = "MISSING-VERDICT"
        elif env.get("RECOVERED"):
            verdict = "RECOVERED"
        else:
            verdict = "NOT-RECOVERED-120s"
        rows.append({
            "cell": cell, "rep": rep, "mode": mode, "keep": keep,
            "t_flood": env.get("FLOOD START", env.get("B-START", "")),
            "t_wedge": env.get("WEDGE", ""),
            "t_reduce": env.get("REDUCE", ""),
            "recovered": rec,
            "t_recover_s": f"{t_rec:.1f}" if t_rec != "" else "",
            "rx7_rate_reduced": "", "oob_rate_reduced": "",
            "probe": env.get("probe", "MISSING"),
            "verdict_online": verdict,
        })
    out = "analysis/rows-metastab.csv"
    os.makedirs("analysis", exist_ok=True)
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else
                           ["cell", "rep", "mode", "keep", "t_flood", "t_wedge",
                            "t_reduce", "recovered", "t_recover_s",
                            "rx7_rate_reduced", "oob_rate_reduced", "probe"])
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print(f"wrote {out}: {len(rows)} cells")

    # ---- the pre-registered class per level ----
    for level, keep in ((158, "10"), (316, "10 11")):
        ms = [r for r in rows if r["mode"] == "M" and r["keep"] == keep]
        bs = [r for r in rows if r["mode"] == "B" and r["keep"] == keep]
        if not ms and not bs:
            continue
        b_wedged = [r for r in bs if r["recovered"] == 0]
        m_notrec = [r for r in ms if r["recovered"] == 0]
        m_fast = [r for r in ms if r["recovered"] == 1 and r["t_recover_s"] != ""
                  and float(r["t_recover_s"]) <= 2.0]
        if b_wedged:
            cls = "Invalid (a B cell wedged; use the other level)"
        elif len(ms) >= 5 and len(m_notrec) >= 4 and len(bs) >= 5 and not b_wedged:
            cls = "Metastable"
        elif len(m_fast) >= 4:
            cls = "Not metastable"
        else:
            cls = "Intermediate (report the distribution; 5 more reps; no claim)"
        print(f"\nlevel {level} (keep {keep}): {cls}")
        print(f"  M cells: {len(ms)}; not recovered: {len(m_notrec)}; "
              f"recovered <=2 s: {len(m_fast)}")
        for r in ms:
            print(f"    M {r['cell']}: recovered={r['recovered']} "
                  f"t_recover_s={r['t_recover_s']} probe={r['probe']} "
                  f"online={r['verdict_online']}")
        print(f"  B cells: {len(bs)}; wedged: {len(b_wedged)}")
        for r in bs:
            print(f"    B {r['cell']}: recovered={r['recovered']} "
                  f"t_recover_s={r['t_recover_s']} probe={r['probe']}")

if __name__ == "__main__":
    main()
