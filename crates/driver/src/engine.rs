use crate::input::InputReport;
use crate::settings::Settings;
use maschine_library::controls::{Buttons, PadEventType};
use maschine_library::lights::{Brightness, Lights, PadColors};
use serde::Serialize;

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(crate) enum Event {
    Status {
        state: String,
        message: String,
        device: String,
        port: String,
    },
    Error {
        message: String,
    },
    Pad {
        pad: usize,
        pressed: bool,
        velocity: u8,
        note: u8,
        channel: u8,
    },
    Button {
        button: usize,
        pressed: bool,
        cc: u8,
        value: u8,
    },
    Encoder {
        value: u8,
        delta: i16,
        cc: u8,
    },
    Strip {
        value: u8,
        touched: bool,
        cc: u8,
        mode: String,
    },
    Configured {
        settings: Settings,
    },
    Snapshot {
        held_pads: [bool; 16],
        held_buttons: Vec<bool>,
        encoder_value: u8,
        strip_value: u8,
        strip_touched: bool,
    },
}

#[derive(Default)]
pub(crate) struct Effects {
    pub midi: Vec<[u8; 3]>,
    pub events: Vec<Event>,
    pub lights_changed: bool,
}

/// MIDI state is independent of HID and I/O, so reconnect, remap and panic
/// share the same release logic.
pub(crate) struct Engine {
    pub settings: Settings,
    held_pads: [bool; 16],
    held_buttons: [bool; 41],
    encoder_previous: Option<u8>,
    encoder_absolute: u8,
    encoder_value: u8,
    strip_raw: u8,
    strip_value: u8,
    pitch_bend_active: bool,
    sustain_active: bool,
    observing: bool,
}

impl Engine {
    pub(crate) fn new(settings: Settings) -> Self {
        let encoder_absolute = settings.encoder_initial;
        Self {
            settings,
            held_pads: [false; 16],
            held_buttons: [false; 41],
            encoder_previous: None,
            encoder_absolute,
            encoder_value: encoder_absolute,
            strip_raw: 0,
            strip_value: 0,
            pitch_bend_active: false,
            sustain_active: false,
            observing: true,
        }
    }

    pub(crate) fn set_observing(&mut self, observing: bool) {
        self.observing = observing;
    }

    /// Recover current control state when the editor resumes observing. Pad
    /// indices follow the grid/settings order, unlike physical-number events.
    pub(crate) fn snapshot(&self) -> Event {
        Event::Snapshot {
            held_pads: self.held_pads,
            held_buttons: self.held_buttons.to_vec(),
            encoder_value: self.encoder_value,
            strip_value: self.strip_value,
            strip_touched: self.strip_raw != 0,
        }
    }

