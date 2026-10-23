import AppKit
import SwiftUI

enum Studio {
    static let background = Color(hex: 0x111416)
    static let sidebar = Color(hex: 0x161A1C)
    static let surface = Color(hex: 0x1D2225)
    static let inset = Color(hex: 0x15191B)
    static let line = Color.white.opacity(0.075)
    static let text = Color(hex: 0xEEEFE7)
    static let muted = Color(hex: 0x87918F)
    static let accent = Color(hex: 0xAAE9C8)
    static let palette: [Color] = [Color(hex: 0x555D60), Color(hex: 0xF07777), Color(hex: 0xF69B68), Color(hex: 0xF3B77D), Color(hex: 0xEACD7B), Color(hex: 0xE6DF70), Color(hex: 0xBCDC7D), Color(hex: 0x79CA89), Color(hex: 0x9BE0BF), Color(hex: 0x76CED1), Color(hex: 0x68B7C9), Color(hex: 0x81A4E8), Color(hex: 0xA49ADD), Color(hex: 0xB397E8), Color(hex: 0xC697D3), Color(hex: 0xDA8CB5), Color(hex: 0xE996CB), Color(hex: 0xF1F0E7)]
    static let colorNames = ["Off", "Red", "Orange", "Light orange", "Warm yellow", "Yellow", "Lime", "Green", "Mint", "Cyan", "Turquoise", "Blue", "Plum", "Violet", "Purple", "Magenta", "Fuchsia", "White"]
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

final class MikroAppDelegate: NSObject, NSApplicationDelegate {
    var model: MikroModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        MainActor.assumeIsolated {
            model.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
}

@main struct MikroApp: App {
    @NSApplicationDelegateAdaptor(MikroAppDelegate.self) var delegate
    @State private var model = MikroModel()

    var body: some Scene {
        WindowGroup("Mikro MIDI", id: "main") {
            MikroWindow(model: model)
                .preferredColorScheme(.dark)
                .onAppear { delegate.model = model; NSApplication.shared.activate(ignoringOtherApps: true) }
                .alert("Mikro MIDI", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK", role: .cancel) { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .newItem) {
                Button("Import Preset…") { model.importPreset() }.keyboardShortcut("o")
                Button("Export Preset…") { model.exportPreset() }.keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Mikro MIDI Help") { model.workspace = .setup }
            }
        }
    }
}

struct MikroWindow: View {
    @Bindable var model: MikroModel
    @State private var showingReset = false
    @State private var preparedPages: Set<Workspace> = [.pads]

    var body: some View {
        HStack(spacing: 0) {
            MikroSidebar(model: model, showingReset: $showingReset)
            Rectangle().fill(Studio.line).frame(width: 1)
            VStack(spacing: 0) {
                ZStack {
                    ForEach(Workspace.allCases, id: \.self) { workspace in
                        if preparedPages.contains(workspace) || model.workspace == workspace {
                            page(workspace)
                                .opacity(model.workspace == workspace ? 1 : 0)
                                .allowsHitTesting(model.workspace == workspace)
                                .disabled(model.workspace != workspace)
                                .accessibilityHidden(model.workspace != workspace)
                                .zIndex(model.workspace == workspace ? 1 : 0)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.canUndoAssignmentReset { MikroAssignmentUndoBanner(model: model) }
                MikroFooter(model: model)
            }
        }
        .frame(minWidth: 1120, minHeight: 750)
        .background(Studio.background)
        .foregroundStyle(Studio.text)
        .font(.system(size: 13))
        .tint(Studio.accent)
        .onChange(of: model.workspace) { _, workspace in preparedPages.insert(workspace) }
        .task {
            // Build native controls once, after the first frame. Retained pages
            // preserve scroll positions and avoid rebuilding forms on tab changes.
            for workspace in Workspace.allCases where workspace != .pads {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
                preparedPages.insert(workspace)
            }
        }
        .confirmationDialog("Restore default mappings and pad colors?", isPresented: $showingReset) {
            Button("Restore Defaults", role: .destructive) { model.reset() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Export a preset first if you want to keep your current settings.") }
    }

    @ViewBuilder private func page(_ workspace: Workspace) -> some View {
        switch workspace {
        case .pads: MikroPadsPage(model: model)
        case .buttons: MikroButtonsPage(model: model)
        case .knob: KnobWorkspace(model: model)
        case .touchStrip: TouchStripWorkspace(model: model)
        case .setup: MikroSetupPage(model: model)
        }
    }
}
