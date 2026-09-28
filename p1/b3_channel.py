#!/usr/bin/env python3
"""p1/b3_channel.py -- name-based channel discovery (version-proof;
b2_dump's bpftrace-correlation priv walk broke on net-next 7.3 --
AN-010's sibling: the addresses moved, not the mechanism).

Prints (the migrate_run discovery contract):
  ch7=0x<channel address>        (the probe's CH arg: rq@CH+0)
  cq7=0x<rq.cq address>          (cross-check)
  napi_state=0x...
  napi_pid=<the poll thread pid or -1>
"""
import drgn
from drgn.helpers.linux.list import list_for_each_entry
import sys

prog = drgn.program_from_kernel()
NAME = sys.argv[1] if len(sys.argv) > 1 else "enp195s0np0"
IX = int(sys.argv[2]) if len(sys.argv) > 2 else 7

dev = None
for d in list_for_each_entry("struct net_device",
                             prog["init_net"].dev_base_head.address_of_(),
                             "dev_list"):
    if d.name.string_().decode() == NAME:
        off = next(m.offset for m in prog.type("struct net_device").members
                   if m.name == "dev_list")
        base = (d.dev_list.address_of_().value_() - off)
        dev = base
        break
if not dev:
    print("NO-DEV")
    sys.exit(1)

# netdev_priv: the mlx5e priv sits right after the net_device
# (NETDEV_ALIGN=32)
sz = prog.type("struct net_device").size
priv = drgn.cast("struct mlx5e_priv *",
                 drgn.Object(prog, "unsigned long",
                             dev + ((sz + 31) & ~31)))
ch = priv.channels.c[IX]
try:
    ch = ch[0]   # 7.3's c[] is an array of POINTERS (deref); older
                 # trees had struct arrays (the deref raises, keep)
except Exception:
    pass
addr = ch.address_of_().value_()
cq = ch.rq.cq.address_of_().value_()
state = ch.napi.state.value_()
pid = -1
try:
    th = ch.napi.thread
    if th and th.pid.value_() > 0:
        pid = th.pid.value_()
except Exception:
    pass
if pid < 0:
    # the thread-pointer fallback: the kthread is named
    # napi/<netdev>-<ix>; find it in /proc (b2_dump's correlation
    # replacement)
    import glob
    want = f"napi/{NAME}-{IX}"
    for st in glob.glob("/proc/[0-9]*/stat"):
        try:
            with open(st) as f:
                t = f.read()
            comm = t.split("(", 1)[1].rsplit(")", 1)[0]
            if comm == want:
                pid = int(st.split("/")[2])
                break
        except Exception:
            continue

print(f"ch7={hex(addr)}")
print(f"cq7={hex(cq)}")
print(f"napi_state={hex(state)}")
print(f"napi_pid={pid}")