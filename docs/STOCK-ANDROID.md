# Stock Android and back

How a Surface Duo 1 running the port goes back to its stock Android, and how
a Duo on stock Android gets Droidian 102 with the port. Both directions were
done on a Duo 1 in September 2026, the port's data kept on the computer and
brought back byte for byte.

Read [SAFETY.md](SAFETY.md) first. The Duo 1 has no public EDL loader: a
bootloader that stops accepting images cannot be revived by software. So
nothing here flashes a partition through fastboot. Images are RAM-booted
(`fastboot boot`), partitions are written with `dd` from a booted system where
they must be written at all, and the one step that destroys data waits until
its backups are checked.

What makes it possible without Microsoft's full image: the stock system and
vendor stay untouched in the `super` partition while the port runs. Droidian's
Android container runs its own Halium system image (a file on userdata) and
only mounts the stock vendor read-only. The stock Android that was on the
phone is still there; it needs only its own kernel and an empty userdata.

## What you need

- The bootloader unlocked (it is, if the port runs).
- A recovery image to RAM-boot, with adb as root: TWRP for the Duo, or a
  Halium/UBports-style recovery on the Duo's 4.14 kernel.
- The **stock kernel that matches the stock system in super**, from your own
  backup (PORT-GUIDE.md step 0 takes it before the port goes on). See
  "Which stock kernel" below.
- About 12 GB free on the computer: a root filesystem image compresses to
  about 1.8 GB with zstd; keep two if you have 101 and 102.
- A USB cable, and the phone at 50 % or more.
- Optional insurance: Microsoft's image for the phone, from
  https://support.microsoft.com/surface-recovery-image with the serial number.
  For a Duo 1 this is a full A/B OTA (`payload.bin` inside). Not needed for
  this path.

## Which stock kernel

The kernel has to belong to the same build as the system and vendor it will
boot. Read what super holds, from the running port (read-only mounts):

```
for p in system_a vendor_a system_b vendor_b; do
  mount -o ro /dev/mapper/dynpart-$p /mnt 2>/dev/null &&
    { grep -h "build.fingerprint=\|build.date=" /mnt/build.prop /mnt/system/build.prop 2>/dev/null; umount /mnt; } ||
    echo "$p: empty"
done
```

Then compare with the build dates of the kernels in your backup
(`strings boot_a.img | grep "Linux version"`) and take the one built with
the system in super - usually minutes apart on the same day. Its slot is the
slot to boot it on. A kernel from another build (an OTA's `boot_b`, say, with
nothing matching in super) is not an option.

Android's fstab marks `userdata` and `metadata` formattable, with file-based
encryption keyed from `/metadata`: given both empty, stock Android formats
them itself on its first boot. That is what `fastboot -w` would do, without
asking this bootloader to write anything.

## A. From the port to stock Android

1. **Back up, from the running port**, over the USB network (172.16.42.1;
   about 20 MB/s, Wi-Fi is several times slower):
   ```
   for p in boot_a boot_b vbmeta_a vbmeta_b dtbo_a dtbo_b misc; do
     ssh root@172.16.42.1 "cat /dev/disk/by-partlabel/$p" > $p.img; done
   ssh root@172.16.42.1 'tar -C /userdata -cf - android-data' | zstd -3 -o android-data.tar.zst
   ```
   Any other image on userdata (a kept `rootfs-101.img`) goes the same way as
   the partitions, through `zstd -3`. Take the sha256 of each on the phone
   and compare it on the computer, also after decompressing.

2. **Take the live root filesystem, frozen.** `rootfs.img` is in use; copy
   it with the filesystem frozen, consistent as if the system were stopped.
   As a script started with `setsid -f sh snap.sh` from `/root` (not `/run`,
   which is noexec):
   ```
   sync
   fsfreeze -f / && { timeout 180 cp --sparse=always /userdata/rootfs.img /userdata/rootfs-snap.img
                      fsfreeze -u /; }
   sha256sum /userdata/rootfs-snap.img
   ```
   The screens stall while it runs (under a minute); the `timeout`
   guarantees the thaw. Mount the copy read-only (`mount -o ro,loop,noload`)
   to see it is whole, pull it as in step 1 and compare the checksums.

3. **Into fastboot**, the way Android asks the kernel (SAFETY.md):
   ```
   python3 -c 'import ctypes; l=ctypes.CDLL("libc.so.6"); l.sync();
   l.syscall(142, 0xfee1dead, 672274793, 0xA1B2C3D4, b"bootloader")'
   fastboot getvar current-slot        # must be the slot of the stock kernel
   ```
   Make sure nothing on the computer is still waiting to run `adb` or
   `fastboot` from earlier: a forgotten background job acts the moment the
   phone appears, before you have checked the slot.

4. **Test the way back before erasing.** RAM-boot the recovery and push a
   large file in parts (below, B.3). If adb holds up, the way back works.

