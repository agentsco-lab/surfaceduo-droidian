# Port guide - Droidian on Surface Duo 1, step by step

Prerequisites: a Surface Duo 1 (any storage size) with an unlockable
bootloader, a Linux host with docker + adb/fastboot + python3 +
device-tree-compiler, and [docs/SAFETY.md](SAFETY.md) read twice. Going
back to stock Android, and coming from it: [STOCK-ANDROID.md](STOCK-ANDROID.md).

## 0. Backups (non-negotiable)

Unlock the bootloader (Microsoft's official instructions). RAM-boot TWRP
(`surfaceduo1-twrp.img`, do NOT flash it):

```
fastboot boot surfaceduo1-twrp.img
adb shell
  cd /dev/block/platform/soc/1d84000.ufshc/by-name
  dd if=boot_a of=/sdcard/boot_a.img
  dd if=boot_b of=/sdcard/boot_b.img
  dd if=misc   of=/sdcard/misc.img
adb pull /sdcard/boot_a.img; adb pull /sdcard/boot_b.img; adb pull /sdcard/misc.img
```

## 1. Kernel

See `kernel-packaging/README.md`. In short: clone Microsoft's OSS tree
(branch `surfaceduo/11/2022.902.48`), run `setup.sh` to install the
packaging, build in the Droidian container. The important choices are
already encoded in the config fragment:

- `CONFIG_SPI_HID=y` - the touch controller driver, built in (the
  droidian rootfs installs no modules, and MODULE_SIG blocks foreign
  ones).
- `CONFIG_MODULE_SIG_FORCE=n` - lets the *stock vendor partition's own
  modules* (`qca_cld3_wlan`, `audio_*`) load into our kernel; they are
  built from this exact tree version.
- pstore/ramoops for crash logs, `pr_info_ratelimited` patch for the
  adsprpcd ioctl flood.

Harvest `out/KERNEL_OBJ/arch/arm64/boot/Image.gz` even if the deb's
boot.img assembly step fails - the flight image is packed manually:

## 2. Boot image

```
tools/extract-stock-dtb.sh boot_b.img stock.dtb   # from YOUR backup
tools/make-boot-image.sh Image.gz <droidian-boot.img-or-initramfs> stock.dtb
```

`make-boot-image.sh` patches the halium initramfs in flight
(data=ordered instead of the 2014 data=journal workaround - without it
the phone stalls under write bursts, see docs/FREEZE-FORENSICS.md),
packs the v2 header with the right offsets/cmdline and validates the
result. The DTB **must** be the generic wildcard extracted from your
stock image (see SAFETY.md, "DTB scheme" - this was our silent-death
root cause). The ramdisk comes from the droidian kernel deb / nightly
boot image.

## 3. Rootfs

Since 0.20 the port runs on **Droidian 102**: take the current nightly,
`rootfs api30 arm64` of the phosh phone variant, from Droidian's image
releases (a file named like
`droidian-OFFICIAL-phosh-phone-rootfs-api30-arm64-next_<date>.zip`), and
check its sha256. 0.20 is built and tested on 102. It still carries 0.18's
phoc, phosh and keyboard for Droidian 101, but was not tested there: on 101,
0.18.0 is the release to use.

**Take only `data/rootfs.img` out of the zip. Do not flash the zip.** Its
installer script writes boot, dtbo and vbmeta with `dd` whenever it finds
them, and this phone gets its boot image from step 2, RAM-booted - see
SAFETY.md.

The image comes small; give apt room before it goes on the phone. On the
computer:

```
unzip -p droidian-*-rootfs-api30-arm64-*.zip data/rootfs.img > rootfs.img
e2fsck -fy rootfs.img && resize2fs rootfs.img 8G
```

(or `resize2fs` in TWRP, if yours has it - not every recovery for this
phone does). After the shell setup in step 6 the image grows by itself to
fill userdata on the next boot.

From TWRP:

```
mke2fs -t ext4 /dev/block/sda6           # userdata, wipes Android!
mount /dev/block/sda6 /data
adb push rootfs.img /data/rootfs.img     # verify sha256 after push
```

The halium initramfs finds `/data/rootfs.img` by the `datapart=`
cmdline argument and loop-mounts it as /.

If the screens stay black after the Debian logo, check `systemctl status
lxc@android` first: 102 waits for the Android container differently from
101, and packages older than 0.20 time out on it on this phone.

## 4. Adaptation

Put the package (from the release, or built with
`adaptation/package/build.sh`) in `out/` - only one version there, the
script takes the newest - and, with the phone still in TWRP, run
`adaptation/ssh/inject-ssh-twrp.sh`. It checks and loop-mounts the image,
puts your ssh key in (`~/.ssh/id_ed25519.pub`, or `SFDUO_PUBKEY`) and a
first-boot unit that installs the package. The 102 image ships sshd, so no
openssh bundle is needed; if `out/ssh-debs/` holds one from 101 days, it is
left out.

The package brings the rest: USB RNDIS access, the touch udev rule,
bluetooth fixes (start timeout + board-address), vendor-daemon taming with
early ADSP boot (without it the system I/O-deadlocks ~2 minutes after
boot), the suspend hooks, audio, modem, wlan and the two-panel shell.

## 5. First boot

```
fastboot getvar current-slot   # see SAFETY.md - slots flip on their own
fastboot set_active a
fastboot erase misc && fastboot flash misc misc-brake.img   # tools/make-misc-brake.sh
tools/flash-safely.sh ram-boot boot-duo1-droidian.img
```

The first boot installs the package and then **reboots once by itself,
into fastboot**: the package's early-boot parts (the ADSP ordering, the
audio modules, the slot guard) only work from the start of a boot, and a
plain reboot would start the kernel on the slot - stock Android's, on a
phone new to the port. When the phone is back in fastboot (a minute or two),
RAM-boot the same image again:

