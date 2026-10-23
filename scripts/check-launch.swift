// macOS GUI smoke check: swift scripts/check-launch.swift "dist/Mikro MIDI.app"
// Uses a temporary, separately identified app in preview mode: no MIDI or login registration.
import AppKit
import ApplicationServices
import CoreGraphics

@MainActor func pause(_ seconds: Double) async {
    try? await Task.sleep(for: .seconds(seconds))
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "MikroLaunchChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

func editorWindows(_ app: NSRunningApplication) -> [[String: Any]] {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier
            && ($0[kCGWindowLayer as String] as? Int) == 0
    }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

func control(_ root: AXUIElement, title: String, role: String, depth: Int = 0) -> AXUIElement? {
    if attribute(root, kAXRoleAttribute) as? String == role,
       [kAXTitleAttribute, kAXDescriptionAttribute].contains(where: { attribute(root, $0) as? String == title }) {
        return root
    }
    guard depth < 24 else { return nil }
    for child in attribute(root, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let match = control(child, title: title, role: role, depth: depth + 1) { return match }
    }
    return nil
}

func press(_ root: AXUIElement, title: String, role: String) throws {
    guard let control = control(root, title: title, role: role) else {
        throw NSError(domain: "MikroLaunchChecks", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot find \(title)"])
    }
    try check(AXUIElementPerformAction(control, kAXPressAction as CFString) == .success, "Cannot press \(title)")
}

func closeEditor(_ root: AXUIElement) throws {
    guard let window = (attribute(root, kAXWindowsAttribute) as? [AXUIElement])?.first,
          let close = attribute(window, kAXCloseButtonAttribute) else {
        throw NSError(domain: "MikroLaunchChecks", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot find window close button"])
    }
    try check(AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) == .success, "Cannot close editor")
}

@MainActor func openApp(_ url: URL, login: Bool) async throws -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--preview"]
    configuration.activates = !login
    if login {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
                                          targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        configuration.appleEvent = event
    }
    return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
}

@MainActor func quit(_ app: NSRunningApplication) async throws {
    try check(app.terminate(), "Could not request Quit")
    for _ in 0..<50 {
        if app.isTerminated { return }
        await pause(0.1)
    }
    throw NSError(domain: "MikroLaunchChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Quit did not terminate the app"])
}

let source = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist/Mikro MIDI.app")
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("MikroLaunchChecks-\(UUID().uuidString)")
let appURL = temporary.appendingPathComponent("Mikro MIDI Launch Checks.app")
let previousApp = NSWorkspace.shared.frontmostApplication
var runningApp: NSRunningApplication?
do {
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: appURL)
    let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
    var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
    plist["CFBundleIdentifier"] = "com.schneidermayer.mikro-midi.launch-checks.\(UUID().uuidString)"
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
    let signing = Process()
    signing.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    signing.arguments = ["--force", "--sign", "-", "--timestamp=none", appURL.path]
    try signing.run()
    signing.waitUntilExit()
    try check(signing.terminationStatus == 0, "Could not sign temporary test app")

    let app = try await openApp(appURL, login: true)
    runningApp = app
    for _ in 0..<30 {
        try check(!app.isTerminated, "Login launch unexpectedly quit")
        try check(!app.isActive, "Login launch took focus")
        try check(editorWindows(app).isEmpty, "Login launch displayed a window")
        await pause(0.1)
    }
    print("Login launch stayed running with no window or focus change.")

    let reopened = try await openApp(appURL, login: false)
    try check(reopened.processIdentifier == app.processIdentifier, "Reopening created another process")
    await pause(1)
    try check(editorWindows(app).count == 1, "Reopening did not show exactly one editor")
    _ = try await openApp(appURL, login: false)
    await pause(0.3)
    try check(editorWindows(app).count == 1, "Repeated reopening created another window")
    print("Opening a background instance shows one editor; repeated opening reuses it.")
    if AXIsProcessTrusted() {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        try press(root, title: "Setup", role: kAXButtonRole)
        await pause(0.3)
        try press(root, title: "Show in menu bar", role: kAXCheckBoxRole)
        await pause(0.3)
        try check(!app.isTerminated && app.activationPolicy == .regular, "Dock-only mode unexpectedly quit or lost its Dock entry")
        try closeEditor(root)
        await pause(0.3)
        try check(!app.isTerminated && editorWindows(app).isEmpty, "Closing the editor did not keep the app in the background")
        _ = try await openApp(appURL, login: false)
        await pause(0.5)
        try check(editorWindows(app).count == 1, "Closed editor did not reopen")
        try press(root, title: "Show in Dock", role: kAXCheckBoxRole)
        await pause(0.3)
        try check(!app.isTerminated && app.activationPolicy == .accessory, "Menu-bar-only mode did not hide the Dock entry")
        print("Dock-only and menu-bar-only modes stay reachable; closing and reopening preserves the editor.")
    } else {
        print("Accessibility checks skipped (permission not granted).")
    }
    try await quit(app)
    runningApp = nil

    let manual = try await openApp(appURL, login: false)
    runningApp = manual
    await pause(1)
    try check(editorWindows(manual).count == 1, "Normal launch did not show the controls")
    if AXIsProcessTrusted() {
        let root = AXUIElementCreateApplication(manual.processIdentifier)
        try press(root, title: "Setup", role: kAXButtonRole)
        await pause(0.3)
        try press(root, title: "Keep running when window closes", role: kAXCheckBoxRole)
        try closeEditor(root)
        await pause(0.5)
        try check(manual.isTerminated, "Closing the editor with background mode disabled did not quit")
        print("Closing the editor quits when background mode is disabled.")
    } else {
        try await quit(manual)
    }
    runningApp = nil
    print("Normal launch shows controls; termination respects the background preference.")
    try FileManager.default.removeItem(at: temporary)
    previousApp?.activate()
} catch {
    runningApp?.forceTerminate()
    try? FileManager.default.removeItem(at: temporary)
    previousApp?.activate()
    fputs("Launch checks failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
