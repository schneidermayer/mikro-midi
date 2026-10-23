// Run with the app open: swift scripts/benchmark-tabs.swift
// Requires Accessibility access for your terminal. Only changes the selected page.
// Measures AX press-to-content-ready latency, including accessibility IPC overhead.
import Foundation
import AppKit
import ApplicationServices

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.schneidermayer.mikro-midi").first else {
    fputs("Open Mikro MIDI before running this benchmark.\n", stderr)
    exit(1)
}
let root = AXUIElementCreateApplication(app.processIdentifier)
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}
func find(_ element: AXUIElement, label: String, depth: Int = 0) -> AXUIElement? {
    if [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains(where: {
        attribute(element, $0) as? String == label
    }) { return element }
    guard depth < 20 else { return nil }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let match = find(child, label: label, depth: depth + 1) { return match }
    }
    return nil
}
let pages = [("Pads", "Select all"), ("Buttons", "39 BUTTON MAPPINGS"),
             ("Knob", "KNOB MAPPING"), ("Touch strip", "STRIP MAPPING"), ("Setup", "MIDI & HARDWARE")]
let buttons = pages.map { page -> AXUIElement in
    guard let button = find(root, label: page.0) else {
        fputs("Cannot find \(page.0). Check Accessibility permission.\n", stderr)
        exit(1)
    }
    return button
}
let rounds = max(1, Int(CommandLine.arguments.dropFirst().first ?? "3") ?? 3)
for round in 0..<rounds {
    for (index, page) in pages.enumerated() {
        let start = ProcessInfo.processInfo.systemUptime
        let result = AXUIElementPerformAction(buttons[index], kAXPressAction as CFString)
        let pressed = ProcessInfo.processInfo.systemUptime
        var ready = false
        while ProcessInfo.processInfo.systemUptime - start < 6 {
            if find(root, label: page.1) != nil { ready = true; break }
            Thread.sleep(forTimeInterval: 0.005)
        }
        let end = ProcessInfo.processInfo.systemUptime
        print(String(format: "round=%d tab=%@ press_ms=%.1f ready_ms=%.1f found=%@ status=%d",
                     round, page.0, (pressed - start) * 1000, (end - start) * 1000,
                     String(ready), result.rawValue))
        fflush(stdout)
        Thread.sleep(forTimeInterval: 0.08)
    }
}
