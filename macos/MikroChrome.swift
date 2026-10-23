import SwiftUI

struct MikroSidebar: View {
    @Bindable var model: MikroModel
    @Binding var showingReset: Bool

    var body: some View {
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
            Spacer(minLength: 28)
            label("CONTROLLER").padding(.leading, 10).padding(.bottom, 10)
            controllerCard
            VStack(spacing: 4) {
                Menu {
                    Button("Import Preset…") { model.importPreset() }
                    Button("Export Preset…") { model.exportPreset() }
                    Divider()
                    Button("Reset MIDI Assignments") { model.resetAssignments() }
                    Button("Restore Defaults…", role: .destructive) { showingReset = true }
                } label: {
                    actionLabel("Presets", icon: "square.stack", accessory: "chevron.down")
                }
                .menuStyle(.button).menuIndicator(.hidden)
                .buttonStyle(SidebarActionStyle()).accessibilityLabel("Presets")

                Button { model.appBehavior.hideWindow() } label: {
                    actionLabel("Run in background", icon: "macwindow", accessory: "arrow.down.right")
                }
                .buttonStyle(SidebarActionStyle())
                .help("Close this window and keep Mikro MIDI running. Reopen it from the menu bar or Dock.")
            }.padding(.top, 10)
            HStack(spacing: 5) {
                Text("OPEN SOURCE").font(.system(size: 8, weight: .medium)).tracking(1.2)
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")").font(.system(size: 9, design: .monospaced))
            }.foregroundStyle(Studio.muted.opacity(0.7)).padding(.top, 18).padding(.bottom, 23)
        }.padding(.horizontal, 16).frame(width: 214).background(Studio.sidebar)
    }

    private var controllerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.4x3.fill")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Studio.accent.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(Studio.accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Maschine").font(.system(size: 12, weight: .semibold))
                    Text("Mikro MK3").font(.system(size: 11)).foregroundStyle(Studio.muted)
                }
            }
            Rectangle().fill(Studio.line).frame(height: 1)
            HStack(spacing: 7) {
                Circle().fill(model.connected ? Studio.accent : Studio.muted).frame(width: 5, height: 5)
                Text(model.stateTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.connected ? Studio.accent : Studio.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button { if model.hasProcess { model.stop() } else { model.start() } } label: {
                    Image(systemName: model.hasProcess ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(SidebarActionStyle(filled: true))
                .disabled(model.preview)
                .accessibilityLabel(model.hasProcess ? "Stop driver" : "Start driver")
                .help(model.hasProcess ? "Stop MIDI driver" : "Start MIDI driver")
            }
        }
        .padding(12)
        .background(Studio.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Studio.line))
    }

    private func actionLabel(_ title: String, icon: String, accessory: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 12)).frame(width: 17)
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer(minLength: 0)
            Image(systemName: accessory).font(.system(size: 8, weight: .semibold)).foregroundStyle(Studio.muted)
        }
        .padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle())
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
    }

    private var logo: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(7), spacing: 3), count: 3), spacing: 3) {
            ForEach(0..<9) { i in RoundedRectangle(cornerRadius: 1.7).fill(Studio.accent.opacity(i == 2 || i == 5 ? 0.35 : 1)).frame(width: 7, height: 7) }
        }.frame(width: 27)
    }

    private func label(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Studio.muted) }
}

private struct SidebarActionStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        SidebarActionBody(configuration: configuration, filled: filled)
    }

    private struct SidebarActionBody: View {
        let configuration: ButtonStyle.Configuration
        let filled: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? Studio.text : Studio.muted)
                .background(Studio.text.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : filled ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 7))
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

struct MikroFooter: View {
    @Bindable var model: MikroModel

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path").font(.system(size: 12)).foregroundStyle(Studio.accent)
            Text(model.settings.port_name).font(.system(size: 10, weight: .medium))
            Text("/  CH \(String(format: "%02d", model.settings.midi_channel))").font(.system(size: 9, design: .monospaced)).foregroundStyle(Studio.muted)
            Spacer()
            Text(model.activity.first?.text ?? (model.preview ? "Preview · hardware disconnected" : "No MIDI activity")).font(.system(size: 10)).foregroundStyle(Studio.muted).lineLimit(1)
            Button { model.workspace = .setup } label: { Image(systemName: "questionmark.circle").font(.system(size: 14)).foregroundStyle(Studio.muted) }.buttonStyle(.plain).help("Setup and help").padding(.leading, 8)
        }.padding(.horizontal, 28).frame(height: 44).background(Studio.sidebar.opacity(0.6)).overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: 1) }
    }
}

struct MikroAssignmentUndoBanner: View {
    @Bindable var model: MikroModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").foregroundStyle(Studio.accent)
            Text("MIDI assignments reset.").font(.system(size: 11, weight: .medium))
            Text("Colors preserved.").font(.system(size: 11)).foregroundStyle(Studio.muted)
            Spacer()
            Button("Undo") { model.undoAssignmentReset() }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Studio.accent)
            Button { model.dismissAssignmentUndo() } label: { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Studio.muted) }
                .buttonStyle(.plain).accessibilityLabel("Dismiss reset notification").padding(.leading, 10)
        }.padding(.horizontal, 28).frame(height: 42).background(Studio.accent.opacity(0.07))
            .overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: 1) }
    }
}
