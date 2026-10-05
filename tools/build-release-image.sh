#!/bin/bash
# build-release-image.sh: the release image (item-tracker #153) - what
# item/grid puts on userdata for a newcomer, or for Erase and install:
# Droidian 102 (a pinned nightly), the port's adaptation and its sensorfw,
# the shell's Python and GTK bits, item as the shell. Everything the port's
# install did by hand on the phone (PORT-GUIDE.md: the TWRP inject, the
# first-boot unit and its extra reboot, sfduo-shell-setup online,
# install-phone.sh) is done here, in a chroot, so the first start is a
# plain start. Shrunk to its contents; the adaptation grows it to fill
# userdata on the first boot.
#
#   adaptation/package/build.sh <version>          (as yourself)
#   item: compositor/tools/package-deb.sh          (as yourself)
#   sudo tools/build-release-image.sh [ADAPTATION.deb] [ITEM.deb]
#
# Out: out/release/<name>/rootfs.img.zst, its sha256s and manifest.json.
# Not in the image: anyone's ssh key (item/grid puts the owner's in when it
# installs), the host's ssh keys and machine-id (made on the first boot).
# The PIN stays Droidian's 1234 until item's first start sets one (#148);
# item/grid asks for a new one after installing.
set -euo pipefail

die() { echo "build-release-image: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root (loop mount, chroot): sudo $0"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OWNER="${SUDO_USER:-root}"
OWNER_HOME="$(getent passwd "$OWNER" | cut -d: -f6)"

# The base: Droidian 102's phosh phone rootfs, api30, arm64 - pinned.
BASE_ZIP="${BASE_ZIP:-$ROOT/out/102/fresh-0929/droidian-OFFICIAL-phosh-phone-rootfs-api30-arm64-next_20260929.zip}"
BASE_SHA="${BASE_SHA:-473255080acb504338b789cbd9bf1361a025da14654e16a6335237e41f8a822c}"
ADAPT="${1:-$(ls "$ROOT"/out/adaptation-droidian-surfaceduo_*_arm64.deb 2>/dev/null | sort -V | tail -1)}"
ITEM="${2:-$(ls -t "$OWNER_HOME"/Desktop/projects/item/item/compositor/target/deb/item_*_arm64.deb 2>/dev/null | head -1)}"
[ -f "$BASE_ZIP" ] || die "no base: $BASE_ZIP"
[ -f "$ADAPT" ] || die "no adaptation package (adaptation/package/build.sh)"
[ -f "$ITEM" ] || die "no item package (compositor/tools/package-deb.sh in item's tree)"
grep -q '^flags: .*F' /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null || die "arm64 binaries cannot run here: qemu-user-static with binfmt (flag F) is needed"
for t in unzip e2fsck resize2fs zstd losetup; do command -v $t >/dev/null || die "$t is missing"; done

ADAPT_VER=$(dpkg-deb -f "$ADAPT" Version)
ITEM_VER=$(dpkg-deb -f "$ITEM" Version)
NAME="item-duo1-$(date -u +%Y%m%d)-port${ADAPT_VER}"
OUT="$ROOT/out/release/$NAME"
WORK="$ROOT/out/release/work"
IMG="$WORK/rootfs.img"
MNT="$WORK/mnt"
echo "== $NAME: Droidian $(basename "$BASE_ZIP"), adaptation $ADAPT_VER, item $ITEM_VER"

echo "== the base, checked"
echo "$BASE_SHA  $BASE_ZIP" | sha256sum -c --quiet || die "the base zip is not the pinned one"
rm -rf "$WORK"; mkdir -p "$WORK" "$MNT" "$OUT"
unzip -p "$BASE_ZIP" data/rootfs.img > "$IMG"
# Room for what goes in; shrunk again at the end.
e2fsck -fy "$IMG" >/dev/null || [ $? -le 1 ]
truncate -s 12G "$IMG"
resize2fs "$IMG" >/dev/null

LOOP=""
cleanup() {
    set +e
    for m in dev/pts dev proc sys run; do mountpoint -q "$MNT/$m" && umount -l "$MNT/$m"; done
    mountpoint -q "$MNT" && umount "$MNT"
    [ -n "$LOOP" ] && losetup -d "$LOOP"
}
trap cleanup EXIT
LOOP=$(losetup --show -f "$IMG")
mount "$LOOP" "$MNT"
mount -t proc proc "$MNT/proc"
mount -t sysfs sys "$MNT/sys"
mount --bind /dev "$MNT/dev"
mount --bind /dev/pts "$MNT/dev/pts"
mount -t tmpfs tmpfs "$MNT/run"
# The network for apt: the image's resolv.conf points into /run.
RESOLV_WAS=$(readlink "$MNT/etc/resolv.conf" || true)
rm -f "$MNT/etc/resolv.conf"; cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"
# No service starts inside the chroot.
printf '#!/bin/sh\nexit 101\n' > "$MNT/usr/sbin/policy-rc.d"; chmod 755 "$MNT/usr/sbin/policy-rc.d"
ch() { chroot "$MNT" /usr/bin/env -i HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"; }

echo "== what sfduo-shell-setup brought online"
ch apt-get update -q
ch apt-get install -y -q --no-install-recommends python3-gi gir1.2-gtk-3.0 dconf-cli python3-evdev e2fsprogs

echo "== the adaptation ($ADAPT_VER) and item ($ITEM_VER)"
cp "$ADAPT" "$ITEM" "$MNT/var/tmp/"
ch apt-get install -y -q --no-install-recommends "/var/tmp/$(basename "$ADAPT")" "/var/tmp/$(basename "$ITEM")"
echo "== sensorfw with the hinge and posture sensors"
ch /usr/local/sbin/sfduo-sensorfw-install || true
ch dpkg-query -W -f='${Version}\n' sensorfw-qt6 | grep -q itemae || die "sensorfw with the hinge sensor did not go in"
ch dconf update || true

echo "== the port's services on, as on a phone it was installed on"
for u in sfduo-wlan.service sfduo-audio.service sfduo-tame-vendor.service sfduo-lid.service sfduo-wakeup.service \
         sfduo-composer-watchdog.service sfduo-slot-guard.service sfduo-grow-rootfs.service sfduo-usb.service; do
    ch systemctl is-enabled -q "$u" || die "$u is not enabled in the image: the adaptation's postinst left it off"
done

echo "== item as the shell (item-switch item, without starting anything)"
ch systemctl disable phosh.service
ch systemctl enable item.service item-face.service

echo "== what the old first-boot path left for nothing"
# The first-boot unit and its reboot are not needed: all of it is in.
rm -f "$MNT/etc/systemd/system/multi-user.target.wants/sfduo-ssh-firstboot.service" "$MNT/etc/systemd/system/sfduo-ssh-firstboot.service"
touch "$MNT/var/lib/sfduo-ssh-installed"

echo "== made per phone on its first boot, not shipped"
rm -f "$MNT"/etc/ssh/ssh_host_*
: > "$MNT/etc/machine-id"
rm -f "$MNT/var/lib/dbus/machine-id"
mkdir -p "$MNT/etc/systemd/system/ssh.service.d"
cat > "$MNT/etc/systemd/system/ssh.service.d/10-host-keys.conf" <<'CONF'
# The release image ships no host keys: each phone makes its own.
[Service]
ExecStartPre=/usr/bin/ssh-keygen -A
CONF
mkdir -p "$MNT/etc/ssh/sshd_config.d"
printf 'PermitRootLogin prohibit-password\n' > "$MNT/etc/ssh/sshd_config.d/10-sfduo.conf"

echo "== cleaned"
ch apt-get clean
rm -rf "$MNT"/var/lib/apt/lists/* "$MNT"/var/tmp/*.deb "$MNT"/var/log/journal/* "$MNT"/root/.bash_history "$MNT"/tmp/*
find "$MNT/var/log" -type f \( -name '*.gz' -o -name '*.[0-9]' \) -delete
find "$MNT/var/log" -type f -exec truncate -s 0 {} +
rm -f "$MNT/usr/sbin/policy-rc.d"
rm -f "$MNT/etc/resolv.conf"; [ -n "$RESOLV_WAS" ] && ln -s "$RESOLV_WAS" "$MNT/etc/resolv.conf"

PKGS=$(ch dpkg-query -W -f='${Package} ${Version}\n' | sort)
cleanup; trap - EXIT; LOOP=""

echo "== shrunk to its contents"
e2fsck -fy "$IMG" >/dev/null || [ $? -le 1 ]
resize2fs -M "$IMG" >/dev/null
e2fsck -fy "$IMG" >/dev/null || [ $? -le 1 ]
RAW_SIZE=$(stat -c %s "$IMG")
RAW_SHA=$(sha256sum "$IMG" | cut -d' ' -f1)

echo "== compressed"
zstd -q -19 -T0 --long=27 -f "$IMG" -o "$OUT/rootfs.img.zst"
ZST_SIZE=$(stat -c %s "$OUT/rootfs.img.zst")
ZST_SHA=$(sha256sum "$OUT/rootfs.img.zst" | cut -d' ' -f1)
echo "$PKGS" > "$OUT/packages.txt"
cat > "$OUT/manifest.json" <<JSON
{
  "name": "$NAME",
  "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "base": {"file": "$(basename "$BASE_ZIP")", "sha256": "$BASE_SHA"},
  "adaptation": "$ADAPT_VER",
  "item": "$ITEM_VER",
  "image": {"file": "rootfs.img", "size": $RAW_SIZE, "sha256": "$RAW_SHA"},
  "compressed": {"file": "rootfs.img.zst", "size": $ZST_SIZE, "sha256": "$ZST_SHA", "zstd_window_log": 27},
  "grows_on_first_boot": true,
  "pin": "1234 until item's first start sets one"
}
JSON
rm -rf "$WORK"
chown -R "$OWNER": "$ROOT/out/release"
echo "== done: $OUT"
echo "   rootfs.img $((RAW_SIZE >> 20)) MB, rootfs.img.zst $((ZST_SIZE >> 20)) MB"
