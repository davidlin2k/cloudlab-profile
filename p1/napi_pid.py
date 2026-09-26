#!/usr/bin/env python3
"""p1/napi_pid.py -- resolve ch<n>'s NAPI kthread pid from the kernel.

napi_struct.thread (offset 352) is the kthread's task_struct*; the pid
sits at task_struct.pid (offset 2512, pahole on this vmlinux). The
/proc comm is unreliable here (all napi kthreads read
"napi/enp195s0np0-0" in this build), so the pid comes from kcore.
Usage: napi_pid.py <ch_addr_hex>
"""
import sys

CH = int(sys.argv[1], 16)
NAPI_THREAD = CH + 10000 + 352
TASK_PID = 2512

import drgn
prog = drgn.program_from_kernel()
try:
    prog.load_debug_info(["/scratch/kbuild/linux/vmlinux"], main=False)
except Exception:
    pass

def u(a, n):
    return int.from_bytes(bytes(prog.read(a, n)), "little")

task = u(NAPI_THREAD, 8)
if task < 0xFF00000000000000:
    sys.exit(f"bad thread ptr {task:#x}")
print(u(task + TASK_PID, 4))
if len(sys.argv) > 2 and sys.argv[2] == "--cpu":
    print(u(task + 20, 4))
