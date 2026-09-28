# p1-T5: the distribution-config survey for C-014 (the 166x undercount)
# (DR-013 addendum T5; superseded version -- the full 20-row survey is
# analysis/t5-distro-survey.md; this note records the corrected summary
# and the two corrections to THIS file's first pass, 2026-09-28)

Question (the memo): which real systems ship CONFIG_IRQ_TIME_ACCOUNTING=n
together with NO_HZ_FULL=y -- the configuration under which C-014's
166x /proc/stat busy-time undercount occurs? The paper states the 166x
only for the configurations measured, and names which distros ship
them; if none did, C-014 would be a custom-kernel caveat.

## Corrected summary (supersedes this file's first 6-row pass)

The full survey (analysis/t5-distro-survey.md, 20 rows, every value
read from a named config source with per-row references, 2026-09-27)
flags the undercount combination on **11 of 20 rows**:

- Ship it: Ubuntu 26.04 generic, Ubuntu 24.04 generic + lowlatency +
  aws + azure + gcp (the cloud-flavor gap in this file's first pass
  is now closed -- launchpad source diffs, not the 403'd cgit),
  Debian 13 trixie, SLES 15 SP6-LTSS/SP7, SLES 16.0/16.1,
  Amazon Linux 2023 (6.1 series; NO_HZ_FULL was turned on
  mid-6.1-series), Bottlerocket (6.1/6.12/6.18).
- Do not: Ubuntu 20.04/22.04 (both options off), Fedora 44 and
  RHEL 9/10 (both y), Azure Linux 3.0 and COS (both off), Flatcar
  and Android GKI (IRQ_TIME=y, NO_HZ_FULL off).
- Documented UNKNOWNs: AL2023's new 6.18 default-kernel config,
  COS's current 129-LTS config (attempts recorded in the survey).

## Corrections to this file's first pass (kept for the record)

1. RHEL/Rocky 10 was listed as matching. WRONG: my fetch read
   redhat/configs/rhel/generic/CONFIG_IRQ_TIME_ACCOUNTING
   (the shared fragment, "not set"); the x86-specific fragment that
   applies to the shipped x86_64 kernel
   (redhat/configs/rhel/generic/x86/CONFIG_IRQ_TIME_ACCOUNTING)
   reads CONFIG_IRQ_TIME_ACCOUNTING=y (re-verified 2026-09-28 via
   the gitlab API). RHEL 9/10 = y/y, does NOT match.
2. Amazon Linux 2023 was listed as not matching ("no NO_HZ_FULL").
   WRONG source: I read the upstream in-tree
   arch/x86/configs/x86_64_defconfig; what ships comes from AL2023's
   SRPM config. A recorded /boot/config of the shipping
   6.1.141-165.249.amzn2023.x86_64 shows NO_HZ_FULL=y with
   IRQ_TIME_ACCOUNTING unset (re-verified 2026-09-28, nyrahul dump).
   AL2023's 6.1 series MATCHES.

## Reading

- C-014 is emphatically NOT a custom-kernel-only caveat: mainstream
  shipping kernels across desktop, server, and cloud images run the
  undercount configuration (11 of 20 surveyed rows, including the
  Ubuntu cloud flavors).
- Section 4 of the paper names the matching set and the
  counter-examples, per the memo's rule. The claim ledger records
  this as C-024 (superseded wording, 2026-09-28).

## Second independent survey (cross-check, 2026-09-28)

A second survey ran in parallel (notes/p1-T5-distro-config.md,
16 rows) and agrees with this summary on every overlapping row. It
adds two rows, both now verified by direct read on this side:

- Ubuntu 25.04 (6.14.0-37-generic): **COMBO** -- extracted the
  shipped linux-modules deb and read /boot/config (NO_HZ_FULL=y,
  IRQ_TIME_ACCOUNTING not set). Verified 2026-09-28.
- Azure Linux 2.0 (5.15.x): both not set (does not match) --
  SPECS/kernel/config raw read. Verified 2026-09-28.

It also upgrades several rows to shipped-artifact sources (stronger
than git-branch reads): RHEL 9 / Rocky 9.8 (kernel-core rpm),
Fedora 41/42 (kernel-core rpms), Debian 13 trixie (shipped deb).
Its "Bottlerocket kernel-6.18 unknown" is ref-scoped (tag v9.2.0
predates the config; the develop-branch config was read in the
first survey). Its GKI note: android14-6.6 does not exist; the 6.6
GKI line is android15-6.6 (IRQ_TIME=y, NO_HZ_FULL absent).

Updated totals: **22 rows surveyed, 12 ship the undercount combo**
(adding Ubuntu 25.04).

## Still unverified (facts only)

- The two UNKNOWNs above (AL2023 kernel-6.18, COS 129 LTS).
- Our H100 nodes' kernel: needs the node pointer (the PROGRAM's
  llm-d gateway hosts); not in this repo.