#!/usr/bin/env python3
"""rxfuzz v0 -- DR-005 task 6 (spec: specs/p2-RXFUZZ.md, frozen).

usage:
  rxfuzz.py run [--cells N] [--seed S] [--date YYYY-MM-DD] [--smoke]
  rxfuzz.py minimize --cell <cell-dir> [--seed S]

One cell: a sampled configuration, a sampled load schedule, one
sampled perturbation during load, the 10k probe, and the oracle pass
over the 1 Hz counters. Rings and channels are set between cells only.
Between cells the task 1 step 4 recovery runs when the previous cell
ends PERMANENT (the spec's discipline), logged in the cell's directory.
hits.csv columns (the spec's): date, cell, oracle, dimensions...,
schedule, onset_s, recovered, reset_needed.
"""
import argparse, datetime, json, os, random, re, subprocess, time

IFACE = "enp195s0np0"
IRQ = "312"
REF = 525000
SENDERS = [(10, 32704), (11, 32726), (12, 32706), (13, 32724), (14, 32725)]
ROOT = "/root/p2/rxfuzz"
DIMENSIONS = {
    "threaded": ["0", "1"],
    "napi_placement": ["irq-cpu", "smt-sibling", "same-l3", "other-l3", "unpin"],
    "adaptive_rx": ["on", "off"],
    "ring": ["default", "8192"],
    "striding_rq": ["on", "off"],
    "gro": ["on", "off"],
    "busy_read": ["0", "50"],
    "napi_defer_hard_irqs": ["0", "2"],
    "gro_flush_timeout": ["0", "200000"],
}
DEFAULTS = {"threaded": "1", "napi_placement": "unpin", "adaptive_rx": "on",
            "ring": "default", "striding_rq": "on", "gro": "on",
            "busy_read": "0", "napi_defer_hard_irqs": "0", "gro_flush_timeout": "0"}
SCHEDULES = {
    1: ("ramp 0.3->1.5x over 60 s", [(0.3, 30), (0.6, 30), (1.0, 30), (1.5, 30)]),
    2: ("flood 1.5x 60 s then 0.6x 120 s", [(1.5, 60), (0.6, 120)]),
    3: ("five cycles of 20 s 1.5x / 20 s 0.3x", [(1.5, 20), (0.3, 20)] * 5),
    4: ("steady 0.9x", [(0.9, 120)]),
}

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout

def napi_threads():
    out = []
    for p in os.listdir("/proc"):
        if not p.isdigit(): continue
        try: c = open(f"/proc/{p}/comm").read().strip()
        except OSError: continue
        if c.startswith(f"napi/{IFACE}-"): out.append(int(p))
    return out

def cpu_topology():
    irq_cpu = 8
    sib = open(f"/sys/devices/system/cpu/cpu{irq_cpu}/topology/thread_siblings_list").read().strip()
    smt = [int(x) for x in re.findall(r"\d+", sib) if int(x) != irq_cpu][0]
    def l3(cpu):
        p = f"/sys/devices/system/cpu/cpu{cpu}/cache/index3/id"
        return open(p).read().strip() if os.path.exists(p) else "?"
    home = l3(irq_cpu); same = other = None
    for cpu in range(os.cpu_count()):
        if cpu in (irq_cpu, smt): continue
        if l3(cpu) == home and same is None: same = cpu
        if l3(cpu) != home and other is None: other = cpu
    return irq_cpu, smt, same or 9, other or 40

