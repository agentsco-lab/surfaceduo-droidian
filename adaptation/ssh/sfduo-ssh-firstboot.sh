#!/bin/sh
# One-shot: install openssh-server from the offline bundle injected by
# inject-ssh-twrp.sh into /var/cache/sfduo-ssh, then start it.
# Verified 2026-07-11 in a qemu chroot of the exact rootfs (api30 101.20251130):
# dpkg -i of the 11 debs exits 0 and enables ssh.service itself.
# The bundle may also carry adaptation-droidian-surfaceduo - installed in
# the same pass (its postinst migrates the hand-injected access files).
set -e

# The bundle is optional: recent rootfs images ship sshd themselves and
# then this directory holds only the adaptation deb, or nothing at all.
# A package the image already has is left as it is: Droidian 102 ships
# openssh 1:10.4, and the 101-era bundle's 1:10.0 installed over it
# downgraded half its dependencies and left them unconfigured (2026-09-27,
# clean-install test) - apt broken, and this script dead before the reboot
# below. The adaptation goes in on its own, and must.
cd /var/cache/sfduo-ssh 2>/dev/null && {
    extra=""
    for d in *.deb; do
        [ -f "$d" ] || continue
        pkg=$(dpkg-deb -f "$d" Package)
        [ "$pkg" = adaptation-droidian-surfaceduo ] && continue
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' && continue
        extra="$extra $d"
    done
    if [ -n "$extra" ]; then
        dpkg -i --refuse-downgrade $extra || dpkg --configure -a || true
    fi
    for d in adaptation-droidian-surfaceduo_*.deb; do
        if [ -f "$d" ]; then
            dpkg -i "$d"
        fi
    done
    true
}

systemctl daemon-reload
# The 101 image ships no sshd, and without the offline bundle there is none
# to enable. Failing here (set -e) skipped the flag below, and the whole
# bundle was installed again on every boot.
if [ -x /usr/sbin/sshd ]; then
    systemctl enable --now ssh.service || true
fi

touch /var/lib/sfduo-ssh-installed
sync

# One reboot, once. The adaptation arrives too late in this boot to do its
# job: the ADSP ordering, the audio modules' early autoload and the slot
# guard all belong to the start of a boot, and a system left running
# without them has no sound and, measured, can freeze within minutes. The
# flag above is written first, so this cannot loop.
#
# The reboot goes to fastboot, not to the system. This boot is a RAM-boot
# (PORT-GUIDE.md), and a plain reboot starts whatever kernel the slot holds:
# on a phone new to the port that is stock Android's, which then boots on
# the port's userdata and poisons misc (SAFETY.md). The misc brake does not
# help - the RAM-boot has consumed it. From fastboot the port's image is
# RAM-booted a second time, by hand.
if dpkg-query -W -f='${Status}' adaptation-droidian-surfaceduo 2>/dev/null \
        | grep -q 'install ok installed'; then
    echo "sfduo: adaptation installed - rebooting once, into fastboot" >&2
    systemctl --no-block --reboot-argument=bootloader reboot
fi
