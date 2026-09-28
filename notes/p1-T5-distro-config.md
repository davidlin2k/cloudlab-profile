# P1-T5: Distro kernel-config survey — CONFIG_IRQ_TIME_ACCOUNTING × CONFIG_NO_HZ_FULL
<!-- DR-013 addendum, item T5. Surveyed 2026-09-28. Values read from shipped kernel configs (debs/rpms),
     distro config git, or published boot-config dumps, as labelled. x86_64 unless noted. -->

```yaml
survey: p1-T5-distro-config
date: 2026-09-28
scope: current shipping x86_64 kernels
markers: y = set; not set = "# CONFIG_x is not set"/absent-with-default-n; unknown = could not verify
mechanism_note: >
  NO_HZ_FULL=y selects VIRT_CPU_ACCOUNTING_GEN (verified =y in every NO_HZ_FULL=y config below),
  replacing tick-based CPU accounting system-wide; with CONFIG_IRQ_TIME_ACCOUNTING unset,
  IRQ time is not tracked at all (DR-013 C-014 undercount precondition).
  NO_HZ_FULL=y alone does not put CPUs in full-dynticks mode at runtime (needs nohz_full= cmdline),
  but VIRT_CPU_ACCOUNTING_GEN=y changes the accounting path regardless.
```

