//! IOKit callbacks and commands share the owning thread's run loop. No HID
//! handles cross threads, and an absent controller requires no polling timer.

use crate::{DriverEvent, DriverResult};
use core_foundation_sys::base::{CFIndex, CFRelease, CFRetain, CFTypeRef};
use core_foundation_sys::dictionary::{
    CFDictionaryCreate, CFDictionaryRef, kCFTypeDictionaryKeyCallBacks,
    kCFTypeDictionaryValueCallBacks,
};
use core_foundation_sys::number::{CFNumberCreate, kCFNumberSInt32Type};
use core_foundation_sys::runloop::*;
use core_foundation_sys::set::{CFSetGetCount, CFSetGetValues, CFSetRef};
use core_foundation_sys::string::{CFStringCreateWithCString, CFStringRef, kCFStringEncodingUTF8};
use std::cell::{Cell, RefCell};
use std::collections::VecDeque;
use std::ffi::c_void;
use std::ptr;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, mpsc};
use std::time::{Duration, Instant};

type HidRef = *const c_void;
type DeviceCallback = unsafe extern "C" fn(*mut c_void, i32, *mut c_void, HidRef);
type ReportCallback =
    unsafe extern "C" fn(*mut c_void, i32, *mut c_void, u32, u32, *mut u8, CFIndex);
const INDEPENDENT_DEVICES: u32 = 0x08;
const SEIZE_DEVICE: u32 = 0x01;

#[link(name = "IOKit", kind = "framework")]
unsafe extern "C" {
    fn IOHIDManagerCreate(allocator: CFTypeRef, options: u32) -> HidRef;
    fn IOHIDManagerSetDeviceMatching(manager: HidRef, matching: CFDictionaryRef);
    fn IOHIDManagerRegisterDeviceMatchingCallback(
        manager: HidRef,
        callback: Option<DeviceCallback>,
        context: *mut c_void,
    );
    fn IOHIDManagerRegisterDeviceRemovalCallback(
        manager: HidRef,
        callback: Option<DeviceCallback>,
        context: *mut c_void,
    );
    fn IOHIDManagerScheduleWithRunLoop(manager: HidRef, run_loop: CFRunLoopRef, mode: CFStringRef);
    fn IOHIDManagerUnscheduleFromRunLoop(
        manager: HidRef,
        run_loop: CFRunLoopRef,
        mode: CFStringRef,
    );
    fn IOHIDManagerOpen(manager: HidRef, options: u32) -> i32;
    fn IOHIDManagerClose(manager: HidRef, options: u32) -> i32;
    fn IOHIDManagerCopyDevices(manager: HidRef) -> CFSetRef;
    fn IOHIDDeviceOpen(device: HidRef, options: u32) -> i32;
    fn IOHIDDeviceClose(device: HidRef, options: u32) -> i32;
    fn IOHIDDeviceScheduleWithRunLoop(device: HidRef, run_loop: CFRunLoopRef, mode: CFStringRef);
    fn IOHIDDeviceUnscheduleFromRunLoop(device: HidRef, run_loop: CFRunLoopRef, mode: CFStringRef);
    fn IOHIDDeviceRegisterInputReportCallback(
        device: HidRef,
        report: *mut u8,
        length: CFIndex,
        callback: Option<ReportCallback>,
        context: *mut c_void,
    );
    fn IOHIDDeviceSetReport(
        device: HidRef,
        report_type: u32,
        report_id: CFIndex,
        report: *const u8,
        length: CFIndex,
    ) -> i32;
}

struct OwnedCF(CFTypeRef);

impl OwnedCF {
    fn created(value: CFTypeRef, description: &str) -> DriverResult<Self> {
        if value.is_null() {
            Err(format!("Could not create {description}.").into())
        } else {
            Ok(Self(value))
        }
    }

    unsafe fn retained(value: CFTypeRef) -> Self {
        Self(unsafe { CFRetain(value) })
    }
}