```
fastboot getvar current-slot
tools/flash-safely.sh ram-boot boot-duo1-droidian.img
```

~60-90 s later both panels show the Phosh lock screen (PIN 1234) and a new
RNDIS interface appears on the host.

If instead the screens go black right after the Debian logo and the
power key looks dead, the system underneath is almost certainly fine:
plymouth has taken DRM master away from the vendor composer. See the
plymouth trap in the top-level README. The short cure is `systemctl
mask plymouth-start.service`, and the adaptation's
`sfduo-composer-watchdog` covers the cases it can detect. Get in over
ssh first, the network comes up regardless of what the panels do.

Tell NetworkManager to leave the RNDIS interface alone, then ssh in:

```
nmcli device set <iface> managed no
ip addr replace 172.16.42.2/24 dev <iface>; ip link set <iface> up
ssh root@172.16.42.1
```

If your host routes 172.16.42.0/24 elsewhere you will "connect" to
something that is not the phone - a sub-2 ms ping RTT is the tell that
you are actually on the USB link.

## 6. The shell, and the rest of the setup

Connect to Wi-Fi (the shade on the left panel, or `nmcli device wifi
connect <ssid> password <password>` over ssh), then:

```
sudo sfduo-shell-setup
sudo reboot
```

The package was installed offline, before the phone had a network, so it
only recommends what it needs from Debian. This installs it: the GTK and
layer-shell libraries of the dock, the clock and the pen's screen,
`python3-evdev` for the pen, `e2fsprogs` for growing the root filesystem.
It then lets the patched phosh tile windows to a panel. The reboot starts
the session with all of it. After it: the
dock in two halves, the pen, and the root filesystem grown to the size of
userdata.

Then, in Settings:

- **Date & Time**: the image starts on UTC. The automatic time zone follows
  the location; if the clock is off, pick the zone by hand.
- **Fingerprint**: enrol a finger; the lock screen unlocks by it whenever
  the locked screen is lit.

See the status matrix in the top-level README for what works. Touch works
end-to-end (kernel spi-hid → vendor touchpen HAL → uinput → udev rule).

## Debug channels, in order of preference

1. ssh (adaptation package).
2. Persistent journald (`Storage=persistent` drop-in must sort AFTER
   droidian's `10-journald-volatile.conf` - name it `99-*`).
3. TWRP + loop-mount of rootfs.img - post-mortem file inspection.
4. pstore/ramoops after a crash (needs the ramoops DT node variant).
5. The initramfs panic shell, for when the boot dies before any of the
   above exist. See below.

## When the boot dies before the rootfs

Symptom: no Debian logo at all, no ssh, the phone just sits there.
Plymouth lives in the rootfs, not in the initramfs, so if even the logo
is missing the rootfs was never mounted.

The halium initramfs does not die quietly in that case. It brings up a
USB RNDIS gadget, runs a DHCP server on it (`192.168.2.20-90`) and
starts telnetd with a root shell. Note the address is **not** the
172.16.42.1 the adaptation uses later:

```
telnet 192.168.2.15
```

Inside, two commands explain almost everything:

```
ls /tmpmnt          # userdata as the initramfs sees it
dmesg | tail -40    # the initramfs logs each decision it makes
```

`/tmpmnt` is the mounted userdata. `identify_file_layout()` looks there
for `rootfs.img`, then `ubuntu.img`, then a `halium-rootfs` directory,
and if none of them exist it falls through to assuming the rootfs sits
on the system partition, which on this device it does not. That
fall-through is silent, and it is the usual cause of a boot with no
logo: the image is missing, misnamed, or landed somewhere else.
