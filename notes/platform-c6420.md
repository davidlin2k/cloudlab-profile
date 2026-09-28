# Platform: Clemson c6420 (T1B, DR-015)

Recorded 2026-09-28 (Day 1) from live commands on clnode208 (rx, pair-1
DUT) and clnode187 (tx1, pair-2 DUT). Experiment davidlin-318237,
repo pin f1f7a26.

## CPUs and memory topology

- 2 sockets x Intel Xeon Gold 6142 @ 2.60 GHz (Skylake-SP, 16 cores
  each, 2 SMT threads) = 64 CPUs, max 3.7 GHz.
- 2 NUMA nodes; **CPU numbering is interleaved by socket**: node0 =
  the even CPUs (0,2,...,62), node1 = the odd CPUs (1,3,...,63).
- SMT sibling pairs: (2k, 2k+32) on node0 and (2k+1, 2k+33) on node1
  (verified: cpu6 siblings = 6,38; core_id 6 = 3).
- L3: 44 MiB, 2 instances -- one L3 per socket (no sub-NUMA
  clustering observed: only 2 NUMA nodes on a 2-socket part).
- No `nohz_full=`/`isolcpus=` on the cmdline (stock Emulab cmdline).

## NIC

- Dual-port Intel X710-DA2 at 0000:18:00.0/1 (i40e).
- Experiment port = 0000:18:00.1 = enp24s0f1np1, MAC 3c:fd:fe:55:f8:a2,
  10G link, **numa_node = 0** (NIC-local socket = node0 = even CPUs).
- Driver i40e (in-tree, 6.17.8-061708), firmware 6.00 0x800034ec
  18.3.6.
- 64 combined channels available; the experiment uses 32 (one per
  physical core of the NIC-local socket per setup.sh).
- Ring: RX 512 descriptors, **16-byte descriptors** (ring->size
  8192 = 512 x 16; DD = bit 0 of the qword at desc+8, i.e. the write-
  back status_error_len; for the 16-byte layout this overlaps the read
  side's hdr_addr as the driver comment says).
- Flow Director: the perfect-match (sideband) filter routes the flood
  (src 10.10.1.10, sport 32704 -> dst 10.10.1.1, dport 7777, udp4)
  to queue 7; verified: every sent packet lands in rx-7 (deltas match
  the sender's count exactly).

## Software

- Kernel: 6.17.8-061708-generic (Ubuntu mainline, build 202511132139)
  on both DUTs -- the same build the r6615 runs; debs staged at
  deep-research-output/rx-placement-admission/deb-cache/.
  NOTE: install requires `dpkg --configure -a` (the DKMS autoinstall
  fails on this image) and `update-initramfs -c -k 6.17.8-061708-generic`
  (dpkg's postinst aborts before building the initramfs), then
  `update-grub` (else the menu still boots 6.8.0-138).
- Threaded NAPI: on (set by the preflight).
- IRQ core: **cpu 6** (node0 = the NIC-local socket, physical core 3).
  The setup.sh boot-time IRQ spread races the i40e probe and does not
  stick; the harness pins TxRx-7 (irq 131) to cpu 6 itself.

## Arm map (DR-015: arms defined by their relation to the IRQ core)

| Arm | CPU | Relation |
|-----|-----|----------|
| A | 38 | the IRQ core's SMT sibling |
| B | 10 | same socket (node0), other physical core |
| C | 24 | other socket (node1) |
| D | - | unpinned |

r6615 analogs: A=40, B=10, C=24, D=unpinned (B and C keep the same
numbers by coincidence of the interleaved numbering).

## Pairs

- Pair 1: DUT clnode208 (rx, 10.10.1.1) + sender clnode195 (10.10.1.10).
- Pair 2: DUT clnode187 (10.10.1.11, promoted: setup.sh rx 3 0) +
  sender clnode186 (10.10.1.12).
- Flood tool: k5blast at /root/k2/k5blast on both senders.

## Probe notes (t1b_probe.py, raw /proc/kcore)

drgn is unusable here (no DWARF on the mainline build; the i40e
structs are absent from both vmlinux and module BTF).  Offsets:
net/net_device from the running kernel's vmlinux BTF; i40e fields
derived from the sources and verified against ethtool:
- init_net via /proc/kallsyms; net.dev_base_head@176;
  net_device name@288, dev_list@344, priv@2688.
- **vsi->rx_rings @ +3304 -- on 6.17.8, +3312 is tx_rings** (verified:
  ring[7].stats.packets == rx-7.packets exactly; +3312 == tx-7.packets).
  The 6.18.9-derived offset is 8 bytes late; this cost a session.
- ring: desc@8, queue_index@56, count@132, next_to_process@128,
  next_to_use@138, next_to_clean@140, stats.packets@152, size@224
  (8192 = 512 x 16 -> 16B descriptors), eth_stats@3008 with
  rx_discards@+32 (verified: rx_bytes/rx_packets match the netdev).
- The poller's work pointer is next_to_process (ntp); the strand
  detector = the DD bit set on any reposted slot in [ntp, ntu) while
  ntp is frozen > 50 ms.  Idle sanity: ntp=ntc=192, ntu=511, pending=0.
