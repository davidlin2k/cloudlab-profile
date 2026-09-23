# CloudLab runbook — receiver-driven host placement (6× r6615)

One receiver (`rx`, 10.10.1.1 — the machine under test) + five senders
(`tx0..tx4`, 10.10.1.10+). Everything below assumes the current program
state: E0 gate built, K2 designed, falsifiers PA/KCOMMIT done in the
emulator, `homa.ko` needs an on-node rebuild.

**One entry point** (`make`): `deploy`, `e0`, `k2`, `load`, `status`,
`unload`, `trace` (regenerate the replay trace from the real Mooncake
JSONLs), `trace-matrix` (trace-driven mechanism matrix on real cores).
`RX`/`TXS` variables override the default 6-node addressing.

**Trace-driven workloads (`wk/`)** — the hybrid pipeline, built:
`trace2pktemu.py` converts the public FAST'25 JSONLs (toolagent /
conversation, 512-token block hashes) into pktemu replay traces with the
KV-size model, reuse-aware pull/push split, layer-chunk trains and the
real bursty timestamps; `trace2cdf.py` exports the same distribution as an
ns-3 message-size CDF; `run_trace.sh` replays a trace through the
placement matrix locally. The converted `wai_full.trace` is 900k messages
from 2,924 real requests over 324s at 51.6 Gbps implied (0.52 of line) —
production pace, not a synthetic approximation.

## 0. Instantiate the profile

Push this directory as a CloudLab profile (portal → New Profile → "from
source"; the repo must contain `profile.py` at its root — this directory is
shaped for that). Instantiate on **Clemson, r6615**, `nsenders=5`
(6 nodes), defaults for the rest. At boot, `setup.sh` runs on every node
via ExecuteService: packages, irqbalance off, performance governor,
32 queues / 1:1 IRQ→core spread on `rx`, and writes:

- `/root/setup-status` — ends with `OK` when phase 2 completed
- `/root/topology.txt` — `cpu core l3id` (the L3 id IS the CCD id on Genoa;
  this file is ground truth for every placement experiment)
- `/root/nic-state.txt`, `/root/rss-key.txt` — NIC dump

Verify from your machine: `ssh root@10.10.1.1 'cat /root/setup-status'`.
If it says `rebooting for iommu change`, just wait for the reboot (only if
you set the iommu_off parameter — off by default).

## 1. Deploy (your machine, from cloudlab-profile/)

```bash
./deploy.sh 10.10.1.1 10.10.1.10 10.10.1.11 10.10.1.12 10.10.1.13 10.10.1.14
```

Pushes the e0/k2 kits to all nodes, **clones HomaModule from
`https://github.com/PlatformLab/HomaModule.git` on every node** (upstream
main, deployed commit recorded to `/root/homa-commit` — idempotent: re-runs
reset to `origin/main`), and rsyncs flowlet-eval (private) to `rx`. sportgen
was rewritten with `--plen`; deploy rebuilds it everywhere.

> If an experiment needs the **rotating-grants patch** (uncommitted in your
> workstation tree, not upstream), use `./deploy.sh --local-homa ...` — that
> rsyncs your local tree instead of cloning. Baselines (native, hijack,
> Gen2/Gen3) don't need it.

## 2. E0 — actuation gate (K1), ~15 min, on rx

```bash
ssh root@10.10.1.1
cd /root/e0 && ./e0_gate.sh --sender 10.10.1.10 --iface <iface>
```

Reads the live Toeplitz key, sweeps 64 source ports × {UDP, TCP-hijack,
proto-146}, verifies predictions against per-queue counters, writes
`e0_result.json`. Expected: **TCP+UDP pass (4-tuple hashing), proto-146
L3-only** → verdict `hijack_gated` → Reins gates on hijack mode, K1 clear.
If UDP/TCP fail → K1 fires, stop and reassess. *(sportgen was rewritten
2026-09-22; if anything looks off, its byte-validation is this same gate's
`--veth` mode: `./e0_gate.sh --veth`.)*

## 3. K2 — DDIO causality, the decisive figure, ~15 min, on rx