def apply_config(cfg):
    sh(f"echo {cfg['threaded']} > /sys/class/net/{IFACE}/threaded")
    sh(f"ethtool -K {IFACE} gro {'on' if cfg['gro'] == 'on' else 'off'} >/dev/null 2>&1")
    sh(f"ethtool -C {IFACE} adaptive-rx {'on' if cfg['adaptive_rx'] == 'on' else 'off'} >/dev/null 2>&1")
    for f in ("napi_defer_hard_irqs", "gro_flush_timeout"):
        p = f"/sys/class/net/{IFACE}/queues/rx-7/{f}"
        if os.path.exists(p): sh(f"echo {cfg[f]} > {p}")
    p = "/proc/sys/net/core/busy_read"
    if os.path.exists(p): sh(f"echo {cfg['busy_read']} > {p}")
    irq_cpu, smt, same, other = cpu_topology()
    want = {"irq-cpu": irq_cpu, "smt-sibling": smt, "same-l3": same,
            "other-l3": other}.get(cfg["napi_placement"])
    for pid in napi_threads():
        if want is None:
            sh(f"taskset -pc 0-{os.cpu_count()-1} {pid} >/dev/null 2>&1")
        else:
            sh(f"taskset -pc {want} {pid} >/dev/null 2>&1")
    sh(f"echo {want if want is not None else irq_cpu} > /proc/irq/{IRQ}/smp_affinity_list")

def set_between_cells(cfg):
    ring = "1024" if cfg["ring"] == "default" else "8192"
    sh(f"ethtool -G {IFACE} rx {ring}")
    sh(f"ethtool --set-priv-flags {IFACE} rx_striding_rq {cfg['striding_rq']}")

def start_senders(rate_pps):
    per = max(1, int(rate_pps / len(SENDERS)))
    for o, s in SENDERS:
        sh(f"ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.{o} "
           f"\"sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip {o} --sport {s} "
           f"--dport 7777 --rate {per} --secs 320 --plen 64 --core 4 > /tmp/rxfuzz-{o}.txt 2>&1 </dev/null &'\"")

def stop_senders():
    for o, _ in SENDERS:
        sh(f"ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.{o} "
           "'sudo pkill -xc k5blast; true'")

def probe(secs=30):
    p0 = int(re.search(r"rx7_packets: (\d+)", sh(f"ethtool -S {IFACE}")).group(1))
    sh("ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=8 davidlin@10.10.1.10 "
       f"\"sudo bash -c 'nohup /root/k2/k5blast --dip 10.10.1.1 --sip 10 --sport 32704 "
       f"--dport 7777 --rate 10000 --secs {secs} --plen 64 --core 4 > /tmp/rxfuzz-probe.txt 2>&1 </dev/null &'\"")
    time.sleep(secs + 2)
    p1 = int(re.search(r"rx7_packets: (\d+)", sh(f"ethtool -S {IFACE}")).group(1))
    return p1 - p0

def parse_counters(path):
    out, t = [], None
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return []
    for ln in lines:
        m = re.match(r"@ (\S+)", ln)
        if m:
            t = float(m.group(1)); out.append([t, None, None]); continue
        if t is None: continue
        m = re.search(r"rx7_packets: (\d+)", ln)
        if m: out[-1][1] = int(m.group(1))
        m = re.search(r"rx_out_of_buffer: (\d+)", ln)
        if m: out[-1][2] = int(m.group(1))
    return [r for r in out if r[1] is not None and r[2] is not None]

def oracle_hits(counters, intervals, drop_time):
    """{class: onset_s}; windows exactly as the frozen spec"""
    hits, flat, under = {}, 0, 0
    if not counters: return hits
    t0 = counters[0][0]
    for i in range(2, len(counters)):
        t, rx7, oob = counters[i]
        d_rx = rx7 - counters[i-1][1]; d_oob = oob - counters[i-1][2]
        flat = flat + 1 if (d_rx == 0 and d_oob > 0) else 0
        if flat >= 6 and "STALL" not in hits:
            hits["STALL"] = counters[i - flat + 1][0] - t0
            if drop_time is not None and hits["STALL"] >= drop_time + 60:
                hits["METASTABLE"] = hits["STALL"]
        rate = None
        for s, e, r in intervals:
            if s <= t - t0 < e: rate = r
        if rate is not None:
            want = 0.5 * min(rate, REF)
            d2 = rx7 - counters[i-2][1]
            under = under + 1 if d2 / 2.0 < want else 0
            if under >= 10 and "COLLAPSE" not in hits:
                hits["COLLAPSE"] = counters[i - under + 1][0] - t0
        else:
            under = 0
    return hits