| # | Distribution (kernel) | CONFIG_IRQ_TIME_ACCOUNTING | CONFIG_NO_HZ_FULL | Source |
|---|---|---|---|---|
| 1 | Ubuntu 24.04 LTS generic (6.8.0-52 anchored; 6.8.0-146 current GA) | not set | **y** | boot-config dump of shipped 6.8.0-52: https://github.com/nyrahul/linux-kernel-configs/blob/main/Ubuntu%2024.04.1%20LTS/6.8.0-52-generic/bootconfig.md ; current GA from pool deb (extracted /boot/config-6.8.0-146-generic, identical): https://archive.ubuntu.com/ubuntu/pool/main/l/linux/linux-modules-6.8.0-146-generic_6.8.0-146.146_amd64.deb |
| 2 | Ubuntu 25.04 (plucky) generic (6.14.0-37) | not set | **y** | Launchpad librarian deb (extracted /boot/config-6.14.0-37-generic): https://launchpad.net/ubuntu/+archive/primary/+files/linux-modules-6.14.0-37-generic_6.14.0-37.37_amd64.deb |
| 3 | Ubuntu linux-aws 24.04 (6.8.0-1066-aws) | not set | **y** | Launchpad librarian deb (extracted /boot/config-6.8.0-1066-aws): https://launchpad.net/ubuntu/+archive/primary/+files/linux-modules-6.8.0-1066-aws_6.8.0-1066.69_amd64.deb |
| 4 | Ubuntu linux-azure 24.04 (6.8.0-1070-azure) | not set | **y** | Launchpad librarian deb (extracted /boot/config-6.8.0-1070-azure): https://launchpad.net/ubuntu/+archive/primary/+files/linux-modules-6.8.0-1070-azure_6.8.0-1070.78_amd64.deb |
| 5 | Debian 13 trixie (6.12.107+deb13-amd64) | not set | **y** | shipped deb /boot/config-6.12.107+deb13-amd64 (verified in both signed and -unsigned debs): https://deb.debian.org/debian/pool/main/l/linux/linux-image-6.12.107%2Bdeb13-amd64-unsigned_6.12.107-1_amd64.deb |
| 6 | Fedora 41 (6.12.15-200.fc41, final F41 kernel line) | **y** | **y** | shipped kernel-core rpm (extracted /lib/modules/6.12.15-200.fc41.x86_64/config): https://kojipkgs.fedoraproject.org/packages/kernel/6.12.15/200.fc41/x86_64/kernel-core-6.12.15-200.fc41.x86_64.rpm ; corroborating config git branch archived-6.12: https://gitlab.com/cki-project/kernel-ark/-/tree/archived-6.12 (redhat/configs/common/generic/CONFIG_NO_HZ_FULL = y; NO_HZ_IDLE not set) |
| 7 | Fedora 42 (6.14.11-300.fc42) | **y** | **y** | shipped kernel-core rpm (extracted /lib/modules/6.14.11-300.fc42.x86_64/config): https://kojipkgs.fedoraproject.org/packages/kernel/6.14.11/300.fc42/x86_64/kernel-core-6.14.11-300.fc42.x86_64.rpm ; corroborating: https://gitlab.com/cki-project/kernel-ark/-/tree/archived-6.14 |
| 8 | RHEL 9 / Rocky 9 (5.14.0-687.52.1.el9_8, Rocky 9.8 BaseOS) | **y** | **y** | shipped kernel-core rpm (extracted /lib/modules/5.14.0-687.52.1.el9_8.x86_64/config): https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/Packages/k/kernel-core-5.14.0-687.52.1.el9_8.x86_64.rpm |
| 9 | SLES 15 SP6 (kernel 6.4, config/x86_64/default; SP7 identical) | not set | **y** | SUSE kernel-source config (public mirror carries the SP6 kernel line as branch SLE15-SP6-LTSS; plain SLE15-SP6 branch not public): https://github.com/SUSE/kernel-source/blob/SLE15-SP6-LTSS/config/x86_64/default (CONFIG_NO_HZ_FULL=y, # CONFIG_NO_HZ_IDLE is not set, VIRT_CPU_ACCOUNTING_GEN=y, # CONFIG_IRQ_TIME_ACCOUNTING is not set; SP7 branch SLE15-SP7 same) |
| 10 | Amazon Linux 2023 (6.1.141-165.249.amzn2023.x86_64, dump 2025-07) | not set | **y** | published boot-config dump: https://github.com/nyrahul/linux-kernel-configs/blob/main/Amazon%20Linux%202023.8.20250715/6.1.141-165.249.amzn2023.x86_64/bootconfig.md (note: older 6.1.19 dump from 2023 still had NO_HZ_FULL off; Amazon enabled it later in the 6.1 line: https://github.com/nyrahul/linux-kernel-configs/blob/main/Amazon%20Linux%202023/6.1.19-30.43.amzn2023.x86_64/bootconfig.md ). AL2023 also offers a kernel-6.12 AMI — config unknown (not verified) |
| 11 | Azure Linux (CBL-Mariner) 2.0 (5.15.x) | not set | not set | spec config: https://github.com/microsoft/CBL-Mariner/blob/2.0/SPECS/kernel/config (# CONFIG_NO_HZ_FULL is not set, # CONFIG_IRQ_TIME_ACCOUNTING is not set) |
| 12 | Azure Linux 3.0 (6.6.x) | not set | not set | spec config: https://github.com/microsoft/azurelinux/blob/3.0/SPECS/kernel/config (same two lines not set) |
| 13 | Google COS 121 LTS (kernel 6.1.x; dump 6.1.85+) | not set | not set | published boot-config dump: https://github.com/nyrahul/linux-kernel-configs/blob/main/Container-Optimized%20OS%20from%20Google/6.1.85%2B/bootconfig.md (NO_HZ_IDLE=y, both targets not set). M125 moved to kernel 6.12 (https://docs.cloud.google.com/container-optimized-os/docs/release-notes/m125) — its config not verified here |
| 14 | Bottlerocket 1.x (kernel-kit v9.2.0; kernel-6.1 and kernel-6.12) | not set | **y** | full merged x86_64 configs, both kernels: https://github.com/bottlerocket-os/bottlerocket-kernel-kit/blob/v9.2.0/packages/kernel-6.12/config-full-bottlerocket-x86_64 and https://github.com/bottlerocket-os/bottlerocket-kernel-kit/blob/v9.2.0/packages/kernel-6.1/config-full-bottlerocket-x86_64 (CONFIG_NO_HZ_FULL=y, NO_HZ_IDLE not set, VIRT_CPU_ACCOUNTING_GEN=y, # CONFIG_IRQ_TIME_ACCOUNTING is not set). New kernel-6.18 has no published full config — unknown |
| 15 | Flatcar stable (6.12.x; coreos-kernel-6.12.111) | **y** | not set | config fragments: https://github.com/flatcar/scripts/blob/main/sdk_container/src/third_party/coreos-overlay/sys-kernel/coreos-modules/files/commonconfig-6.12 (CONFIG_IRQ_TIME_ACCOUNTING=y; NO_HZ_FULL appears in no fragment → kernel default n); empirical dump (6.1.96-flatcar): https://github.com/nyrahul/linux-kernel-configs/blob/main/Flatcar%20Container%20Linux%20by%20Kinvolk%203815.2.5%20(Oklo)/6.1.96-flatcar/bootconfig.md (NO_HZ_IDLE=y, NO_HZ_FULL not set, IRQ_TIME_ACCOUNTING=y) |
| 16 | Android GKI 6.6 — android14-6.6 **does not exist**; 6.6 GKI line = android15-6.6 (x86_64 gki_defconfig) | **y** | not set | branch check: https://android.googlesource.com/kernel/common/+/refs/heads/android14-6.6/Makefile returns gitiles NOT_FOUND (as do dated android14-6.6-* variants), while android14-6.1 serves normally → no android14-6.6 branch on kernel/common. Verified android15-6.6 defconfigs (GitHub mirror): https://github.com/aosp-mirror/kernel_common/blob/android15-6.6/arch/x86/configs/gki_defconfig and .../arch/arm64/configs/gki_defconfig (CONFIG_IRQ_TIME_ACCOUNTING=y, CONFIG_NO_HZ=y, no NO_HZ_FULL line → not set) |

