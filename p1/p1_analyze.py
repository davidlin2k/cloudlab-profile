#!/usr/bin/env python3
"""p1_analyze.py -- derive tidy result rows from p1cell.sh output trees.

Run ON rx:  python3 /root/k2/p1_analyze.py TAG [SLO_US] > rows.csv
One row per run. Derived numbers come only from this script (lab rule:
raw data is never edited; only scripts produce reported numbers).

Columns:
  tag cell policy workload rate plen rep gates_ok offered goodput deliv
  lat_p50 lat_p90 lat_p99 lat_p999 under_slo resp censored sockdrops
  app_ns c_net_ns cyc refcyc cpu8_busy_s softirq_s napi_s
where:
  goodput   = sum of 1s-window pkts over the measure window / MEAS
              (W2: completed RPCs/s from sender summaries)
  under_slo = goodput with latency <= SLO_US (W1: rx->dequeue hist share
              of measure pkts; W2: merged client RTT hist share of resp)
  c_net_ns  = NAPI-side CPU ns per delivered packet (napi kthread
              schedstat delta for P2-P4; cpu8 softirq time for P0/P0X)
  c_app_ns  = app thread on-CPU ns per packet (k2_rx self schedstat)
"""
import json, re, sys, os, glob

def load_manifest(run):
    with open(os.path.join(run, "manifest.json")) as f:
        return json.load(f)

def parse_kv(text, keys):
    out = {}
    for k in keys:
        vals = re.findall(r"%s=([0-9.]+)" % re.escape(k), text)
        if vals:
            out[k] = sum(float(v) for v in vals)
    return out

def win_lines(run):
    p = os.path.join(run, "consumer.err")
    rows = []
    if not os.path.exists(p):
        return rows
    for ln in open(p):
        m = re.match(r"\[k2rx-win\] t=(\d+) pkts=(\d+) rate=([0-9.]+) drops=(\d+)(?: wp50_us=(\d+))?", ln)
        if m:
            rows.append((int(m.group(1)), int(m.group(2)), float(m.group(3)),
                         int(m.group(4)), int(m.group(5) or 0)))
    return rows

def merge_hists(run):
    tot = {}
    for p in glob.glob(os.path.join(run, "hist-*.txt")):
        for ln in open(p):
            a = ln.split()
            if len(a) == 2:
                b, c = int(a[0]), int(a[1])
                tot[b] = tot.get(b, 0) + c
    return tot

def pct(hist, q):
    n = sum(hist.values())
    if not n:
        return -1.0
    acc = 0
    for b in sorted(hist):
        acc += hist[b]
        if acc >= q * n / 100.0:
            return b + 0.5
    return -1.0

def hist_frac_le(hist, us):
    n = sum(hist.values())
    if not n:
        return 0.0, 0
    c = sum(v for b, v in hist.items() if b + 0.5 <= us)
    return c / n, c

def ethtool_delta(run):
    """rx7 delta (wire arrivals on the target queue) + ring drops from
    the bracketing ethtool snapshots."""
    def snap(name):
        out = {}
        try:
            for ln in open(os.path.join(run, name)):
                a = ln.split(":")
                if len(a) == 2:
                    out[a[0].strip()] = int(a[1].strip())
        except OSError:
            pass
        return out
    pre, post = snap("nic-pre.txt"), snap("nic-post.txt")
    tq = sum(v for k, v in post.items() if k.startswith("rx") and k.endswith("_packets") and k[2] == "7" and k[3] == "_") - \
         sum(v for k, v in pre.items() if k.startswith("rx") and k.endswith("_packets") and k[2] == "7" and k[3] == "_")
    allp = sum(v for k, v in post.items() if k.startswith("rx") and k.endswith("_packets")) - \
           sum(v for k, v in pre.items() if k.startswith("rx") and k.endswith("_packets"))
    ring = sum(v for k, v in post.items() if k in ("rx_discards", "rx_out_of_buffer")) - \
           sum(v for k, v in pre.items() if k in ("rx_discards", "rx_out_of_buffer"))
    return max(tq, 0), max(allp, 0), max(ring, 0)

