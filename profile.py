#!/usr/bin/python3
"""
Receiver-driven host networking testbed -- v2 for the current program.

One receiver (machine under test) + N senders on a single 100G experiment LAN.
6 r6615 nodes = rx + tx0..tx4. The profile repo is mounted at
/local/repository on every node; setup.sh runs at boot via ExecuteService
(deps + one grub-reboot if needed + NIC/IRQ/topology prep on the receiver).
Private trees (HomaModule with local patches, flowlet-eval) are pushed at
experiment time with deploy.sh -- they are not part of this repo.

Experiments served, in order:
  E0   e0/e0_gate.sh   -- port->queue actuation gate (K1)
  K2   k2/k2_ddio.sh   -- DDIO causality, the decisive figure
  MAT  homa.ko baseline matrix (after E0/K2 decide the shape)

Instantiate on Clemson with hwtype=r6615 (AMD Genoa 9354P, 32c, 4 CCDs,
12ch DDR5, CX-6 100G). Ubuntu 24.04 stock kernel; homa.ko is rebuilt
on-node against it (setup.sh installs the headers).
"""

import geni.portal as portal
import geni.rspec.pg as rspec

hwtypes = [
    ("r6615", "Clemson r6615: 1x32c AMD Genoa 9354P, 4 CCDs, CX-6 100G"),
    ("r650", "Clemson r650: 2x36c Ice Lake 8360Y, CX-6 100G, uncore PMON/CAT"),
    ("r6525", "Clemson r6525: 2x32c AMD Milan, CX-6 100G"),
    ("sm110p", "Wisconsin sm110p: 1x16c Ice Lake, CX-6 DX 100G (SIRD/Caladan)"),
    ("d7525", "Wisconsin d7525: 2x16c AMD Rome, CX-6 DX 200G, 8 small L3s"),
    ("c6620", "Utah c6620: 1x28c Emerald Rapids, Intel E810-C 100G"),
]

osimages = [
    "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU24-64-STD",
]

pc = portal.context()
request = pc.makeRequestRSpec()

pc.defineParameter(
    "hwtype", "Hardware type", portal.ParameterType.STRING, "r6615", hwtypes,
    longDescription="Must match the cluster chosen at instantiation.")
pc.defineParameter(
    "nsenders", "Number of sender nodes (6-node reservation: use 5)",
    portal.ParameterType.INTEGER, 5)
pc.defineParameter(
    "osimage", "OS image", portal.ParameterType.STRING, osimages[0], osimages)
pc.defineParameter(
    "scratchgb", "Extra scratch on the receiver (GB, 0 to skip)",
    portal.ParameterType.INTEGER, 50, advanced=True)
pc.defineParameter(
    "tuneboot", "Run setup.sh at boot (deps, irqbalance off, governor, NIC)",
    portal.ParameterType.BOOLEAN, True, advanced=True)
pc.defineParameter(
    "iommu_off", "Reboot once with amd_iommu/intel_iommu=off (grub edit + one reboot)",
    portal.ParameterType.BOOLEAN, False, advanced=True)

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

    if params.tuneboot:
        node.addService(rspec.ExecuteService(
            shell="bash",
            command="bash /local/repository/setup.sh {} {} {}".format(
                role, params.nsenders, 1 if params.iommu_off else 0)))
    return node


rx = make_node("rx", "10.10.1.1", "rx")
if params.scratchgb > 0:
    bs = rx.Blockstore("rx-scratch", "/scratch")
    bs.size = "%dGB" % params.scratchgb

for i in range(params.nsenders):
    make_node("tx%d" % i, "10.10.1.%d" % (10 + i), "tx")

pc.printRequestRSpec(request)
