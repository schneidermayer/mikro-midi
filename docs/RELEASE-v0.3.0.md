# Mikro MIDI 0.3.0

**Play your Mikro. Skip the bloat.**

Use your Maschine Mikro MK3 as a MIDI controller without the official software stack. Mikro MIDI's own bridge connects it to your music app: no Native Access, Komplete Kontrol, or NIHostIntegrationAgent required. Your music app supplies the instruments and sound.

- Native SwiftUI app with connection status, reactive pad glow, and live MIDI feedback.
- Velocity-sensitive pad notes, editable note assignments, and optional polyphonic aftertouch.
- MIDI mappings for buttons, encoder, and touch strip.
- Dedicated Knob page with three relative formats, absolute mode, step size, direction, and range settings.
- Individual or selected-group pad colors, built-in color themes, and brightness control.
- JSON preset import/export and automatic settings persistence.
- Fast page switching with retained controls and focused live updates.
- Reset all MIDI assignments in one click, preserving colors, with Undo.
- Automatic reconnection and Panic with sustain release and pitch-bend reset.
- Self-contained, Developer ID signed and Apple-notarized app: unzip, move to Applications, and open.

## Download

Download **Mikro-MIDI-0.3.0-macOS-arm64.zip** below. Requires an Apple Silicon Mac, macOS 14 or later, and a Maschine Mikro MK3. Select **Mikro MIDI** as the input in your music app after opening the helper.

The `.sha256` file contains the checksum for the ZIP. On macOS 27.0.1 on Apple Silicon, an independent CoreMIDI monitor verified all 16 pads, 14 button inputs, absolute encoder movement in both directions, and touch-strip CC and pitch bend. Color configuration, Panic, and shutdown were also exercised. Automated tests cover mapping and cleanup behavior; the advanced knob combinations have not all been physically tested. Older supported OS versions have not been tested with the controller.

This provides generic MIDI control. It does not generate sound or connect to Controller Editor.

Built on [r00tman's MIT-licensed Maschine Mikro MK3 driver](https://github.com/r00tman/maschine-mikro-mk3-driver). See the [README](https://github.com/schneidermayer/mikro-midi#readme) for setup, troubleshooting, and source builds.