impl Drop for OwnedCF {
    fn drop(&mut self) {
        unsafe { CFRelease(self.0) };
    }
}

// Only these retained CF objects are shared. Core Foundation permits source
// signalling and run-loop wakeup from other threads; no HID objects are shared.
struct WakeHandle {
    source: CFRunLoopSourceRef,
    run_loop: CFRunLoopRef,
    accepting: AtomicBool,
}

unsafe impl Send for WakeHandle {}
unsafe impl Sync for WakeHandle {}

impl Drop for WakeHandle {
    fn drop(&mut self) {
        unsafe {
            CFRelease(self.source.cast());
            CFRelease(self.run_loop.cast());
        }
    }
}

#[derive(Clone)]
pub(crate) struct EventSender {
    sender: mpsc::Sender<DriverEvent>,
    wake: Arc<WakeHandle>,
}

impl EventSender {
    pub(crate) fn send(&self, event: DriverEvent) -> Result<(), mpsc::SendError<DriverEvent>> {
        if !self.wake.accepting.load(Ordering::Acquire) {
            return Err(mpsc::SendError(event));
        }
        self.sender.send(event)?;
        // A signal remains pending if this races the transition into sleep.
        unsafe {
            CFRunLoopSourceSignal(self.wake.source);
            CFRunLoopWakeUp(self.wake.run_loop);
        }
        Ok(())
    }
}

struct LoopContext {
    run_loop: CFRunLoopRef,
    blocking: Cell<bool>,
}

impl LoopContext {
    fn event_ready(&self) {
        // During the nonblocking pass, allow both the command source and HID
        // port source to run. This avoids starving USB under a command flood.
        if self.blocking.get() {
            unsafe { CFRunLoopStop(self.run_loop) };
        }
    }
}

extern "C" fn command_ready(info: *const c_void) {
    unsafe { &*info.cast::<LoopContext>() }.event_ready();
}

struct EventPump {
    context: Rc<LoopContext>,
    sender: EventSender,
    receiver: mpsc::Receiver<DriverEvent>,
}

impl EventPump {
    fn new() -> DriverResult<Self> {
        let run_loop = unsafe { CFRunLoopGetCurrent() };
        let context = Rc::new(LoopContext {
            run_loop,
            blocking: Cell::new(false),
        });
        let mut source_context = CFRunLoopSourceContext {
            version: 0,
            info: Rc::as_ptr(&context).cast_mut().cast(),
            retain: None,
            release: None,
            copyDescription: None,
            equal: None,
            hash: None,
            schedule: None,
            cancel: None,
            perform: command_ready,
        };
        let source = unsafe { CFRunLoopSourceCreate(ptr::null(), 0, &mut source_context) };
        if source.is_null() {
            return Err("Could not create the driver command run-loop source.".into());
        }
        unsafe {
            CFRetain(run_loop.cast());
            CFRunLoopAddSource(run_loop, source, kCFRunLoopDefaultMode);
        }
        let (sender, receiver) = mpsc::channel();
        Ok(Self {
            context,
            sender: EventSender {
                sender,
                wake: Arc::new(WakeHandle {
                    source,
                    run_loop,
                    accepting: AtomicBool::new(true),
                }),
            },
            receiver,
        })
    }

    fn poll_sources(&self) {
        self.context.blocking.set(false);
        unsafe { CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0, 0) };
    }

    fn wait(&self, timeout: Option<Duration>) {
        self.context.blocking.set(true);
        unsafe {
            if let Some(timeout) = timeout {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout.as_secs_f64(), 1);
            } else {
                CFRunLoopRun();
            }
        }
        self.context.blocking.set(false);
    }
}

