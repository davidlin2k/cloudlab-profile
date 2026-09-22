# E0 actuation gate (Reins K1)

**What K1 asks:** on a ConnectX-6 (mlx5) pair, does a chosen UDP source port
deterministically select a chosen RX queue on the receiver?  If yes, Reins can
steer each message to a chosen core by assigning the sender's ephemeral port —
the whole mechanism rests on this actuation primitive.  This kit answers it
empirically: it dumps the receiver's live Toeplitz key + RSS indirection table
(`ethtool -x`), predicts the queue for each probed 4-tuple with `toeplitz.py`,
makes the sender fire exact-4-tuple packets with `sportgen`, and checks the
per-queue hardware counters (`ethtool -S`).  Run it between **two nodes**; it
cannot use loopback (packets to the node's own IP never traverse the NIC's RX
path).  `--veth` gives a single-node plumbing smoke test only (veth does no
RSS).

Files: `toeplitz.py` (reference Toeplitz + queue prediction, selftested against
the Intel 82599 verification vectors from DPDK `test_thash.c`), `sportgen.c`
(raw UDP / TCP-shaped / IP-proto-146 emitter), `e0_gate.sh` (the gate).

## Prerequisites

* Two r6615 nodes from `profile.py` on the experiment LAN: receiver `10.10.1.1`,
  sender `10.10.1.11` (first tx node).  CloudLab nodes share SSH keys.
* Receiver: `python3`, `ethtool`, `iproute2`; root for `ethtool -x`
  (CAP_NET_ADMIN).  Run the gate under `sudo` (CloudLab sudo is passwordless),
  or it re-invokes `sudo -n` per privileged call.
* Sender: the kit at the same path (default `~/e0`); `gcc` if the binary is not
  built yet (the gate builds it automatically).

## Run

```sh
# from the workstation (or wherever the kit lives):
scp -r /home/david/network-workspace/cloudlab-profile/e0 rx:e0
ssh rx 'scp -r e0 tx:'

# on the receiver:
cd ~/e0
sudo ./e0_gate.sh --veth                        # optional plumbing smoke test
sudo ./e0_gate.sh --sender 10.10.1.11           # the gate; ~5-10 min at defaults
# knobs: --iface eno1 --n-sports 64 --pkts 20000 --dports 4240,4421
#         --ssh-user root --remote-kit ~/e0 --steer-core 30 --set-ntuple off
```

Output: human verdict table + `e0_result.json`
(`{proto: {pass, mean_hit_frac, n_trials, n_pass}}` per proto) plus raw
artifacts in `e0_last_run/` (ethtool dumps, `trials.csv`, predictions, sender
plan).  Exit 0 only if **tcp AND udp** pass; the proto-146 result is
informational.  A trial passes when >= 97% of its 20000 packets land on the
predicted queue; the gate calibrates the prediction mode (key byte order x
canonicalization) on 3 udp trials first and records it as `predict_mode`.

## Expected outcomes

| udp  | tcp  | 146  | verdict                 | meaning |
|------|------|------|-------------------------|---------|
| pass | pass | fail | `hijack_gated`          | 4-tuple RSS is deterministic; Homa-native (proto 146) traffic hashes L3-only.  **Reins is gated on hijack mode** (ship Homa frames as TCP, `homa_hijack.c` + `net.homa.hijack_tcp=1`).  This is the expected result. |
| fail | fail | any  | `k1_fires`              | No port -> queue determinism: K1 fires.  Inspect `predict_mode`, ntuple rules, aRFS, `trials.csv` scatter before concluding. |
| pass | pass | pass | `unexpected_native_pass`| Would contradict L3-only hashing for portless protocols; re-check driver/firmware. |
| fail | pass | any  | `udp_anomaly`           | TCP-shaped works, UDP doesn't; check rx offloads (`ethtool -k`, saved in artifacts). |

## mlx5 quirks the kit handles (with sources)

* **The default RSS key is randomized per boot** — `mlx5e_rss_params_init()`
  calls `netdev_rss_key_fill()` (`drivers/net/ethernet/mellanox/mlx5/core/en/rss.c`).
  Never hardcode a key; the gate dumps it every run.
* mlx5 consumes the key **exactly as ethtool prints it** (`mlx5e_rss_set_rxfh()`
  memcpy's it unchanged).  Reversed consumption is an older-mlx4 habit; the
  calibration would surface it as `predict_mode=rev*` if an adapter did it.
* **Symmetric hashing**: default `symmetric = true` in current mlx5e (`en/rss.c`),
  not set (i.e. off) on Ubuntu 24.04's 6.8 kernel.  The gate tries
  `ethtool -X <iface> symmetric off` and otherwise calibrates among the
  candidate canonicalizations (`--all-modes`: `fwd fwd_xor fwd_swap rev*`).
* The indirection table (RQT) is padded to a power of two that can exceed the
  channel count (`mlx5e_rqt_size()`, `en/rx_res.c`); extra entries map to
  queue 0.  Queue = `indir[hash & (indir_size - 1)]` — lowest bits of the
  32-bit Toeplitz result (the DPDK `HASH_MSK` convention).
* Portless protocols (146) hash L3-only, so the queue cannot follow the sport —
  the expected informational failure above.
* Per-queue counter names vary (`rx_3_packets` vs `rx3_packets`); both are parsed.

## After the gate: hijack-mode end-to-end

The CloudLab image is Ubuntu 24.04 (`UBUNTU24-64-STD`) with a **stock kernel** —
`uname -r` (e.g. 6.8.x).  `homa.ko` in
`/home/david/network-workspace/HomaModule` was built for 6.19.14, so it must be
rebuilt against the node kernel:

```sh
sudo apt install -y linux-headers-$(uname -r) build-essential
rsync -a rx:HomaModule/ HomaModule/        # or git clone
cd HomaModule && make all                  # INSTALL.md step 2
sudo insmod homa.ko                        # INSTALL.md step 3
sudo sysctl net.homa.hijack_tcp=1          # enable hijack (INSTALL.md)
```

`e0_gate.sh`'s TCP-shaped probe (`sportgen --proto tcp`: PSH|ACK, valid
checksums, fixed seq) matches the frames `homa_hijack.c` intercepts, so a
`hijack_gated` verdict means the next step — Reins assigning per-message source
ports end to end through homa.ko, grants and all (`homa_grant_hdr`,
`homa_wire.h:329`) — is actuable.
