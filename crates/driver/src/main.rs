mod engine;
mod input;
mod self_test;
mod settings;

use crate::engine::{Effects, Engine, Event};
use crate::input::parse_report;
use crate::settings::Settings;
use clap::Parser;
use config::Config;
use hidapi::{HidApi, HidDevice};
use maschine_library::lights::Lights;
use maschine_library::screen::Screen;
use midir::os::unix::VirtualOutput;
use midir::{MidiOutput, MidiOutputConnection};
use serde::Deserialize;
use std::error::Error;
use std::io::{self, BufRead, Write};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
    mpsc,
};
use std::time::{Duration, Instant};

type DriverResult<T> = Result<T, Box<dyn Error>>;
const DEVICE_NAME: &str = "Maschine Mikro MK3";

#[derive(Parser, Debug)]
#[clap(name = "Mikro MIDI", version = env!("CARGO_PKG_VERSION"), author = env!("CARGO_PKG_AUTHORS"))]
struct Args {
    #[clap(short, long, help = "Load settings from a JSON or TOML file")]
    config: Option<String>,
    #[clap(long, help = "Open the matching HID device without writes or MIDI")]
    probe: bool,
    #[clap(
        long,
        help = "Exit after this many seconds, releasing notes and resetting lights"
    )]
    duration: Option<u64>,
    #[clap(long, help = "Run the upstream LED and display self-test at startup")]
    self_test: bool,
    #[clap(
        long,
        help = "Write newline-delimited JSON events to stdout; read JSON commands from stdin"
    )]
    json: bool,
    #[clap(
        long,
        help = "Wait for the controller and reconnect after it is unplugged"
    )]
    wait: bool,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case", deny_unknown_fields)]
enum Command {
    Configure { settings: Box<Settings> },
    Panic {},
    Stop {},
}

struct Reporter {
    json: bool,
}

impl Reporter {
    fn emit(&self, event: &Event) -> io::Result<()> {
        let stdout = io::stdout();
        let mut stdout = stdout.lock();
        if self.json {
            serde_json::to_writer(&mut stdout, event)?;
            writeln!(stdout)?;
        } else {
            match event {
                Event::Status { message, .. } => writeln!(stdout, "{message}")?,
                Event::Error { .. } => {} // Error details are always written to stderr.
                other => writeln!(stdout, "{other:?}")?,
            }
        }
        stdout.flush()
    }

    fn status(&self, state: &str, message: impl Into<String>, port: &str) -> io::Result<()> {
        self.emit(&Event::Status {
            state: state.into(),
            message: message.into(),
            device: DEVICE_NAME.into(),
            port: port.into(),
        })
    }

    fn error(&self, message: impl Into<String>) -> io::Result<()> {
        let message = message.into();
        eprintln!("{message}");
        self.emit(&Event::Error { message })
    }
}

fn main() {
    let args = Args::parse();
    let reporter = Reporter { json: args.json };
    if let Err(error) = run(&args, &reporter) {
        let _ = reporter.error(error.to_string());
        std::process::exit(1);
    }
}