def trace_for(cls, d):
    sh(f"trace-cmd record -C mono -b 262144 -o {d}/hit-{cls}.dat "
       f"-e napi:napi_poll -e irq:irq_handler_entry -p function -l mlx5e_napi_poll "
       f"-l mlx5e_completion_event & sleep 10; pkill -xc trace-cmd")

def step4_recover(logpath):
    """the task 1 step 4 recovery (the spec's between-cell discipline)"""
    log = open(logpath, "a")
    def w(s): log.write(s + "\n"); log.flush()
    sh(f"echo 0 > /sys/class/net/{IFACE}/threaded"); time.sleep(5)
    sh(f"echo 1 > /sys/class/net/{IFACE}/threaded"); time.sleep(3)
    adv = probe(8)
    w(f"recovery threaded-toggle probe adv={adv}")
    if adv >= 14000: w("RECOVERED-BY-THREADED-TOGGLE"); return True
    sh(f"ethtool -L {IFACE} combined 32")
    irq_cpu, _, _, _ = cpu_topology()
    sh(f"echo {irq_cpu} > /proc/irq/{IRQ}/smp_affinity_list")
    time.sleep(3); adv = probe(8)
    w(f"recovery channels-32 probe adv={adv}")
    if adv >= 14000: w("RECOVERED-BY-CHANNELS"); return True
    sh(f"ethtool -L {IFACE} combined 16"); time.sleep(2)
    sh(f"ethtool -L {IFACE} combined 32")
    sh(f"echo {irq_cpu} > /proc/irq/{IRQ}/smp_affinity_list")
    time.sleep(3); adv = probe(8)
    w(f"recovery recreate-16-32 probe adv={adv}")
    w("RECOVERED-BY-RECREATION" if adv >= 14000 else "UNRECOVERED")
    return adv >= 14000

def perturb(rng):
    what = rng.choice(["threaded-toggle", "move-napi", "move-irq", "ethtool-C"])
    if what == "threaded-toggle":
        sh(f"echo 0 > /sys/class/net/{IFACE}/threaded"); time.sleep(1)
        sh(f"echo 1 > /sys/class/net/{IFACE}/threaded")
    elif what == "move-napi":
        irq_cpu, smt, same, other = cpu_topology()
        for pid in napi_threads():
            sh(f"taskset -pc {rng.choice([smt, same, other])} {pid} >/dev/null 2>&1")
    elif what == "move-irq":
        irq_cpu, smt, same, other = cpu_topology()
        sh(f"echo {rng.choice([irq_cpu, smt, same, other])} > /proc/irq/{IRQ}/smp_affinity_list")
    else:
        sh(f"ethtool -C {IFACE} rx-usecs {rng.choice([0, 8, 30])} >/dev/null 2>&1")
    return what