5. **Clear userdata and metadata - all of them.** Only after every checksum
   matches; from here the port's data is only on the computer. Zeroing just
   the start is not enough: ext4 keeps backup superblocks across the
   partition, stock's first-boot check can bring the old filesystem back,
   and Android then poisons misc. From the RAM-booted recovery:
   ```
   dd if=/dev/zero of=/dev/block/sda3 bs=1M     # metadata
   dd if=/dev/zero of=/dev/block/sda6 bs=4M     # userdata, ~7 minutes
   ```
   Check the names first:
   `ls -l /dev/block/platform/soc/1d84000.ufshc/by-name/ | grep -w "metadata\|userdata"`.

6. **Park the brake, then RAM-boot stock:**
   ```
   adb reboot bootloader
   fastboot getvar current-slot
   fastboot erase misc && fastboot flash misc misc-brake.img   # tools/make-misc-brake.sh
   fastboot boot boot_a-stock.img
   ```
   The brake makes an unattended reset park in fastboot instead of starting
   the port's kernel, still on the slot, on Android's userdata.

7. **First boot of stock.** Android formats userdata and metadata itself and
   starts its setup. For adb: Settings - About phone - tap Build number seven
   times - System - Developer options - USB debugging, and allow the
   computer. adb may show only the file-transfer device until debugging is
   switched off and on again.

Stock Android runs RAM-booted: the port's kernel is still on the slot, and a
plain restart goes back to fastboot (the brake) or to that kernel, not to
Android. Every stock boot is `fastboot boot` again.

## B. From stock Android to the port on Droidian 102

The way back from A, and the path for a Duo that is on stock Android. A new
install follows [PORT-GUIDE.md](PORT-GUIDE.md) from step 3; the steps here
also restore a backup.

1. **Into fastboot** (`adb reboot bootloader`), check the slot.

2. **RAM-boot the recovery**, and make userdata a plain ext4 again - this
   wipes Android's data. Wait for the recovery to settle (about a minute, its
   menu appears; press nothing), then:
   ```
   fastboot boot recovery.img
   adb shell 'mke2fs -F -t ext4 -L userdata /dev/block/sda6 && mkdir -p /tmp/ud && mount /dev/block/sda6 /tmp/ud'
   ```

3. **Put the root filesystem on it.** A new install: `rootfs.img` from the
   nightly, grown and injected as in PORT-GUIDE.md steps 3-4. Restoring a
   backup: the images go decompressed on the fly, in 512 MB parts, each
   part's sha256 compared on the phone and a part that arrives wrong sent
   again; then the whole image's sha256 against the one taken in A:
   ```
   # part i of rootfs.img (bs=1M, 512 blocks a part)
   zstd -dc rootfs.img.zst | dd bs=1M skip=$((i*512)) count=512 iflag=fullblock |
     adb exec-in "dd of=/tmp/ud/rootfs.img bs=1M seek=$((i*512)) conv=notrunc"
   ```
   In a script, `adb` inside a `while read` loop swallows the loop's input:
   read the list from another descriptor and give `adb` `</dev/null`. Before
   unmounting, make sure no `dd` from a timed-out part still holds the image
   open (`ls -l /proc/*/fd | grep rootfs`).
   The container data comes back with its owners:
   `zstd -dc android-data.tar.zst | adb exec-in 'tar -C /tmp/ud -xpf -'`.

4. **Clear misc** - a stock boot that failed may have left
   `--prompt_and_wipe_data` there:
   `dd if=/dev/zero of=/dev/block/platform/soc/1d84000.ufshc/by-name/misc bs=2048 count=1`.

5. **Boot the port.** Unmount userdata. Going back, the port's kernel is
   still on the slot: `adb reboot` starts it, about 90 s to the lock screen.
   A new install RAM-boots the port's boot image (`tools/flash-safely.sh
   ram-boot`) and writes it with `dd` from the running port only once it has
   proven itself (SAFETY.md).

6. **Leave the port's kernel on both slots.** Stock Android on the other
   slot is a trap: if the active slot drifts (it does, SAFETY.md), stock
   boots on the port's userdata and poisons misc.

## C. Back to stock Android for good (item/grid, "stock › android")

Done on this Duo on 2026-10-06, about 8 minutes (item/grid's
`android::go_clean`). Unlike A, Android does not run RAM-booted: its own
boot is on the slot again, and a plain restart starts it.

What it read first (`itemgrid android-plan`, nothing written): super held
Android 2022.902.32 on slot a only - slot b's `system_b` and `vendor_b`
carry no filesystem (an OTA to 902.48 begun there and never finished), so
nothing is written to b. Microsoft's 902.48 package on the computer did not
belong to that build (its kernel a month newer); the stock kernel came from
the backup taken before the port (`out/backups/device-2026-09-18/
boot_a-stock-backup.img`, built 10 Jul 2023 like the vendor in super).
The port changes only boot and vbmeta (`vbmeta-disabled.img`); dtbo it never
touches.

1. TWRP RAM-booted (no full backup taken first: the owner's choice).
2. metadata and userdata zeroed whole and read back (all zeros).
3. Into slot a with dd from TWRP, each sent, checked, written and read back:
   `boot_a` <- the stock kernel, `vbmeta_a` <- the stock vbmeta (AVB flags 0).
4. misc cleared; `adb reboot`: Android's setup came up by itself.

The bootloader stays unlocked. To bring item back: item/grid's "install
item" on the phone in stock Android (USB debugging on) - or B, from a full
backup.
