import Foundation
import AppKit
import SwiftUI
import Observation

struct MikroSettings: Codable, Equatable {
    var notemaps = [48, 49, 50, 51, 44, 45, 46, 47, 40, 41, 42, 43, 36, 37, 38, 39]
    var pad_colors = [11, 11, 12, 12, 9, 9, 13, 13, 8, 8, 2, 2, 7, 7, 4, 4]
    var pad_idle_brightness = 1
    var pad_active_brightness = 3
    var midi_channel = 1
    var button_ccs = Array(20...60)
    var encoder_cc = 1
    var encoder_mode = "relative"
    var encoder_step = 1
    var encoder_invert = false
    var encoder_relative_format = "offset"
    var encoder_min = 0
    var encoder_max = 127
    var encoder_initial = 64
    var touch_strip_cc = 9
    var touch_strip_mode = "cc"
    var poly_aftertouch = false
    var client_name = "Mikro MIDI"
    var port_name = "Mikro MIDI"

    enum CodingKeys: String, CodingKey {
        case notemaps, pad_colors, pad_idle_brightness, pad_active_brightness, midi_channel, button_ccs
        case encoder_cc, encoder_mode, encoder_step, encoder_invert, encoder_relative_format, encoder_min, encoder_max, encoder_initial
        case touch_strip_cc, touch_strip_mode, poly_aftertouch, client_name, port_name
    }

    init() { }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Preserve older presets when new settings are added.
        notemaps = try c.decodeIfPresent([Int].self, forKey: .notemaps) ?? notemaps
        pad_colors = try c.decodeIfPresent([Int].self, forKey: .pad_colors) ?? pad_colors
        pad_idle_brightness = try c.decodeIfPresent(Int.self, forKey: .pad_idle_brightness) ?? pad_idle_brightness
        pad_active_brightness = try c.decodeIfPresent(Int.self, forKey: .pad_active_brightness) ?? pad_active_brightness
        midi_channel = try c.decodeIfPresent(Int.self, forKey: .midi_channel) ?? midi_channel
        button_ccs = try c.decodeIfPresent([Int].self, forKey: .button_ccs) ?? button_ccs
        encoder_cc = try c.decodeIfPresent(Int.self, forKey: .encoder_cc) ?? encoder_cc
        encoder_mode = try c.decodeIfPresent(String.self, forKey: .encoder_mode) ?? encoder_mode
        encoder_step = try c.decodeIfPresent(Int.self, forKey: .encoder_step) ?? encoder_step
        encoder_invert = try c.decodeIfPresent(Bool.self, forKey: .encoder_invert) ?? encoder_invert
        encoder_relative_format = try c.decodeIfPresent(String.self, forKey: .encoder_relative_format) ?? encoder_relative_format
        encoder_min = try c.decodeIfPresent(Int.self, forKey: .encoder_min) ?? encoder_min
        encoder_max = try c.decodeIfPresent(Int.self, forKey: .encoder_max) ?? encoder_max
        encoder_initial = try c.decodeIfPresent(Int.self, forKey: .encoder_initial) ?? encoder_initial
        touch_strip_cc = try c.decodeIfPresent(Int.self, forKey: .touch_strip_cc) ?? touch_strip_cc
        touch_strip_mode = try c.decodeIfPresent(String.self, forKey: .touch_strip_mode) ?? touch_strip_mode
        poly_aftertouch = try c.decodeIfPresent(Bool.self, forKey: .poly_aftertouch) ?? poly_aftertouch
        client_name = try c.decodeIfPresent(String.self, forKey: .client_name) ?? client_name
        port_name = try c.decodeIfPresent(String.self, forKey: .port_name) ?? port_name
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    func validated() throws -> MikroSettings {
        guard notemaps.count == 16, pad_colors.count == 16, button_ccs.count == 41,
              notemaps.allSatisfy({ (0...127).contains($0) }),
              pad_colors.allSatisfy({ (0...17).contains($0) }),
              button_ccs.allSatisfy({ (0...127).contains($0) }),
              (0...3).contains(pad_idle_brightness), (0...3).contains(pad_active_brightness),
              (1...16).contains(midi_channel), (0...127).contains(encoder_cc),
              (0...127).contains(touch_strip_cc), ["relative", "absolute"].contains(encoder_mode),
              (1...16).contains(encoder_step), ["offset", "twos_complement", "sign_magnitude"].contains(encoder_relative_format),
              (0...127).contains(encoder_min), (0...127).contains(encoder_max), encoder_min < encoder_max,
              (encoder_min...encoder_max).contains(encoder_initial),
              ["cc", "pitch_bend"].contains(touch_strip_mode),
              !client_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !port_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !client_name.contains("\0"), !port_name.contains("\0")
        else { throw NSError(domain: "Mikro MIDI", code: 1, userInfo: [NSLocalizedDescriptionKey: "This preset has invalid MIDI mappings or colors."]) }
        // Imported CLI presets must not rename the app’s live MIDI endpoint.
        var result = self
        result.client_name = "Mikro MIDI"
        result.port_name = "Mikro MIDI"
        return result
    }
}