fn run(args: &Args, reporter: &Reporter) -> DriverResult<()> {
    let mut cfg = Config::builder();
    if let Some(path) = &args.config {
        cfg = cfg.add_source(config::File::with_name(path));
    }
    let settings = Settings::from_config(cfg.build()?)?;
    let mut api = HidApi::new()?;
    if args.probe {
        let _device = open_device(&mut api)?;
        reporter.status("connected", "Opened Maschine Mikro MK3 (USB 17cc:1700). Probe complete: no output reports sent and no MIDI source created.", &settings.port_name)?;
        return Ok(());
    }

    let running = Arc::new(AtomicBool::new(true));
    let signal_running = Arc::clone(&running);
    ctrlc::set_handler(move || signal_running.store(false, Ordering::Relaxed))?;
    // Keep this connection alive through USB disconnects, so the DAW keeps its routing.
    let output = MidiOutput::new(&settings.client_name)?;
    let mut port = output.create_virtual(&settings.port_name)?;
    let mut engine = Engine::new(settings);
    let commands = command_reader(args.json);
    let mut device: Option<HidDevice> = None;
    let mut lights = Lights::new();
    let started = Instant::now();
    let deadline = args.duration.map(Duration::from_secs);
    let mut next_attempt = Instant::now();
    let mut last_connection_error: Option<String> = None;
    let mut self_test_done = false;
    let mut buffer = [0; 64];
    reporter.status(
        "connecting",
        format!(
            "Waiting for {DEVICE_NAME}. MIDI source: {}",
            engine.settings.port_name
        ),
        &engine.settings.port_name,
    )?;

    let result: DriverResult<()> = (|| {
        while running.load(Ordering::Relaxed)
            && deadline.is_none_or(|limit| started.elapsed() < limit)
        {
            // Bound each batch so a busy UI cannot starve the HID reader.
            for command in commands.try_iter().take(100) {
                match command {
                    Err(message) => reporter.error(message)?,
                    Ok(Command::Stop {}) => {
                        running.store(false, Ordering::Relaxed);
                        break;
                    }
                    Ok(Command::Panic {}) => {
                        deliver(engine.panic(), &mut port, reporter)?;
                        engine.paint(&mut lights);
                        if let Some(hid) = &device
                            && let Err(error) = lights.write(hid)
                        {
                            reporter.error(format!("Could not update lights: {error}"))?;
                        }
                    }
                    Ok(Command::Configure { settings }) => {
                        if let Err(error) = settings.validate() {
                            reporter.error(format!("Configuration rejected: {error}"))?;
                            continue;
                        }
                        if settings.client_name != engine.settings.client_name
                            || settings.port_name != engine.settings.port_name
                        {
                            reporter.error("Configuration rejected: restart the driver to change client_name or port_name.")?;
                            continue;
                        }
                        deliver(engine.configure(*settings), &mut port, reporter)?;
                        engine.paint(&mut lights);
                        if let Some(hid) = &device
                            && let Err(error) = lights.write(hid)
                        {
                            reporter.error(format!("Could not update lights: {error}"))?;
                        }
                    }
                }
            }
            if !running.load(Ordering::Relaxed) {
                break;
            }

            if device.is_none() {
                if Instant::now() < next_attempt {
                    std::thread::sleep(Duration::from_millis(20));
                    continue;
                }
                let attempt: DriverResult<HidDevice> = (|| {
                    let hid = open_device(&mut api)?;
                    hid.set_blocking_mode(false)?;
                    if args.self_test && !self_test_done {
                        self_test::self_test(&hid, &mut Screen::new(), &mut lights)?;
                        self_test_done = true;
                    }
                    engine.paint(&mut lights);
                    lights.write(&hid)?;
                    Ok(hid)
                })();
                match attempt {
                    Ok(hid) => {
                        device = Some(hid);
                        last_connection_error = None;
                        reporter.status(
                            "connected",
                            format!(
                                "{DEVICE_NAME} connected. MIDI source: {}",
                                engine.settings.port_name
                            ),
                            &engine.settings.port_name,
                        )?;
                    }
                    Err(error) => {
                        let message = error.to_string();
                        if last_connection_error.as_ref() != Some(&message) {
                            reporter.status(
                                "disconnected",
                                &message,
                                &engine.settings.port_name,
                            )?;
                            reporter.error(&message)?;
                            last_connection_error = Some(message);
                        }
                        if !args.wait {
                            return Err(error);
                        }
                        next_attempt = Instant::now() + Duration::from_millis(500);
                        continue;
                    }
                }
            }

            let mut connection_error = None;
            if let Some(hid) = &device {
                match hid.read_timeout(&mut buffer, 10) {
                    Ok(size) => {
                        if let Some(report) = parse_report(&buffer[..size]) {
                            let effects = engine.process(report);
                            let repaint = effects.lights_changed;
                            deliver(effects, &mut port, reporter)?;
                            if repaint {
                                engine.paint(&mut lights);
                                if let Err(error) = lights.write(hid) {
                                    connection_error = Some(error.to_string());
                                }
                            }
                        }
                    }
                    Err(error) => connection_error = Some(error.to_string()),
                }
            }
            if let Some(error) = connection_error {
                if !running.load(Ordering::Relaxed) {
                    break;
                }
                // Note offs are sent using the old mappings before dropping the device.
                deliver(engine.panic(), &mut port, reporter)?;
                device = None;
                reporter.status(
                    "disconnected",
                    format!("Controller disconnected: {error}"),
                    &engine.settings.port_name,
                )?;
                reporter.error(&error)?;
                last_connection_error = Some(error.clone());
                if !args.wait {
                    return Err(error.into());
                }
                next_attempt = Instant::now() + Duration::from_millis(500);
            }
        }
        Ok(())
    })();

    // Attempt every cleanup even if MIDI, JSON output, or HID I/O failed.
    let midi_cleanup = deliver(engine.panic(), &mut port, reporter);
    if let Some(hid) = &device {
        lights.reset();
        if let Err(error) = lights.write(hid).or_else(|_| {
            std::thread::sleep(Duration::from_millis(10));
            lights.write(hid)
        }) {
            let _ = reporter.error(format!("Could not reset controller lights: {error}"));
        }
    }
    let status = reporter.status(
        "stopped",
        "Stopped. Held notes released and MIDI source closed.",
        &engine.settings.port_name,
    );
    result?;
    midi_cleanup?;
    status?;
    Ok(())
}

