#!/usr/bin/env python3
"""p1/napi_pid.py -- resolve ch<n>'s NAPI kthread pid from the kernel.

Reads napi_struct.napi_id (offset 380, pahole on this build) from the
channel struct and prints the /proc pid whose comm is
napi/<dev>-<napi_id>. The comm's id changes on every channel
recreation, so the pid must be resolved at run time, not hardcoded.
Usage: napi_pid.py <ch_addr_hex>
"""
import os
import sys

CH = int(sys.argv[1], 16)
NAPI = CH + 10000
NAPI_ID = NAPI + 380

import drgn
prog = drgn.program_from_kernel()
try:
    prog.load_debug_info(["/scratch/kbuild/linux/vmlinux"], main=False)
except Exception:
    pass

napi_id = int.from_bytes(bytes(prog.read(NAPI_ID, 4)), "little")
want = f"napi/enp195s0np0-{napi_id}"
for p in os.listdir("/proc"):
    if not p.isdigit():
        continue
    try:
        if open(f"/proc/{p}/comm").read().strip() == want:
            print(p)
            sys.exit(0)
    except Exception:
        continue
sys.exit(f"no proc matches {want}")
