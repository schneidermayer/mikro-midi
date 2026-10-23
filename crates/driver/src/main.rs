#[cfg(target_os = "macos")]
#[path = "device_macos.rs"]
mod device;
#[cfg(not(target_os = "macos"))]
#[path = "device_polling.rs"]
mod device;
mod engine;
mod input;
mod self_test;
mod settings;

use crate::device::{DeviceLoop, EventSender};
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
use std::time::{Duration, Instant};

type DriverResult<T> = Result<T, Box<dyn Error>>;
type DriverCommand = Result<Command, String>;
const DEVICE_NAME: &str = "Maschine Mikro MK3";
#[derive(Debug)]
pub(crate) enum DriverEvent {
    Command(DriverCommand),
    Connected,
    Disconnected(String),
    Report { data: [u8; 64], len: usize },
    ConnectionError(String),
}

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
    #[clap(
        long,
        help = "Send status and errors only until UI observation is enabled"
    )]
    quiet_events: bool,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case", deny_unknown_fields)]
enum Command {
    Configure { settings: Box<Settings> },
    Observe { enabled: bool },
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
        if self.json {
            self.emit(&Event::Error { message })
        } else {
            eprintln!("{message}");
            Ok(())
        }
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
    if args.probe {
        let _device = open_device(&mut HidApi::new()?)?;
        reporter.status("connected", "Opened Maschine Mikro MK3 (USB 17cc:1700). Probe complete: no output reports sent and no MIDI source created.", &settings.port_name)?;
        return Ok(());
    }

    let mut device = DeviceLoop::new()?;
    let signal_sender = device.sender();
    ctrlc::set_handler(move || {
        let _ = signal_sender.send(DriverEvent::Command(Ok(Command::Stop {})));
    })?;
    // This connection outlives every USB connection: no MIDI heartbeat is needed.
    let output = MidiOutput::new(&settings.client_name)?;
    let mut port = output.create_virtual(&settings.port_name)?;
    let mut engine = Engine::new(settings);
    engine.set_observing(!args.quiet_events);
    let mut observing = !args.quiet_events;
    command_reader(args.json, device.sender());
    let mut lights = Lights::new();
    let mut last_lights = None;
    let deadline = args
        .duration
        .map(|seconds| Instant::now() + Duration::from_secs(seconds));
    let mut self_test_done = false;
    reporter.status(
        "connecting",
        format!(
            "Waiting for {DEVICE_NAME}. MIDI source: {}",
            engine.settings.port_name
        ),
        &engine.settings.port_name,
    )?;

    let result: DriverResult<()> = (|| {
        loop {
            let timeout = deadline.map(|end| end.saturating_duration_since(Instant::now()));
            if timeout == Some(Duration::ZERO) {
                break;
            }
            // On macOS this blocks in the native event loop until USB activity,
            // a command, a signal, or the explicitly requested duration expires.
            let Some(event) = device.next_event(timeout)? else {
                break;
            };
            let effects = match event {
                DriverEvent::Command(Err(message)) => {
                    reporter.error(message)?;
                    continue;
                }
                DriverEvent::Command(Ok(Command::Stop {})) => break,
                DriverEvent::Command(Ok(Command::Observe { enabled })) => {
                    observing = enabled;
                    engine.set_observing(enabled);
                    if enabled {
                        reporter.emit(&engine.snapshot())?;
                    }
                    continue;
                }
                DriverEvent::Command(Ok(Command::Panic {})) => engine.panic(),
                DriverEvent::Command(Ok(Command::Configure { settings })) => {
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
                    engine.configure(*settings)
                }
                DriverEvent::Connected => {
                    last_lights = None;
                    if args.self_test && !self_test_done {
                        if let Err(error) = self_test::self_test(
                            |report| device.write(report),
                            &mut Screen::new(),
                            &mut lights,
                        ) {
                            device.disconnect();
                            report_disconnected(
                                &mut engine,
                                &mut port,
                                reporter,
                                &error.to_string(),
                            )?;
                            if !args.wait {
                                return Err(error);
                            }
                            continue;
                        }
                        self_test_done = true;
                    }
                    engine.paint(&mut lights);
                    if let Err(error) = write_lights(&device, &lights, &mut last_lights) {
                        device.disconnect();
                        report_disconnected(&mut engine, &mut port, reporter, &error.to_string())?;
                        if !args.wait {
                            return Err(error);
                        }
                        continue;
                    }
                    reporter.status(
                        "connected",
                        format!(
                            "{DEVICE_NAME} connected. MIDI source: {}",
                            engine.settings.port_name
                        ),
                        &engine.settings.port_name,
                    )?;
                    if observing {
                        reporter.emit(&engine.snapshot())?;
                    }
                    continue;
                }
                DriverEvent::Disconnected(message) | DriverEvent::ConnectionError(message) => {
                    last_lights = None;
                    report_disconnected(&mut engine, &mut port, reporter, &message)?;
                    if !args.wait {
                        return Err(message.into());
                    }
                    continue;
                }
                DriverEvent::Report { data, len } => {
                    if !device.is_connected() {
                        continue;
                    }
                    let Some(report) = data.get(..len).and_then(parse_report) else {
                        continue;
                    };
                    engine.process(report)
                }
            };
            let repaint = effects.lights_changed;
            deliver(effects, &mut port, reporter)?;
            if repaint && device.is_connected() {
                engine.paint(&mut lights);
                if let Err(error) = write_lights(&device, &lights, &mut last_lights) {
                    device.disconnect();
                    last_lights = None;
                    report_disconnected(&mut engine, &mut port, reporter, &error.to_string())?;
                    if !args.wait {
                        return Err(error);
                    }
                }
            }
        }
        Ok(())
    })();

