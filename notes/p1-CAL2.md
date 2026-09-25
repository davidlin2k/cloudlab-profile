# Calibration 2/3: memcached per-CPU costs (feeds the W3 pre-registration)

Question: per-request CPU costs of memcached -t 1 serving mutilate's 32 B
key / 32 B value 90%-GET workload at low load (20k aggregate QPS), split by
placement; plus the idle p99 and the load-model calibration.

Run: cal-3/cal-3b on rx (2026-09-25 08:49Z, 09:05Z), 5 independent mutilate
masters on tx0-tx4, measure window 65 s, PMU bracket [t0+6, t0+70].

## Result (cal-3b, kthread 1594438 pinned to CPU 8)

Requests in bracket 1,278,596 (P0) / 1,278,952 (P0X). Achieved 19,983
aggregate QPS (5 masters, per-master 3,992-4,001 vs 4,000 target).

- P0 (worker + receive on CPU 8): CPU8 61.28e9 + CPU9 5.75e9 ref-cycles =
  52,424 rc = 16,130 ns per request.
- P0X (worker CPU 9, receive CPU 8): CPU8 25.21e9 rc = 6,066 ns/req (receive);
  CPU9 50.45e9 rc = 12,138 ns/req (app).
- Idle p99 (98.7 QPS trickle): 104.1 us (P0), 105.5 us (P0X).
- Load-window latency at 20k QPS: p99 521 us (P0) / 490 us (P0X); op_q 1.2-1.3.

Validities: Misses 0.0% (all 10 windows), Skipped TXs 0.0%, landing purity
99.93-99.95% (ntuple rule tcp4 dport 11211 -> queue 7), achieved within 0.2%.

## Instrument facts (recorded for the paper)

- Pacing law (10 masters): achieved = -q / c per master (mutilate divides the
  thread rate by its connection count). The spec's flags use q = (target/5)*c.
- `--update 0.1` = exactly 90% GETs (Connection.cc:127, drand48).
- mutilate toolchain: py3 SConstruct port (/tmp/SConstruct.py3); Generator.cc
  segfault for bare distributions fixed (p1/patches/Generator.cc.upstream,
  strtok_r on NULL a_ptr); build needs libzmq3-dev + libevent-2.1 (agent mode
  links -lzmq); binaries md5 96f66318e584ca9b74d1eabf4ab41092 on all 5 nodes.
- Agent mode (-A/-a) works but is restart-fragile (a killed master strands its
  agents; masters then hang) -> five independent masters in the spec.
- memcached (Debian build) defaults to 127.0.0.1 -> explicit -l 10.10.1.1.
- The threaded-NAPI kthread for queue 7 (PID 1594438) was found with affinity
  9 and wanders (AN-006A saw it on CPU 40): any per-CPU accounting REQUIRES
  pinning it (cal-3 without the pin garbled the split).

## Superseded numbers

cal-3 (08:49Z, kthread unpinned) reported P0 24.7 us/req and P0X split
0.025/21.8 us: superseded by cal-3b (the kthread had migrated to CPU 9; the
P0X receive cost on CPU 8 was invisible). cal-2 runs are void (mutilate
missing libevent/zmq on senders; memcached bound localhost).
