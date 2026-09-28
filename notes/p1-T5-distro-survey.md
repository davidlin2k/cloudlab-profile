# p1-T5: the distribution-config survey for C-014 (the 166x undercount)
# (DR-013 addendum T5; facts only, one row per distro, sources cited)

Question (the memo): which real systems ship CONFIG_IRQ_TIME_ACCOUNTING=n
together with NO_HZ_FULL=y -- the configuration under which C-014's
166x /proc/stat busy-time undercount occurs? The paper states the 166x
only for the configurations measured, and names which distros ship
them; if none did, C-014 would be a custom-kernel caveat.

## Verified (config source read directly, date 2026-09-28)

| Distro / kernel | IRQ_TIME_ACCOUNTING | NO_HZ_FULL | Undercount config? | Source |
|---|---|---|---|---|
| Ubuntu 24.04 LTS generic 6.8.0-52 | not set | y | YES | community boot-config record of the shipped kernel (github.com/nyrahul/linux-kernel-configs, Ubuntu 24.04.1 6.8.0-52 bootconfig) |
| Debian sid (debian/latest packaging) | not set (amd64/config) | y (base config) | YES | salsa.debian.org/kernel-team/linux, branch debian/latest: debian/config/config + debian/config/amd64/config |
| Fedora (kernel-ark os-build) | y (fedora/generic fragment) | y (common/generic) | NO (irq-time on) | gitlab.com/cki-project/kernel-ark, os-build: redhat/configs/fedora/generic/CONFIG_IRQ_TIME_ACCOUNTING + common/generic/CONFIG_NO_HZ_FULL |
| RHEL / Rocky 10 (centos-stream-10) | not set (rhel/generic) | y (common/generic) | YES | gitlab.com/redhat/centos-stream/src/kernel/centos-stream-10, main: redhat/configs/rhel/generic/CONFIG_IRQ_TIME_ACCOUNTING + common/generic/CONFIG_NO_HZ_FULL |
| SUSE SLE15-SP7 x86_64 default | not set | y | YES | github.com/SUSE/kernel-source, SLE15-SP7: config/x86_64/default |
| Amazon Linux 2023 (in-tree x86_64_defconfig) | absent (n) | absent (n) | NO (no NO_HZ_FULL) | github.com/amazonlinux/linux, master: arch/x86/configs/x86_64_defconfig |

## Reading

- The undercount configuration is NOT a custom-kernel-only caveat:
  four mainstream shipping kernels (Ubuntu generic, Debian sid,
  RHEL/Rocky 10, SUSE SLE15) ship IRQ_TIME_ACCOUNTING=n with
  NO_HZ_FULL=y.
- Fedora ships IRQ_TIME_ACCOUNTING=y (the accounting is exact there);
  Amazon Linux 2023 does not enable NO_HZ_FULL (no undercount mode).
- So C-014 stands for the measured configuration AND for the four
  distro configurations above; section 4 names them and the two
  counter-examples.

## Not verified remotely (2026-09-28, facts only)

- Ubuntu CLOUD kernels (linux-azure/-gcp/-aws): launchpad's gitweb and
  kernel.ubuntu.com return 403 for datacenter fetches; the
  annotations were not reachable. Next probe: read /boot/config-*
  from an actual cloud instance (the reservations or a test VM).
- Azure Linux, Google Container-Optimized OS, Bottlerocket, Flatcar,
  Android GKI: the config sources exist but the fetches did not
  resolve this pass (git hosting walls / tree-layout churn).
- Our H100 nodes' kernel: needs the node pointer (the PROGRAM's llm-d
  gateway hosts); not in this repo.