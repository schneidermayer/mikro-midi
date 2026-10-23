import SwiftUI

struct MikroButtonsPage: View {
    @Bindable var model: MikroModel

    var body: some View {
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
                                MIDIIntegerField(value: Binding(get: { model.settings.button_ccs[index] }, set: { model.settings.button_ccs[index] = $0 }), range: 0...127, label: "\(MikroModel.buttonNames[index]) MIDI CC")
                            }
                        }.padding(12).background(model.activeButtons.contains(index) ? Studio.accent.opacity(0.10) : Studio.surface, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(model.activeButtons.contains(index) ? Studio.accent.opacity(0.5) : Studio.line))
                    }
                }
            }.padding(28)
        }
    }

    private func label(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Studio.muted) }
}

struct MikroSetupPage: View {
    @Bindable var model: MikroModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                appBehaviorCard
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 22) {
                        label("MIDI & HARDWARE")
                        HStack { Text("MIDI channel"); Spacer(); MIDIIntegerField(value: $model.settings.midi_channel, range: 1...16, label: "MIDI channel") }
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
                        Button { model.panic() } label: {
                            Label("All notes off (Panic)", systemImage: "speaker.slash")
                                .font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(Studio.line, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).disabled(!model.hasProcess)
                        Text("Settings save automatically.").font(.system(size: 11)).foregroundStyle(Studio.muted)
                    }.padding(22).frame(maxWidth: .infinity).background(Studio.surface, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 18) {
                        label("GET STARTED")
                        helpStep("1", "Connect USB", "Close other controller software.")
                        helpStep("2", "Enable MIDI input", "Select “\(model.settings.port_name)” in your music app.")
                        helpStep("3", "Load an instrument", "Load a drum kit or synth. Mikro MIDI sends MIDI, not audio.")
                    }.padding(22).frame(maxWidth: .infinity).background(Studio.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                }
                HStack(spacing: 18) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 19)).foregroundStyle(Studio.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Reset MIDI assignments").font(.system(size: 13, weight: .semibold))
                        Text("Restore default mappings. Keep colors and brightness.")
                            .font(.system(size: 11)).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Reset assignments") { model.resetAssignments() }
                        .buttonStyle(.bordered).controlSize(.small).accessibilityLabel("Reset MIDI assignments")
                }.padding(19).background(Studio.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 14) {
                    HStack { label("LIVE ACTIVITY"); Spacer(); Button("Clear") { model.activity = [] }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Studio.muted) }
                    if model.activity.isEmpty {
                        Text("No MIDI activity yet.").font(.system(size: 12)).foregroundStyle(Studio.muted).padding(.vertical, 18)
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
                    Text("Controller busy? Close other controller software and reconnect USB.")
                        .font(.system(size: 11)).foregroundStyle(Studio.muted).lineSpacing(4)
                }
            }.padding(28)
        }
    }

    private var appBehaviorCard: some View {
        @Bindable var behavior = model.appBehavior
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "macwindow")
                    .font(.system(size: 20, weight: .light)).foregroundStyle(Studio.accent)
                    .frame(width: 38, height: 38)
                    .background(Studio.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text("App behavior").font(.system(size: 15, weight: .semibold))
                    Text("Keep MIDI running while you focus on your music.")
                        .font(.system(size: 11)).foregroundStyle(Studio.muted)
                }
                Spacer()
                Button("Run in background") { behavior.hideWindow() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Close this window and keep Mikro MIDI running.")
            }
            Rectangle().fill(Studio.line).frame(height: 1)
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 20) {
                    behaviorToggle("Keep running when window closes", detail: "Closing the window keeps the driver active.", isOn: $behavior.runInBackground)
                    behaviorToggle("Start driver when app opens", detail: "Connect to your Mikro automatically.", isOn: $model.autoStart)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 20) {
                    behaviorToggle("Show in menu bar", detail: "Quick access to status and driver controls.", isOn: $behavior.showInMenuBar)
                    behaviorToggle("Show in Dock", detail: "Reopen the window from the Dock or ⌘ Tab.", isOn: $behavior.showInDock)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Reopen from the menu bar or Dock. Quit Mikro MIDI to stop the driver.")
                .font(.system(size: 11)).foregroundStyle(Studio.muted)
        }
        .padding(22).background(Studio.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Studio.line))
    }

    private func behaviorToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Studio.muted)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
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

    private func label(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Studio.muted) }
}
