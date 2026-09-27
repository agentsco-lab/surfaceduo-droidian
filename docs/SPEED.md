# Speed: the port against stock Android

The same measurements on the port and on stock Android, taken 2026-09-26/27:
the Surface Duo 1 on its stock Android 12L (2022.902.32), the same Duo 1 on
the port - 0.18.0 on Droidian 101 and 0.20.0 (release candidate 2, the
binaries 0.20.0 ships) on Droidian 102 - and, for the newer phone, a Surface
Duo 2 on its stock Android 12L. How each number is taken, and under what
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

| Launch, ms | Duo 1, Android | Duo 2, Android | Duo 1, 0.20 on 102 | Duo 1, 0.18 on 101 |
|---|---|---|---|---|
| Settings | 368 | 398 | 794 | 1166 |
| Calculator | 340 | 404 | 687 | 1045 |
| Contacts | 413 | 260 | 649 | 1022 |
| Camera | 308 | - | 935 | 1332 |
| Weather | - | - | 694 | 1094 |
| Browser | 507 (Edge) | 1132 (Edge) | 1289 (GNOME Web) | 2339 (Firefox) |
| Calendar | 584 (Outlook) | 636 (Outlook) | 1747 | 2038 |
| Clock, running | 92 | 74 | 59 | 135 |
| Phone, running | 92 | 69 | 59 | 303 |
| Messages, running | 121 | 86 | 133 | 242 |

On 102 the port opens apps about a third faster than on 101 (Droidian 102's
libraries, the launch boost, glycin without its sandbox - see the 0.20.0
notes). Stock Android still opens them about twice as fast. A window of an app
that is already running comes as quickly as on Android.

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

| | Duo 1, 0.20 on 102 | Duo 1, 0.18 on 101 |
|---|---|---|
| Battery draw | 35-65 mA, readings after the fix | 58 mAh/h, a 6-hour average by the charge counter |

On 102 the draw was ~150 mA at first: Droidian 102's mobile-power-saver
lifted the NPU's memory bandwidth vote to its maximum with the screen off
(#230, fixed in 0.20). A 6-hour average on 102 is still to be taken, and the
closed phone has not been measured on stock Android.

## Stock Android, for reference

Not yet measured the same way on the port.

| | Duo 1 | Duo 2 |
|---|---|---|
| Boot, kernel start to the lock screen | 13.75 s (median of 5) | 11.7 s and 30.7 s (2 boots) |
| Screen lit after the power key | ~545 ms | ~480 ms |

The Duo 2's first boot, 30.7 s, came after the phone had been up for three
days; the second, 11.7 s, right after it. The Duo 1 booted five times in a row,
13.3-15.0 s.

The port's boot is in the top-level README: about two minutes from a reboot
to an ssh login on the debug kernel, 40-50 s on the perf kernel.