enum Workspace: String, CaseIterable {
    case pads = "Pads", buttons = "Buttons", knob = "Knob", touchStrip = "Touch strip", setup = "Setup"
    var icon: String {
        switch self {
        case .pads: return "square.grid.3x3.fill"
        case .buttons: return "square.grid.2x2"
        case .knob: return "dial.medium"
        case .touchStrip: return "slider.horizontal.below.rectangle"
        case .setup: return "gearshape"
        }
    }
}

struct PadTheme: Identifiable {
    let name: String
    let colors: [Int]
    var id: String { name }
    var swatches: [Int] { [colors[0], colors[5], colors[10], colors[15]] }
    static let all: [PadTheme] = [
        .init(name: "Aurora", colors: [11,11,12,12,9,9,13,13,8,8,2,2,7,7,4,4]),
        .init(name: "Ember", colors: [15,15,16,16,1,1,1,1,2,2,3,3,4,4,5,5]),
        .init(name: "Mint", colors: Array(repeating: 8, count: 16)),
        .init(name: "Ocean", colors: [11,11,11,11,10,10,10,10,9,9,9,9,8,8,8,8]),
        .init(name: "Sunset", colors: [13,13,14,14,15,15,16,16,1,1,2,2,3,3,4,4]),
        .init(name: "Neon", colors: [16,9,16,9,9,6,9,6,6,13,6,13,13,16,13,16]),
        .init(name: "Ice", colors: [11,11,10,10,10,10,9,9,9,9,17,17,17,17,17,17]),
        .init(name: "Mono", colors: Array(repeating: 17, count: 16))
    ]
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let text: String
    let time = Date()
}

@Observable @MainActor final class MikroModel {
    var settings = MikroSettings() {
        didSet {
            if settings.encoder_mode != oldValue.encoder_mode || settings.encoder_cc != oldValue.encoder_cc || settings.encoder_min != oldValue.encoder_min || settings.encoder_max != oldValue.encoder_max || settings.encoder_initial != oldValue.encoder_initial {
                encoderValue = settings.encoder_initial
                encoderHasActivity = false
            }
            scheduleSave()
        }
    }
    var workspace = Workspace.pads
    var selectedPad = 12
    var selectedPads: Set<Int> = [12]
    var paletteUsesSelection = false
    var glowEnabled = UserDefaults.standard.object(forKey: "padGlow") as? Bool ?? true {
        didSet { if !preview { UserDefaults.standard.set(glowEnabled, forKey: "padGlow") } }
    }
    var state = "stopped"
    var statusMessage = "Ready when you are"
    var activePads = Set<Int>()
    var glowingPads = Set<Int>()
    var activeButtons = Set<Int>()
    var velocities: [Int: Int] = [:]
    var activity: [ActivityItem] = []
    var encoderValue = 64
    var encoderHasActivity = false
    var encoderRotation = 0.0
    var encoderLastDelta = 0
    var stripValue = 0
    var stripTouched = false
    var errorMessage: String?
    var canUndoAssignmentReset = false
    var autoStart: Bool { didSet { if !preview { UserDefaults.standard.set(autoStart, forKey: "autoStart") } } }
    var hasProcess = false
    let preview: Bool
    var appBehavior: MikroAppBehavior
    let loginItem: MikroLoginItem
    let configURL: URL
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var inputPipe: Pipe?
    @ObservationIgnored private var outputPipe: Pipe?
    @ObservationIgnored private var errorPipe: Pipe?
    @ObservationIgnored private var outputBuffer = ""
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var loading = true
    @ObservationIgnored private var selectionAnchor = 12
    @ObservationIgnored private var glowTokens: [Int: UUID] = [:]
    @ObservationIgnored private var assignmentResetSnapshot: MikroSettings?