impl Drop for EventPump {
    fn drop(&mut self) {
        self.sender.wake.accepting.store(false, Ordering::Release);
        // Invalidate while the callback context is still alive. Concurrent
        // senders retain the CF objects; signalling an invalid source is safe.
        unsafe {
            CFRunLoopRemoveSource(
                self.context.run_loop,
                self.sender.wake.source,
                kCFRunLoopDefaultMode,
            );
            CFRunLoopSourceInvalidate(self.sender.wake.source);
        }
    }
}

enum NativeEvent {
    Matched(OwnedCF),
    Removed(OwnedCF),
    Report {
        generation: u64,
        data: [u8; 64],
        len: usize,
    },
    InputError {
        generation: u64,
        result: i32,
    },
}

struct CallbackState {
    loop_context: Rc<LoopContext>,
    events: RefCell<VecDeque<NativeEvent>>,
}

impl CallbackState {
    fn push(&self, event: NativeEvent) {
        self.events.borrow_mut().push_back(event);
        self.loop_context.event_ready();
    }
}

unsafe extern "C" fn matched(context: *mut c_void, result: i32, _: *mut c_void, device: HidRef) {
    if result == 0 && !device.is_null() {
        let state = unsafe { &*context.cast::<CallbackState>() };
        state.push(NativeEvent::Matched(unsafe { OwnedCF::retained(device) }));
    }
}

unsafe extern "C" fn removed(context: *mut c_void, _: i32, _: *mut c_void, device: HidRef) {
    if !device.is_null() {
        let state = unsafe { &*context.cast::<CallbackState>() };
        state.push(NativeEvent::Removed(unsafe { OwnedCF::retained(device) }));
    }
}

struct ReportContext {
    state: *const CallbackState,
    generation: u64,
}

fn copy_report(report_id: u32, bytes: &[u8]) -> Option<([u8; 64], usize)> {
    // Like hidapi's macOS backend, IOKit supplies the numbered report ID in
    // byte zero already. Do not prepend it a second time.
    if bytes.is_empty()
        || bytes.len() > 64
        || report_id > u32::from(u8::MAX)
        || (report_id != 0 && u32::from(bytes[0]) != report_id)
    {
        return None;
    }
    let mut data = [0; 64];
    data[..bytes.len()].copy_from_slice(bytes);
    Some((data, bytes.len()))
}

unsafe extern "C" fn input_report(
    context: *mut c_void,
    result: i32,
    _: *mut c_void,
    report_type: u32,
    report_id: u32,
    report: *mut u8,
    length: CFIndex,
) {
    let context = unsafe { &*context.cast::<ReportContext>() };
    let state = unsafe { &*context.state };
    if result != 0 {
        state.push(NativeEvent::InputError {
            generation: context.generation,
            result,
        });
    } else if report_type == 0 && !report.is_null() && (1..=64).contains(&length) {
        let bytes = unsafe { std::slice::from_raw_parts(report, length as usize) };
        if let Some((data, len)) = copy_report(report_id, bytes) {
            state.push(NativeEvent::Report {
                generation: context.generation,
                data,
                len,
            });
        }
    }
}

struct OpenedDevice {
    device: OwnedCF,
    run_loop: CFRunLoopRef,
    buffer: Box<[u8; 64]>,
    context: Box<ReportContext>,
}

impl Drop for OpenedDevice {
    fn drop(&mut self) {
        // Both callbacks and teardown run on the owner thread. Unregister and
        // unschedule before releasing either the report buffer or its context.
        unsafe {
            IOHIDDeviceRegisterInputReportCallback(
                self.device.0,
                self.buffer.as_mut_ptr(),
                self.buffer.len() as CFIndex,
                None,
                ptr::null_mut(),
            );
            IOHIDDeviceUnscheduleFromRunLoop(self.device.0, self.run_loop, kCFRunLoopDefaultMode);
            IOHIDDeviceClose(self.device.0, SEIZE_DEVICE);
        }
    }
}

struct Candidate {
    device: OwnedCF,
    attempted: bool,
}

