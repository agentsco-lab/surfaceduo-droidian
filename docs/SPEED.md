# Speed: the port against stock Android

The same measurements on the port and on stock Android, taken 2026-09-26/27:
the Surface Duo 1 on its stock Android 12L (2022.902.32), the same Duo 1 on
the port - 0.18.0 on Droidian 101 and 0.20.0 (release candidate 2, the
binaries 0.20.0 ships) on Droidian 102 - and, for the newer phone, a Surface
Duo 2 on its stock Android 12L. 0.20.1's column was taken 2026-09-27/28 on
the same Duo 1: its launch boost as an A/B on 0.20.0 (the boost alone
changed, 10 launches each, the same afternoon), its boot and its closed-phone
draw on the phone as 0.20.1 ships them. How each number is taken, and under what
conditions, is in [bench/README.md](../bench/README.md); `bench/sfduo-bench`
takes them.

In short: book posture, rotation 0, screen on and unlocked, on USB power,
charge between 100 and 60 %, the same backlight level. Median of 10
repetitions, 5 for the motions. The first repetition after a boot is kept.

## Opening an app

From the request to the app's first frame, ms. On Android that is
`am start -W`'s TotalTime (the app has drawn its first frame); on the port,
the dock's launch to the compositor putting the window on the panel - the
stricter of the two, by up to a frame. Apps are started from nothing (window
closed, process gone), except those marked running. Where the two systems
have different apps, the app is named.

| Launch, ms | Duo 1, Android | Duo 2, Android | Duo 1, 0.20.1 on 102 | Duo 1, 0.20 on 102 | Duo 1, 0.18 on 101 |
|---|---|---|---|---|---|
| Settings | 368 | 398 | 704 | 794 | 1166 |
| Calculator | 340 | 404 | 573 | 687 | 1045 |
| Contacts | 413 | 260 | 561 | 649 | 1022 |
| Camera | 308 | - | 832 | 935 | 1332 |
| Weather | - | - | 592 | 694 | 1094 |
| Browser | 507 (Edge) | 1132 (Edge) | 1202 (GNOME Web) | 1289 (GNOME Web) | 2339 (Firefox) |
| Calendar | 584 (Outlook) | 636 (Outlook) | 1572 | 1747 | 2038 |
| Clock, running | 92 | 74 | 59 | 59 | 135 |
| Phone, running | 92 | 69 | 59 | 59 | 303 |
| Messages, running | 121 | 86 | 133 | 133 | 242 |

On 102 the port opens apps about a third faster than on 101 (Droidian 102's
libraries, the launch boost, glycin without its sandbox - see the 0.20.0
notes). 0.20.1 takes off another 7-21 %: for the 1.5 s after a tap its launch
boost does what Android's perf HAL does (hint 0x1081, type 1) - every
cluster's frequency floor at its top, the CPU-LLCC and LLCC-DDR bandwidth and
L3 latency floors at their maximum, /dev/cpu_dma_latency at 1 us - where 0.20
only raised sched_boost. Held 2 s, as Android does, it gave the same within 2 %.
Stock Android still opens apps about 1.5-2x as fast. A window of an app that
is already running comes as quickly as on Android; those rows did not change
in 0.20.1.

A first frame is not a finished screen. Android's apps go on drawing after
it; measured to the last frame before 500 ms without one, Settings,
Calculator and Contacts settle at 1008, 910 and 725 ms on the Duo 1 and 617,
812 and 537 ms on the Duo 2.

## The shell's motions

| | Duo 1, Android | Duo 2, Android | Duo 1, 0.20 on 102 | Duo 1, 0.18 on 101 |
|---|---|---|---|---|
| Bringing back a minimized app from the dock, ms | - | - | 59 | 444-491 |
| Opening the app grid, dropped frames | 2 | 0 | 0 | 0 |
| Moving an app to the other panel, dropped frames | - | - | 0-1 | 0-1 |
| Closing an app, dropped frames | - | - | 0 | 0-1 |

The restore went from ~450 to 59 ms with phoc 0026: work queued for the
compositor's idle waited for the next unrelated client message.

## Battery, the phone closed

The phone folded, the display blanked, on battery, Wi-Fi and the modem on.

| | Duo 1, 0.20.1 on 102 | Duo 1, 0.20 on 102 | Duo 1, 0.18 on 101 |
|---|---|---|---|
| Battery draw | 46-48 mA on Wi-Fi, 73 mA on mobile data alone | 35-65 mA; 74 mA with the modem on 3G | 58 mAh/h, a 6-hour average by the charge counter |

On 102 the draw was ~150 mA at first: Droidian 102's mobile-power-saver
lifted the NPU's memory bandwidth vote to its maximum with the screen off
(#230, fixed in 0.20). Then on 0.20 the closed phone sometimes drew 74 mA: the
same daemon sets the highest technology the modem lists when it starts, nr,
and the Duo 1's modem lists 5G it does not have. Asking for it, the modem sat
on 3G with LTE around and never slept (0 % asleep by the rpmh statistics); on
LTE it sleeps 95 % of the time. 0.20.1 puts the preference back to LTE.
Without Wi-Fi the phone's little traffic goes through the modem and wakes it:
73 mA. The rest is the SoC kept out of its system sleep states - the port does
not suspend a closed phone, so that calls and alarms are not missed. A 6-hour
average on 102 is still to be taken, and the closed phone has not been
measured on stock Android.

## Boot and wake

| | Duo 1, Android | Duo 2, Android | Duo 1, 0.20.1 on 102 | Duo 1, 0.20 on 102 |
|---|---|---|---|---|
| Boot, kernel start to the lock screen, s | 13.75 (median of 5) | 11.7 and 30.7 (2 boots) | 22.3 | 47.7 |
| Screen lit after the power key, ms | ~545 | ~480 | 541-549 | - |

0.20.1's boot is less than half 0.20's, by two changes to the kernel's
command line. droidian.lvm.prefer made the initramfs look for an LVM volume
group five times, 2 s apart, before taking rootfs.img from userdata, where the
port always is: 11 s. And the stock command line carried a serial console,
console=ttyMSM0 and earlycon, that the Duo has no UART for: every kernel
message waited for it at 115200 baud - 3.6 s replaying the log when the
console came up, and the whole boot held up with it (the kernel reached the
initramfs at 9.7 s; now at 1.6 s). Both are gone; the journal and dmesg keep
every message. The screen lit after the power key was already Android's; what
is left there is the panels' own power-on (~525 ms on Android too).

On Android the Duo 2's first boot, 30.7 s, came after the phone had been up
for three days; the second, 11.7 s, right after it. The Duo 1 booted five
times in a row, 13.3-15.0 s.
