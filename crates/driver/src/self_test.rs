use hidapi::{HidDevice, HidResult};
use maschine_library::font::Font;
use maschine_library::lights::{Brightness, Lights, PadColors};
use maschine_library::screen::Screen;
use std::{thread, time};

pub(crate) fn self_test(
    device: &HidDevice,
    screen: &mut Screen,
    lights: &mut Lights,
) -> HidResult<()> {
    for (position, digit) in [1, 3, 3, 7].into_iter().enumerate() {
        Font::write_digit(screen, 0, position * 32, digit, 4);
        screen.write(device)?;
        if position < 3 {
            thread::sleep(time::Duration::from_millis(100));
        }
    }

    let brightnesses = [Brightness::Bright, Brightness::Normal, Brightness::Dim];
    for i in 0..39 {
        let button = num::FromPrimitive::from_u32(i).unwrap();
        for brightness in brightnesses {
            lights.set_button(button, brightness);
            lights.write(device)?;
        }
    }
    for i in 0..16 {
        for brightness in brightnesses {
            let color: PadColors = num::FromPrimitive::from_usize(
                i + 1 + usize::from(brightness == Brightness::Bright),
            )
            .unwrap();
            lights.set_pad(i, color, brightness);
            lights.write(device)?;
        }
    }
    for i in 0..25 {
        for brightness in brightnesses {
            lights.set_slider(i, brightness);
            lights.write(device)?;
        }
    }
    lights.reset();
    lights.write(device)?;

    screen.reset();
    screen.write(device)?;

    Ok(())
}