pub(crate) struct DeviceLoop {
    manager: OwnedCF,
    state: Box<CallbackState>,
    pump: EventPump,
    candidates: Vec<Candidate>,
    active: Option<OpenedDevice>,
    pending: VecDeque<DriverEvent>,
    generation: u64,
    prefer_command: bool,
}

impl DeviceLoop {
    pub(crate) fn new() -> DriverResult<Self> {
        Self::matching(0x17cc, 0x1700)
    }

    fn matching(vendor_id: i32, product_id: i32) -> DriverResult<Self> {
        let pump = EventPump::new()?;
        let state = Box::new(CallbackState {
            loop_context: Rc::clone(&pump.context),
            events: RefCell::new(VecDeque::new()),
        });
        let manager = OwnedCF::created(
            unsafe { IOHIDManagerCreate(ptr::null(), INDEPENDENT_DEVICES) },
            "the HID manager",
        )?;
        let mut result = Self {
            manager,
            state,
            pump,
            candidates: Vec::new(),
            active: None,
            pending: VecDeque::new(),
            generation: 0,
            prefer_command: true,
        };
        let matching = matching_dictionary(vendor_id, product_id)?;
        let context = (&*result.state as *const CallbackState).cast_mut().cast();
        unsafe {
            IOHIDManagerSetDeviceMatching(result.manager.0, matching.0.cast());
            IOHIDManagerRegisterDeviceMatchingCallback(result.manager.0, Some(matched), context);
            IOHIDManagerRegisterDeviceRemovalCallback(result.manager.0, Some(removed), context);
            IOHIDManagerScheduleWithRunLoop(
                result.manager.0,
                result.pump.context.run_loop,
                kCFRunLoopDefaultMode,
            );
            let status = IOHIDManagerOpen(result.manager.0, 0);
            if status != 0 {
                return Err(format!(
                    "Could not observe USB devices (IOKit 0x{:08x}).",
                    status as u32
                )
                .into());
            }
            let devices = IOHIDManagerCopyDevices(result.manager.0);
            if !devices.is_null() {
                let devices = OwnedCF(devices.cast());
                let mut values = vec![ptr::null(); CFSetGetCount(devices.0.cast()) as usize];
                CFSetGetValues(devices.0.cast(), values.as_mut_ptr());
                for device in values {
                    result.remember(OwnedCF::retained(device));
                }
            }
        }
        let initial = result.try_connect().unwrap_or_else(|| {
            DriverEvent::ConnectionError(
                "Maschine Mikro MK3 not found. Connect the controller to USB.".into(),
            )
        });
        result.pending.push_back(initial);
        Ok(result)
    }

    pub(crate) fn sender(&self) -> EventSender {
        self.pump.sender.clone()
    }

    pub(crate) fn is_connected(&self) -> bool {
        self.active.is_some()
    }

    pub(crate) fn disconnect(&mut self) {
        self.active.take();
        self.state.events.borrow_mut().retain(|event| {
            !matches!(
                event,
                NativeEvent::Report { .. } | NativeEvent::InputError { .. }
            )
        });
    }

    pub(crate) fn write(&self, report: &[u8]) -> DriverResult<()> {
        let device = self.active.as_ref().ok_or("The Mikro is disconnected.")?;
        let (&report_id, _) = report
            .split_first()
            .ok_or("Cannot send an empty HID report.")?;
        let bytes = if report_id == 0 { &report[1..] } else { report };
        let length = CFIndex::try_from(bytes.len())?;
        let status = unsafe {
            IOHIDDeviceSetReport(
                device.device.0,
                1,
                CFIndex::from(report_id),
                bytes.as_ptr(),
                length,
            )
        };
        if status == 0 {
            Ok(())
        } else {
            Err(format!("Could not write to Mikro (IOKit 0x{:08x}).", status as u32).into())
        }
    }