```bash
ssh root@10.10.1.1
cd /root/k2 && ./k2_ddio.sh clnode337.clemson.cloudlab.us 10.10.1.10 enp195s0np0
```

**Network policy (CloudLab control-net rule):** the first argument is the
sender's *control-net hostname* — used for orchestration ssh only; the
second is the sender's *experiment* address (10.10.1.x), used only as
sportgen's `--dip`. Experiment traffic rides the experiment LAN and only
the experiment LAN; orchestration never shares it, because ssh bytes
during a measurement cell are background traffic corrupting the DDIO
result.

Streams 1400B UDP at ~1 Mpps with source ports empirically steered to three
queues (consumer's own, same-CCD other core, other-CCD), consumed by a
pinned, perf-counter-self-monitored core. Five cells → `/root/k2_result.json`
and a verdict:

- **queue-side delta** (far-queue vs own-queue, same consumer) > ~15% of
  baseline → pre-DMA placement moves what post-DMA cannot: the program's
  decisive figure, in the affirmative.
- ≈ 0 → the emulator's DDIO-floor assumption holds on server silicon:
  Reins's hardware win shrinks toward "flowlet without migration code"
  (kill K2) and the paper leans on the KCOMMIT/granularity results.

Either verdict is a publishable number; run it before anything else on the
nodes.

## 4. Calibration replication (~1 h, rx only)

Run the flowlet-eval microbenchmarks on Genoa to bridge emulator ↔ testbed
(l3 sweeps now span 4 real domains, not 2):

```bash
cd /root/flowlet-eval && gcc -O2 -pthread -I bench -o bench/calib bench/calib.c
taskset -c 0 ./bench/calib m0 && HOT=65536 taskset -c 0,8 ./bench/calib m4 64
```

Then the W-AI / placement matrix in the emulator on-node (same binaries as
your workstation; only `ccd_of()` in pktemu.c assumes 2 CCDs — retarget the
core list with `--wcpus=` for 4-CCD runs).

## 5. homa.ko + the end-to-end matrix (after E0/K2 decide the shape)

`homa.ko` is **already built on every node by deploy.sh** (against the node
kernel, 6.8; build log in `/root/homa-build.log`, source commit in
`/root/homa-commit`). Loading is fleet-wide, idempotent, one command —
**both ends need the module** (senders originate proto-146 traffic):

```bash
./homa-ctl.sh 10.10.1.1 10.10.1.10 10.10.1.11 10.10.1.12 10.10.1.13 10.10.1.14 load
./homa-ctl.sh 10.10.1.1 10.10.1.10 10.10.1.11 10.10.1.12 10.10.1.13 10.10.1.14 status   # shows homa.* sysctls
./homa-ctl.sh ... unload   # between experiment arms
```

Then the baseline matrix: native proto-146 (single-queue per sender — worth
reporting alone), hijack+RSS spread, Gen2/Gen3 (`homa.gro_policy` sysctl —
no reload needed between arms),
under W2/W3/W5 + the W-AI mix, senders driving via multiple ports per
tx node for 8–16 effective peers. **Skip the port-steer and flowlet columns
until K2's verdict is in** — it determines whether the grant-header patch
is worth writing.

## What NOT to do

Don't run the full matrix before E0/K2 (hours vs. the two figures that gate
everything), don't skip the deploy build step, and don't trust
`perf`-derived queue mappings on a node where `irqbalance` is running
(setup.sh disabled it — re-check with `systemctl is-active irqbalance`
after any reboot).

## The gap map (docs/gap-map.html) (docs/gap-map.html)

Open `docs/gap-map.html` in a browser for the one-page picture of the whole
program: the verdict board (six claims, post-review), the design-space stack
(who decides what — and the one decision no layer makes), the actuator×sensor
matrix with measured/open/occupied cells, the regime-boundary chart
(placement's leverage collapses 22×→~1× on production bursts while admission
order persists 27×→13×), and the theory triangle. Every numeric bar is
cross-checked against `flowlet-eval/FINDINGS.md`; schematic panels are marked
as such. Source-of-truth review: `~/deep-research-output/rx-placement-admission/`
(49-paper database, deep dives, verdict appendix).
