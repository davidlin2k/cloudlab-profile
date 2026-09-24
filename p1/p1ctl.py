#!/usr/bin/env python3
"""p1ctl -- the predictive placement ladder controller (P7, Fig 5/6).

Stock kernel interfaces only: /proc/net/softnet_stat for the per-queue
arrival rate (the queue's IRQ is pinned to one CPU, so that CPU's row IS
the queue), /sys/class/net/<iface>/threaded for per-NAPI threading, and
sched_setaffinity for the NAPI kthread. The knee model (Fig 4, form F)
takes the two measured per-packet costs plus the SMT factor as config:

  rung 0  inline on the app core      knee = 1e9/(c_app+c_net)
  rung 1  kthread on the SMT sibling  knee = (2/s)*1e9/(c_app+c_net)
  rung 2  kthread on another core     knee = 1e9/max(c_app, c_net)

Switch policy: CLIMB when the measured rate reaches HEADROOM x the
current rung's predicted capacity (moves BEFORE the knee is crossed);
DESCEND when the rate stays below DESCEND_F x the next-lower rung's
capacity for HOLD seconds (hysteresis: no flapping). Every move is
logged with ns timestamps and the rate estimate (Fig 5 time series,
Table 2 switch latency).

The NAPI kthread for the target queue is identified PASSIVELY: on the
first climb, snapshot all napi/*/schedstat runtimes, wait one window,
and take the thread whose runtime grew most (the queue's traffic was
already flowing). No probe traffic is injected.

usage: p1ctl.py --c-app NS --c-net NS --smt S [--iface IF] [--irq-cpu N]
                [--sib-cpu N] [--other-cpu N] [--duration S] [--log F]
"""
import argparse, os, re, time

def softnet_processed(cpu):
    with open("/proc/net/softnet_stat") as f:
        for i, ln in enumerate(f):
            if i == cpu:
                return int(ln.split()[0], 16)
    return 0

def napi_threads():
    out = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/comm") as f:
                c = f.read().strip()
        except OSError:
            continue
        if c.startswith("napi/"):
            try:
                with open(f"/proc/{pid}/schedstat") as f:
                    rt = int(f.read().split()[0])
            except OSError:
                rt = 0
            out[pid] = (c, rt)
    return out

def find_napi_cpu(log):
    """passive identification: the napi thread whose runtime moves."""
    a = napi_threads()
    time.sleep(0.5)
    b = napi_threads()
    best, best_d = None, -1
    for pid in a:
        d = b.get(pid, (None, 0))[1] - a[pid][1]
        if d > best_d:
            best, best_d = pid, d
    if best is None or best_d <= 0:
        log("napi-id: UNRESOLVED (no moving thread)")
        return None
    log(f"napi-id: pid={best} name={a[best][0]} delta={best_d}ns")
    return best

def set_rung(rung, cfg, napi_pid, log):
    t0 = time.time_ns()
    if rung == 0:
        with open(f"/sys/class/net/{cfg.iface}/threaded", "w") as f:
            f.write("0")
    else:
        with open(f"/sys/class/net/{cfg.iface}/threaded", "w") as f:
            f.write("1")
        if napi_pid:
            os.sched_setaffinity(int(napi_pid),
                                 {cfg.sib_cpu if rung == 1 else cfg.other_cpu})
    dt = time.time_ns() - t0
    log(f"switch -> rung {rung} in {dt/1e6:.2f} ms")
    return dt

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iface", default="enp195s0np0")
    ap.add_argument("--irq-cpu", type=int, default=8)
    ap.add_argument("--sib-cpu", type=int, default=40)
    ap.add_argument("--other-cpu", type=int, default=9)
    ap.add_argument("--c-app", type=float, required=True, help="ns/pkt")
    ap.add_argument("--c-net", type=float, required=True, help="ns/pkt")
    ap.add_argument("--smt", type=float, default=1.24)
    ap.add_argument("--window", type=float, default=0.2)
    ap.add_argument("--headroom", type=float, default=0.8)
    ap.add_argument("--descend-f", type=float, default=0.5)
    ap.add_argument("--hold", type=float, default=2.0)
    ap.add_argument("--duration", type=float, default=180.0)
    ap.add_argument("--log", default="/root/p1/p1ctl.log")
    cfg = ap.parse_args()

    knees = [1e9 / (cfg.c_app + cfg.c_net),
             (2.0 / cfg.smt) * 1e9 / (cfg.c_app + cfg.c_net),
             1e9 / max(cfg.c_app, cfg.c_net)]

    lf = open(cfg.log, "w", buffering=1)

    def log(msg):
        lf.write(f"{time.time():.6f} {msg}\n")

    log(f"model knees pps: rung0={knees[0]:.0f} rung1={knees[1]:.0f} "
        f"rung2={knees[2]:.0f} (c_app={cfg.c_app} c_net={cfg.c_net} s={cfg.smt})")
    rung = 0
    napi_pid = None
    set_rung(0, cfg, napi_pid, log)
    last = softnet_processed(cfg.irq_cpu)
    t_start = time.time()
    low_since = None
    switches = 0
    while time.time() - t_start < cfg.duration:
        time.sleep(cfg.window)
        now = softnet_processed(cfg.irq_cpu)
        rate = (now - last) / cfg.window
        last = now
        if rung == 0 and rate > cfg.headroom * knees[0]:
            if napi_pid is None:
                napi_pid = find_napi_cpu(log)
            rung = 1 if rate < cfg.headroom * knees[1] else 2
            set_rung(rung, cfg, napi_pid, log)
            switches += 1
            low_since = None
        elif rung == 1 and rate > cfg.headroom * knees[1]:
            rung = 2
            set_rung(rung, cfg, napi_pid, log)
            switches += 1
            low_since = None
        elif rung > 0:
            lower_ok = rate < cfg.descend_f * knees[rung - 1]
            if lower_ok:
                low_since = low_since or time.time()
                if time.time() - low_since > cfg.hold:
                    rung -= 1
                    set_rung(rung, cfg, napi_pid, log)
                    switches += 1
                    low_since = None
            else:
                low_since = None
        log(f"rate={rate:.0f} rung={rung} knee={knees[rung]:.0f}     f"t_rel={time.time()-t_start:.2f}")
    log(f"done switches={switches}")
    lf.close()

if __name__ == "__main__":
    main()
