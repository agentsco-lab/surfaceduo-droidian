# Droidian's shell on two panels

Phosh runs on this device out of the box, and it centres things. Both panels
are a single output, so the middle of the screen is the middle of the hinge:
84 physical pixels that are addressable and physically hidden. The lock
screen's clock was cut in half by it, the home bar's drag handle was entirely
inside it, a column of app icons fell into it, and windows, the keyboard and
the notification banners sat across it.

The port keeps Droidian's own shell - phosh, phoc and the on-screen keyboard
as Droidian ships them - and fixes only where the hinge meets it: a handful
of patches that teach phosh, phoc and the keyboard about a seam down the
middle of the display, a stylesheet that keeps phosh's own furniture off it,
and the output scale. Windows are maximized one panel each, a new one opens
on the panel touched last, and each half has its own top bar and shade.

The two-panel shell - a dock across both panels that is also the desktop,
windows tiled to the panel they were launched from, the system screen and
the pen's sheet at the outer edges, a Settings of one column - is a package
of its own on top of this one: item-shell, from
[agentsco-lab/item](https://github.com/agentsco-lab/item). While it is
installed, the install scripts below put its builds of phoc, phosh and the
keyboard in place instead of the port's, and `sfduo-shell-css` appends its
rules to the port's; removed, the port's come back.

## gmobile's cutout: what it does, and what it costs


gmobile carries a description of the display panel for each device and phosh
asks it where the cutouts are, looking the file up by the device tree's
`compatible` string:

```
$ cat /firmware/devicetree/base/compatible
qcom,sm8150-mtp
```

Droidian's phosh session already sets

```
G_RESOURCE_OVERLAYS=/org/gnome/gmobile/devices/display-panels=/var/lib/droidian/phosh-notch
```

and nothing ever put a file there. Dropping a `qcom,sm8150-mtp.json` in that
directory, with the hinge as a cutout

```json
{ "name": "Surface Duo 1", "x-res": 2784, "y-res": 1800, "border-radius": 0,
  "width": 145, "height": 93,
  "cutouts": [ { "name": "hinge", "path": "M 1350 0 h 84 v 1800 h -84 Z" } ] }
```

does work: the log says `Mapped file … as a resource overlay` and the top
bar's clock moves out of the bezel. That is also the only thing phosh does
with cutouts.

**And on a stock phosh it breaks the notification shade completely.** With
that file in place, pulling the shade down gives a black screen: no clock, no
quick settings, no notifications, and the status bar gone with them - the
panel unfolds and nothing at all is drawn in it. Remove the file, restart
phosh, and the shade comes back exactly as it should. It was reproduced both
ways, twice.

The cause is one line. phosh treats a cutout that overlaps the clock as a
notch and shifts the bar's contents by `notch.height + notch.y` - and that
same shift is applied as a top margin to the settings menu. A notch is tens
of pixels tall. A hinge is the whole display, so the shade is pushed 1800
pixels down, off the bottom of a screen 1800 pixels tall.

`phosh-patches-0.55/0004` says so: a cutout as tall as the panel is not a notch
but a **seam**, a hinge between two halves of one display. Phosh skips the
notch arithmetic for it, and the shell gives such a display a top bar - and
so a notification shade - per half, each anchored to its own three edges and
reaching only as far as the seam. Either half can be pulled down on its own,
neither is cut in two by the bezel, and each centres its own clock, so the
CSS that used to nudge the clock out of the bezel is gone.

At first both bars drew all of it - the same clock, the same signal, the
same battery, a hinge apart - which side by side reads as one bar drawn
twice rather than as two halves. It showed on the lock screen first, where
the bar is only indicators.

So `gtk.css` deals the contents out instead. phosh's bar is a box with three
children: the network group at the start, the clock as the centre child, the
indicators at the end. Each half keeps the children that belong at its own
outer edge and lets go of the rest - signal and clock on the near half,
battery and the rest of the indicators on the far half, nothing in the
middle where the bezel is. Read across the open device it is still one bar,
and nothing in it is said twice.

Let go of, not removed: an invisible child keeps its place in the box, which
is what holds the clock centred on its own half rather than letting it slide
over once the indicators beside it stop drawing. The strips themselves stay
whole - each is what the finger pulls its own shade by.

Two things the far half did not inherit on its own, both found by pulling
its shade down and watching it stop:

- **Its height.** The shell sets the top panel's surface to the display's
  usable height whenever the monitor is configured, and did it for the first
  panel only. A shade is as tall as the surface it unfolds inside, so the far
  one opened a finger's width and stopped there, arrow and all.
- **Its background.** Each panel makes a second layer surface behind itself,
  anchored to all four edges, which is what dims the screen under an open
  shade. Two of them, each the full width, meant either shade dimmed both
  halves. The background now carries its panel's margins - set when the panel
  is mapped, not where the background is made: margins are ordinary
  properties and GObject applies those after `constructed()` has run, so
  asking for them there returns zero, which is exactly the bug in a quieter
  form.
- **One pixel of exclusive zone.** The near panel reserves the bar's height
  and the far one, whose bar is the same bar, must reserve almost nothing,
  since the zones of surfaces anchored to the same edge are added up. Almost,
  not exactly: phoc keeps a dragged surface's zone at its reservation less
  the margin it is folded by, so a panel that reserved nothing reached zero
  the moment its shade was fully unfolded - and phoc draws every surface
  whose zone is zero or less underneath every surface whose zone is positive.
  The far shade opened *behind its own dimming surface*: it was there,
  drawing its buttons, and the half was black. Both screenshots were black to
  the byte, because a black dimmer over a black wallpaper is the same
  picture.

  One pixel keeps that panel on the near one's side of the line. It costs a
  logical pixel of the display's top and leaves the two halves of the bar two
  physical pixels out of line, both measured. Splitting the reservation in
  half instead is arithmetically neater and looks wrong: two positive zones
  on one edge stack, so the second half's bar sat sixteen pixels lower.

Taking the bar off the lock screen entirely was tried first, on the grounds
that that screen has a clock of its own. It only moved the question: the
halves are uneven everywhere, not only there. Split honestly and there is
nothing left to hide, so the lock screen gets the same bar as everything
else.

## The patches

Each is built for exactly the Droidian package it stands in for and
installed only beside that version (see "Installing" below). On Droidian 102:

**phoc** (`phoc-patches/`, on droidian/phoc 7e682c6, a rebuild of 98211ea):

- 0001 tiled views stay out of a seam in the middle of the output, named by
  `tiling-seam` in `phoc.ini`
- 0002 a new view is centred on the panel touched last
- 0003 a new exclusive height on a draggable surface takes effect at once
- 0004 a window on a panel is fitted into it, and maximized means one panel
- 0005 frame done goes out before the repaint, not after hwcomposer's swap
- 0006 a tiled window is put at its tile when its geometry moves
- 0007 a keyboard on one panel reserves only that panel's bottom
- 0008 on a display with a seam a tiled window is tiled on all four edges
- 0009 a layer surface acking after the timeout is not an error
- 0010 work queued for the Wayland loop's idle is done before GLib sleeps
- 0011 a window scaled to fit a panel reaches past its edges (no line of
  wallpaper)
- 0012 a window maximized before it is mapped goes to the panel touched last
- 0013, 0014 the pixel a folded bar keeps on its panel is not taken from
  windows

**phosh** (`phosh-patches-0.55/`, on droidian/phosh `group/next/phosh-0.55`,
bee1861):

- 0001 the shell tells logind it came up locked
- 0002 LTE is called "LTE", not "4G"
- 0003 the home commits after dropping keyboard interactivity, so a window
  can take the focus
- 0004 a full-height cutout is a seam: a top bar and a shade per half
- 0005 a notification banner drops in on the far half
- 0006 no overview thumbnail for an activity nobody can see
- 0007 one cached wallpaper, only as large as an output needs
- 0008 the volume bubble on the right panel
- 0009 a tap beside the app grid's search entry takes its focus away
- 0010 the launch splash on the panel the app was launched from

**The keyboard** (`osk-patches-stevia/`, on droidian's phosh-osk-stevia
`group/next/phosh-0.55`, cfcbe7a): see below.

`phosh-patches/` and `osk-patches/` are the sets for Droidian 101 (phosh
0.49, phosh-osk-stub), kept for reference; 0.21 builds for 102 only.

## The output scale

Droidian's generic `phoc.ini` scales every phone's output by 3, which makes
the Duo's two panels 928x600 logical - a phone's worth of space in which GNOME
Calculator loses its bottom row. Android runs these panels at 400 dpi, a
scale of 2.5, and from 0.14.1 to 0.15.3 so did the port. But GTK3 has no
fractional scale: at 2.5 it draws at 3 into a 27 MB buffer per frame and
phoc scales it down, and the lock screen's unlock swipe ran at 40 fps that
way; at 2 the same swipe runs at 55-60 (`docs/PERF.md`, "The lock screen,
measured"). So since 0.15.4 the port's scale is 2: `phoc.ini` (this
directory, Droidian's file with that one line changed - phosh-session takes
`/etc/phosh/phoc.ini` whole when it exists) makes the output 1392x900
logical, with the hinge at [675, 717]. It is a conffile: change the scale
there (2.5 is still there to try), run `sudo sfduo-shell-css`, restart the
shell.

Everything below is in logical pixels and therefore depends on the scale.
Everything below is in logical pixels and therefore depends on the scale; the
CSS cannot ask, so it is a template.

## The rest, in CSS

`gtk.css` belongs in the session user's `~/.config/gtk-3.0/gtk.css`. GTK3
reads user CSS from the user config directory only; there is no system-wide
`gtk.css` it will load, so the file is installed per user. It is generated:
`gtk.css.in` holds the rules with tokens where the geometry goes, and
`sfduo-shell-css` fills them in for the scale in `phoc.ini` (the package does
it at build time and again in postinst). The numbers in this section are
the scale-3 ones the rules were worked out with; at 2 read 717 for 478,
675 for 450 and 1392 for 928 (at 2.5: 573, 540, 1113).

Each widget the shell centres is given `margin-left: 478px` - the near panel
plus the hinge - so that what was centred on the whole screen is centred on
the right panel, under the thumb of a right hand. The app grid is the
exception: it keeps both panels, and only its column count changes.

Three things had to be learned the hard way, and they are why the selectors
look the way they do:

- **`PhoshLayerSurface` is a `GtkWindow`, and a GTK3 window does not apply its
  own CSS padding to its child.** `phosh-lockscreen { padding-right: … }`
  parses, matches, paints its background across the whole screen, and moves
  nothing.
- **GtkBuilder ids are not visible to CSS here.** `#box_info`, `#box_unlock`,
  `#box_datetime` - the ids in phosh's `.ui` files - match nothing at all.
  What matches is an element name from phosh's own stylesheet
  (`phosh-lockscreen`, `phosh-app-grid-button`), a style class from the `.ui`
  (`.phosh-lockscreen-arrow`, `.phosh-search-bar`), or a name set explicitly
  with `<property name="name">` (`#phosh-lockscreen-clock`, `#home-bar`).
- **A style class reaches everything that wears it, including what is not
  on screen.** `label.dim-label` was meant for the "Slide up to unlock" hint;
  it also matched the artist line in the lock screen's media player, hidden
  in a revealer - and a revealer that shows nothing still asks for its
  child's width. A 478px margin on that label made the player ask for 598,
  the area holding the notifications could shrink no further, and everything
  in the box drifted. Two afternoons of "the layout will not hold still"
  came down to that one selector. Select by position in the tree when the
  widget has no name of its own.
- **A CSS margin only lands on a widget GTK3 allocates through a CSS gadget.**
  Labels, images and boxes have one. `GtkEventBox` does not, which is why the
  home bar's handle ignores a margin and the box that centres it does not.

The `.ui` files are the reference for all of this and they are inside the
binary:

```
gresource list    /usr/libexec/phosh
gresource extract /usr/libexec/phosh /mobi/phosh/ui/lockscreen.ui
```

### The app grid

A `GtkFlowBox` fits as many equal columns as the child's minimum width allows,
and an odd number of columns always puts one column astride the hinge. At the
icons' natural width that is seven columns, with the fourth in the bezel.

Six columns instead. The minimum width that produces six is the child's whole
width, padding included - 145 px against 922 px of usable row and 6 px of
column spacing - so the button gets `min-width: 109px` and 18 px of padding on
each side. The gap between the third and the fourth column then falls on 464,
the middle of the seam, and the padding insets each icon far enough that the
two columns beside the gap stop drawing well before the bezel begins.

## The on-screen keyboard takes one panel

The keyboard anchors its surface to the left and right edges, so on this
display it ran across the bezel: half the keys on each panel and a dead
column through the middle. `osk-patches-stevia/0001` anchors it to one
panel when phoc.ini names a `tiling-seam` and the output is in landscape -
the right one, with the width of a panel computed from the monitor's
geometry and the seam, the same arithmetic as the CSS. In portrait the panels
are stacked and it spans the output as before. Stevia sizes itself for the
display's physical height (355 px here, rows of 88); on a display with a seam
0002 keeps four 60 px rows instead. 0003 gives its slide a timer of its own.

## Installing, and going back

The adaptation package installs all of it. The patched programs are carried
one build per Droidian release, under the exact version of the package each
replaces (`/usr/lib/sfduo/<program>/<version>/`), and three scripts put them
in place on every install and upgrade:

```
sfduo-phosh-install    phosh, the hinge description, phoc's auto-maximize lock
sfduo-phoc-install     phoc
sfduo-osk-install      phosh-osk-stevia
```

Each installs only beside exactly the version it was built for, keeps the
packaged binary as `<binary>.stock`, and leaves anything else alone: a
Droidian upgrade overwrites the patched binary with the new stock one, which
is the safe way for it to stop applying. The gmobile cutout goes in with the
patched phosh and only with it, since on a stock phosh it costs the whole
notification shade, as described above.

To go back to Droidian's packaged programs, each script has `--restore`,
which leaves a marker so the package keeps the stock binary through upgrades,
and `--patched`, which removes it:

```
sudo sfduo-phosh-install --restore     # --patched brings it back
sudo sfduo-phoc-install --restore
sudo sfduo-osk-install --restore
sudo systemctl restart phosh
```

With phosh restored, `sfduo-shell-css` writes an empty stylesheet: the
margins made for the patched phosh only push the packaged one about.

A black background, which suits a screen with a black bar down the middle,
is the package's default (`/etc/dconf/db/local.d/51-sfduo-background`).

## Building

The three are built on the phone itself, on 102, against its own libraries:
Droidian's source at the commit named above, the patches applied in order
with `git am`, the build dependencies from the tree's `debian/control`,
`meson setup _build --prefix=/usr --libdir=lib/aarch64-linux-gnu` with the
options in its `debian/rules`, `ninja -C _build`. Six cores build phosh in a
few minutes, faster than the arm64 container under qemu. The binaries go to
`out/phoc/`, `out/phosh/` and `out/osk/` under the names
`adaptation/package/build.sh` looks for.

## Checking it without a finger

`grim` needs the output awake or it fails with "failed to copy output":

```
wlr-randr --output HWCOMPOSER-1 --on
grim /tmp/shot.png
```

`wtype` drives the shell from the shell: any key press moves the lock screen
to the passcode page, and `wtype -M alt -k F1 -m alt` toggles the app grid
(`org.gnome.desktop.wm.keybindings panel-main-menu`). With no application
running phosh keeps the grid open, so the home bar is only visible once
something has been launched.

## The hinge, and the fold effect

`sfduo-posture` holds the one session with sensorfw and publishes what it
reads as `org.sfduo.Posture` on the session bus: the angle sixty times a
second, the raw reading, the posture, whether the hinge is turning and how
fast. Readings arrive ten times a second, in whole degrees, fifteen apart
during a brisk fold; the daemon glides between them at a constant speed
rather than springing, which is the difference between a smooth picture and
a shivering one. Everything that wants the hinge reads this instead of
talking to sensorfw itself.

`sfduo-fold` is what the hinge drives. Opening the device turns the lit
pieces of the last frame away from the eye and brings them back to flat as
the hand finishes the movement - the pieces travel out of step with each
other and arrive together, and the sheet is blurred and dimmed towards its
outer edge. It ends at `FOLD_BOOK` degrees, 150 by default: at 90 the sheet
is sharp while the hand is still opening and the last third of the movement
has nothing to look at. Every number is an environment variable, listed at
the top of the script.

Both autostart with the session. The effect reads the hinge only through
`org.sfduo.Posture`, so without the posture daemon it starts, says so and
does nothing.

## Brightness

The screen came back at 100% every time the device was opened, and there were
two separate reasons.

The first is the ambient light sensor: `gsettings get
org.gnome.settings-daemon.plugins.power ambient-enabled` was `true`, there is
a real sensor behind `net.hadess.SensorProxy`, and with an empty
`ambient-brightness-points` curve the level it computed after every unlock was
the maximum. Setting `ambient-enabled false` is the whole fix.

The second outlives that one. Closing the device powers the two DSI panels
down, and bringing them back up leaves each panel's backlight at the driver's
default, which is full: `panel0-backlight` and `panel1-backlight` both at 255
while gnome-settings-daemon still said 60%. Nothing re-applies it, because as
far as the shell is concerned nothing changed. `sfduo-brightness` watches the
two panels and, when one is at full while the shell believes otherwise, writes
the shell's own number back to it - handing gsd its current value is enough to
make it write the hardware again. A level of 100% is left alone, which is what
makes it safe.

Which device to watch matters. There are three:

```
backlight         pm8150l WLED, max 4095 - not wired to anything here, pinned at full
panel0-backlight  the left panel,  max 255
panel1-backlight  the right panel, max 255
```

The Duo's panels are OLED and are driven by DCS commands through the mdss
nodes, so `panel0`/`panel1` are the real ones. Reading `backlight` tells you
nothing: it says 4095 no matter what the screen is doing.