    pub(crate) fn process(&mut self, report: InputReport) -> Effects {
        let mut effects = Effects::default();
        let channel = self.settings.midi_channel - 1;
        match report {
            InputReport::Pads(pads) => {
                for pad in pads {
                    let velocity = ((pad.value >> 5).min(127) as u8).max(u8::from(pad.value > 0));
                    let note = self.settings.notemaps[pad.index];
                    let held = &mut self.held_pads[pad.index];
                    let pressed = match pad.event {
                        PadEventType::NoteOn | PadEventType::PressOn if velocity > 0 => Some(true),
                        PadEventType::NoteOff | PadEventType::PressOff => Some(false),
                        _ => None,
                    };
                    if let Some(pressed) = pressed {
                        if *held == pressed {
                            continue;
                        }
                        *held = pressed;
                        effects.lights_changed = true;
                        effects.midi.push([
                            (if pressed { 0x90 } else { 0x80 }) | channel,
                            note,
                            velocity,
                        ]);
                        if self.observing {
                            effects.events.push(Event::Pad {
                                pad: physical_pad(pad.index),
                                pressed,
                                velocity,
                                note,
                                channel: self.settings.midi_channel,
                            });
                        }
                    } else if matches!(pad.event, PadEventType::Aftertouch)
                        && *held
                        && self.settings.poly_aftertouch
                    {
                        effects.midi.push([0xa0 | channel, note, velocity]);
                    }
                }
            }
            InputReport::Buttons {
                pressed,
                encoder,
                slider,
            } => {
                for (button, pressed) in pressed.into_iter().enumerate() {
                    if self.held_buttons[button] == pressed {
                        continue;
                    }
                    self.held_buttons[button] = pressed;
                    let cc = self.settings.button_ccs[button];
                    let value = if pressed { 127 } else { 0 };
                    effects.midi.push([0xb0 | channel, cc, value]);
                    if self.observing {
                        effects.events.push(Event::Button {
                            button,
                            pressed,
                            cc,
                            value,
                        });
                    }
                    effects.lights_changed = true;
                }
                let encoder = encoder & 0x0f;
                if let Some(previous) = self.encoder_previous {
                    let direction = if self.settings.encoder_invert { -1 } else { 1 };
                    let delta = i16::from(encoder_delta(previous, encoder))
                        * direction
                        * i16::from(self.settings.encoder_step);
                    if delta != 0 {
                        let cc = self.settings.encoder_cc;
                        let value = if self.settings.encoder_mode == "relative" {
                            let value =
                                match (self.settings.encoder_relative_format.as_str(), delta > 0) {
                                    ("twos_complement", true) | ("sign_magnitude", true) => 1,
                                    ("twos_complement", false) => 127,
                                    ("sign_magnitude", false) | ("offset", true) => 65,
                                    _ => 63,
                                };
                            for _ in 0..delta.unsigned_abs() {
                                effects.midi.push([0xb0 | channel, cc, value]);
                            }
                            value
                        } else {
                            self.encoder_absolute = (i16::from(self.encoder_absolute) + delta)
                                .clamp(
                                    i16::from(self.settings.encoder_min),
                                    i16::from(self.settings.encoder_max),
                                ) as u8;
                            effects
                                .midi
                                .push([0xb0 | channel, cc, self.encoder_absolute]);
                            self.encoder_absolute
                        };
                        self.encoder_value = value;
                        if self.observing {
                            effects.events.push(Event::Encoder { value, delta, cc });
                        }
                    }
                }
                self.encoder_previous = Some(encoder);
                let slider = slider.min(200);
                if slider != self.strip_raw {
                    let touched = slider != 0;
                    if touched {
                        self.strip_value = strip_value(slider);
                        if self.settings.touch_strip_mode == "pitch_bend" {
                            let bend = (u32::from(slider - 1) * 16383 / 199) as u16;
                            self.pitch_bend_active = bend != 8192;
                            effects.midi.push([
                                0xe0 | channel,
                                (bend & 0x7f) as u8,
                                (bend >> 7) as u8,
                            ]);
                        } else if self.strip_raw == 0
                            || strip_value(self.strip_raw) != self.strip_value
                        {
                            effects.midi.push([
                                0xb0 | channel,
                                self.settings.touch_strip_cc,
                                self.strip_value,
                            ]);
                        }
                    }
                    if self.observing {
                        effects.events.push(Event::Strip {
                            value: self.strip_value,
                            touched,
                            cc: self.settings.touch_strip_cc,
                            mode: self.settings.touch_strip_mode.clone(),
                        });
                    }
                    self.strip_raw = slider;
                    effects.lights_changed = true;
                }
            }
        }
        for message in &effects.midi {
            if message[0] & 0xf0 == 0xb0 && message[1] == 64 {
                self.sustain_active = message[2] >= 64;
            }
        }
        effects
    }