    // Attempt every cleanup even if MIDI, JSON output, or HID I/O failed.
    let midi_cleanup = deliver(engine.panic(), &mut port, reporter);
    if device.is_connected() {
        lights.reset();
        if let Err(error) = write_lights(&device, &lights, &mut last_lights) {
            let _ = reporter.error(format!("Could not reset controller lights: {error}"));
        }
    }
    device.disconnect();
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

fn write_lights(
    device: &DeviceLoop,
    lights: &Lights,
    previous: &mut Option<[u8; 81]>,
) -> DriverResult<()> {
    let report = lights.report();
    if previous.as_ref() != Some(&report) {
        device.write(&report)?;
        *previous = Some(report);
    }
    Ok(())
}

fn report_disconnected(
    engine: &mut Engine,
    port: &mut MidiOutputConnection,
    reporter: &Reporter,
    message: &str,
) -> DriverResult<()> {
    deliver(engine.panic(), port, reporter)?;
    reporter.status("disconnected", message, &engine.settings.port_name)?;
    reporter.error(message)?;
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

fn command_reader(stop_at_eof: bool, sender: EventSender) {
    std::thread::spawn(move || {
        read_commands(io::stdin().lock(), stop_at_eof, |command| {
            sender.send(DriverEvent::Command(command)).is_ok()
        });
    });
}

fn read_commands(
    input: impl BufRead,
    stop_at_eof: bool,
    mut send: impl FnMut(DriverCommand) -> bool,
) {
    for line in input.lines() {
        let command = match line {
            Ok(line) if line.trim().is_empty() => continue,
            Ok(line) => {
                serde_json::from_str(&line).map_err(|error| format!("Invalid command: {error}"))
            }
            Err(error) => {
                send(Err(format!("Cannot read commands: {error}")));
                break;
            }
        };
        if !send(command) {
            return;
        }
    }
    // The GUI owns stdin: if it exits, do not leave a hidden driver holding USB.
    if stop_at_eof {
        send(Ok(Command::Stop {}));
    }
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

    #[test]
    fn observe_protocol_requires_an_explicit_boolean() {
        assert!(matches!(
            serde_json::from_str::<Command>(r#"{"command":"observe","enabled":false}"#).unwrap(),
            Command::Observe { enabled: false }
        ));
        assert!(serde_json::from_str::<Command>(r#"{"command":"observe"}"#).is_err());
        assert!(
            serde_json::from_str::<Command>(r#"{"command":"observe","enabled":"false"}"#).is_err()
        );
    }

    #[test]
    fn commands_preserve_order_and_only_gui_eof_stops_the_driver() {
        let mut commands = Vec::new();
        read_commands(
            &b"{\"command\":\"panic\"}\n{\"command\":\"observe\",\"enabled\":true}\n"[..],
            true,
            |command| {
                commands.push(command);
                true
            },
        );
        assert!(matches!(commands[0], Ok(Command::Panic {})));
        assert!(matches!(
            commands[1],
            Ok(Command::Observe { enabled: true })
        ));
        assert!(matches!(commands[2], Ok(Command::Stop {})));
        assert_eq!(commands.len(), 3);
        let mut called = false;
        read_commands(&b""[..], false, |_| {
            called = true;
            true
        });
        assert!(!called);
    }
}
