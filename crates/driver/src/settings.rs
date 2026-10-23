use serde::{Deserialize, Serialize};

/// Arrays follow the device report order: top row first, left to right.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct Settings {
    pub notemaps: Vec<u8>,
    pub client_name: String,
    pub port_name: String,
    pub pad_colors: Vec<u8>,
    pub pad_idle_brightness: u8,
    pub pad_active_brightness: u8,
    pub midi_channel: u8,
    pub button_ccs: Vec<u8>,
    pub encoder_cc: u8,
    pub encoder_mode: String,
    pub encoder_step: u8,
    pub encoder_invert: bool,
    pub encoder_relative_format: String,
    pub encoder_min: u8,
    pub encoder_max: u8,
    pub encoder_initial: u8,
    pub touch_strip_cc: u8,
    pub touch_strip_mode: String,
    pub poly_aftertouch: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            notemaps: vec![
                48, 49, 50, 51, 44, 45, 46, 47, 40, 41, 42, 43, 36, 37, 38, 39,
            ],
            client_name: "Mikro MIDI".into(),
            port_name: "Mikro MIDI".into(),
            pad_colors: vec![11, 11, 11, 11, 10, 10, 10, 10, 7, 7, 7, 7, 3, 3, 3, 3],
            pad_idle_brightness: 1,
            pad_active_brightness: 3,
            midi_channel: 1,
            button_ccs: (20..=60).collect(),
            encoder_cc: 1,
            encoder_mode: "relative".into(),
            encoder_step: 1,
            encoder_invert: false,
            encoder_relative_format: "offset".into(),
            encoder_min: 0,
            encoder_max: 127,
            encoder_initial: 64,
            touch_strip_cc: 9,
            touch_strip_mode: "cc".into(),
            poly_aftertouch: false,
        }
    }
}

impl Settings {
    pub(crate) fn from_config(config: config::Config) -> Result<Self, Box<dyn std::error::Error>> {
        // config's typed deserializer coerces strings and fractional numbers.
        // Preserve source types so files follow the same strict schema as stdin.
        let value = config.try_deserialize::<serde_json::Value>()?;
        let settings: Self = serde_json::from_value(value)?;
        settings.validate()?;
        Ok(settings)
    }