    pub(crate) fn configure(&mut self, settings: Settings) -> Effects {
        let mapping_changed = self.settings.notemaps != settings.notemaps
            || self.settings.midi_channel != settings.midi_channel
            || self.settings.button_ccs != settings.button_ccs;
        let mut effects = if mapping_changed {
            self.release_all()
        } else {
            Effects::default()
        };
        let controls_changed = self.settings.encoder_mode != settings.encoder_mode
            || self.settings.encoder_cc != settings.encoder_cc
            || self.settings.touch_strip_cc != settings.touch_strip_cc
            || self.settings.touch_strip_mode != settings.touch_strip_mode;
        if controls_changed && self.sustain_active {
            effects
                .midi
                .push([0xb0 | (self.settings.midi_channel - 1), 64, 0]);
            self.sustain_active = false;
        }
        if self.settings.encoder_mode != settings.encoder_mode
            || self.settings.encoder_cc != settings.encoder_cc
            || self.settings.encoder_min != settings.encoder_min
            || self.settings.encoder_max != settings.encoder_max
            || self.settings.encoder_initial != settings.encoder_initial
        {
            self.encoder_absolute = settings.encoder_initial;
            self.encoder_value = settings.encoder_initial;
            self.encoder_previous = None;
        }
        if self.settings.touch_strip_cc != settings.touch_strip_cc
            || self.settings.touch_strip_mode != settings.touch_strip_mode
        {
            if self.pitch_bend_active && settings.touch_strip_mode != "pitch_bend" {
                effects
                    .midi
                    .push([0xe0 | (self.settings.midi_channel - 1), 0, 64]);
                self.pitch_bend_active = false;
            }
            self.strip_raw = 0;
        }
        self.settings = settings;
        effects.events.push(Event::Configured {
            settings: self.settings.clone(),
        });
        effects.lights_changed = true;
        effects
    }

    pub(crate) fn release_all(&mut self) -> Effects {
        let mut effects = Effects {
            lights_changed: true,
            ..Effects::default()
        };
        let channel = self.settings.midi_channel - 1;
        for (index, held) in self.held_pads.iter_mut().enumerate() {
            if *held {
                let note = self.settings.notemaps[index];
                effects.midi.push([0x80 | channel, note, 0]);
                if self.observing {
                    effects.events.push(Event::Pad {
                        pad: physical_pad(index),
                        pressed: false,
                        velocity: 0,
                        note,
                        channel: self.settings.midi_channel,
                    });
                }
                *held = false;
            }
        }
        for (button, held) in self.held_buttons.iter_mut().enumerate() {
            if *held {
                let cc = self.settings.button_ccs[button];
                effects.midi.push([0xb0 | channel, cc, 0]);
                if self.observing {
                    effects.events.push(Event::Button {
                        button,
                        pressed: false,
                        cc,
                        value: 0,
                    });
                }
                *held = false;
            }
        }
        if self.sustain_active {
            effects.midi.push([0xb0 | channel, 64, 0]);
            self.sustain_active = false;
        }
        effects.midi.push([0xb0 | channel, 123, 0]);
        if self.pitch_bend_active {
            effects.midi.push([0xe0 | channel, 0, 64]);
            self.pitch_bend_active = false;
        }
        if self.observing && self.strip_raw != 0 {
            effects.events.push(Event::Strip {
                value: self.strip_value,
                touched: false,
                cc: self.settings.touch_strip_cc,
                mode: self.settings.touch_strip_mode.clone(),
            });
        }
        self.strip_raw = 0;
        self.encoder_previous = None;
        effects
    }

    pub(crate) fn panic(&mut self) -> Effects {
        let mut effects = self.release_all();
        let channel = self.settings.midi_channel - 1;
        // CC123 alone can leave sound sustained by CC64 or a receiver's envelope.
        effects.midi.push([0xb0 | channel, 64, 0]);
        effects.midi.push([0xb0 | channel, 120, 0]);
        effects
    }

    pub(crate) fn paint(&self, lights: &mut Lights) {
        lights.reset();
        for index in 0..16 {
            let color: PadColors = num::FromPrimitive::from_u8(self.settings.pad_colors[index])
                .unwrap_or(PadColors::Off);
            let brightness = if self.held_pads[index] {
                self.settings.pad_active_brightness
            } else {
                self.settings.pad_idle_brightness
            };
            lights.set_pad(
                index,
                color,
                if color == PadColors::Off {
                    Brightness::Off
                } else {
                    brightness_level(brightness)
                },
            );
        }
        for (index, pressed) in self.held_buttons.iter().enumerate() {
            if let Some(button) = num::FromPrimitive::from_usize(index) {
                let button: Buttons = button;
                if lights.button_has_light(button) {
                    lights.set_button(
                        button,
                        if *pressed {
                            Brightness::Normal
                        } else {
                            Brightness::Off
                        },
                    );
                }
            }
        }
        if self.strip_raw != 0 {
            let selected = usize::from(self.strip_value) * 24 / 127;
            for index in 0..=selected {
                lights.set_slider(
                    index,
                    if index == selected {
                        Brightness::Bright
                    } else {
                        Brightness::Dim
                    },
                );
            }
        }
    }
}

