//! Portable hidapi fallback. The shipped macOS app uses native callbacks instead.
use crate::{DriverEvent, DriverResult, open_device};
use hidapi::{HidApi, HidDevice};
use std::collections::VecDeque;
use std::sync::mpsc;
use std::time::{Duration, Instant};

pub(crate) type EventSender = mpsc::Sender<DriverEvent>;

pub(crate) struct DeviceLoop {
    api: HidApi,
    device: Option<HidDevice>,
    sender: EventSender,
    commands: mpsc::Receiver<DriverEvent>,
    pending: VecDeque<DriverEvent>,
    next_attempt: Instant,
    last_error: Option<String>,
}

impl DeviceLoop {
    pub(crate) fn new() -> DriverResult<Self> {
        let (sender, commands) = mpsc::channel();
        let mut driver = Self {
            api: HidApi::new()?,
            device: None,
            sender,
            commands,
            pending: VecDeque::new(),
            next_attempt: Instant::now(),
            last_error: None,
        };
        driver.connect();
        Ok(driver)
    }

    pub(crate) fn sender(&self) -> EventSender {
        self.sender.clone()
    }
    pub(crate) fn is_connected(&self) -> bool {
        self.device.is_some()
    }

    fn connect(&mut self) {
        match open_device(&mut self.api) {
            Ok(device) => {
                self.device = Some(device);
                self.last_error = None;
                self.pending.push_back(DriverEvent::Connected);
            }
            Err(error) => {
                let message = error.to_string();
                if self.last_error.as_ref() != Some(&message) {
                    self.pending
                        .push_back(DriverEvent::ConnectionError(message.clone()));
                    self.last_error = Some(message);
                }
                self.next_attempt = Instant::now() + Duration::from_millis(500);
            }
        }
    }

    pub(crate) fn next_event(
        &mut self,
        timeout: Option<Duration>,
    ) -> DriverResult<Option<DriverEvent>> {
        let deadline = timeout.map(|timeout| Instant::now() + timeout);
        loop {
            if let Some(event) = self.pending.pop_front() {
                return Ok(Some(event));
            }
            if let Ok(command) = self.commands.try_recv() {
                return Ok(Some(command));
            }
            let remaining =
                deadline.map(|deadline| deadline.saturating_duration_since(Instant::now()));
            if remaining == Some(Duration::ZERO) {
                return Ok(None);
            }
            if let Some(device) = &self.device {
                let mut data = [0; 64];
                let wait = remaining
                    .unwrap_or(Duration::from_millis(10))
                    .min(Duration::from_millis(10));
                match device.read_timeout(&mut data, wait.as_millis().max(1) as i32) {
                    Ok(0) => {}
                    Ok(len) => return Ok(Some(DriverEvent::Report { data, len })),
                    Err(error) => {
                        self.disconnect();
                        return Ok(Some(DriverEvent::Disconnected(error.to_string())));
                    }
                }
            } else {
                let until_retry = self.next_attempt.saturating_duration_since(Instant::now());
                if until_retry.is_zero() {
                    self.connect();
                    continue;
                }
                let wait = remaining.map_or(until_retry, |remaining| remaining.min(until_retry));
                if let Ok(command) = self.commands.recv_timeout(wait) {
                    return Ok(Some(command));
                }
            }
        }
    }

    pub(crate) fn write(&self, report: &[u8]) -> DriverResult<()> {
        self.device
            .as_ref()
            .ok_or("Controller disconnected")?
            .write(report)?;
        Ok(())
    }

    pub(crate) fn disconnect(&mut self) {
        self.device = None;
        self.next_attempt = Instant::now() + Duration::from_millis(500);
    }
}