def softnet_delta(run):
    """cpu8 row: packets processed and dropped at the backlog."""
    def snap(name):
        try:
            ln = open(os.path.join(run, name)).readlines()[8]
            a = ln.split()
            return int(a[0], 16), int(a[1], 16)
        except (OSError, IndexError):
            return 0, 0
    p0, d0 = snap("softnet-pre.txt")
    p1, d1 = snap("softnet-post.txt")
    return max(p1 - p0, 0), max(d1 - d0, 0)

def cpu_log_stats(run, w_lo, w_hi):
    """per-second sampler rows -> CPU seconds over the measure window."""
    p = os.path.join(run, "cpu.log")
    st = {"softirq_s": 0.0, "cpu8_busy_s": 0.0, "napi_s": 0.0,
          "ksi_s": 0.0, "app_s": 0.0}
    if not os.path.exists(p):
        return st
    prev = {}
    t = 0
    for ln in open(p):
        ln = ln.strip()
        if ln.startswith("@"):
            t += 1
            continue
        if t < w_lo or t > w_hi:
            continue
        a = ln.split()
        if not a:
            continue
        if a[0] == "cpu8":
            # user nice system idle iowait irq softirq ...
            v = [int(x) for x in a[1:9]]
            if "c8" in prev:
                d = [x - y for x, y in zip(v, prev["c8"])]
                st["softirq_s"] += d[7] / 100.0
                st["cpu8_busy_s"] += (sum(d) - d[3] - d[4]) / 100.0
            prev["c8"] = v
        elif a[0] == "task" and a[1] in ("napi", "ksi8", "ksi9", "app"):
            rt = int(a[2])
            k = a[1]
            if k in prev and rt >= prev[k]:
                bucket = {"napi": "napi_s", "app": "app_s"}.get(k, "ksi_s")
                st[bucket] += (rt - prev[k]) / 1e9
            prev[k] = rt
    return st