    pub(crate) fn next_event(
        &mut self,
        timeout: Option<Duration>,
    ) -> DriverResult<Option<DriverEvent>> {
        let started = Instant::now();
        // Service native notifications even while stdin continuously queues commands.
        self.pump.poll_sources();
        loop {
            if let Some(event) = self.pending.pop_front() {
                return Ok(Some(event));
            }
            if self.prefer_command
                && let Ok(event) = self.pump.receiver.try_recv()
            {
                self.prefer_command = false;
                return Ok(Some(event));
            }
            if let Some(event) = self.take_native_event() {
                self.prefer_command = true;
                return Ok(Some(event));
            }
            if let Some(event) = self.try_connect() {
                self.prefer_command = true;
                return Ok(Some(event));
            }
            if let Ok(event) = self.pump.receiver.try_recv() {
                self.prefer_command = false;
                return Ok(Some(event));
            }
            let remaining = timeout.map(|limit| limit.saturating_sub(started.elapsed()));
            if remaining == Some(Duration::ZERO) {
                return Ok(None);
            }
            self.pump.wait(remaining);
        }
    }

    fn remember(&mut self, device: OwnedCF) {
        if !self
            .candidates
            .iter()
            .any(|candidate| candidate.device.0 == device.0)
        {
            self.candidates.push(Candidate {
                device,
                attempted: false,
            });
        }
    }

    fn try_connect(&mut self) -> Option<DriverEvent> {
        if self.active.is_some() {
            return None;
        }
        let mut error = None;
        for candidate in self
            .candidates
            .iter_mut()
            .filter(|candidate| !candidate.attempted)
        {
            candidate.attempted = true;
            let status = unsafe { IOHIDDeviceOpen(candidate.device.0, SEIZE_DEVICE) };
            if status != 0 {
                error = Some(DriverEvent::ConnectionError(format!(
                    "Could not open Mikro (IOKit 0x{:08x}). Close other controller software, then reconnect USB or restart the driver.",
                    status as u32,
                )));
                continue;
            }
            self.generation = self.generation.wrapping_add(1);
            let mut device = OpenedDevice {
                device: unsafe { OwnedCF::retained(candidate.device.0) },
                run_loop: self.pump.context.run_loop,
                buffer: Box::new([0; 64]),
                context: Box::new(ReportContext {
                    state: &*self.state,
                    generation: self.generation,
                }),
            };
            unsafe {
                IOHIDDeviceRegisterInputReportCallback(
                    device.device.0,
                    device.buffer.as_mut_ptr(),
                    device.buffer.len() as CFIndex,
                    Some(input_report),
                    (&mut *device.context as *mut ReportContext).cast(),
                );
                IOHIDDeviceScheduleWithRunLoop(
                    device.device.0,
                    device.run_loop,
                    kCFRunLoopDefaultMode,
                );
            }
            self.active = Some(device);
            return Some(DriverEvent::Connected);
        }
        error
    }

    fn take_native_event(&mut self) -> Option<DriverEvent> {
        loop {
            let event = self.state.events.borrow_mut().pop_front()?;
            match event {
                NativeEvent::Matched(device) => self.remember(device),
                NativeEvent::Removed(device) => {
                    self.candidates
                        .retain(|candidate| candidate.device.0 != device.0);
                    if self
                        .active
                        .as_ref()
                        .is_some_and(|active| active.device.0 == device.0)
                    {
                        self.disconnect();
                        return Some(DriverEvent::Disconnected("Controller disconnected.".into()));
                    }
                }
                NativeEvent::Report {
                    generation,
                    data,
                    len,
                } => {
                    if self
                        .active
                        .as_ref()
                        .is_some_and(|active| active.context.generation == generation)
                    {
                        return Some(DriverEvent::Report { data, len });
                    }
                }
                NativeEvent::InputError { generation, result } => {
                    if self
                        .active
                        .as_ref()
                        .is_some_and(|active| active.context.generation == generation)
                    {
                        self.disconnect();
                        return Some(DriverEvent::Disconnected(format!(
                            "Mikro input failed (IOKit 0x{:08x}).",
                            result as u32
                        )));
                    }
                }
            }
        }
    }
}