fn open_device(api: &mut HidApi) -> DriverResult<HidDevice> {
    api.refresh_devices()?;
    let info = api
        .device_list()
        .find(|info| info.vendor_id() == 0x17cc && info.product_id() == 0x1700)
        .ok_or("Maschine Mikro MK3 not found. Connect the controller to USB.")?;
    Ok(info.open_device(api)?)
}

fn deliver(
    effects: Effects,
    port: &mut MidiOutputConnection,
    reporter: &Reporter,
) -> DriverResult<()> {
    // Send all MIDI first, so a closed UI pipe cannot interrupt note cleanup.
    let mut midi_error = None;
    for bytes in effects.midi {
        if let Err(error) = port.send(&bytes) {
            midi_error = Some(error);
        }
    }
    for event in effects.events {
        reporter.emit(&event)?;
    }
    if let Some(error) = midi_error {
        return Err(error.into());
    }
    Ok(())
}

fn command_reader(stop_at_eof: bool) -> mpsc::Receiver<Result<Command, String>> {
    let (sender, receiver) = mpsc::channel();
    std::thread::spawn(move || {
        for line in io::stdin().lock().lines() {
            let command = match line {
                Ok(line) if line.trim().is_empty() => continue,
                Ok(line) => {
                    serde_json::from_str(&line).map_err(|error| format!("Invalid command: {error}"))
                }
                Err(error) => {
                    let _ = sender.send(Err(format!("Cannot read commands: {error}")));
                    break;
                }
            };
            if sender.send(command).is_err() {
                return;
            }
        }
        // The GUI owns stdin: if it exits, do not leave a hidden driver holding USB.
        if stop_at_eof {
            let _ = sender.send(Ok(Command::Stop {}));
        }
    });
    receiver
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn protocol_accepts_documented_commands_and_rejects_unknown_fields() {
        assert!(matches!(
            serde_json::from_str::<Command>(r#"{"command":"panic"}"#).unwrap(),
            Command::Panic {}
        ));
        assert!(matches!(
            serde_json::from_str::<Command>(r#"{"command":"stop"}"#).unwrap(),
            Command::Stop {}
        ));
        assert!(matches!(
            serde_json::from_str::<Command>(
                r#"{"command":"configure","settings":{"midi_channel":2}}"#
            )
            .unwrap(),
            Command::Configure { .. }
        ));
        assert!(serde_json::from_str::<Command>(r#"{"command":"unknown"}"#).is_err());
        assert!(
            serde_json::from_str::<Command>(r#"{"command":"panic","unexpected":true}"#).is_err()
        );
    }
}
