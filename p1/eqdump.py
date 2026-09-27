#!/usr/bin/env python3
"""p1/eqdump.py -- one-off: a channel's comp EQ pointer + arm state.

Facts only. mcq = ch + 320 (mlx5e_rq.cq) + 56 (mlx5e_cq.mcq); DWARF
offsets from the build-tree mlx5_core.ko (pahole): arm_db=16,
arm_sn=100, eq=176. Memory via /proc/kcore (drgn raw reads).

Usage: sudo python3 eqdump.py <ch_addr_hex>
Prints machine lines: EQ=0x... (the logger's input) plus the arm
state at read time.
"""
import drgn
import sys

prog = drgn.program_from_kernel()
CH = int(sys.argv[1], 16)
MCQ = CH + 320 + 56

def rd(addr, n):
    return prog.read(addr, n)

u64 = lambda b: int.from_bytes(b, "little")
u32 = lambda b: int.from_bytes(b, "little")

eq = u64(rd(MCQ + 176, 8))
armdb_ptr = u64(rd(MCQ + 16, 8))
arm_sn = u32(rd(MCQ + 100, 4))
if armdb_ptr > 0xFFFF000000000000:
    adb_raw = rd(armdb_ptr, 4)
    adb_sn = (int.from_bytes(adb_raw, "big") >> 28) & 3
else:
    adb_sn = -1
print(f"EQ={hex(eq)}")
print(f"ch={hex(CH)} mcq={hex(MCQ)} arm_db={hex(armdb_ptr)}")
print(f"arm_sn={arm_sn} arm_sn&3={arm_sn & 3} adb_sn={adb_sn}")
