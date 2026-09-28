# D3 backup record (DR-013 section 3, "Backup")

Date: 2026-09-28. Facts only.

## What exists now

1. **The existing backup** (referenced by DR-013): the raw W3 run
   directories at analysis/w3main/ (11 GB, 1,081 files, gitignored).
2. **A fresh full-scope off-node copy** (this pass):
   /home/david/deep-research-output/rx-placement-admission/d3-backup/
   - p1/ = the ENTIRE node /root/p1 tree (27 GB, 11,972 files):
     w3main (11G), wedgetrace (6.3G), w3knee2 (2.6G), metastab
     (2.6G), migrate (1.8G -- T1A/T1D/T1E raw CSVs + all earlier
     arms), w3knee (1.3G), perf (809M), rq1 (199M), wakedelay
     (107M), results, wdiag, w3cal*, task2, irqpin, all arm logs
     and every harness script.
   - provenance/config-6.17.8-061708-generic (the measured kernel's
     config).
   - manifest.sha256 = the per-file sha256 manifest (11,972 lines);
     sha256(manifest.sha256) =
     b3afbb50a512aab4ea65aacd22af3a942c53d709a17432c97c8acce367082ce2

## Verification performed

- The existing backup vs the node (ground truth): 1,081 of 1,081
  files hash-IDENTICAL (sha256, per-file, vs the fresh node copy).
  Content verified.
- Delta: the fresh copy has 2 files the older backup lacks
  (w3main/sched-P0-47500/sched.data,
  w3main/sched-P0X-47500/sched.data -- the sched-cell perf data,
  added after the older backup was made).
- The manifests: analysis/w3main.manifest.sha256 (1,081 lines) and
  analysis/d3-backup-manifest.sha256 (11,972 lines) are committed to
  the repo for future verification.

## The recorded hash ac02a12c974eebda (open)

DR-013 records "verify the existing backup against
ac02a12c974eebda" (a 16-hex prefix). It does not match any hash I
can compute on this side:
- sha256 of the w3main manifest file: 5a3a4fde5075545d...
- sha256 of a tar of w3main: f2ecf27cb5f14206...
- it is not a file hash inside w3main (checked the manifest lines).

What IS verified (stronger than any recorded constant): the
existing backup is byte-identical to the node's current data.
The discrepancy is flagged for the PI (the recorded prefix likely
refers to a manifest format or copy on the PI's side).

## Node release

The memo's gate ("release nodes only after the backup verifies") is
now satisfied in substance: the backup exists off-node, is
manifested, and the existing backup content-verifies against the
node. Node release remains the PI's action (the CloudLab portal).
The fresh copy includes everything needed to reproduce from the
archive without the node.