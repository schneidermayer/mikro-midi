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
    @StateObject private var model = MikroModel()

    var body: some Scene {
        WindowGroup("Mikro MIDI", id: "main") {
            MikroWindow()
                .environmentObject(model)
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
    @EnvironmentObject var model: MikroModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var showingReset = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Studio.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                Rectangle().fill(Studio.line).frame(height: 1)
                Group {
                    switch model.workspace {
                    case .pads: padsWorkspace
                    case .buttons: buttonsWorkspace
                    case .knob: KnobWorkspace()
                    case .touchStrip: TouchStripWorkspace()
                    case .setup: setupWorkspace
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .frame(minWidth: 1120, minHeight: 750)
        .background(Studio.background)
        .foregroundStyle(Studio.text)
        .font(.system(size: 13))
        .tint(Studio.accent)
        .confirmationDialog("Restore default mappings and pad colors?", isPresented: $showingReset) {
            Button("Restore Defaults", role: .destructive) { model.reset() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Export a preset first if you want to keep your current settings.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                logo
                VStack(alignment: .leading, spacing: 0) {
                    Text("mikro").font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-1)
                    Text("M I D I").font(.system(size: 9, weight: .semibold)).foregroundStyle(Studio.muted)
                }
            }.padding(.top, 44).padding(.bottom, 42)

            label("WORKSPACE").padding(.bottom, 14)
            ForEach(Workspace.allCases, id: \.self) { item in
                Button { model.workspace = item } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.icon).font(.system(size: 14)).frame(width: 18)
                        Text(item.rawValue).font(.system(size: 12, weight: model.workspace == item ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer()
                        if model.workspace == item { Circle().fill(Studio.accent).frame(width: 5, height: 5) }
                    }
                    .foregroundStyle(model.workspace == item ? Studio.accent : Studio.muted)
                    .padding(.horizontal, 12).frame(height: 42)
                    .background(model.workspace == item ? Studio.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).accessibilityLabel(item.rawValue).padding(.bottom, 5)
            }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cable.connector").font(.system(size: 15)).foregroundStyle(Studio.accent)
                    Spacer()
                    Circle().fill(model.connected ? Studio.accent : Studio.muted).frame(width: 6, height: 6)
                }
                Text("MASCHINE\nMIKRO MK3").font(.system(size: 11, weight: .semibold)).tracking(1).lineSpacing(4)
                Text(model.stateTitle).font(.system(size: 11)).foregroundStyle(Studio.muted)
                Button { if model.hasProcess { model.stop() } else { model.start() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.hasProcess ? "stop.fill" : "play.fill").font(.system(size: 9))
                        Text(model.hasProcess ? "Stop driver" : "Start driver").font(.system(size: 11, weight: .medium))
                    }.frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Studio.line, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).disabled(model.preview)
            }.padding(14).background(Studio.inset, in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 5) {
                Text("OPEN SOURCE").font(.system(size: 8, weight: .medium)).tracking(1.2)
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0")").font(.system(size: 9, design: .monospaced))
            }.foregroundStyle(Studio.muted.opacity(0.7)).padding(.top, 18).padding(.bottom, 23)
        }.padding(.horizontal, 20).frame(width: 190).background(Studio.sidebar)
    }

    private var logo: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(7), spacing: 3), count: 3), spacing: 3) {
            ForEach(0..<9) { i in RoundedRectangle(cornerRadius: 1.7).fill(Studio.accent.opacity(i == 2 || i == 5 ? 0.35 : 1)).frame(width: 7, height: 7) }
        }.frame(width: 27)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                label("YOUR MIKRO. NO NI INSTALLS.")
                Text(model.workspace == .pads ? "Play. Without the bloat." : model.workspace.headline)
                    .font(.system(size: 27, weight: .semibold)).tracking(-0.8)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(model.connected ? Studio.accent : Studio.muted).frame(width: 6, height: 6)
                Text(model.stateTitle).font(.system(size: 11, weight: .medium))
            }.foregroundStyle(model.connected ? Studio.accent : Studio.muted)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(Studio.surface, in: Capsule())
            Menu {
                Button("Import Preset…") { model.importPreset() }
                Button("Export Preset…") { model.exportPreset() }
                Divider()
                Button("Restore Defaults…", role: .destructive) { showingReset = true }
            } label: {
                HStack(spacing: 7) { Image(systemName: "square.stack"); Text("Presets") }
                    .font(.system(size: 11, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Studio.surface, in: Capsule())
            }.menuStyle(.borderlessButton).fixedSize().padding(.leading, 5)
        }.padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 23)
    }

    private var padsWorkspace: some View {
        HStack(alignment: .top, spacing: 0) {
            GeometryReader { space in
              ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        label("PAD WORKSPACE")
                        Spacer()
                        Text("\(model.selectedPads.count) selected").font(.system(size: 10)).foregroundStyle(Studio.muted)
                        Button("Select all") { model.selectedPads = Set(0..<16) }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Studio.accent).padding(.leading, 5)
                        Button("Clear") { model.selectedPads.removeAll() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Studio.muted).padding(.leading, 5)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(0..<16) { index in pad(index, height: max(72, min(102, (space.size.height - 302) / 4))) }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "cursorarrow.click").font(.system(size: 12))
                        Text("⌘ click to select more · ⇧ click for a range · Play to see the glow.").font(.system(size: 10))
                    }.foregroundStyle(Studio.muted)
                    themePicker
                }.padding(24)
              }
            }
            Rectangle().fill(Studio.line).frame(width: 1)
            padInspector.frame(width: 258).frame(maxHeight: .infinity).background(Studio.sidebar.opacity(0.7))
        }
    }

    private func pad(_ index: Int, height: CGFloat) -> some View {
        let number = MikroModel.physicalPad(index)
        let tint = Studio.palette[model.settings.pad_colors[index]]
        let selected = model.selectedPads.contains(index)
        let pressed = model.activePads.contains(number)
        let glowing = model.glowEnabled && (pressed || model.glowingPads.contains(number))
        return Button { model.selectPad(index, modifiers: NSEvent.modifierFlags) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(String(format: "%02d", number)).font(.system(size: 11, weight: .medium, design: .monospaced))
                    Spacer()
                    if pressed { Circle().fill(tint).frame(width: 6, height: 6) }
                    else if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                }.foregroundStyle(tint.opacity(0.9))
                Spacer(minLength: 4)
                Text(MikroModel.noteName(model.settings.notemaps[index])).font(.system(size: 20, weight: .semibold)).tracking(-0.5)
                HStack(spacing: 3) {
                    Text("NOTE")
                    Text(String(model.settings.notemaps[index]))
                }.font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(0.8).foregroundStyle(tint.opacity(0.65)).padding(.top, 4)
            }
            .foregroundStyle(tint)
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(LinearGradient(colors: [tint.opacity(glowing ? 0.65 : selected ? 0.24 : 0.15), tint.opacity(glowing ? 0.3 : 0.065)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(tint.opacity(selected || pressed ? 0.85 : 0.16), lineWidth: selected ? 1.5 : 1))
            .overlay(alignment: .bottom) { Capsule().fill(tint.opacity(pressed ? 1 : 0.6)).frame(width: 26, height: 2).padding(.bottom, 7) }
            .shadow(color: tint.opacity(glowing ? 0.5 : selected ? 0.06 : 0), radius: glowing ? 19 : 9)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: glowing ? 0.06 : 0.3), value: glowing)
        }.buttonStyle(.plain).accessibilityLabel("Pad \(number), \(MikroModel.noteName(model.settings.notemaps[index])), MIDI note \(model.settings.notemaps[index])")
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                label("PALETTE STUDIO")
                Spacer()
                Picker("Apply palette to", selection: $model.paletteUsesSelection) {
                    Text("All pads").tag(false)
                    Text("Selected").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 152).controlSize(.mini)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                ForEach(PadTheme.all) { item in theme(item.name, colors: item.swatches) }
            }
        }.padding(12).background(Studio.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }

    private func theme(_ name: String, colors: [Int]) -> some View {
        Button { model.applyTheme(name) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 2) { ForEach(Array(colors.enumerated()), id: \.offset) { _, color in RoundedRectangle(cornerRadius: 1.5).fill(Studio.palette[color]).frame(height: 6) } }
                Text(name).font(.system(size: 10, weight: .medium))
            }.padding(8).frame(maxWidth: .infinity)
                .background(Studio.inset, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityLabel("Apply \(name) palette").disabled(model.paletteUsesSelection && model.selectedPads.isEmpty)
    }

    private var padInspector: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                label("PAD INSPECTOR")
                Spacer()
                Image(systemName: "slider.horizontal.3").foregroundStyle(Studio.muted)
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Studio.palette[model.settings.pad_colors[model.selectedPad]].opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Studio.palette[model.settings.pad_colors[model.selectedPad]].opacity(0.5)))
                    .overlay(Text(model.selectedPads.count == 1 ? String(format: "%02d", model.selectedPhysicalPad) : "\(model.selectedPads.count)").font(.system(size: 19, weight: .medium, design: .monospaced)).foregroundStyle(Studio.palette[model.settings.pad_colors[model.selectedPad]]))
                    .frame(width: 49, height: 49)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.selectionTitle).font(.system(size: 19, weight: .semibold))
                    Text(model.selectedPads.count > 1 ? "Edit your selection together" : "Note on / note off").font(.system(size: 10)).foregroundStyle(Studio.muted)
                }
            }
            separator
            if model.selectedPads.count == 1 {
              VStack(alignment: .leading, spacing: 11) {
                label("MIDI NOTE")
                HStack {
                    Text(MikroModel.noteName(model.settings.notemaps[model.selectedPad])).font(.system(size: 25, weight: .medium)).tracking(-0.8)
                    Spacer()
                    numberField(value: Binding(get: { model.settings.notemaps[model.selectedPad] }, set: { model.settings.notemaps[model.selectedPad] = $0 }), range: 0...127)
                }.padding(12).background(Studio.inset, in: RoundedRectangle(cornerRadius: 9))
                Text("MIDI number 0–127 · C3 = 60").font(.system(size: 10)).foregroundStyle(Studio.muted)
              }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    label("TRANSPOSE SELECTION")
                    HStack(spacing: 6) {
                        ForEach([-12, -1, 1, 12], id: \.self) { amount in
                            Button { model.transposeSelection(amount) } label: {
                                Text(amount > 0 ? "+\(amount)" : "\(amount)").font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .frame(maxWidth: .infinity).padding(.vertical, 11).background(Studio.inset, in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).disabled(!model.canTranspose(amount))
                        }
                    }
                    Text("Shift notes by semitones. Keeps their spacing.").font(.system(size: 10)).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 11) {
                HStack { label("PAD COLOR"); Spacer(); Text(model.selectedColor.map { Studio.colorNames[$0] } ?? (model.selectedPads.isEmpty ? "None" : "Mixed")).font(.system(size: 10)).foregroundStyle(Studio.muted) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 6), spacing: 10) {
                    ForEach(0..<18) { code in
                        Button {
                            model.colorSelection(code)
                        } label: {
                            Circle().fill(Studio.palette[code]).frame(width: 23, height: 23)
                                .overlay { if code == 0 { Image(systemName: "slash.circle").foregroundStyle(Studio.background).font(.system(size: 23)) } }
                                .overlay { if model.selectedColor == code { Image(systemName: "checkmark").foregroundStyle(Studio.background).font(.system(size: 10, weight: .bold)) } }
                                .padding(3).overlay(Circle().strokeBorder(model.selectedColor == code ? Studio.text.opacity(0.7) : .clear, lineWidth: 1))
                        }.buttonStyle(.plain).help(Studio.colorNames[code]).accessibilityLabel(Studio.colorNames[code]).disabled(model.selectedPads.isEmpty)
                    }
                }
                Text("Applies to \(model.selectedPads.count) selected \(model.selectedPads.count == 1 ? "pad" : "pads").").font(.system(size: 10)).foregroundStyle(Studio.muted)
            }
            separator
            VStack(alignment: .leading, spacing: 12) {
                HStack { label("LAST VELOCITY"); Spacer(); Text(String(model.velocities[model.selectedPhysicalPad] ?? 0)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Studio.accent) }
                GeometryReader { geometry in
                    Capsule().fill(Studio.line).overlay(alignment: .leading) { Capsule().fill(Studio.accent).frame(width: geometry.size.width * Double(model.velocities[model.selectedPhysicalPad] ?? 0) / 127) }
                }.frame(height: 4)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle").foregroundStyle(Studio.accent)
                Text("Changes save automatically.\nYour setup, ready next time.").font(.system(size: 10)).lineSpacing(4).foregroundStyle(Studio.muted)
            }
        }.padding(24)
    }

    private var buttonsWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack { label("39 BUTTON MAPPINGS"); Spacer(); Text("Press → 127  ·  Release → 0").font(.system(size: 11)).foregroundStyle(Studio.muted) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(0..<39) { index in
                        VStack(alignment: .leading, spacing: 13) {
                            HStack(spacing: 5) {
                                Circle().fill(model.activeButtons.contains(index) ? Studio.accent : Studio.muted.opacity(0.3)).frame(width: 4, height: 4)
                                Text(MikroModel.buttonNames[index]).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                            }
                            HStack {
                                Text("CC").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Studio.muted)
                                Spacer()
                                numberField(value: Binding(get: { model.settings.button_ccs[index] }, set: { model.settings.button_ccs[index] = $0 }), range: 0...127)
                            }
                        }.padding(12).background(model.activeButtons.contains(index) ? Studio.accent.opacity(0.10) : Studio.surface, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(model.activeButtons.contains(index) ? Studio.accent.opacity(0.5) : Studio.line))
                    }
                }
            }.padding(28)
        }
    }

    private var setupWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 22) {
                        label("MIDI & HARDWARE")
                        HStack { Text("MIDI channel"); Spacer(); numberField(value: $model.settings.midi_channel, range: 1...16) }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Pad brightness · idle")
                            Picker("Brightness", selection: $model.settings.pad_idle_brightness) { Text("Off").tag(0); Text("Low").tag(1); Text("Medium").tag(2); Text("High").tag(3) }.pickerStyle(.segmented).labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Pad brightness · on press")
                            Picker("On press brightness", selection: $model.settings.pad_active_brightness) { Text("Off").tag(0); Text("Low").tag(1); Text("Medium").tag(2); Text("High").tag(3) }.pickerStyle(.segmented).labelsHidden()
                        }
                        Toggle("Pad glow in this app", isOn: $model.glowEnabled).toggleStyle(.switch).controlSize(.small)
                        Toggle("Polyphonic aftertouch", isOn: $model.settings.poly_aftertouch).toggleStyle(.switch).controlSize(.small)
                        Toggle("Start driver when app opens", isOn: $model.autoStart).toggleStyle(.switch).controlSize(.small)
                        Button { model.panic() } label: {
                            Label("All notes off (Panic)", systemImage: "speaker.slash")
                                .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(Studio.line, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).disabled(!model.hasProcess)
                        Text("Settings and mappings save automatically on this Mac.").font(.system(size: 11)).foregroundStyle(Studio.muted)
                    }.padding(22).frame(maxWidth: .infinity).background(Studio.surface, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 18) {
                        label("THREE STEPS TO SOUND")
                        helpStep("1", "Connect your Mikro", "Plug Maschine Mikro MK3 into USB. Close Maschine and Controller Editor.")
                        helpStep("2", "Choose the MIDI input", "In your DAW, enable “\(model.settings.port_name)” as a MIDI input.")
                        helpStep("3", "Load an instrument", "Choose a drum kit or synth and play. Mikro MIDI sends MIDI; it does not generate sound.")
                    }.padding(22).frame(maxWidth: .infinity).background(Studio.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack { label("LIVE ACTIVITY"); Spacer(); Button("Clear") { model.activity = [] }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Studio.muted) }
                    if model.activity.isEmpty {
                        Text("Play a pad or move a control to see MIDI activity here.").font(.system(size: 12)).foregroundStyle(Studio.muted).padding(.vertical, 18)
                    } else {
                        ForEach(model.activity.prefix(12)) { item in
                            HStack(spacing: 16) {
                                Text(item.time, style: .time).font(.system(size: 10, design: .monospaced)).foregroundStyle(Studio.muted)
                                Text(item.text).font(.system(size: 11, design: .monospaced)).lineLimit(2)
                                Spacer()
                            }
                        }
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Studio.surface, in: RoundedRectangle(cornerRadius: 12))
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle").foregroundStyle(Studio.muted)
                    Text("No Native Access, Komplete Kontrol, or NIHostIntegrationAgent needed. If your controller is busy, close other controller software and reconnect the USB cable.")
                        .font(.system(size: 11)).foregroundStyle(Studio.muted).lineSpacing(4)
                }
            }.padding(28)
        }
    }

    private func helpStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Studio.accent).frame(width: 23, height: 23).background(Studio.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Studio.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path").font(.system(size: 12)).foregroundStyle(Studio.accent)
            Text(model.settings.port_name).font(.system(size: 10, weight: .medium))
            Text("/  CH \(String(format: "%02d", model.settings.midi_channel))").font(.system(size: 9, design: .monospaced)).foregroundStyle(Studio.muted)
            Spacer()
            Text(model.activity.first?.text ?? (model.preview ? "Preview · hardware disconnected" : "Play something. We’re listening.")).font(.system(size: 10)).foregroundStyle(Studio.muted).lineLimit(1)
            Button { model.workspace = .setup } label: { Image(systemName: "questionmark.circle").font(.system(size: 14)).foregroundStyle(Studio.muted) }.buttonStyle(.plain).help("Setup and help").padding(.leading, 8)
        }.padding(.horizontal, 28).frame(height: 44).background(Studio.sidebar.opacity(0.6)).overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: 1) }
    }

    private func label(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Studio.muted) }
    private var separator: some View { Rectangle().fill(Studio.line).frame(height: 1) }
    private func numberField(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            TextField("", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }), format: .number.grouping(.never))
                .textFieldStyle(.plain).font(.system(size: 13, weight: .medium, design: .monospaced)).multilineTextAlignment(.trailing).frame(width: 32)
                .accessibilityLabel("MIDI value")
            Stepper("", value: value, in: range).labelsHidden().controlSize(.mini).fixedSize()
        }.padding(.vertical, 4).padding(.leading, 7).padding(.trailing, 3).background(Studio.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
    }
}
