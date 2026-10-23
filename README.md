# Mikro MIDI

**Play your Mikro. Skip the bloat.**

A free, open-source Mac app that lets you play your **Native Instruments Maschine Mikro MK3** without installing the official software stack. Its own MIDI bridge connects your controller to your music app. Play the pads, map the buttons, turn the knob, use the touch strip, and give every pad its own color.

No Native Access. No Komplete Kontrol. No NIHostIntegrationAgent. Just Mikro MIDI and your favorite music app.

[**Download for Apple Silicon**](https://github.com/schneidermayer/mikro-midi/releases/latest) · [Release notes](https://github.com/schneidermayer/mikro-midi/releases) · [Report a problem](https://github.com/schneidermayer/mikro-midi/issues)

![Mikro MIDI showing its pad layout, color palette, and controller settings](docs/images/mikro-midi.png)

## Start making music

1. **Plug in** your Maschine Mikro MK3 over USB.
2. **Open Mikro MIDI.** Download the release ZIP, unzip it, and drag **Mikro MIDI.app** into Applications. The app connects automatically.
3. **Select “Mikro MIDI”** as a MIDI input in your music app and load an instrument.

Keep Mikro MIDI open while you play. It creates the MIDI input; your music app creates the sound. No special button combination or MIDI mode is needed.

**Requirements:** an Apple Silicon Mac (M1 or newer), macOS 14 or later, and a Maschine Mikro MK3. The downloadable app is arm64 only. Other Maschine models are not supported.

Official release downloads are signed with a Developer ID and notarized by Apple.

## Make it yours

- **Pads:** select a pad to edit its note, or select several pads and color them together. Pads send velocity-sensitive notes, with optional polyphonic aftertouch.
- **Colors:** choose Aurora, Ember, Mint, Ocean, Sunset, Neon, Ice, or Mono, then customize individual pads or a selection. Adjust idle and on-press brightness in Setup.
- **Knob:** choose the MIDI CC, relative format or absolute output, step size, direction, and absolute range on its own page.
- **Controls:** assign MIDI CCs to the buttons and touch strip, or use the strip for pitch bend.
- **Presets:** import and export your setup as a JSON file. Settings save automatically between launches.
- **Live feedback:** pads glow when you play them, and the app shows knob movement, incoming events, and connection status. Unplug and reconnect your controller without restarting.

The **Pads**, **Buttons**, **Knob**, **Touch strip**, and **Setup** pages keep the everyday settings together. Changes apply to the controller while the app is running.

**Select a group:** ⌘-click to add or remove pads, ⇧-click to select a range, or use **Select all**. Color the group or transpose its notes together. The palette selector can apply a theme to **All pads** or only **Selected** pads.

<details>
<summary>See the dedicated knob controls</summary>

![Mikro MIDI knob mapping with live position, range, step size, and direction controls](docs/images/mikro-midi-knob.png)

</details>

## Defaults and MIDI behavior

Physical pads are numbered from the bottom left, matching the controller. Pad 1 sends MIDI note **36**, pad 16 sends **51**, on MIDI channel **1**. The on-screen grid follows the physical layout:

```text
Pad 13 · 48    Pad 14 · 49    Pad 15 · 50    Pad 16 · 51
Pad  9 · 44    Pad 10 · 45    Pad 11 · 46    Pad 12 · 47
Pad  5 · 40    Pad  6 · 41    Pad  7 · 42    Pad  8 · 43
Pad  1 · 36    Pad  2 · 37    Pad  3 · 38    Pad  4 · 39
```

| Control | Default output | Options |
| --- | --- | --- |
| 16 pads | Notes 36–51, velocity | Per-pad note, color, optional polyphonic aftertouch |
| Buttons | CC 20–58, press 127 / release 0 | Per-button CC |
| Encoder press / touch | CC 59 / 60, press 127 / release 0 | Separate CC assignments |
| Encoder | CC 1, relative | Three relative formats, absolute CC, step size, direction, range |
| Touch strip | CC 9, 0–127 | CC or 14-bit pitch bend |
| MIDI channel | Channel 1 | Channels 1–16 |

By default, the relative encoder sends **65 clockwise / 63 counterclockwise** (64-centered relative encoding). Choose the relative format that matches your music app on the Knob page, or use absolute mode. The default absolute range is 0–127, starting at 64; you can narrow the range, adjust the step size, or reverse the direction.

| Relative format | Clockwise | Counterclockwise |
| --- | --- | --- |
| Offset (default) | 65 | 63 |
| Two's complement | 1 | 127 |
| Sign magnitude | 1 | 65 |

Step size ranges from **1 to 16**. Relative mode sends that many one-step messages per encoder increment; absolute mode changes its value by that amount. Invert reverses the direction. Absolute mode also lets you set the minimum, maximum, and initial value.

Use your music app's MIDI Learn function to assign a button, knob, or strip gesture to an instrument parameter. MIDI note numbers are shown because applications use different octave labels for the same note.

Play, Record, and Stop send CC 42, 43, and 44 by default. Assign them to your music app's transport controls if needed; these buttons send ordinary CC messages, rather than MIDI clock or transport commands.

Pad colors use the Mikro MK3's fixed hardware palette, so they may look slightly different from the screen. This app provides general MIDI control; it does not connect to Native Instruments Controller Editor or provide Maschine software integration.

## If something does not connect

- **Waiting for controller:** check the USB cable, try a direct USB connection, and close other software that may be using the Mikro MK3. The app retries automatically.
- **Connected, but no sound:** enable the **Mikro MIDI** input in your music app, load an instrument, and enable monitoring or arm its track. A MIDI controller does not make sound by itself.
- **No input in your music app:** start Mikro MIDI first, then refresh the MIDI device list or reopen your music app.
- **A stuck note:** use **Setup → All notes off (Panic)** to release sustain, center pitch bend, and stop sounding notes.
- **Unexpected mappings:** restore the default preset, or import a previously exported preset.

Settings are stored at `~/Library/Application Support/Mikro MIDI/settings.json`.

## Build from source

On an Apple Silicon Mac, install [Rust](https://www.rust-lang.org/tools/install) and Apple's Command Line Tools (`xcode-select --install`), then:

```sh
git clone https://github.com/schneidermayer/mikro-midi.git
cd mikro-midi
./scripts/build-macos.sh
open "dist/Mikro MIDI.app"
```

The script builds the Rust MIDI bridge and native SwiftUI app, bundles everything into `dist/Mikro MIDI.app`, and creates a release ZIP with a SHA-256 checksum. No NI software is needed to build or run it.

Local builds are ad-hoc signed. To sign with your own Developer ID certificate, set `SIGNING_IDENTITY` when running the build script. Signing alone does not notarize the app. Optionally set `NOTARY_PROFILE` to your own saved `notarytool` keychain profile to submit, staple, and package a notarized release.

For an unnotarized build from a source you trust, try opening the app once, then use **System Settings → Privacy & Security → Open Anyway** if macOS blocks it. See [Apple's first-open instructions](https://support.apple.com/en-us/102445).

```sh
make check     # Rust formatting and automated tests
make app       # Build the app and release ZIP
```

The app targets macOS 14 and later. On an Apple Silicon Mac running macOS 27.0.1, an independent CoreMIDI monitor verified all 16 pads, presses/releases from 14 button inputs, absolute encoder movement in both directions, and touch-strip CC and pitch-bend output. Live color configuration, Panic, and graceful shutdown were also exercised. Automated tests cover mapping boundaries, relative encoder wraparound, malformed input, remapping, sustain cleanup, and pitch-bend reset. The advanced knob combinations have not all been exercised on the hardware. Older supported OS versions have not been tested with the controller. CI builds the app on macOS 15 without an attached controller.

### Standalone driver and Linux

The Rust command-line driver remains available independently of the Mac app:

```sh
cargo build --release --locked
./target/release/driver --help
./target/release/driver --probe
./target/release/driver --wait
```

Use `--config preset.json` (or a TOML file) to load settings, `--duration 60` for a timed session, and `--json` for machine-readable event output. The native app manages this process for you.

The code retains the upstream Linux MIDI backend. Linux users need ALSA, libudev, and libusb development packages; an optional JACK backend is available with `--features jack`. The included `98-maschine.rules` supplies USB access rules. See the [upstream Linux setup guide](https://github.com/r00tman/maschine-mikro-mk3-driver#readme) for platform dependencies. This project's packaged desktop app and release validation are for macOS.

## Credits and license

Mikro MIDI builds on **[r00tman's Maschine Mikro MK3 driver](https://github.com/r00tman/maschine-mikro-mk3-driver)** by Viktor Rudnev, whose work provides the controller protocol, HID handling, and hardware foundation. The upstream project was inspired by [maschine.rs](https://github.com/wrl/maschine.rs).

The Mac app and expanded MIDI mapping are by Hannes Schneidermayer. Released under the [MIT License](LICENSE), with the original copyright notice preserved.

Independent community software, not affiliated with or endorsed by Native Instruments. Maschine and Native Instruments are trademarks of their respective owners.
