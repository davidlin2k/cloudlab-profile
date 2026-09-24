#!/bin/bash
# p1-kernel.sh -- install Ubuntu mainline v6.4 (pre-6.5 ksoftirqd
# deferral kernel) on rx and arm it as the NEXT boot default. Run as root
# AFTER the running batches finish and BEFORE rebooting. Verify with
# p1-kernel.sh status; the P1 batch runs only under the 6.4 uname.
set -u
KDEB=/root/p1/kdeb
VER=6.4.0-060400-generic
OLD=6.17.8-061708-generic

case "${1:-install}" in
  install)
    [ -f "$KDEB/DONE" ] || { echo "kdeb not downloaded"; exit 1; }
    dpkg -i "$KDEB"/linux-headers-6.4.0-060400_*.deb \
            "$KDEB"/linux-headers-6.4.0-060400-generic_*.deb \
            "$KDEB"/linux-modules-6.4.0-060400-generic_*.deb \
            "$KDEB"/linux-image-unsigned-6.4.0-060400-generic_*.deb || true
    # arm grub one-shot style: saved default + explicit entry titles
    grep -q '^GRUB_DEFAULT=saved' /etc/default/grub || \
      sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
    update-grub
    echo "-- grub entries:"
    grep -oE '^[^ ]*menuentry .*' /boot/grub/grub.cfg | head -8
    ;;
  arm-p1)
    grub-set-default "Advanced options for Ubuntu>Ubuntu, with Linux $VER"
    update-grub
    echo "NEXT BOOT: $VER (reboot now)"
    ;;
  arm-restore)
    grub-set-default "Advanced options for Ubuntu>Ubuntu, with Linux $OLD"
    update-grub
    echo "NEXT BOOT: $OLD (reboot now)"
    ;;
  status)
    echo "running: $(uname -r)"
    echo "default: $(grub-editenv list 2>/dev/null | grep saved_entry || echo '<boot order>')"
    ;;
esac
