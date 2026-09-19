#!/bin/bash
# /local/repository/setup.sh <receiver|sender> <tunekernel> <iommu> <nsenders>
# Runs at every boot. Phase 1 installs and edits grub, then reboots once;
# phase 2 does the per-boot NIC and IRQ setup.
set -euo pipefail

echo "TODO"
