# Hinge-angle and posture sensors for sensorfw (Surface Duo)

The Duo's hinge angle (0-360°, `android.sensor.hinge_angle`, type 36,
served by the MS `sns_fold` sensor on the SLPI) is not a sensor type
sensorfw knows about. This patch adds a `hybrishingeadaptor` +
`hingesensor` pair so the live angle is available over DBus.

Verified on device 2026-07-11: fold the device and degrees stream in
real time (146→167→152→120→156° in one test).

## Microsoft's posture sensor (added 2026-10-03, 0.14.8+itemae2)

The sensors HAL also serves Microsoft's own **Posture** sensor (vendor type
33171009, 17 postures, which panel faces the user among them - item-tracker
#116), and sensorfw ignores vendor types. A `hybrispostureadaptor` +
`posturesensor` pair, built as the hinge's, publishes its first value over
DBus (`/SensorManager/posturesensor`, `local.PostureSensor`) and logs the
first four values at each change (`journalctl -u sensorfwd`, "Surface
posture:"), to be read against the ways the Duo is held - Microsoft does not
publish what they mean.

What its values mean, read on the device (2026-10-03), the first of the four:

| value | the Duo |
|---|---|
| 0 | closed |
| 3 | open as a book or a laptop (~100°) |
| 5 | flat |
| 7 | closing |
| 13 | on the way to back to back |
| 11 | back to back, the **left** panel facing the user |
| 9 | back to back, the **right** panel facing the user |

The third value repeats the facing as flags (32+2 for left, 32+1 for right;
12 in a turn); the fourth looks like a confidence (0 in a turn, 0.5-1 at
rest).

**Ask for an interval.** Started without one (`setInterval` on the session
before `start`), the sensor reports once and never again. With 100 ms it
reports each change. `sfduo-posture` does this, and publishes `Surface` (the
value) and `Facing` (left or right) - when run with `SFDUO_POSTURE_SURFACE=1`;
nothing uses them yet.

**Connect the data socket.** sensorfw takes a session whose client has not
connected `/run/sensord.sock` (and written its session number there) within
ten seconds of `requestSensor` for lost, and stops its sensor. A client that
only polls the D-Bus property sees the value freeze after ten seconds.

Map it as the hinge's:

```
postureadaptor = hybrispostureadaptor
```

## What's here

- `core.patch` - changes to existing sensorfw files (the hinge's and the
  posture's):
  `core/hybrisadaptor.{h,cpp}` (SENSOR_TYPE_HINGE_ANGLE), registration
  in `adaptors/adaptors.pro` + `sensors/sensors.pro`, and the new
  plugin `.so`s added to `debian/libsensorfw-qt6-plugins.install`.
- `new-files/` - the new adaptor + sensor sources (drop onto the tree
  as-is) and a template `debian/changelog` (the Droidian CI generates
  one at build time; building outside CI you must provide it yourself).

## Build

```
git clone https://github.com/sailfishos/sensorfw.git   # droidian uses the qt6 branch of its fork
# use the same source the droidian package was built from:
#   apt source sensorfw-qt6      (on the device or any droidian chroot)
cd sensorfw
git apply /path/to/core.patch
cp -r /path/to/new-files/* .
dpkg-buildpackage -us -uc -b       # arm64; a qemu-aarch64 chroot of the
                                   # droidian rootfs works but is slow, needs
                                   # debhelper + qt6 build-deps installed
```

Built on the Duo itself (a chroot of a copy of its rootfs, 2026-10-03), it
takes about half an hour, and two traps show up:

- A newer GCC rejects `qt-api/socketreader.h` without `<QDebug>`. The include
  is in `core.patch`.
- Under the Duo's 4.14 kernel, `qmake6 -install qinstall` fails with "Invalid
  argument" when it copies a file, so `make install` and `debian/rules`
  stop. In the build chroot, use a stand-in:
  - a `qinstall-shim` that does the same with `install -D` (and `cp -a` for
    directories);
  - run the build with `MAKEFLAGS="QINSTALL=qinstall-shim
    QINSTALL_PROGRAM=qinstall-shim-exe"`;
  - point the direct call in `debian/rules` at the shim.
  This is a build-machine problem only; the packages are the same.

## Install traps (all hit in practice)

- Install the resulting qt6 debs with `apt install ./libsensorfw-qt6*.deb
  ./sensorfw-qt6*.deb` - plus the **qt5 transitional stubs from the same
  build**. Installing only the qt6 halves deconfigures the stock qt5
  stubs and wedges apt.
- The plugin only loads if it is mapped in the config file sensorfwd
  actually reads: it runs with `-c=/etc/sensorfw/sensord-hybris.conf`
  and ignores conf.d-style numbered files. Append:

  ```
  [plugins]
  hingeadaptor = hybrishingeadaptor
  ```

  (`adaptation/package/build.sh`'s postinst does this automatically.)

## Reading the angle

```
dbus-send --system --print-reply --dest=com.nokia.SensorService \
  /SensorManager local.SensorManager.requestSensor string:hingesensor
dbus-send --system --print-reply --dest=com.nokia.SensorService \
  /SensorManager/hingesensor local.HingeSensor.start int32:<sessionid>
dbus-send --system --print-reply --dest=com.nokia.SensorService \
  /SensorManager/hingesensor org.freedesktop.DBus.Properties.Get \
  string:local.HingeSensor string:hinge      # uint32 degrees
```
