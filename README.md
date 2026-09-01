# Loud or Not

A menu bar app that pulses a glow around the edge of every screen when you start
talking too loudly on a video call. Slow yellow when you first cross the line,
fast red when you are really going, plus a discreet beep in your headphones once
you are properly shouting.

## Requirements

macOS 14 or later. Xcode is not required; the Command Line Tools are enough.

## Build and install

```bash
make
```

That creates a code signing identity if you do not already have one, builds a release
binary, assembles and signs the bundle, installs it to `/Applications/Loud or Not.app`,
and launches it. The app has no dock icon; look for a waveform in the menu bar.

If you had *Launch at login* turned on before installing to `/Applications`, toggle it
off and back on once so it registers the new location.

| Command | What it does |
| --- | --- |
| `make install` | Build, sign, install to `/Applications`, relaunch (the default) |
| `make app` | Build and sign into `build/` without installing |
| `make run` | Build and launch from `build/` without installing |
| `make identity` | Create the signing identity (the build does this for you) |
| `make icon` | Redraw `Resources/AppIcon.icns` after editing the icon script |
| `make test` | Run the unit tests |
| `make stop` | Quit a running copy |
| `make uninstall` | Remove it from `/Applications` |
| `make clean` | Remove build artifacts |

## First run

macOS will ask for microphone access the first time. If you miss the prompt, the
panel shows an **Open Privacy Settings** button.

The app listens to the microphone alongside whatever meeting app is using it -
macOS allows several processes to read the same input device at once, so this does
not interfere with Zoom, Meet, Teams, or Slack.

## Calibrating

Microphone gain varies enormously between machines and headsets, so the shipped
thresholds are only a starting point.

Click the menu bar icon and talk. The segmented meter works like the microphone input
level in System Settings, lighting up green, then amber, then red as your voice
crosses the two thresholds.

The amber and red markers are the thresholds themselves: drag them along the meter
until they sit where your voice crosses from fine, to loud, to too loud. Each
threshold's value travels underneath its marker, and changes take effect immediately.

Loudness is a rolling average over roughly one and a half seconds, gated so that
silence between sentences does not drag it down and a single cough or laugh cannot
set it off. The glow also holds on until you drop about 2 dB below the warn
threshold, so it does not flicker while you hover right at the line.

## The audible warning

When your voice reaches the red threshold and you are wearing headphones, the app plays
two short rising pips, at most once every 3.5 seconds. The glow only helps if you happen
to be looking at the screen; the beep is for when you are looking at a person. There is a
**Beep when loud** checkbox in the panel to turn it off.

Note that the beep fires at the *red* threshold, not the amber one, so if the two are far
apart you will see a lot of glow before you ever hear anything.

The audio engine is built for each beep and torn down when it finishes. Holding one open
kept a CoreAudio render thread and the output device alive for a quarter of a second of
sound, and an engine started against headphones that later slept or reconnected would stay
wedged, silently swallowing every beep after that.

It is deliberately limited to headphones. A beep through the speakers would carry into
the room, which is the exact thing this app exists to prevent. Rather than guess from how
a device is connected, the app asks CoreAudio what the output stream actually terminates
in, because a USB headset and a pair of USB desk speakers share a transport type, as do
Bluetooth earbuds and a Bluetooth speaker. Wired headphones in the built-in jack are
recognised too, via the data source the built-in device switches to.

## Listening modes

| Mode | Behaviour |
| --- | --- |
| Only during meetings | Listens whenever another app is capturing the microphone |
| Always on | Listens whenever the app is enabled |

**Only during meetings** watches CoreAudio directly to see which processes are
recording, rather than guessing from a list of known meeting apps. When nothing is
recording, the app stops its own audio engine, so the orange microphone indicator
stays out of your menu bar.

Ships in **Always on** so it can be tested and calibrated without joining a call.

## Which microphone it listens to

The **Microphone** menu in the panel picks the input, so you do not have to go to
System Settings. It only moves this app: your system input device is left alone, so
a meeting carries on using whichever microphone it was already on.

It defaults to the built-in microphone rather than to the system default input,
which matters for two reasons. Opening a Bluetooth headset's microphone drags the
whole device into its call mode, so simply launching this app would make your music
and everyone's voices sound worse. The built-in microphone is also the better sensor
for the question being asked, since it hears the room roughly the way the person
sitting in it does, rather than from an inch off your cheek.

Unplugging the microphone you picked falls back to the built-in one, and plugging it
back in returns to it.

## Notes

The overlay windows are excluded from screen capture, so the glow will not appear
to other participants if you share your screen. To include it anyway (for a
screen recording or a demo), launch with:

```bash
LOUDORNOT_CAPTURABLE=1 "/Applications/Loud or Not.app/Contents/MacOS/LoudOrNot"
```

The glow is drawn on every connected display and follows monitors being plugged in
or unplugged. It sits above full-screen apps and ignores mouse clicks, so it never
gets in the way.

## The icon

`Scripts/make-icon.swift` draws the icon rather than shipping a pile of PNGs: a dark
screen with its border glowing in the same yellow-to-red ramp the overlay uses, around a
voice waveform whose peak has gone red. Each size is drawn at its own resolution instead
of being downsampled from one large image, because the rim glow and the thin bars turn to
mush when they are resampled, and the 16pt version drops from five bars to three so it
still reads in the Finder sidebar.

The generated `Resources/AppIcon.icns` is committed, so only run `make icon` if you
change the artwork.

## Code signing and the microphone permission

macOS ties the microphone grant to the app's designated requirement. Under an ad-hoc
signature that requirement includes the binary's own hash, so every rebuild looks like
a brand new app and the permission has to be granted all over again.

`make identity` creates a self-signed certificate named *Loud or Not Local Signing* in
your login keychain, and the build signs with it. The designated requirement then
points at the certificate rather than the binary, so the permission survives rebuilds.
The build creates it automatically the first time; if macOS asks whether `codesign` may
use the key, choose Always Allow.

The certificate is self-signed and so is not trusted for Gatekeeper, which does not
matter here. Locally built apps are not quarantined, and signing, launching, and the
permission all work regardless. Deleting the certificate and making a new one counts
as a new app, so you would be asked for the microphone once more.

If the permission ever gets stuck:

```bash
tccutil reset Microphone com.cmorss.loudornot
```

To see what the app thinks it is doing, run it with logging on:

```bash
LOUDORNOT_DEBUG=1 "/Applications/Loud or Not.app/Contents/MacOS/LoudOrNot"
```

## Layout

- `Sources/LoudOrNotCore` - pure loudness maths, update rate limiting, input device choice, beep throttling and tone synthesis, unit tested
- `Sources/LoudOrNot/Audio` - the capture session, the input device list, the mic-usage watcher, headphone detection, beep playback
- `Sources/LoudOrNot/Overlay` - the per-screen glow windows and their rendering
- `Sources/LoudOrNot/Menu` - the menu bar panel
- `Coordinator.swift` - decides when to arm and turns level into glow intensity
