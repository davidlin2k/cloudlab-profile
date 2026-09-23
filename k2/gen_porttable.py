#!/usr/bin/env python3
"""Generate the K5 port-authoring tables.

Default mode: for every sender node (sip octet 10..14) and pinned source
port (32700..32719), find a destination port per RSS queue 0..7 that
lands there under the DPDK reference key with the identity 32-entry
indirection table (queue = hash & 31). Rows: sip sport dport queue

--blasters mode: for each dport in a pool, list every (sip, sport) whose
4-tuple hashes that dport onto queue 0 -- extra demand sources so a
capacity cell can saturate one port with several spin-paced blasters.
Rows: dport sip sport"""
import sys
sys.path.insert(0, "/mnt/davidlin-personal/cloudlab-profile/e0")
from toeplitz import toeplitz, stream4, DPDK_KEY

key = bytes.fromhex(DPDK_KEY)

if "--blasters" in sys.argv:
    rows = []
    for dp in range(5000, 5300):
        for sip in range(10, 15):
            sip_s = f"10.10.1.{sip}"
            for sport in range(32700, 32720):
                if toeplitz(key, stream4(sip_s, "10.10.1.1", sport, dp)) & 31 == 0:
                    rows.append(f"{dp} {sip} {sport}")
    print("\n".join(rows))
    sys.exit(0)

rows = []
for sip_oct in range(10, 15):
    sip = f"10.10.1.{sip_oct}"
    for sport in range(32700, 32720):
        found = {}
        d = 5000
        while d < 30000 and len(found) < 8:
            q = toeplitz(key, stream4(sip, "10.10.1.1", sport, d)) & 31
            if q < 8 and q not in found:
                found[q] = d
            d += 1
        for q, dp in sorted(found.items()):
            rows.append(f"{sip_oct} {sport} {dp} {q}")
print("\n".join(rows))