    pub(crate) fn validate(&self) -> Result<(), String> {
        for (name, values, length, max) in [
            ("notemaps", &self.notemaps, 16, 127),
            ("pad_colors", &self.pad_colors, 16, 17),
            ("button_ccs", &self.button_ccs, 41, 127),
        ] {
            if values.len() != length {
                return Err(format!("{name} must contain exactly {length} values"));
            }
            if values.iter().any(|value| *value > max) {
                return Err(format!("{name} values must be between 0 and {max}"));
            }
        }
        if !(1..=16).contains(&self.midi_channel) {
            return Err("midi_channel must be between 1 and 16".into());
        }
        if self.pad_idle_brightness > 3 || self.pad_active_brightness > 3 {
            return Err("Pad brightness must be between 0 and 3".into());
        }
        if self.encoder_cc > 127 || self.touch_strip_cc > 127 {
            return Err("MIDI CC numbers must be between 0 and 127".into());
        }
        if !matches!(self.encoder_mode.as_str(), "relative" | "absolute") {
            return Err("encoder_mode must be 'relative' or 'absolute'".into());
        }
        if !(1..=16).contains(&self.encoder_step) {
            return Err("encoder_step must be between 1 and 16".into());
        }
        if !matches!(
            self.encoder_relative_format.as_str(),
            "offset" | "twos_complement" | "sign_magnitude"
        ) {
            return Err(
                "encoder_relative_format must be 'offset', 'twos_complement', or 'sign_magnitude'"
                    .into(),
            );
        }
        if self.encoder_max > 127
            || self.encoder_min >= self.encoder_max
            || !(self.encoder_min..=self.encoder_max).contains(&self.encoder_initial)
        {
            return Err("Encoder range must satisfy 0 <= encoder_min < encoder_max <= 127, with encoder_initial inside that range".into());
        }
        if !matches!(self.touch_strip_mode.as_str(), "cc" | "pitch_bend") {
            return Err("touch_strip_mode must be 'cc' or 'pitch_bend'".into());
        }
        for (name, value) in [
            ("client_name", &self.client_name),
            ("port_name", &self.port_name),
        ] {
            if value.trim().is_empty() || value.contains('\0') {
                return Err(format!(
                    "{name} must be nonempty and contain no NUL characters"
                ));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::Settings;
    use config::{Config, File, FileFormat};

    #[test]
    fn json_and_toml_preserve_defaults() {
        for (source, format) in [
            ("port_name = 'My drum pads'", FileFormat::Toml),
            (r#"{"port_name":"My drum pads"}"#, FileFormat::Json),
        ] {
            let settings = Settings::from_config(
                Config::builder()
                    .add_source(File::from_str(source, format))
                    .build()
                    .unwrap(),
            )
            .unwrap();
            settings.validate().unwrap();
            assert_eq!(settings.port_name, "My drum pads");
            assert_eq!(settings.notemaps, Settings::default().notemaps);
        }
    }

    #[test]
    fn rejects_wrong_lengths_ranges_modes_and_names() {
        let bad_configs = [
            r#"{"notemaps":[1]}"#,
            r#"{"pad_colors":[1]}"#,
            r#"{"button_ccs":[1]}"#,
            r#"{"midi_channel":0}"#,
            r#"{"midi_channel":17}"#,
            r#"{"pad_idle_brightness":4}"#,
            r#"{"pad_active_brightness":4}"#,
            r#"{"encoder_cc":128}"#,
            r#"{"touch_strip_cc":128}"#,
            r#"{"encoder_mode":"other"}"#,
            r#"{"encoder_step":0}"#,
            r#"{"encoder_step":17}"#,
            r#"{"encoder_relative_format":"other"}"#,
            r#"{"encoder_min":127}"#,
            r#"{"encoder_min":70,"encoder_max":60}"#,
            r#"{"encoder_max":128}"#,
            r#"{"encoder_min":65}"#,
            r#"{"encoder_max":63}"#,
            r#"{"encoder_initial":128}"#,
            r#"{"touch_strip_mode":"other"}"#,
            r#"{"client_name":"  "}"#,
            r#"{"port_name":""}"#,
        ];
        for json in bad_configs {
            let settings: Settings = serde_json::from_str(json).unwrap();
            assert!(settings.validate().is_err(), "accepted {json}");
        }
        for (key, length, value) in [
            ("notemaps", 16, 128),
            ("pad_colors", 16, 18),
            ("button_ccs", 41, 128),
        ] {
            let mut json = serde_json::json!({});
            json[key] = serde_json::json!(vec![value; length]);
            assert!(
                serde_json::from_value::<Settings>(json)
                    .unwrap()
                    .validate()
                    .is_err()
            );
        }
        assert!(serde_json::from_str::<Settings>(r#"{"midi_channel":-1}"#).is_err());
        assert!(serde_json::from_str::<Settings>(r#"{"unknown_option":true}"#).is_err());
    }

    #[test]
    fn defaults_are_valid_and_pad_numbers_ascend_from_bottom_left() {
        let settings = Settings::default();
        settings.validate().unwrap();
        assert_eq!(settings.notemaps[12], 36);
        assert_eq!(settings.notemaps[3], 51);
        assert_eq!(settings.button_ccs, (20..=60).collect::<Vec<_>>());
        assert_eq!(settings.encoder_step, 1);
        assert!(!settings.encoder_invert);
        assert_eq!(settings.encoder_relative_format, "offset");
        assert_eq!(
            (
                settings.encoder_min,
                settings.encoder_max,
                settings.encoder_initial
            ),
            (0, 127, 64)
        );
        assert_eq!(
            serde_json::from_str::<Settings>(&serde_json::to_string(&settings).unwrap()).unwrap(),
            settings
        );
    }

    #[test]
    fn encoder_range_accepts_endpoints_and_legacy_configs_gain_defaults() {
        let mut settings: Settings =
            serde_json::from_str(r#"{"encoder_mode":"absolute","encoder_cc":71}"#).unwrap();
        assert_eq!(settings.encoder_step, 1);
        assert_eq!(settings.encoder_initial, 64);
        settings.encoder_min = 10;
        settings.encoder_max = 20;
        settings.encoder_initial = 10;
        settings.validate().unwrap();
        settings.encoder_initial = 20;
        settings.validate().unwrap();
        assert!(serde_json::from_str::<Settings>(r#"{"encoder_invert":"true"}"#).is_err());
    }

    #[test]
    fn configuration_files_reject_fractional_and_string_numbers() {
        for (source, format) in [
            ("midi_channel = 1.5", FileFormat::Toml),
            ("midi_channel = '2'", FileFormat::Toml),
            (r#"{"encoder_cc":1.5}"#, FileFormat::Json),
            (r#"{"encoder_cc":"2"}"#, FileFormat::Json),
        ] {
            let result = Settings::from_config(
                Config::builder()
                    .add_source(File::from_str(source, format))
                    .build()
                    .unwrap(),
            );
            assert!(result.is_err(), "accepted {source}");
        }
    }
}
