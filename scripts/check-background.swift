// swiftc -parse-as-library macos/MikroAppBehavior.swift macos/MikroLoginItem.swift macos/MikroModel.swift scripts/check-background.swift -o target/swift-checks/background
// target/swift-checks/background
import AppKit

// No window is ordered onscreen. Synthetic window state lets the actual delegate
// callbacks exercise occlusion/minimization without taking focus from the user.
@MainActor private final class VisibilityWindow: NSWindow {
    var reportedVisible = false
    var reportedMiniaturized = false
    var reportedOcclusion: NSWindow.OcclusionState = []
    override var isVisible: Bool { reportedVisible }
    override var isMiniaturized: Bool { reportedMiniaturized }
    override var occlusionState: NSWindow.OcclusionState { reportedOcclusion }

    func notifyOcclusion() {
        delegate?.windowDidChangeOcclusionState?(Notification(name: NSWindow.didChangeOcclusionStateNotification, object: self))
    }
}

@main struct BackgroundChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let model = MikroModel(preview: true)
        model.appBehavior.showInDock = false
        let window = VisibilityWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        model.appBehavior.attach(window: window)

        func emit(_ event: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: event)
            model.consumeOutput(String(decoding: data, as: UTF8.self) + "\n")
        }
        let padPress: [String: Any] = ["type": "pad", "pad": 2, "pressed": true, "velocity": 96, "note": 37]
        let buttonPress: [String: Any] = ["type": "button", "button": 4, "pressed": true, "cc": 24]
        let encoder: [String: Any] = ["type": "encoder", "value": 87, "delta": 1]
        let strip: [String: Any] = ["type": "strip", "value": 100, "touched": true]
        var heldPads = [Bool](repeating: false, count: 16)
        heldPads[0] = true
        heldPads[12] = true
        var heldButtons = [Bool](repeating: false, count: 41)
        heldButtons[40] = true
        let snapshot: [String: Any] = ["type": "snapshot", "held_pads": heldPads, "held_buttons": heldButtons,
                                       "encoder_value": 77, "strip_value": 63, "strip_touched": true]

        precondition(!model.appBehavior.editorVisible)
        for event in [padPress, buttonPress, encoder, strip, snapshot] { try emit(event) }
        precondition(model.activePads.isEmpty && model.activeButtons.isEmpty && model.velocities.isEmpty)
        precondition(model.activity.isEmpty && !model.stripTouched && !model.encoderHasActivity, "A never-opened editor must ignore all input feedback")
        try emit(["type": "status", "state": "connected", "message": "Connected in background"])
        try emit(["type": "error", "message": "Background driver error"])
        precondition(model.connected && model.statusMessage == "Background driver error")
        precondition(model.activity.count == 2, "Status and errors must remain available in the background")

        window.reportedVisible = true
        window.reportedOcclusion = .visible
        window.notifyOcclusion()
        precondition(model.appBehavior.editorVisible)
        try emit(padPress)
        precondition(model.activePads.isEmpty && model.activity.count == 2, "Opening must wait for a snapshot instead of accepting stale queued events")
        var malformedSnapshot = snapshot
        malformedSnapshot["held_pads"] = [true]
        try emit(malformedSnapshot)
        try emit(padPress)
        precondition(model.activePads.isEmpty, "A malformed snapshot must not unlock event delivery")
        try emit(snapshot)
        precondition(model.activePads == [1, 13] && model.activeButtons == [40], "Snapshot grid indices must map to physical pad numbers")
        precondition(model.encoderValue == 77 && model.stripValue == 63 && model.stripTouched)
        precondition(model.activity.count == 2, "Snapshots must not invent activity-log entries")

        model.glowEnabled = false
        try emit(padPress)
        try emit(buttonPress)
        try emit(encoder)
        try emit(strip)
        precondition(model.activePads.contains(2) && model.velocities[2] == 96)
        precondition(model.activeButtons.contains(4) && model.encoderHasActivity && model.stripValue == 100)
        try emit(["type": "pad", "pad": 2, "pressed": false, "velocity": 0])
        precondition(!model.activePads.contains(2), "Visible pad feedback must follow held state without a glow timer")

        window.reportedOcclusion = []
        window.notifyOcclusion()
        precondition(!model.appBehavior.editorVisible && model.activePads.isEmpty && model.activeButtons.isEmpty)
        precondition(model.velocities.isEmpty && !model.stripTouched && !model.encoderHasActivity)
        let activityCount = model.activity.count
        for event in [padPress, buttonPress, encoder, strip, snapshot] { try emit(event) }
        precondition(model.activePads.isEmpty && model.activity.count == activityCount, "Occlusion must suppress queued events and logging")

        window.reportedOcclusion = .visible
        window.reportedMiniaturized = true
        window.delegate?.windowDidMiniaturize?(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
        precondition(!model.appBehavior.editorVisible, "A minimized window must stay unobserved even if marked visible")
        window.reportedMiniaturized = false
        window.delegate?.windowDidDeminiaturize?(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        precondition(model.appBehavior.editorVisible)
        try emit(snapshot)
        precondition(model.activePads == [1, 13])
        window.notifyOcclusion()
        try emit(padPress)
        precondition(model.activePads.contains(2), "An unchanged visibility notification must not request another snapshot")

        window.delegate?.windowWillClose?(Notification(name: NSWindow.willCloseNotification, object: window))
        precondition(!model.appBehavior.editorVisible && model.activePads.isEmpty, "Closing must stop observation before the window disappears")
        try emit(padPress)
        precondition(model.activePads.isEmpty)
        window.reportedVisible = false
        window.notifyOcclusion()
        precondition(!model.appBehavior.editorVisible)

        print("Background checks passed: hidden input suppression, status/errors, snapshots, occlusion, minimization, close, held-pad feedback.")
    }
}
