use maschine_library::controls::PadEventType;

#[derive(Debug)]
pub(crate) struct PadInput {
    pub index: usize,
    pub event: PadEventType,
    pub value: u16,
}

#[derive(Debug)]
pub(crate) enum InputReport {
    Buttons {
        pressed: [bool; 41],
        encoder: u8,
        slider: u8,
    },
    Pads(Vec<PadInput>),
}

/// Decode only bytes returned by HID. Ignore unsupported and incomplete data.
pub(crate) fn parse_report(bytes: &[u8]) -> Option<InputReport> {
    match bytes.first()? {
        0x01 if bytes.len() >= 11 => {
            let mut pressed = [false; 41];
            for (index, status) in pressed.iter_mut().enumerate() {
                *status = bytes[1 + index / 8] & (1 << (index % 8)) != 0;
            }
            Some(InputReport::Buttons {
                pressed,
                encoder: bytes[7],
                slider: bytes[10],
            })
        }
        0x02 => {
            let mut pads = Vec::new();
            for (position, triplet) in bytes[1..].as_chunks::<3>().0.iter().enumerate() {
                if position > 0 && *triplet == [0, 0, 0] {
                    break;
                }
                let index = usize::from(triplet[0]);
                if index >= 16 {
                    continue;
                }
                let Some(event) = num::FromPrimitive::from_u8(triplet[1] & 0xf0) else {
                    continue;
                };
                let value = (u16::from(triplet[1] & 0x0f) << 8) | u16::from(triplet[2]);
                pads.push(PadInput {
                    index,
                    event,
                    value,
                });
            }
            Some(InputReport::Pads(pads))
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::{InputReport, parse_report};
    use maschine_library::controls::PadEventType;

    #[test]
    fn short_and_unknown_reports_are_ignored() {
        assert!(parse_report(&[]).is_none());
        assert!(parse_report(&[0x01; 10]).is_none());
        assert!(parse_report(&[0xff; 64]).is_none());
    }

    #[test]
    fn decodes_complete_pad_and_ignores_incomplete_tail() {
        let Some(InputReport::Pads(pads)) = parse_report(&[0x02, 15, 0x1a, 0xbc, 1, 0x30]) else {
            panic!("expected pads");
        };
        assert_eq!(pads.len(), 1);
        assert_eq!(pads[0].index, 15);
        assert_eq!(pads[0].value, 0xabc);
        assert!(matches!(pads[0].event, PadEventType::NoteOn));
    }

    #[test]
    fn invalid_index_and_unknown_event_cannot_escape_parser() {
        let Some(InputReport::Pads(pads)) =
            parse_report(&[0x02, 255, 0x10, 1, 3, 0xf0, 1, 2, 0x30, 0])
        else {
            panic!("expected pads");
        };
        assert_eq!(pads.len(), 1);
        assert_eq!(pads[0].index, 2);
        assert!(matches!(pads[0].event, PadEventType::NoteOff));
    }

    #[test]
    fn reads_only_actual_returned_bytes() {
        let backing_buffer = [0x02, 1, 0x10, 0x80, 2, 0x10, 0xff];
        let Some(InputReport::Pads(pads)) = parse_report(&backing_buffer[..4]) else {
            panic!("expected pads");
        };
        assert_eq!(pads.len(), 1);
        assert_eq!(pads[0].index, 1);
    }
}
