import SwiftUI

struct KnobWorkspace: View {
    @Bindable var model: MikroModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private var absolute: Bool { model.settings.encoder_mode == "absolute" }
    private var normalized: Double {
        let span = max(1, model.settings.encoder_max - model.settings.encoder_min)
        return min(1, max(0, Double(model.encoderValue - model.settings.encoder_min) / Double(span)))
    }
    private var formatDetail: String {
        switch model.settings.encoder_relative_format {
        case "twos_complement": return "Clockwise 1 · counterclockwise 127"
        case "sign_magnitude": return "Clockwise 1 · counterclockwise 65"
        default: return "Clockwise 65 · counterclockwise 63"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 28) {
                    knobMonitor.frame(width: 260)
                    Rectangle().fill(Studio.line).frame(width: 1)
                    mapping.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(26).background(Studio.surface, in: RoundedRectangle(cornerRadius: 15))

                HStack(alignment: .top, spacing: 14) {
                    knobButton(39, title: "Press", icon: "hand.tap")
                    knobButton(40, title: "Touch", icon: "hand.point.up")
                    VStack(alignment: .leading, spacing: 9) {
                        overline("MAKE THE CONNECTION")
                        Text("Use MIDI learn in your DAW to assign the knob. For relative mode, match its encoder format to the one above.")
                            .font(.system(size: 11)).foregroundStyle(Studio.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Studio.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
                }
            }.padding(28)
        }
    }

    private var knobMonitor: some View {
        VStack(spacing: 19) {
            HStack { overline("ROTARY ENCODER"); Spacer(); liveBadge(model.connected ? (model.encoderHasActivity ? "Live" : "Ready") : "Disconnected", active: model.connected) }
            ZStack {
                ForEach(0..<41) { tick in
                    Capsule().fill(tick % 5 == 0 ? Studio.muted.opacity(0.65) : Studio.muted.opacity(0.2))
                        .frame(width: tick % 5 == 0 ? 2 : 1, height: tick % 5 == 0 ? 9 : 5)
                        .offset(y: -103).rotationEffect(.degrees(Double(tick) * 6.75 - 135))
                }
                Circle().trim(from: 0.125, to: 0.875).stroke(Studio.line, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(90)).frame(width: 180, height: 180)
                if absolute {
                    Circle().trim(from: 0.125, to: 0.125 + normalized * 0.75)
                        .stroke(Studio.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(90))
                        .frame(width: 180, height: 180).shadow(color: Studio.accent.opacity(0.25), radius: 10)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: model.encoderValue)
                }
                Circle().fill(LinearGradient(colors: [Color(hex: 0x323B3D), Studio.inset], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(Studio.text.opacity(0.08), lineWidth: 1))
                    .frame(width: 153, height: 153).shadow(color: .black.opacity(0.4), radius: 14, y: 9)
                Circle().strokeBorder(Studio.line, lineWidth: 1).frame(width: 129, height: 129)
                Capsule().fill(Studio.accent).frame(width: 4, height: 15).offset(y: -61)
                    .rotationEffect(.degrees(absolute ? -135 + normalized * 270 : model.encoderRotation))
                    .shadow(color: Studio.accent.opacity(0.5), radius: 5)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: absolute ? Double(model.encoderValue) : model.encoderRotation)
                VStack(spacing: 5) {
                    Text(absolute ? String(model.encoderValue) : model.encoderHasActivity ? (model.encoderLastDelta > 0 ? "+\(model.encoderLastDelta)" : "\(model.encoderLastDelta)") : "—")
                        .font(.system(size: 34, weight: .medium, design: .monospaced)).foregroundStyle(Studio.text).contentTransition(.numericText())
                    Text(absolute ? (model.encoderHasActivity ? "VALUE" : "INITIAL") : "LAST DELTA")
                        .font(.system(size: 8, weight: .semibold)).tracking(1.5).foregroundStyle(Studio.muted)
                }
            }.frame(width: 226, height: 226)
            HStack {
                VStack(alignment: .leading, spacing: 5) { overline("MIDI CC"); Text(String(format: "%03d", model.settings.encoder_cc)).font(.system(size: 16, weight: .medium, design: .monospaced)) }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) { overline("MODE"); Text(absolute ? "Absolute" : "Relative").font(.system(size: 13, weight: .medium)).foregroundStyle(Studio.accent) }
            }
            Text("Turn your Mikro’s knob to see it respond.").font(.system(size: 10)).foregroundStyle(Studio.muted)
        }
    }

    private var mapping: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { overline("KNOB MAPPING"); Spacer(); Text("Channel \(model.settings.midi_channel)").font(.system(size: 10)).foregroundStyle(Studio.muted) }
            HStack { Text("MIDI control change"); Spacer(); MIDIIntegerField(value: $model.settings.encoder_cc, range: 0...127, label: "Knob MIDI CC") }
            Picker("Knob mode", selection: $model.settings.encoder_mode) { Text("Relative").tag("relative"); Text("Absolute").tag("absolute") }.pickerStyle(.segmented).labelsHidden()
            VStack(alignment: .leading, spacing: 9) {
                if absolute {
                    overline("VALUE RANGE")
                    HStack(spacing: 15) {
                        rangeValue("Minimum", binding: Binding(get: { model.settings.encoder_min }, set: { model.setEncoderMinimum($0) }), range: 0...(model.settings.encoder_max - 1))
                        rangeValue("Maximum", binding: Binding(get: { model.settings.encoder_max }, set: { model.setEncoderMaximum($0) }), range: (model.settings.encoder_min + 1)...127)
                        rangeValue("Initial", binding: $model.settings.encoder_initial, range: model.settings.encoder_min...model.settings.encoder_max)
                    }
                    Text("Initial is the starting value. Turning sends the next value within this range.").font(.system(size: 10)).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    overline("DAW ENCODER FORMAT")
                    Picker("Encoder format", selection: $model.settings.encoder_relative_format) {
                        Text("64 offset").tag("offset")
                        Text("Two’s complement").tag("twos_complement")
                        Text("Sign magnitude").tag("sign_magnitude")
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatDetail + (model.settings.encoder_invert ? " · reversed" : ""))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Studio.muted)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Studio.inset, in: RoundedRectangle(cornerRadius: 9))
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("Step size"); Text(absolute ? "Value change per detent" : "MIDI increments per detent").font(.system(size: 10)).foregroundStyle(Studio.muted) }
                Spacer()
                MIDIIntegerField(value: $model.settings.encoder_step, range: 1...16, label: "Knob step size")
            }
            Toggle("Reverse direction", isOn: $model.settings.encoder_invert).toggleStyle(.switch).controlSize(.small)
        }
    }

    private func rangeValue(_ title: String, binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10)).foregroundStyle(Studio.muted)
            MIDIIntegerField(value: binding, range: range, label: "Knob \(title.lowercased())")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func knobButton(_ index: Int, title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Studio.accent)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Circle().fill(model.activeButtons.contains(index) ? Studio.accent : Studio.muted.opacity(0.25)).frame(width: 5, height: 5)
            }
            HStack { Text("CC").font(.system(size: 11, design: .monospaced)).foregroundStyle(Studio.muted); Spacer(); MIDIIntegerField(value: Binding(get: { model.settings.button_ccs[index] }, set: { model.settings.button_ccs[index] = $0 }), range: 0...127, label: "Knob \(title.lowercased()) CC") }
        }.padding(18).frame(width: 150).background(Studio.surface, in: RoundedRectangle(cornerRadius: 11))
    }
}

