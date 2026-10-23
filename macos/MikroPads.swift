import SwiftUI
import AppKit

struct MikroPadsPage: View {
    @Bindable var model: MikroModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
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
                        Text("⌘ click to add pads · ⇧ click for a range").font(.system(size: 10))
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
        let glowing = model.glowEnabled && pressed
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
                    Text(model.selectedPads.count > 1 ? "Group editing" : "Note on / note off").font(.system(size: 10)).foregroundStyle(Studio.muted)
                }
            }
            separator
            if model.selectedPads.count == 1 {
              VStack(alignment: .leading, spacing: 11) {
                label("MIDI NOTE")
                HStack {
                    Text(MikroModel.noteName(model.settings.notemaps[model.selectedPad])).font(.system(size: 25, weight: .medium)).tracking(-0.8)
                    Spacer()
                    MIDIIntegerField(value: Binding(get: { model.settings.notemaps[model.selectedPad] }, set: { model.settings.notemaps[model.selectedPad] = $0 }), range: 0...127, label: "Pad \(model.selectedPhysicalPad) MIDI note")
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
                    Text("Transpose in semitones.").font(.system(size: 10)).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
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
                Text("Saved automatically.").font(.system(size: 10)).lineSpacing(4).foregroundStyle(Studio.muted)
            }
        }.padding(24)
    }

    private func label(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Studio.muted) }

    private var separator: some View { Rectangle().fill(Studio.line).frame(height: 1) }
}