impl Drop for DeviceLoop {
    fn drop(&mut self) {
        self.disconnect();
        unsafe {
            IOHIDManagerRegisterDeviceMatchingCallback(self.manager.0, None, ptr::null_mut());
            IOHIDManagerRegisterDeviceRemovalCallback(self.manager.0, None, ptr::null_mut());
            IOHIDManagerUnscheduleFromRunLoop(
                self.manager.0,
                self.pump.context.run_loop,
                kCFRunLoopDefaultMode,
            );
            IOHIDManagerClose(self.manager.0, 0);
        }
    }
}

fn matching_dictionary(vendor_id: i32, product_id: i32) -> DriverResult<OwnedCF> {
    let mut keys = Vec::new();
    let mut values = Vec::new();
    for (key, value) in [(c"VendorID", vendor_id), (c"ProductID", product_id)] {
        keys.push(OwnedCF::created(
            unsafe {
                CFStringCreateWithCString(ptr::null(), key.as_ptr(), kCFStringEncodingUTF8).cast()
            },
            "a HID matching key",
        )?);
        values.push(OwnedCF::created(
            unsafe {
                CFNumberCreate(
                    ptr::null(),
                    kCFNumberSInt32Type,
                    (&value as *const i32).cast(),
                )
                .cast()
            },
            "a HID matching value",
        )?);
    }
    let key_refs = [keys[0].0, keys[1].0];
    let value_refs = [values[0].0, values[1].0];
    OwnedCF::created(
        unsafe {
            CFDictionaryCreate(
                ptr::null(),
                key_refs.as_ptr(),
                value_refs.as_ptr(),
                2,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks,
            )
            .cast()
        },
        "the HID matching dictionary",
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numbered_reports_keep_the_id_and_reject_invalid_lengths() {
        let (data, len) = copy_report(2, &[2, 15, 0x1a, 0xbc]).unwrap();
        assert_eq!(&data[..len], &[2, 15, 0x1a, 0xbc]);
        assert!(copy_report(2, &[1, 0, 0]).is_none());
        assert!(copy_report(2, &[]).is_none());
        assert!(copy_report(2, &[2; 65]).is_none());
        assert!(copy_report(256, &[0; 64]).is_none());
    }

    #[test]
    fn no_device_wait_blocks_until_a_command_without_a_timer() {
        // This impossible USB ID cannot seize a real user's Mikro during tests.
        let mut devices = DeviceLoop::matching(-1, -1).unwrap();
        assert!(matches!(
            devices.next_event(Some(Duration::ZERO)).unwrap(),
            Some(DriverEvent::ConnectionError(_))
        ));
        assert!(!devices.is_connected());
        let sender = devices.sender();
        let writer = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(30));
            sender
                .send(DriverEvent::ConnectionError("test wake".into()))
                .unwrap();
        });
        let started = Instant::now();
        assert!(
            matches!(devices.next_event(None).unwrap(), Some(DriverEvent::ConnectionError(message)) if message == "test wake")
        );
        assert!(started.elapsed() >= Duration::from_millis(20));
        assert!(started.elapsed() < Duration::from_secs(2));
        writer.join().unwrap();
    }

    #[test]
    fn no_device_wait_obeys_deadline_and_sender_rejects_after_teardown() {
        let mut devices = DeviceLoop::matching(-1, -1).unwrap();
        devices.next_event(Some(Duration::ZERO)).unwrap();
        let timeout = Duration::from_millis(30);
        let started = Instant::now();
        assert!(devices.next_event(Some(timeout)).unwrap().is_none());
        assert!(started.elapsed() >= timeout);
        let sender = devices.sender();
        drop(devices);
        assert!(
            sender
                .send(DriverEvent::ConnectionError("late".into()))
                .is_err()
        );
    }
}
