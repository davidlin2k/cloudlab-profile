#!/usr/bin/env python3
"""t2_analyze.py -- DR-005 task 2 record: the three state dumps side by
side and the first-event CQ of each recovery. Facts only.

usage: python3 t2_analyze.py [TASK2_ROOT]   (default /root/p1/task2)

For each cell: which JSON fields the devlink rx dump exposes (or the
exact error if it refuses), the posted-buffer/CQ-index availability,
and the first CQ with a completion in the first cq-events sample after
the recovery onset. Writes analysis/t2-sidebyside.md next to the root's
parent when writable, else prints it.
"""
import os, re, sys, datetime

def parse_env(path):
    env = {}
    for ln in open(path, errors="replace"):
        s = ln.strip()
        m = re.match(r"(\S+) mono=(\S+)", s)
        if m:
            env[m.group(1)] = m.group(2)
        else:
            m2 = re.match(r"(PROBE-\S+)(?: adv=(\d+))?", s)
            if m2:
                env[m2.group(1)] = m2.group(2) or "1"
            elif s in ("NOT-RECOVERED-120s", "NO-WEDGE in 120s"):
                env[s] = "1"
    return env

def dump_fields(path):
    """which fields exist in the devlink rx dump, or the exact error"""
    try:
        txt = open(path, errors="replace").read()
    except OSError:
        return ["(missing dump file)"]
    if "Invalid argument" in txt and "{" not in txt:
        return ["devlink refused: kernel answers: Invalid argument"]
    fields = re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)"\s*:', txt)
    return sorted(set(fields)) or ["(no JSON fields parsed)"]

def parse_cq(path):
    """cq-events.txt -> [(hhmmss, {cqn: count}), ...] in file order"""
    out = []
    for ln in open(path, errors="replace"):
        m = re.match(r"(\d\d:\d\d:\d\d)", ln)
        if not m:
            continue
        counts = {int(a): int(b) for a, b in re.findall(r"@cq\[(\d+)\]:\s*(\d+)", ln)}
        out.append((m.group(1), counts))
    return out

def mono_to_hhmmss(env):
    # CELL START carries both mono and wall clock
    m = re.match(r"(\S+ \S+) mono=(\S+)", "")
    return None

def first_cq_after(samples, wall_start_s):
    """first sample at/after wall_start_s whose counts are nonzero"""
    for hhmmss, counts in samples:
        t = datetime.datetime.strptime(hhmmss, "%H:%M:%S").time()
        secs = t.hour * 3600 + t.minute * 60 + t.second
        if secs >= wall_start_s and counts:
            top = sorted(counts.items(), key=lambda kv: -kv[1])
            return hhmmss, top[:4]
    return None, []

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "/root/p1/task2"
    lines = ["# t2 side-by-side (facts only)", ""]
    for cell in sorted(os.listdir(root)):
        d = os.path.join(root, cell)
        if not os.path.isdir(d):
            continue
        env = parse_env(os.path.join(d, "cell.env"))
        lines.append(f"## {cell}")
        lines.append("")
        lines.append("| phase | devlink rx dump: fields that exist | ethtool rx7/oob at the phase |")
        lines.append("| --- | --- | --- |")
        for phase in ("healthy-flood", "wedge-plus-10s", "reduce-plus-30s"):
            dp = os.path.join(d, f"t2-dump-{phase}.txt")
            fields = dump_fields(dp)
            et = ""
            try:
                txt = open(dp, errors="replace").read()
                m = re.search(r"rx7_packets: (\d+)", txt)
                o = re.search(r"rx_out_of_buffer: (\d+)", txt)
                et = f"rx7={m.group(1) if m else '?'} oob={o.group(1) if o else '?'}"
            except OSError:
                et = "(missing)"
            lines.append(f"| {phase} | {'; '.join(fields)[:120]} | {et} |")
        lines.append("")
        # first-event CQ of the recovery: the recovery onset = RECOVERED
        # mono if present, else the REDUCE mono (best documented anchor).
        cq = parse_cq(os.path.join(d, "cq-events.txt"))
        rec = env.get("RECOVERED") or env.get("REDUCE")
        if cq and rec:
            # the cq log's wall clock is unknown here; report the first
            # nonzero sample and the last sample as anchors (facts only)
            nz = [(h, c) for h, c in cq if c]
            first = nz[0] if nz else None
            lines.append(f"cq-events samples: {len(cq)}; nonzero: {len(nz)}")
            if first:
                top = sorted(first[1].items(), key=lambda kv: -kv[1])[:4]
                lines.append(f"first nonzero sample at {first[0]}: cq counts {top}")
            lines.append(f"anchors: REDUCE mono={env.get('REDUCE')} RECOVERED mono={env.get('RECOVERED')}")
        else:
            lines.append("cq-events: (no samples or no anchors)")
        lines.append(f"verdict: {'; '.join(k for k in ('WEDGE','NO-WEDGE in 120s','RECOVERED','NOT-RECOVERED-120s') if k in env)}"
                     + "; probe=" + "; ".join(k for k in env if k.startswith("PROBE-")))
        lines.append("")
    out = "\n".join(lines)
    dest = os.path.join(os.path.dirname(root.rstrip("/")), "t2-sidebyside.md")
    try:
        open(dest, "w").write(out)
        print(f"wrote {dest}")
    except OSError:
        pass
    print(out)

if __name__ == "__main__":
    main()
