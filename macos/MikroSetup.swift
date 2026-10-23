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
                                numberField(value: Binding(get: { model.settings.button_ccs[index] }, set: { model.settings.button_ccs[index] = $0 }), range: 0...127)
                            }
                        }.padding(12).background(model.activeButtons.contains(index) ? Studio.accent.opacity(0.10) : Studio.surface, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(model.activeButtons.contains(index) ? Studio.accent.opacity(0.5) : Studio.line))
                    }
                }
            }.padding(28)
        }
    }

    private func label(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Studio.muted) }

    private func numberField(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            TextField("", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }), format: .number.grouping(.never))
                .textFieldStyle(.plain).font(.system(size: 13, weight: .medium, design: .monospaced)).multilineTextAlignment(.trailing).frame(width: 32)
                .accessibilityLabel("MIDI value")
            Stepper("", value: value, in: range).labelsHidden().controlSize(.mini).fixedSize()
        }.padding(.vertical, 4).padding(.leading, 7).padding(.trailing, 3).background(Studio.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct MikroSetupPage: View {
    @Bindable var model: MikroModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 19)).foregroundStyle(Studio.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A fresh set of assignments").font(.system(size: 13, weight: .semibold))
                        Text("Reset notes, buttons, knob, strip and MIDI channel. Keep your colors and brightness.")
                            .font(.system(size: 11)).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Reset assignments") { model.resetAssignments() }
                        .buttonStyle(.bordered).controlSize(.small).accessibilityLabel("Reset MIDI assignments")
                }.padding(19).background(Studio.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
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

    private func label(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Studio.muted) }

    private func numberField(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            TextField("", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }), format: .number.grouping(.never))
                .textFieldStyle(.plain).font(.system(size: 13, weight: .medium, design: .monospaced)).multilineTextAlignment(.trailing).frame(width: 32)
                .accessibilityLabel("MIDI value")
            Stepper("", value: value, in: range).labelsHidden().controlSize(.mini).fixedSize()
        }.padding(.vertical, 4).padding(.leading, 7).padding(.trailing, 3).background(Studio.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
    }
}