struct TouchStripWorkspace: View {
    @Bindable var model: MikroModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    private var pitchBend: Bool { model.settings.touch_strip_mode == "pitch_bend" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 25) {
                    HStack {
                        overline("TOUCH STRIP")
                        Spacer()
                        liveBadge(model.connected ? (model.stripTouched ? "Touch active" : "Ready") : "Disconnected", active: model.connected)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(format: "%03d", model.stripValue)).font(.system(size: 46, weight: .medium, design: .monospaced)).tracking(-2)
                        Text("POSITION / 127").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(Studio.muted)
                        Spacer()
                        Text(pitchBend ? "Pitch bend" : "CC \(model.settings.touch_strip_cc)").font(.system(size: 13, weight: .medium)).foregroundStyle(Studio.accent)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<32) { segment in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Double(segment) / 31 <= Double(model.stripValue) / 127 && model.stripTouched ? Studio.accent : Studio.accent.opacity(0.07))
                                .frame(height: 43)
                        }
                    }.padding(13).background(Studio.inset, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Studio.accent.opacity(model.stripTouched ? 0.08 : 0), radius: 18)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.07), value: model.stripValue)
                    HStack { Text("LEFT"); Spacer(); Text("Move your finger along the hardware strip."); Spacer(); Text("RIGHT") }.font(.system(size: 10)).foregroundStyle(Studio.muted)
                }.padding(26).background(Studio.surface, in: RoundedRectangle(cornerRadius: 14))
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 20) {
                        overline("STRIP MAPPING")
                        Picker("Touch strip mode", selection: $model.settings.touch_strip_mode) { Text("Control change").tag("cc"); Text("Pitch bend").tag("pitch_bend") }.pickerStyle(.segmented).labelsHidden()
                        HStack { Text("MIDI CC").foregroundStyle(pitchBend ? Studio.muted : Studio.text); Spacer(); MIDIIntegerField(value: $model.settings.touch_strip_cc, range: 0...127, label: "Touch strip MIDI CC").disabled(pitchBend).opacity(pitchBend ? 0.4 : 1) }
                        Text(pitchBend ? "Pitch bend uses its own MIDI message. CC is unused in this mode." : "Control change sends values from 0 to 127.").font(.system(size: 11)).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
                    }.padding(24).frame(maxWidth: .infinity).background(Studio.surface, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 15) {
                        overline("A LITTLE MOVEMENT")
                        Text(pitchBend ? "Bend a lead. Add a little life." : "Open a filter. Sweep an effect.").font(.system(size: 20, weight: .medium)).tracking(-0.4)
                        Text(pitchBend ? "Your instrument controls the pitch-bend range. Pitch stays at the last position. Use Panic in Setup to return to center." : "Use MIDI learn in your DAW to connect this strip to a parameter. Its last CC value stays in place when you lift your finger.")
                            .font(.system(size: 12)).foregroundStyle(Studio.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Studio.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(28)
        }
    }
}

struct MIDIIntegerField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            TextField(label, value: Binding(get: { value }, set: { value = min(range.upperBound, max(range.lowerBound, $0)) }), format: .number.grouping(.never))
                .textFieldStyle(.plain).font(.system(size: 13, weight: .medium, design: .monospaced)).multilineTextAlignment(.trailing).frame(width: 33)
                .accessibilityLabel(label)
            Stepper(label, value: $value, in: range).labelsHidden().controlSize(.mini).fixedSize()
        }.padding(.vertical, 5).padding(.leading, 8).padding(.trailing, 3).background(Studio.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
    }
}

private func overline(_ title: String) -> some View {
    Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(Studio.muted)
}

private func liveBadge(_ text: String, active: Bool) -> some View {
    HStack(spacing: 5) { Circle().fill(active ? Studio.accent : Studio.muted).frame(width: 4, height: 4); Text(text).font(.system(size: 9, weight: .medium)).foregroundStyle(active ? Studio.accent : Studio.muted) }
        .padding(.horizontal, 8).padding(.vertical, 5).background(Studio.accent.opacity(0.07), in: Capsule())
}