def run_cell(date, cell_id, cfg, sched_id, rng, smoke=False):
    d = f"{ROOT}/{date}/{cell_id}"
    os.makedirs(d, exist_ok=True)
    json.dump(cfg, open(f"{d}/config.json", "w"), indent=1)
    name, segs = SCHEDULES[sched_id]
    open(f"{d}/schedule.txt", "w").write(f"{sched_id}: {name}\n{segs}\n")
    set_between_cells(cfg)
    apply_config(cfg)
    cw = subprocess.Popen(["bash", "/root/k2/tracewatch.sh", f"{d}/counters.log"])
    t0 = time.time(); intervals = []; drop_time = None
    segs = segs[:1] if smoke else segs
    total = sum(s for _, s in segs)
    sh("/root/k2/k2_rx --port 7777 --core 8 --secs 420 --skip 0 > /dev/null 2>&1 &")
    time.sleep(1)
    pert_at = rng.uniform(0.25, 0.75)
    traced, done = set(), 0
    for frac, secs in segs:
        rate = int(frac * REF)
        start_senders(rate)
        s0 = time.time() - t0
        intervals.append((s0, s0 + secs, rate))
        if frac <= 0.6: drop_time = drop_time or s0
        for elapsed in range(secs):
            time.sleep(1)
            if (done + elapsed + 1) / total >= pert_at:
                what = perturb(rng)
                open(f"{d}/schedule.txt", "a").write(f"perturbation at {done+elapsed}s: {what}\n")
                pert_at = 2.0
            cs = parse_counters(f"{d}/counters.log")
            if len(cs) >= 10:
                tail = cs[-12:]
                shift = tail[0][0] - cs[0][0]
                live = oracle_hits(tail,
                                   [(a - shift, b - shift, r) for a, b, r in intervals],
                                   (drop_time - shift) if drop_time is not None else None)
                for cls in ("STALL", "METASTABLE", "COLLAPSE"):
                    if cls in live and cls not in traced:
                        traced.add(cls); trace_for(cls, d)
        done += secs
        stop_senders(); time.sleep(0.2)
    adv = probe()
    hits = {}
    if adv < 270000:
        hits["PERMANENT"] = done
        if "PERMANENT" not in traced:
            traced.add("PERMANENT"); trace_for("PERMANENT", d)
    cw.terminate(); time.sleep(1)
    counters = parse_counters(f"{d}/counters.log")
    hits.update(oracle_hits(counters, intervals, drop_time))
    recovered = adv >= 270000
    reset_needed = False
    if not recovered:
        reset_needed = True
        step4_recover(f"{d}/recovery.log")
    sh(f"dmesg -T | tail -40 > {d}/dmesg.txt")
    open(f"{d}/verdict.txt", "w").write(
        f"probe_adv={adv}\nhits={sorted(hits)}\nonset={hits}\n"
        f"recovered={recovered}\nreset_needed={reset_needed}\n"
        f"config={json.dumps(cfg)}\nschedule={sched_id}\n")
    if hits:
        cols = ["date", "cell", "oracle"] + list(DIMENSIONS) + \
               ["schedule", "onset_s", "recovered", "reset_needed"]
        hp = f"{ROOT}/hits.csv"
        if not os.path.exists(hp):
            open(hp, "w").write(",".join(cols) + "\n")
        for cls, onset in sorted(hits.items()):
            row = [date, cell_id, cls] + [cfg[k] for k in DIMENSIONS] + \
                  [str(sched_id), f"{onset:.1f}", str(int(recovered)), str(int(reset_needed))]
            open(hp, "a").write(",".join(row) + "\n")
    return sorted(hits), adv, reset_needed

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["run", "minimize"])
    ap.add_argument("--cells", type=int, default=96)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--smoke", action="store_true")
    ap.add_argument("--cell")
    a = ap.parse_args()
    seed = a.seed if a.seed is not None else int(time.time())
    rng = random.Random(seed)
    os.makedirs(f"{ROOT}/{a.date}", exist_ok=True)
    if a.mode == "run":
        sh(f"echo seed={seed} > {ROOT}/{a.date}/seed.txt")
        for i in range(1, a.cells + 1):
            cfg = {k: rng.choice(v) for k, v in DIMENSIONS.items()}
            sched = rng.choice([1, 2, 3, 4])
            hits, adv, reset = run_cell(a.date, f"cell-{i:03d}", cfg, sched, rng, smoke=a.smoke)
            print(f"cell {i:03d} sched={sched} probe={adv} hits={hits} reset={reset}", flush=True)
            sh(f"kill $(ps -eo pid,args | awk '/k2_rx --port 7777/ && !/awk/ {{print $1}}') 2>/dev/null")
    else:
        cfg = json.load(open(f"{a.cell}/config.json"))
        sched = int(re.match(r"(\d+)", open(f"{a.cell}/schedule.txt").read()).group(1))
        keep = []
        for dim in DIMENSIONS:
            c2 = dict(cfg); c2[dim] = DEFAULTS[dim]
            hits, adv, _ = run_cell(a.date, f"min-{dim}", c2, sched, rng)
            if not hits: keep.append(dim)
        print("minimal dimensions (reset removes the hit):", keep)
        for rep in range(3):
            c2 = {k: (DEFAULTS[k] if k in keep else cfg[k]) for k in cfg}
            hits, adv, _ = run_cell(a.date, f"min-confirm-{rep}", c2, sched, rng)
            print(f"confirm {rep}: hits={hits} probe={adv}")

if __name__ == "__main__":
    main()
