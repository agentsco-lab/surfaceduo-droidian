# System pieces the device needs

Small files that belong to the port rather than to any application on it.
Each was found necessary on hardware; none is optional.

Since 0.13 the adaptation package installs all of them except the sudoers
rule (units go to `/usr/lib/systemd/system/` there); the paths below are for
installing by hand.

```
sfduo-slot-guard.service   /etc/systemd/system/          mark the boot good, pin slot A
sfduo-slot-guard           /usr/local/sbin/              ...the script it runs, which checks it took
sfduo-modem.service        /etc/systemd/system/          the modem online and on LTE, every boot
sfduo-modem                /usr/local/sbin/              ...the script it runs
sfduo-ofono2mm-fix         /usr/local/sbin/              ofono2mm's bearers let go together (each suspend)
sfduo-nm-wake-fix          /usr/local/sbin/              NetworkManager leaves WoWLAN Wi-Fi up after a resume (binary patch)
90-sfduo-mobile-data       /etc/NetworkManager/dispatcher.d/  mobile data off while on Wi-Fi
50-sfduo-lid.conf          /etc/systemd/logind.conf.d/   closing the device locks it
sfduo-screens              /usr/local/sbin/              panel power without the compositor
50-sfduo-screens           /etc/sudoers.d/               the session may run the above
dconf/profile-user         /etc/dconf/profile/user       makes the system database count
```

## The slot guard

The Duo has A/B slots and a bootloader that counts failed boots. Nothing in
Droidian marks a boot successful on this device, so after enough boots the
bootloader concludes the slot is broken and switches to the other one -
which has nothing bootable in it, and the device lands in fastboot. That is
the "slot-b drift" the SAFETY protocol talks about.

The unit runs after the Android container is up (the bootctrl HAL lives
there) and calls `android_bootctl mark-boot-successful` and
`set-active-boot-slot 0`. It needs `/var/lib/droidian/lxc_attach_workaround`
to exist on this device, or `lxc-attach` silently eats the last argument and
the call does nothing - the failure that caused the drift in the first place.

The order of the two calls matters: `set-active-boot-slot` clears the
slot's "successful" mark. The unit used to mark first and set active after,
undoing its own mark at every boot (found 2026-09-27) - harmless in practice,
since setting a slot active also gives it its tries back, but slot a never
read as good, and `flash-safely.sh` saw a slot that had never booted
successfully. `sfduo-slot-guard` sets the slot active first, marks the boot
good after, reads the mark back (`is-slot-marked-successful 0`), and repeats
both every 5 s for up to two minutes until it holds; if it never does, the
unit fails and shows in `systemctl --failed`.

```
install -m755 sfduo-slot-guard /usr/local/sbin/
install -m644 sfduo-slot-guard.service /etc/systemd/system/
systemctl enable sfduo-slot-guard.service
```

## The modem comes up offline, and on 3G

Measured on two consecutive boots with the SIM in (2026-09-17): ofono leaves
`/ril_0` at `Online=false`, ModemManager probes it in that state, marks it
`failed` and never looks again - the shell shows no SIM at all. And when it is
put online by hand, `TechnologyPreference` is `umts` although
`AvailableTechnologies` lists `lte`: 3G gave signal 37 and 170-650 ms pings
where LTE gives 77-87 and 70-90 ms. Every install of this port therefore
looks like "the modem does not work", then like "LTE does not work".

`sfduo-modem` waits for ofono's modem, sets `Online`, prefers `lte` if the
modem offers it, and restarts ModemManager if it had already given up.
ofono does store the preference (`/var/lib/ofono/<imsi>/radiosetting`), and
once it has been set it came back as `lte` on the next boot - but only after
something put the modem online, so the unit does both.

```
install -m755 sfduo-modem /usr/local/sbin/
install -m644 sfduo-modem.service /etc/systemd/system/
systemctl enable sfduo-modem.service
```

Mobile data is one line, and needs nothing else - its route metric lands at
700 against wifi's 600, so wifi stays preferred:

```
nmcli c add type gsm ifname '*' con-name <name> apn <apn>
```

## Closing the device locks it

The hinge has a hall sensor and it shows up as a lid switch
(`Surface Duo Lid Switch`, `SW_LID`), so logind sees every fold. What it does
about it is `HandleLidSwitch*`. The port's status table records fold-to-sleep
working through this switch; on the device as it is today suspend is turned
off in the session (`sm.puri.phosh enable-suspend` is `false`), so the policy
here is lock - on battery, on power and docked alike. To have the fold
suspend again, turn that setting on and set the three keys to `suspend`.

Locking alone left the display on: with idle blanking off nothing ever
turned it off, and behind the closed lid both panels stayed lit on the lock
screen. So the lid daemon also blanks the display when the phone closes and
turns it back on when it opens - phosh's `PowerSaveMode` on
`org.gnome.Mutter.DisplayConfig`, which is what GNOME blanks with and what
Droidian's `mobile-power-saver` follows (#103). Measured closed on battery:
126-184 mA with the display on, 33-55 mA blanked - 4-6 % of the battery an
hour against 1-1.7 %. A 4-hour measurement closed on battery (2026-09-23,
4 h 14 min, display blanked): 97 % to 89 %, 53-57 mA, about 2 % an hour.

A closed phone whose display something turns back on - a call, a critical
notification, the power key - has it turned off again after ~4 s (#105):
in that same measurement an unanswered call lit the panels behind the lid,
and they stayed lit at 163 mA until the phone was looked at.

Two things worth knowing about the mechanics:

- Drop-ins in `logind.conf.d` apply in name order and the last one wins. A
  file that sorts later and says `ignore` silently takes the lock away, on
  battery only, and the device then folds and unfolds straight back to the
  desktop. That is what it looked like when another project's drop-in was
  still installed.
- `systemctl kill -s HUP systemd-logind` reloads the config without a
  restart. It may drop an ssh session in passing; the shell survives.

Once locked, the fingerprint sensor on the power key unlocks it the moment a
finger rests there - which, on a device you hold by that edge, is the moment
you open it. It can look as if the lock screen never came.

Who arms the reader matters. Droidian's `fpd-unlockd` asks droidian-fpd to
listen only when logind's `IdleHint` goes from idle to active, and the
idle-delay of 0 below (0.14.1) means the session is never idle: the reader
listened once, when `fpd-unlockd` started, the daemon gave that attempt up
after its 30 seconds, and every later lock had nobody listening - the finger
did nothing and the enrolment looked broken. `sfduo-fingerprint` (in
`../shell`) arms it on what the screen shows instead: locked and lit. It
listens again after each timeout or unknown finger, lets go when the screen
goes dark or the phone is unlocked another way, and buzzes - 150 ms on an
unlock, 100 ms for a finger it does not know; `fpd-unlockd`'s buzz was 12 ms
and went unnoticed. droidian-fpd serves one client at a time, so the package
masks `fpd-unlockd` with a link to `/dev/null` in `/etc/systemd/user`.

A finger is enrolled from the settings (`droidian-fpd-gui` and
`droidian-fpd-client` from the archive cannot be installed: both need
`libbatman-wrappers`, which rolling no longer carries).

## An open device stays on

Since 0.14.1 the screen does not blank and lock on its own
(`dconf/52-sfduo-idle`: `org.gnome.desktop.session idle-delay` is 0, a
default a user's own value overrides). An open Duo on a desk is being looked
at, and closing it is how it is put away; the backlight still dims after a
short idle (`idle-dim`, to 30 %), and the power button locks as before.
Settings' Surface Duo page sets a delay again ("Turn the screen off when
idle"); it writes the same key as Battery and Power's "Screen Blank".

There is a second reason, found while measuring the kernel: Droidian's
`mobile-power-saver` ties its hard saving to the blanked screen - the CPU
governor goes to `powersave` (every core at its lowest clock: 576 MHz on the
little ones, 826 MHz on the big one, of 2.8 GHz) and processes are frozen.
Anything measured over ssh with the screen off measures that, not the
system: a root login that starts a user manager took 20 s that way and
1.5 s with the screen on, `systemctl daemon-reload` 7 s against 1.7 s. With
idle blanking off an open device runs at full speed; Droidian already has
idle suspend on battery off (`sleep-inactive-battery-type` is `nothing`).

And a third: at boot the screen is off until phosh has drawn, so the saver
starts in its off state, and the first "on" never reaches it - the device
runs at its lowest clocks until the screen has been turned off and on once
by hand. Measured 2026-09-18 on the debug kernel: `daemon-reload` 30 s that
way, 2.2 s after a screen cycle; a root login 26 s against 2 s. The
"debug kernel" numbers that had been going around were mostly this. Since
0.15.1 `sfduo-cpufreq.service` waits for the shell and sets `schedutil`
once; the saver keeps toggling on screen events after that.

## Panel power

`sfduo-screens off|on|toggle` drives `bl_power` on the two panel backlights,
the same path the system uses. It exists because `wlr-randr --off` on the
sole `HWCOMPOSER-1` output crashed the compositor of the day. Brightness
survives a cycle; rendering continues underneath.

## Windows tile; phosh would rather they did not

On the port's own shell phosh maximizes every window, and phoc makes that
one panel. The two-panel shell (item-shell) tiles windows itself, which only
works while `sm.puri.phoc auto-maximize` is off - and phosh turns it on
again on every start unless it decides the device is docked. item-shell
carries the value as a system dconf default; `sfduo-phosh-install` puts the
lock on the key (`/etc/dconf/db/local.d/locks/50-sfduo-phoc`) beside the
patched phosh while the dock can run, and takes it away when it cannot, so
the packaged phosh and the port's own shell keep maximizing. A locked key is
not writable by anyone in the session, phosh included - `gsettings set`
answers "The key is not writable" - and phoc picks the value up live. The
system database only counts with a profile naming it (`dconf-cli` is not
installed by default):

```
install -Dm644 dconf/profile-user        /etc/dconf/profile/user
dconf update
```

## Applications

The image's app grid is Droidian's; the port hides what it does not want
(`apps/hidden.list` - an override per desktop id in
`/usr/local/share/applications`, which `XDG_DATA_DIRS` lists before
`/usr/share`; the packages stay, because purging any of them takes the
`droidian-phosh-full` metapackage with it and the next `apt autoremove`
would take half the system), sets six favourites as a dconf default
(`dconf/53-sfduo-apps`; a user's own favourites win; the two-panel shell's
dock shows them too), and adds what a fresh image lacks once it is online:
`sudo sfduo-apps` installs Telegram, cool-retro-term (the terminal among
the favourites - its CRT shaders render through hybris), what Claude Code needs and
Claude Code itself from npm, fastfetch and htop. `sfduo-apps --purge` does
remove the hidden packages, after marking the metapackage's other
dependencies as wanted. No Spotify: there is no client for arm64 Linux and
the web player needs Widevine, which Firefox lacks here.

## Settings

The port keeps GNOME Settings and Mobile Settings as Droidian has them. The
two-panel shell (item-shell, from agentsco-lab/item) adds a Settings of its
own, one column on one panel, grouping the pages that apply to this phone;
it is described there, in docs/SETTINGS.md.

## The hinge angle

`sudo sfduo-sensorfw-install`, once after the package: the hinge-angle
sensor is a rebuilt sensorfw (`sensorfw-hinge-patch/` - the patch touches
the hybris adaptor library, so it is not a plugin that can be dropped in),
carried as debs under `/usr/lib/sfduo/sensorfw/`; dpkg holds its lock while
the package's postinst runs, so it cannot install them itself. The script
installs the qt6 debs and the qt5 transitional stubs from the same build
(the qt6 half alone deconfigures the stock stubs and wedges apt), maps the
adaptor in `sensord-hybris.conf` - the one file sensorfwd reads - restarts
it and checks that `hingesensor` loads. Found missing on a fresh 101 image
on 2026-09-18 (#54): the July install had it by hand.