def main():
    tag = sys.argv[1]
    slo = float(sys.argv[2]) if len(sys.argv) > 2 else 500.0
    base = "/root/p1/results/%s" % tag
    print("tag cell policy workload rate plen rep gates_ok offered goodput deliv "
          "lat_p50 lat_p90 lat_p99 lat_p999 under_slo resp censored sockdrops "
          "app_ns c_net_ns cyc refcyc cpu8_busy_s softirq_s napi_s "
          "wire_ok layers_ok")
    for mpath in sorted(glob.glob(base + "/*/rep*/manifest.json")):
        run = os.path.dirname(mpath)
        try:
            m = load_manifest(run)
            cell = m["cell"]
        except Exception as e:
            print("WARN bad-manifest %s: %s" % (mpath, e), file=sys.stderr)
            continue
        warm = m["time"]["warmup_s"]
        meas = m["time"]["measure_s"]
        g = m["gates"]
        gates_ok = all(v == "pass" for v in g.values())
        cons = open(os.path.join(run, "consumer.txt")).read()
        kv = parse_kv(cons, ["pkts", "mpkts", "sockdrops", "echoed",
                             "cyc/pkt", "refcyc/pkt", "app_ns/pkt",
                             "p50_us", "p90_us", "p99_us", "p99.9_us"])
        snd = ""
        for p in sorted(glob.glob(os.path.join(run, "sender-*.txt"))):
            for ln in open(p):
                if ln.startswith("[k5blast] dip=") or ln.startswith("[k4send] sip="):
                    snd += ln
        skv = parse_kv(snd, ["sent", "resp", "censored"])
        sent = int(skv.get("sent", 0))
        offered = sent / (warm + meas + 1) if sent else 0
        wins = [w for w in win_lines(run) if warm < w[0] <= warm + meas]
        wgood = sum(w[1] for w in wins) / meas if wins else 0
        cs = cpu_log_stats(run, warm + 1, warm + meas)
        if cell["workload"] == "W1":
            # goodput from the consumer's measure-window counter over
            # its measure span (skip..secs = meas+3 s); the 1s-win file is
            # NOT trustworthy (a straggler's fd can clobber it - fig1-3)
            goodput = kv.get("mpkts", 0) / float(meas + 3)
            lp = [kv.get(k, -1) for k in ("p50_us", "p90_us", "p99_us", "p99.9_us")]
            # SLO share of the latency histogram == measure pkts * frac;
            # consumer hist covers the measure window already (--skip)
            under = ""
            if slo > 0 and "mpkts" in kv and kv["mpkts"] > 0:
                frac = 0.0
                # approximate from percentiles when under_slo share not
                # separable: p50<p99 bracketing is too coarse - use hist
                # dump if present, else NaN
                hp = os.path.join(run, "lat-hist.txt")
                if os.path.exists(hp):
                    hh = {}
                    for ln in open(hp):
                        a = ln.split()
                        if len(a) == 2:
                            hh[int(a[0])] = int(a[1])
                    fr, c = hist_frac_le(hh, slo)
                    under = "%.0f" % (fr * goodput)
            resp = cens = ""
        else:
            resp = int(skv.get("resp", 0))
            cens = int(skv.get("censored", 0))
            goodput = resp / (warm + meas + 1)
            hh = merge_hists(run)
            lp = [pct(hh, q) for q in (50, 90, 99, 99.9)]
            fr, c = hist_frac_le(hh, slo)
            under = "%.0f" % (c / (warm + meas + 1))
        # per-hop accounting (analysis-time validity): sent == wire
        # arrivals (the queue's rx counter) within 2%; wire ==
        # consumed + sockdrops + backlog drops + ring drops within 2%.
        # The harness's single-layer gate legitimately fails at overload
        # where drops move below the socket -- that is the result.
        wire, allp, ring = ethtool_delta(run)
        bproc, bdrop = softnet_delta(run)
        close_wire = abs(wire - sent) <= 0.02 * max(sent, 1)
        acc = pkts_true + int(kv.get("sockdrops", 0)) + bdrop + ring
        close_layers = abs(wire - acc) <= 0.03 * max(wire, 1)
        # parse_kv key "pkts" substring-matches "mpkts=" too, so
        # kv["pkts"] == pkts + mpkts; recover the true total
        pkts_true = int(kv.get("pkts", 0)) - int(kv.get("mpkts", 0))
        pk = kv.get("mpkts", 0) or pkts_true or 1
        # c_net basis: napi kthread runtime for threaded arms; inline
        # arm = cpu8 busy minus the app thread's own runtime (P0X: all
        # of cpu8 is network processing, the app sits on cpu 9)
        if cell["policy"] in ("P2", "P3", "P4") and cs["napi_s"] > 0:
            c_net = "%.0f" % (cs["napi_s"] * 1e9 / pk)
        elif cell["policy"] == "P0X":
            c_net = "%.0f" % (cs["cpu8_busy_s"] * 1e9 / pk)
        else:
            c_net = "%.0f" % (max(cs["cpu8_busy_s"] - cs["app_s"], 0.0) * 1e9 / pk)
        print("%s %s %s %s %d %d %d %s %.0f %.0f %.3f %s %s %s %s %s %s %s %s "
              "%.0f %s %.1f %.1f %.2f %.2f %.2f %d %d" % (
                  tag, cell_path_cell(run), cell["policy"], cell["workload"],
                  cell["rate"], cell["plen"], cell["rep"], "1" if gates_ok else "0",
                  offered, goodput,
                  (pkts_true / sent) if sent else 0,
                  lp[0], lp[1], lp[2], lp[3], under or "-",
                  resp if resp != "" else "-",
                  cens if cens != "" else "-",
                  int(kv.get("sockdrops", 0)),
                  kv.get("app_ns/pkt", -1), c_net,
                  kv.get("cyc/pkt", -1), kv.get("refcyc/pkt", -1),
                  cs["cpu8_busy_s"], cs["softirq_s"], cs["napi_s"],
                  int(close_wire), int(close_layers)))

def cell_path_cell(run):
    # .../results/TAG/<CELL>/rep<k> -> <CELL>
    return os.path.basename(os.path.dirname(run))

if __name__ == "__main__":
    main()
