#!/bin/python3

"""
Receiver-driven host networking testbed.

One receiver node plus N sender nodes on a single 100Gb experiment LAN.
The receiver is the machine under test: Homa module, placement, NIC-filter
baseline, split-flow cost, L3-domain sweeps. Senders are load generators.

Instantiate on Clemson with hwtype=r6615 (single-socket AMD Genoa, 4 CCDs,
12ch DDR5, ConnectX-6 100G) for the primary experiments, and on Clemson with
hwtype=r650 (dual Ice Lake, uncore PMON, CAT/MBA) for host-counter work.
"""

# Import the Portal object.
import geni.portal as portal
import geni.rspec.pg as rspec

hwtypes = [
    ("r6615", "Clemson r6615: 1x32c AMD 9354P, 12ch DDR5, CX-6 100G"),
    ("r650", "Clemson r650: 2x36c Ice Lake 8360Y, CX-6 100G, uncore PMON"),
    ("r6525", "Clemson r6525: 2x32c AMD Milan, CX-6 100G"),
    ("sm110p", "Wisconsin sm110p: 1x16c Ice Lake, CX-6 DX 100G (SIRD/Caladan)"),
    ("d7525", "Wisconsin d7525: 2x16c AMD Rome, CX-6 DX 200G, 8 small L3s"),
    ("c6620", "Utah c6620: 1x28c Emerald Rapids, Intel E810-C 100G"),
]

osimages = [
    "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU24-64-STD",
]

pc = portal.context
request = pc.makeRequestRSpec()

pc.defineParameter(
    "hwtype",
    "Hardware type",
    portal.ParameterType.STRING,
    "r6615",
    hwtypes,
    longDescription="Must match the cluster chosen at instantiation.",
)

pc.defineParameter(
    "nsenders", "Number of sender nodes", portal.ParameterType.INTEGER, 1
)
pc.defineParameter(
    "osimage",
    "OS image",
    portal.ParameterType.STRING,
    osimages[0],
    osimages,
)

pc.defineParameter(
    "tmpfs",
    "Extra scratch space on the receiver (GB), 0 to skip",
    portal.ParameterType.INTEGER,
    0,
    advanced=True,
)

params = pc.bindParameters()

if params.nsenders < 1 or params.nsenders > 31:
    pc.reportError(portal.ParameterError("nsenders must be 1..31", ["nsenders"]))
pc.verifyParameters()

# Single experiment LAN. No bandwidth is set: setting one inserts shaping
# nodes. best_effort keeps the allocator from reserving capacity we do not
# want it to police.
lan = request.LAN("lan")
lan.best_effort = True
lan.vlan_tagging = False
lan.link_multiplexing = False


def make_node(name, ip, role):
    node = request.RawPC(name)
    node.hardware_type = params.hwtype
    node.disk_image = params.osimage

    iface = node.addInterface("eth-exp")
    iface.addAddress(rspec.IPv4Address(ip, "255.255.255.0"))
    lan.addInterface(iface)

    return node


receiver = make_node("rx", "10.10.1.1", "receiver")

if params.tmpfs > 0:
    bs = receiver.Blockstore("rx-scratch", "/scratch")
    bs.size = "%dGB" % params.tmpfs

for i in range(params.nsenders):
    make_node("tx%d" % i, "10.10.1.%d" % (10 + i), "sender")

pc.printRequestRSpec(request)
