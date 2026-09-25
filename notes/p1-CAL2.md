# p1-CAL2 -- calibration note: memcached low-load costs + idle p99

*Calibration for the W3 spec's pre-registered knee (DR-004 task 4).
Not an experiment set: no claim rests on these outputs alone.*

Setup: memcached 1.6.24 `-t 1` (whole process pinned: P0 = CPU 8,
P0X = CPU 9), queue 7 steer via ntuple rule on dport 11211 (landing
gated), mutilate (built from leverich/mutilate master, SConstruct
ported to python3) open-loop Poisson from n2-n6, 30 B keys, 32 B
values, 10% sets / 90% gets (`--update 0.1`; set probability per
Connection.cc:127), 100k keyspace. Cost window: 20 kQPS, 60 s measure
after 5 s warmup; PMU bracket [6.5, 64.5] of ref-cycles on CPUs 8,9
at TSC 3.250 GHz (the C-014 basis). Idle p99 from a 200 QPS trickle.
SLO = 10x idle p99.

Outputs: /root/p1/w3cal2/{arm-P0,arm-P0X,load-P0,load-P0X,perf-P0,
perf-P0X,idle-P0,idle-P0X,ntuple.log,ntuple-dump.txt,samples-*}.txt.

Open instrument items recorded at run time: whether the ntuple rule
lands on queue 7 (counters gate in arm-*.txt), and the bracket's
+/-0.5 s edge offset against the load window (cost error ~1.7%).