## Verdict

| Category | Configurations |
|---|---|
| **Match DR-013 undercount combo (IRQ_TIME_ACCOUNTING not set AND NO_HZ_FULL=y)** — 10 rows | Ubuntu generic 24.04 LTS (6.8.0-52 anchored & 6.8.0-146 current) · Ubuntu 25.04 (6.14.0-37) · Ubuntu linux-aws 24.04 (6.8.0-1066-aws) · Ubuntu linux-azure 24.04 (6.8.0-1070-azure) · Debian 13 trixie (6.12.107+deb13) · SLES 15 SP6 (6.4, SP7 same) · Amazon Linux 2023 (6.1.141, current 6.1 line) · Bottlerocket 1.x (kernel-6.1 & kernel-6.12) |
| NO_HZ_FULL=y but IRQ accounting ON (undercount combo NOT present) | Fedora 41 (6.12.15) · Fedora 42 (6.14.11) · RHEL 9 / Rocky 9 (5.14.0-687) — all three ship CONFIG_IRQ_TIME_ACCOUNTING=y |
| NO_HZ_FULL off (not set) | Azure Linux 2.0 · Azure Linux 3.0 · Google COS 121 LTS (6.1.x) · Flatcar stable (6.12.x) · Android GKI 6.6 (android15-6.6 defconfigs) |
| Unknown (not verified — do not extrapolate) | AL2023 kernel-6.12 AMI · COS M125 (kernel 6.12) · Bottlerocket kernel-6.18 · any config not listed above |

### Notes / caveats
- The paper may state the 166x undercount for: Ubuntu (generic, AWS, Azure variants, 24.04–25.04), Debian 13, SLES 15 SP6/SP7, Amazon Linux 2023 (6.1 line), Bottlerocket 1.x (6.1/6.12 kernels). Fedora 41/42 and RHEL/Rocky 9 must NOT be cited as matching: they ship NO_HZ_FULL=y **with** IRQ_TIME_ACCOUNTING=y.
- Ubuntu turned NO_HZ_FULL on in the generic kernel around hirsute (21.04); 24.04/25.04 and the linux-aws/linux-azure derivatives inherit it with IRQ_TIME_ACCOUNTING unset.
- Ubuntu /boot/config-<kver> lives in the linux-modules-<kver>-* deb (not in linux-image*); Debian's lives in both linux-image-*-unsigned and the signed image deb (identical).
- SUSE's public GitHub kernel-source mirror exposes the SP6 codeline only as SLE15-SP6-LTSS (identical kernel/config line; SP7 branch matches too).
- android14-6.6 does not exist on android.googlesource.com/kernel/common (gitiles NOT_FOUND on Makefile, root, and dated variants; controls android14-6.1/android15-6.6 respond normally). The 6.6 GKI line is android15-6.6; both its x86_64 and arm64 gki_defconfig set IRQ_TIME_ACCOUNTING=y and do not set NO_HZ_FULL.
- Amazon Linux 2023 enabled NO_HZ_FULL at some point in the 6.1 series (6.1.19-era dump: off; 6.1.141 dump: on).