fn physical_pad(index: usize) -> usize {
    (3 - index / 4) * 4 + index % 4 + 1
}
fn encoder_delta(previous: u8, current: u8) -> i8 {
    (current as i8 - previous as i8 + 8).rem_euclid(16) - 8
}
fn strip_value(raw: u8) -> u8 {
    (u16::from(raw.saturating_sub(1).min(199)) * 127 / 199) as u8
}
fn brightness_level(level: u8) -> Brightness {
    match level {
        0 => Brightness::Off,
        1 => Brightness::Dim,
        2 => Brightness::Normal,
        _ => Brightness::Bright,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::input::PadInput;

    fn controls(pressed: &[usize], encoder: u8, slider: u8) -> InputReport {
        let mut buttons = [false; 41];
        for index in pressed {
            buttons[*index] = true;
        }
        InputReport::Buttons {
            pressed: buttons,
            encoder,
            slider,
        }
    }
    fn pad(index: usize, event: PadEventType, value: u16) -> InputReport {
        InputReport::Pads(vec![PadInput {
            index,
            event,
            value,
        }])
    }

    fn assert_matching_lights(observed: &Engine, hidden: &Engine) {
        let mut observed_lights = Lights::new();
        let mut hidden_lights = Lights::new();
        observed.paint(&mut observed_lights);
        hidden.paint(&mut hidden_lights);
        assert_eq!(observed_lights.report(), hidden_lights.report());
    }

    #[test]
    fn hidden_observation_preserves_midi_and_lights_without_activity_allocations() {
        let reports: &[&[u8]] = &[
            &[0x02, 12, 0x18, 0],
            &[0x02, 12, 0x48, 0],
            &[0x01, 1, 0, 64, 0, 0, 1, 15, 0, 0, 100],
            &[0x01, 1, 0, 64, 0, 0, 1, 0, 0, 0, 200],
            &[0x01, 0, 0, 0, 0, 0, 0, 15, 0, 0, 0],
            &[0x02, 12, 0x30, 0],
            &[0x02, 0, 0x18, 0],
            &[0x01, 1, 0, 64, 0, 0, 1, 1, 0, 0, 200],
        ];
        for encoder_mode in ["relative", "absolute"] {
            for touch_strip_mode in ["cc", "pitch_bend"] {
                let settings = Settings {
                    encoder_mode: encoder_mode.into(),
                    touch_strip_mode: touch_strip_mode.into(),
                    poly_aftertouch: true,
                    ..Settings::default()
                };
                let mut observed = Engine::new(settings.clone());
                let mut hidden = Engine::new(settings);
                hidden.set_observing(false);
                for report in reports {
                    let normal = observed.process(crate::input::parse_report(report).unwrap());
                    let quiet = hidden.process(crate::input::parse_report(report).unwrap());
                    assert_eq!(normal.midi, quiet.midi);
                    assert_eq!(normal.lights_changed, quiet.lights_changed);
                    assert!(quiet.events.is_empty());
                    assert_eq!(quiet.events.capacity(), 0);
                    assert_matching_lights(&observed, &hidden);
                }
                let normal = observed.panic();
                let quiet = hidden.panic();
                assert_eq!(normal.midi, quiet.midi);
                assert_eq!(normal.lights_changed, quiet.lights_changed);
                assert!(!normal.events.is_empty());
                assert_eq!(quiet.events.capacity(), 0);
                assert_matching_lights(&observed, &hidden);
            }
        }
    }

    #[test]
    fn snapshot_recovers_hidden_input_release_and_panic_state() {
        let mut engine = Engine::new(Settings::default());
        engine.set_observing(false);
        engine.process(pad(12, PadEventType::NoteOn, 2048));
        engine.process(pad(3, PadEventType::NoteOn, 2048));
        engine.process(controls(&[22, 40], 15, 100));
        engine.process(controls(&[22, 40], 0, 200));
        let snapshot = serde_json::to_value(engine.snapshot()).unwrap();
        assert_eq!(snapshot["type"], "snapshot");
        let pads = snapshot["held_pads"].as_array().unwrap();
        assert_eq!(pads.len(), 16);
        assert_eq!(pads.iter().filter(|held| **held == true).count(), 2);
        assert_eq!(pads[12], true); // Grid index 12 is physical pad 1.
        assert_eq!(pads[3], true);
        let buttons = snapshot["held_buttons"].as_array().unwrap();
        assert_eq!(buttons.len(), 41);
        assert_eq!(buttons.iter().filter(|held| **held == true).count(), 2);
        assert_eq!(buttons[22], true);
        assert_eq!(buttons[40], true);
        assert_eq!(snapshot["encoder_value"], 65);
        assert_eq!(snapshot["strip_value"], 127);
        assert_eq!(snapshot["strip_touched"], true);

        engine.process(pad(12, PadEventType::NoteOff, 0));
        engine.process(controls(&[40], 0, 0));
        let snapshot = serde_json::to_value(engine.snapshot()).unwrap();
        assert_eq!(snapshot["held_pads"][12], false);
        assert_eq!(snapshot["held_pads"][3], true);
        assert_eq!(snapshot["held_buttons"][22], false);
        assert_eq!(snapshot["held_buttons"][40], true);
        assert_eq!(snapshot["strip_value"], 127); // Release holds the last value.
        assert_eq!(snapshot["strip_touched"], false);

        engine.panic();
        let snapshot = serde_json::to_value(engine.snapshot()).unwrap();
        assert!(
            snapshot["held_pads"]
                .as_array()
                .unwrap()
                .iter()
                .all(|held| *held == false)
        );
        assert!(
            snapshot["held_buttons"]
                .as_array()
                .unwrap()
                .iter()
                .all(|held| *held == false)
        );
        assert_eq!(snapshot["strip_touched"], false);
        engine.set_observing(true);
        assert!(matches!(
            engine.process(pad(12, PadEventType::NoteOn, 2048)).events[0],
            Event::Pad {
                pad: 1,
                pressed: true,
                ..
            }
        ));
    }

    #[test]
    fn hidden_configuration_still_reports_settings_and_resets_snapshot_state() {
        let mut engine = Engine::new(Settings {
            encoder_mode: "absolute".into(),
            ..Settings::default()
        });
        engine.set_observing(false);
        engine.process(pad(12, PadEventType::NoteOn, 2048));
        engine.process(controls(&[22], 0, 200));
        engine.process(controls(&[22], 3, 200));
        let snapshot = serde_json::to_value(engine.snapshot()).unwrap();
        assert_eq!(snapshot["encoder_value"], 67);
        let mut settings = engine.settings.clone();
        settings.encoder_initial = 40;
        settings.notemaps[12] = 60;
        let effects = engine.configure(settings);
        assert_eq!(effects.events.len(), 1);
        assert!(
            matches!(&effects.events[0], Event::Configured { settings } if settings.encoder_initial == 40)
        );
        assert!(effects.midi.contains(&[0x80, 36, 0]));
        let snapshot = serde_json::to_value(engine.snapshot()).unwrap();
        assert_eq!(snapshot["encoder_value"], 40);
        assert_eq!(snapshot["held_pads"][12], false);
        assert_eq!(snapshot["held_buttons"][22], false);
        assert_eq!(snapshot["strip_touched"], false);
    }

    #[test]
    fn buttons_emit_only_on_edges_including_encoder_touch() {
        let mut engine = Engine::new(Settings::default());
        assert_eq!(
            engine.process(controls(&[22, 40], 0, 0)).midi,
            vec![[0xb0, 42, 127], [0xb0, 60, 127]]
        );
        assert!(engine.process(controls(&[22, 40], 0, 0)).midi.is_empty());
        assert_eq!(
            engine.process(controls(&[], 0, 0)).midi,
            vec![[0xb0, 42, 0], [0xb0, 60, 0]]
        );
    }

    #[test]
    fn relative_encoder_has_baseline_and_wraps_both_directions() {
        let mut engine = Engine::new(Settings::default());
        assert!(engine.process(controls(&[], 15, 0)).midi.is_empty());
        assert_eq!(
            engine.process(controls(&[], 0, 0)).midi,
            vec![[0xb0, 1, 65]]
        );
        assert_eq!(
            engine.process(controls(&[], 15, 0)).midi,
            vec![[0xb0, 1, 63]]
        );
        assert_eq!(engine.process(controls(&[], 1, 0)).midi.len(), 2);
    }

    #[test]
    fn absolute_encoder_starts_at_64_and_clamps() {
        let mut engine = Engine::new(Settings {
            encoder_mode: "absolute".into(),
            ..Settings::default()
        });
        engine.process(controls(&[], 0, 0));
        assert_eq!(
            engine.process(controls(&[], 1, 0)).midi,
            vec![[0xb0, 1, 65]]
        );
        for index in 2..100 {
            engine.process(controls(&[], index % 16, 0));
        }
        assert_eq!(engine.encoder_absolute, 127);
        for index in (0..200).rev() {
            engine.process(controls(&[], index % 16, 0));
        }
        assert_eq!(engine.encoder_absolute, 0);
    }

    #[test]
    fn relative_encoder_formats_step_and_inversion_are_consistent() {
        for (format, positive, negative) in [
            ("offset", 65, 63),
            ("twos_complement", 1, 127),
            ("sign_magnitude", 1, 65),
        ] {
            for invert in [false, true] {
                let mut engine = Engine::new(Settings {
                    encoder_relative_format: format.into(),
                    encoder_step: 3,
                    encoder_invert: invert,
                    ..Settings::default()
                });
                engine.process(controls(&[], 15, 0));
                let clockwise = engine.process(controls(&[], 0, 0));
                assert_eq!(
                    clockwise.midi,
                    vec![[0xb0, 1, if invert { negative } else { positive }]; 3]
                );
                assert!(
                    matches!(clockwise.events[0], Event::Encoder { delta, .. } if delta == if invert { -3 } else { 3 })
                );
                assert_eq!(
                    engine.process(controls(&[], 15, 0)).midi,
                    vec![[0xb0, 1, if invert { positive } else { negative }]; 3]
                );
            }
        }
    }

    #[test]
    fn maximum_inverted_step_does_not_overflow() {
        let mut engine = Engine::new(Settings {
            encoder_step: 16,
            encoder_invert: true,
            ..Settings::default()
        });
        engine.process(controls(&[], 0, 0));
        let effects = engine.process(controls(&[], 8, 0));
        assert_eq!(effects.midi, vec![[0xb0, 1, 65]; 128]);
        assert!(matches!(
            effects.events[0],
            Event::Encoder { delta: 128, .. }
        ));
    }

    #[test]
    fn absolute_encoder_respects_custom_range_initial_step_and_invert() {
        let mut engine = Engine::new(Settings {
            encoder_mode: "absolute".into(),
            encoder_min: 40,
            encoder_max: 70,
            encoder_initial: 50,
            encoder_step: 8,
            encoder_invert: true,
            ..Settings::default()
        });
        engine.process(controls(&[], 15, 0));
        assert_eq!(
            engine.process(controls(&[], 0, 0)).midi,
            vec![[0xb0, 1, 42]]
        );
        assert_eq!(
            engine.process(controls(&[], 1, 0)).midi,
            vec![[0xb0, 1, 40]]
        );
        assert_eq!(
            engine.process(controls(&[], 13, 0)).midi,
            vec![[0xb0, 1, 70]]
        );
    }

    #[test]
    fn encoder_config_reset_and_preservation_match_control_changes() {
        let mut engine = Engine::new(Settings {
            encoder_mode: "absolute".into(),
            encoder_initial: 50,
            ..Settings::default()
        });
        engine.process(controls(&[], 0, 0));
        engine.process(controls(&[], 1, 0));
        let mut settings = engine.settings.clone();
        settings.encoder_step = 4;
        settings.encoder_invert = true;
        settings.encoder_relative_format = "twos_complement".into();
        engine.configure(settings);
        assert_eq!(
            engine.process(controls(&[], 2, 0)).midi,
            vec![[0xb0, 1, 47]]
        );

        let mut settings = engine.settings.clone();
        settings.encoder_min = 20;
        settings.encoder_max = 80;
        settings.encoder_initial = 60;
        engine.configure(settings);
        assert_eq!(engine.encoder_absolute, 60);
        assert!(engine.process(controls(&[], 3, 0)).midi.is_empty());
        assert_eq!(
            engine.process(controls(&[], 4, 0)).midi,
            vec![[0xb0, 1, 56]]
        );
    }

    #[test]
    fn strip_endpoints_and_release_does_not_send_a_jump() {
        let mut engine = Engine::new(Settings::default());
        assert_eq!(engine.process(controls(&[], 0, 1)).midi, vec![[0xb0, 9, 0]]);
        assert_eq!(
            engine.process(controls(&[], 0, 200)).midi,
            vec![[0xb0, 9, 127]]
        );
        let release = engine.process(controls(&[], 0, 0));
        assert!(release.midi.is_empty());
        assert!(matches!(
            release.events[0],
            Event::Strip {
                touched: false,
                value: 127,
                ..
            }
        ));
        assert!(engine.process(controls(&[], 0, 0)).events.is_empty());
    }

    #[test]
    fn pitch_bend_uses_full_14_bit_range_and_channel() {
        let mut engine = Engine::new(Settings {
            touch_strip_mode: "pitch_bend".into(),
            midi_channel: 16,
            ..Settings::default()
        });
        assert_eq!(engine.process(controls(&[], 0, 1)).midi, vec![[0xef, 0, 0]]);
        assert_eq!(
            engine.process(controls(&[], 0, 200)).midi,
            vec![[0xef, 127, 127]]
        );
        assert!(engine.process(controls(&[], 0, 0)).midi.is_empty());
    }

    #[test]
    fn pitch_bend_resets_after_release_on_panic_channel_and_mode_changes() {
        let mut engine = Engine::new(Settings {
            touch_strip_mode: "pitch_bend".into(),
            midi_channel: 3,
            ..Settings::default()
        });
        engine.process(controls(&[], 0, 200));
        engine.process(controls(&[], 0, 0));
        assert_eq!(
            engine.release_all().midi,
            vec![[0xb2, 123, 0], [0xe2, 0, 64]]
        );
        assert_eq!(engine.release_all().midi, vec![[0xb2, 123, 0]]);

        engine.process(controls(&[], 0, 1));
        engine.process(controls(&[], 0, 0));
        let mut settings = engine.settings.clone();
        settings.midi_channel = 4;
        assert_eq!(
            engine.configure(settings).midi,
            vec![[0xb2, 123, 0], [0xe2, 0, 64]]
        );

        engine.process(controls(&[], 0, 200));
        engine.process(controls(&[], 0, 0));
        let mut settings = engine.settings.clone();
        settings.touch_strip_mode = "cc".into();
        assert_eq!(engine.configure(settings).midi, vec![[0xe3, 0, 64]]);
    }

    #[test]
    fn cleanup_releases_mapped_sustain_and_panic_stops_all_sound() {
        let mut engine = Engine::new(Settings {
            touch_strip_cc: 64,
            ..Settings::default()
        });
        engine.process(controls(&[], 0, 200));
        engine.process(controls(&[], 0, 0));
        let mut settings = engine.settings.clone();
        settings.midi_channel = 2;
        assert_eq!(
            engine.configure(settings).midi,
            vec![[0xb0, 64, 0], [0xb0, 123, 0]]
        );
        assert_eq!(
            engine.panic().midi,
            vec![[0xb1, 123, 0], [0xb1, 64, 0], [0xb1, 120, 0]]
        );
        engine.process(controls(&[], 0, 200));
        let mut settings = engine.settings.clone();
        settings.touch_strip_cc = 9;
        assert_eq!(engine.configure(settings).midi, vec![[0xb1, 64, 0]]);
    }

    #[test]
    fn parsed_hid_reports_produce_midi_and_physical_pad_events() {
        let mut engine = Engine::new(Settings::default());
        let press = crate::input::parse_report(&[0x02, 12, 0x18, 0x00]).unwrap();
        let effects = engine.process(press);
        assert_eq!(effects.midi, vec![[0x90, 36, 64]]);
        assert!(matches!(
            effects.events[0],
            Event::Pad {
                pad: 1,
                pressed: true,
                note: 36,
                ..
            }
        ));
        let mut controls_report = [0x01, 0, 0, 0, 0, 0, 0, 15, 0, 0, 1];
        controls_report[3] = 1 << 6; // button22, Play
        assert_eq!(
            engine
                .process(crate::input::parse_report(&controls_report).unwrap())
                .midi,
            vec![[0xb0, 42, 127], [0xb0, 9, 0]]
        );
        controls_report[3] = 0;
        controls_report[7] = 0;
        controls_report[10] = 200;
        assert_eq!(
            engine
                .process(crate::input::parse_report(&controls_report).unwrap())
                .midi,
            vec![[0xb0, 42, 0], [0xb0, 1, 65], [0xb0, 9, 127]]
        );
        assert_eq!(
            engine.release_all().midi,
            vec![[0x80, 36, 0], [0xb0, 123, 0]]
        );
    }

    #[test]
    fn note_edges_are_deduplicated_and_remap_releases_old_notes_and_channel() {
        let mut engine = Engine::new(Settings::default());
        assert_eq!(
            engine.process(pad(12, PadEventType::NoteOn, 2048)).midi,
            vec![[0x90, 36, 64]]
        );
        assert!(
            engine
                .process(pad(12, PadEventType::PressOn, 2048))
                .midi
                .is_empty()
        );
        let mut settings = engine.settings.clone();
        settings.notemaps[12] = 60;
        settings.midi_channel = 2;
        assert_eq!(
            engine.configure(settings).midi,
            vec![[0x80, 36, 0], [0xb0, 123, 0]]
        );
        assert_eq!(
            engine.process(pad(12, PadEventType::NoteOn, 2048)).midi,
            vec![[0x91, 60, 64]]
        );
        assert_eq!(
            engine.release_all().midi,
            vec![[0x81, 60, 0], [0xb1, 123, 0]]
        );
    }

    #[test]
    fn color_update_keeps_held_notes_and_repaints() {
        let mut engine = Engine::new(Settings::default());
        engine.process(pad(0, PadEventType::NoteOn, 4095));
        let mut settings = engine.settings.clone();
        settings.pad_colors[0] = 1;
        assert!(engine.configure(settings).midi.is_empty());
        let mut lights = Lights::new();
        engine.paint(&mut lights);
        assert_eq!(lights.get_pad(0), (PadColors::Red, Brightness::Bright));
        assert_eq!(lights.get_pad(1), (PadColors::Blue, Brightness::Dim));
    }

    #[test]
    fn aftertouch_is_optional_and_never_opens_a_note() {
        let mut engine = Engine::new(Settings::default());
        engine.process(pad(0, PadEventType::NoteOn, 32));
        assert!(
            engine
                .process(pad(0, PadEventType::Aftertouch, 2048))
                .midi
                .is_empty()
        );
        engine.settings.poly_aftertouch = true;
        assert_eq!(
            engine.process(pad(0, PadEventType::Aftertouch, 2048)).midi,
            vec![[0xa0, 48, 64]]
        );
        engine.release_all();
        assert!(
            engine
                .process(pad(0, PadEventType::Aftertouch, 2048))
                .midi
                .is_empty()
        );
        assert!(
            engine
                .process(pad(0, PadEventType::PressOn, 0))
                .midi
                .is_empty()
        );
    }
}
