# p2-CLNODES: CloudLab node types with non-Mellanox NICs

Source: CloudLab hardware documentation,
https://docs.cloudlab.us/hardware.html (retrieved 2026-09-25). Drivers
inferred from the documented NIC models (the docs do not name drivers).
Deliverable: DR-005 task 6 second driver (ice/i40e/bnxt), due Oct 2.

## Named classes (the memo's ice / i40e / bnxt)

| Class | Node type | Cluster | Nodes | Documented NIC |
|---|---|---|---|---|
| ice (E810) | c6620 | Utah | 132 | Intel E810-XXV 25Gb + E810-C 100Gb |
| ice (E810) | d760 | Utah | 4 | Intel E810-XXV 25Gb + E810-C 100Gb (request-only) |
| ice (E810) | d760-hbm | Utah | 2 | Intel E810-XXV 25Gb + E810-C 100Gb (request-only) |
| i40e (X710) | c6420 | Clemson | 72 | Intel X710 10Gb |
| i40e (X710) | c4130 | Clemson | 2 | Intel X710 10Gb (+ i350 1G) |
| bnxt | d6515 | Utah | 28 | Broadcom 57414 25Gb (+ CX5 100Gb) |
| bnxt | d750 | Utah | 4 | Broadcom BCM57504 25Gb (request-only) |
| bnxt | rs440 | Mass | 5 | Broadcom 57412 10Gb |

Best second-driver candidates: **c6420 (Clemson, i40e, 72 nodes)** --
same cluster as the existing experiment, 10G experiment net; or
**c6620 (Utah, ice, 132 nodes)** -- the largest non-Mellanox pool.
The Clemson r650 carries Mellanox NICs only (CX5 25G + CX6 100G) per
the docs, so the second driver does not fit on the r650 itself.

## Other non-Mellanox types (outside the named classes)

| Driver | Node types | Cluster | Nodes | NIC |
|---|---|---|---|---|
| ixgbe (X520) | c220g1, c240g1, c220g2, c240g2, c220g5 | Wisconsin | 474 | Intel X520-DA2 10Gb |
| ixgbe (X520) | c6320, dss7500 | Clemson | 84 | Intel X520 10Gb |
| ixgbe (X520) | c6220 | Apt | 56 | Intel X520 10Gb |
| bnx2x (NetXtreme II) | ibm8335 | Clemson | 6 | Broadcom BCM57800 1/10Gb |
| sfc (Solarflare) | rs620, rs630 | Mass | 76 | Solarflare SFC9120 10G |

(Unspecified "Intel 10Gbe" on Clemson c8220/c8220x, 100 nodes -- model
not given in the docs.)