    static let buttonNames = ["Project", "Star", "Browse", "Volume", "Swing", "Tempo", "Plug-in", "Sampling", "Left", "Right", "Pitch", "Mod", "Perform", "Notes", "Group", "Auto", "Lock", "Note Repeat", "Restart", "Erase", "Tap", "Follow", "Play", "Record", "Stop", "Shift", "Fixed Velocity", "Pad Mode", "Keyboard", "Chords", "Step", "Scene", "Pattern", "Events", "Variation", "Duplicate", "Select", "Solo", "Mute", "Encoder Press", "Encoder Touch"]

    init() {
        preview = CommandLine.arguments.contains("--preview")
        appBehavior = MikroAppBehavior(preview: preview)
        loginItem = MikroLoginItem(preview: preview)
        autoStart = preview ? true : UserDefaults.standard.object(forKey: "autoStart") as? Bool ?? true
        configURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mikro MIDI/settings.json")
        if let data = try? Data(contentsOf: configURL) {
            do { settings = try JSONDecoder().decode(MikroSettings.self, from: data).validated() }
            catch { errorMessage = "Your settings could not be loaded. Defaults are active. \(error.localizedDescription)" }
        }
        encoderValue = settings.encoder_initial
        loading = false
        persist()
        if preview {
            statusMessage = "Preview · hardware is not connected"
        } else if autoStart {
            DispatchQueue.main.async { [weak self] in self?.start() }
        }
    }

    var connected: Bool { state == "connected" }
    var stateTitle: String {
        switch state {
        case "connected": return "Connected"
        case "connecting": return "Connecting"
        case "disconnected": return "Waiting for Mikro"
        default: return preview ? "Preview" : "Stopped"
        }
    }
    var selectedPhysicalPad: Int { Self.physicalPad(selectedPad) }
    var selectionTitle: String { selectedPads.isEmpty ? "Select a pad" : selectedPads.count == 1 ? "Pad \(selectedPhysicalPad)" : "\(selectedPads.count) pads" }
    var selectedColor: Int? {
        let colors = Set(selectedPads.map { settings.pad_colors[$0] })
        return colors.count == 1 ? colors.first : nil
    }
    static func physicalPad(_ index: Int) -> Int { (3 - index / 4) * 4 + index % 4 + 1 }
    static func gridIndex(_ physicalPad: Int) -> Int { (3 - (physicalPad - 1) / 4) * 4 + (physicalPad - 1) % 4 }
    static func noteName(_ note: Int) -> String { ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][note % 12] + String(note / 12 - 2) }

    func selectPad(_ index: Int, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift) {
            let first = min(Self.physicalPad(selectionAnchor), Self.physicalPad(index))
            let last = max(Self.physicalPad(selectionAnchor), Self.physicalPad(index))
            let range = Set((first...last).map(Self.gridIndex))
            selectedPads = modifiers.contains(.command) ? selectedPads.union(range) : range
            selectedPad = index
        } else if modifiers.contains(.command) {
            if selectedPads.contains(index) { selectedPads.remove(index) }
            else { selectedPads.insert(index) }
            selectedPad = selectedPads.contains(index) ? index : selectedPads.first ?? index
            selectionAnchor = selectedPad
        } else {
            selectedPads = [index]
            selectedPad = index
            selectionAnchor = index
        }
    }

    func colorSelection(_ code: Int) {
        var colors = settings.pad_colors
        for index in selectedPads { colors[index] = code }
        settings.pad_colors = colors
    }

    func transposeSelection(_ semitones: Int) {
        guard !selectedPads.isEmpty, selectedPads.allSatisfy({ (0...127).contains(settings.notemaps[$0] + semitones) }) else { return }
        var notes = settings.notemaps
        for index in selectedPads { notes[index] += semitones }
        settings.notemaps = notes
    }

    func canTranspose(_ semitones: Int) -> Bool {
        !selectedPads.isEmpty && selectedPads.allSatisfy { (0...127).contains(settings.notemaps[$0] + semitones) }
    }

    func setEncoderMinimum(_ value: Int) {
        var next = settings
        next.encoder_min = min(max(0, value), next.encoder_max - 1)
        next.encoder_initial = max(next.encoder_initial, next.encoder_min)
        settings = next
    }

    func setEncoderMaximum(_ value: Int) {
        var next = settings
        next.encoder_max = max(min(127, value), next.encoder_min + 1)
        next.encoder_initial = min(next.encoder_initial, next.encoder_max)
        settings = next
    }

    func start() {
        guard process == nil, !preview else { return }
        persist()
        let backendURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mikro-driver")
        guard FileManager.default.isExecutableFile(atPath: backendURL.path) else {
            errorMessage = "The MIDI driver is missing from this app. Download the complete Mikro MIDI app and try again."
            return
        }
        let child = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        child.executableURL = backendURL
        child.arguments = ["--json", "--wait", "--config", configURL.path]
        child.standardInput = input
        child.standardOutput = output
        child.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.consumeOutput(text) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.log(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        child.terminationHandler = { [weak self] child in
            Task { @MainActor [weak self] in
                guard let self, self.process === child else { return }
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.errorPipe?.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.hasProcess = false
                self.inputPipe = nil
                self.activePads.removeAll()
                self.activeButtons.removeAll()
                self.state = "stopped"
                self.statusMessage = child.terminationStatus == 0 ? "Driver stopped" : "Driver stopped. Open Setup for help."
                if child.terminationStatus != 0 { self.log("Driver exited with code \(child.terminationStatus)") }
            }
        }
        do {
            try child.run()
            process = child
            inputPipe = input
            outputPipe = output
            errorPipe = errors
            outputBuffer = ""
            hasProcess = true
            encoderValue = settings.encoder_initial
            encoderHasActivity = false
            encoderRotation = 0
            state = "connecting"
            statusMessage = "Looking for Maschine Mikro MK3…"
            log("MIDI driver started")
        } catch {
            errorMessage = "Could not start the driver: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard let child = process else { return }
        send("stop")
        state = "stopped"
        statusMessage = "Stopping driver…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak child] in
            guard let child, child.isRunning, self?.process === child else { return }
            child.terminate()
        }
    }

    func shutdown(completion: @escaping () -> Void) {
        saveWork?.cancel()
        persist()
        guard let child = process else { DispatchQueue.main.async { completion() }; return }
        send("stop")
        inputPipe?.fileHandleForWriting.closeFile()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if child.isRunning { child.terminate() }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            child.waitUntilExit()
            DispatchQueue.main.async { completion() }
        }
    }

    func panic() {
        send("panic")
        activePads.removeAll()
        glowingPads.removeAll()
        activeButtons.removeAll()
        log("All notes off sent")
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.persist()
            self.send("configure", settings: self.settings)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func persist() {
        guard !preview else { return }
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try settings.write(to: configURL)
        } catch { errorMessage = "Settings could not be saved: \(error.localizedDescription)" }
    }

    private struct DriverCommand: Encodable {
        let command: String
        let settings: MikroSettings?
    }

    private func send(_ command: String, settings: MikroSettings? = nil) {
        guard let handle = inputPipe?.fileHandleForWriting, process?.isRunning == true,
              var data = try? JSONEncoder().encode(DriverCommand(command: command, settings: settings)) else { return }
        data.append(10)
        do { try handle.write(contentsOf: data) }
        catch { log("Could not update driver: \(error.localizedDescription)") }
    }

    private func consumeOutput(_ text: String) {
        outputBuffer += text
        while let newline = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            guard let data = line.data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { if !line.isEmpty { log(line) }; continue }
            receive(event)
        }
    }

    private func receive(_ event: [String: Any]) {
        let type = event["type"] as? String ?? ""
        switch type {
        case "status":
            state = event["state"] as? String ?? state
            statusMessage = event["message"] as? String ?? stateTitle
            if !connected { activePads.removeAll(); glowingPads.removeAll(); activeButtons.removeAll(); stripTouched = false }
            log(statusMessage)
        case "pad":
            guard let pad = event["pad"] as? Int, (1...16).contains(pad) else { return }
            let pressed = event["pressed"] as? Bool ?? false
            let velocity = event["velocity"] as? Int ?? 0
            if pressed {
                activePads.insert(pad); velocities[pad] = velocity
                let token = UUID()
                glowTokens[pad] = token
                glowingPads.insert(pad)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                    guard let self, self.glowTokens[pad] == token else { return }
                    self.glowingPads.remove(pad)
                }
            }
            else { activePads.remove(pad) }
            if pressed { log("Pad \(pad)  ·  \(Self.noteName(event["note"] as? Int ?? settings.notemaps[Self.gridIndex(pad)]))  ·  velocity \(velocity)") }
        case "button":
            guard let button = event["button"] as? Int, (0..<41).contains(button) else { return }
            let pressed = event["pressed"] as? Bool ?? false
            if pressed { activeButtons.insert(button) } else { activeButtons.remove(button) }
            if pressed { log("\(Self.buttonNames[button])  ·  CC \(event["cc"] as? Int ?? settings.button_ccs[button])") }
        case "encoder":
            encoderValue = event["value"] as? Int ?? encoderValue
            encoderLastDelta = event["delta"] as? Int ?? 0
            encoderRotation += Double(encoderLastDelta) * 6
            encoderHasActivity = true
            log("Knob  ·  CC \(settings.encoder_cc)  ·  \(encoderLastDelta > 0 ? "+" : "")\(encoderLastDelta)")
        case "strip":
            stripValue = event["value"] as? Int ?? 0
            stripTouched = event["touched"] as? Bool ?? false
            log("Touch strip  ·  \(settings.touch_strip_mode == "pitch_bend" ? "pitch bend" : "CC \(settings.touch_strip_cc)")  ·  \(stripValue)")
        case "configured": break
        case "error":
            statusMessage = event["message"] as? String ?? "Driver error"
            log(statusMessage)
            if statusMessage.hasPrefix("Configuration rejected:") { errorMessage = statusMessage }
        default: break
        }
    }

    private func log(_ text: String) {
        guard !text.isEmpty else { return }
        if activity.first?.text == text { return }
        activity.insert(ActivityItem(text: text), at: 0)
        if activity.count > 80 { activity.removeLast(activity.count - 80) }
    }

    func applyTheme(_ name: String) {
        guard let theme = PadTheme.all.first(where: { $0.name == name }) else { return }
        if paletteUsesSelection {
            var colors = settings.pad_colors
            for index in selectedPads { colors[index] = theme.colors[index] }
            settings.pad_colors = colors
        } else {
            settings.pad_colors = theme.colors
        }
    }

    func resetAssignments() {
        // Keep the earliest snapshot if Reset is clicked twice before Undo.
        if assignmentResetSnapshot == nil { assignmentResetSnapshot = settings }
        if hasProcess { panic() }
        applyAssignments(from: MikroSettings())
        canUndoAssignmentReset = true
        log("MIDI assignments reset; pad colors and brightness preserved")
    }

    func undoAssignmentReset() {
        guard let snapshot = assignmentResetSnapshot else { return }
        if hasProcess { panic() }
        applyAssignments(from: snapshot)
        dismissAssignmentUndo()
        log("Previous MIDI assignments restored")
    }

    func dismissAssignmentUndo() {
        assignmentResetSnapshot = nil
        canUndoAssignmentReset = false
    }

    private func applyAssignments(from source: MikroSettings) {
        var next = source
        next.pad_colors = settings.pad_colors
        next.pad_idle_brightness = settings.pad_idle_brightness
        next.pad_active_brightness = settings.pad_active_brightness
        settings = next
    }

    func reset() {
        dismissAssignmentUndo()
        settings = MikroSettings()
        log("Default mappings restored")
    }

    func exportPreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Mikro MIDI Preset.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.write(to: url)
        } catch { errorMessage = "Could not export preset: \(error.localizedDescription)" }
    }

    func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            settings = try JSONDecoder().decode(MikroSettings.self, from: Data(contentsOf: url)).validated()
            dismissAssignmentUndo()
            log("Loaded preset: \(url.deletingPathExtension().lastPathComponent)")
        } catch { errorMessage = "Could not import preset: \(error.localizedDescription)" }
    }
}
