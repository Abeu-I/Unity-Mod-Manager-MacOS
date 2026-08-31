import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: InstallerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    gameSection
                    actions
                    status
                    friendlyResults
                }
                .padding(24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "Restore vanilla ADOFAI?",
            isPresented: $model.showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Vanilla", role: .destructive) { model.restore() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The loader will be removed and the original game executable restored. Your Mods folder is preserved.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.orange.gradient)
                .frame(width: 48, height: 48)
                .background(.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("ADOFAI Mod Installer").font(.title2.bold())
                Text("Native Unity Mod Manager setup for macOS")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("NO WINE")
                .font(.caption.bold())
                .foregroundStyle(.green)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.green.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
        .background(.bar)
    }

    private var gameSection: some View {
        GroupBox("Steam game") {
            HStack {
                Image(systemName: model.gameApp.isEmpty ? "questionmark.folder" : "checkmark.circle.fill")
                    .foregroundStyle(model.gameApp.isEmpty ? Color.secondary : Color.green)
                Text(model.gameApp.isEmpty ? "ADOFAI was not found automatically" : model.gameApp)
                    .font(.callout).lineLimit(2).truncationMode(.middle)
                Spacer()
                Button("Choose…") { model.chooseGame() }
            }
            .padding(.vertical, 6)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ActionButton(title: model.isInstalled ? "Repair or Update" : "Install", subtitle: model.isInstalled ? "Existing installation detected" : "Loader + Steam support", icon: "arrow.down.app.fill", tint: .blue) { model.install() }
                ActionButton(title: "Run Diagnostics", subtitle: "Check every component", icon: "stethoscope", tint: .purple) { model.diagnose() }
            }
            HStack(spacing: 12) {
                ActionButton(title: "Add a Mod", subtitle: model.modFolder.isEmpty ? "Choose an unpacked folder" : URL(fileURLWithPath: model.modFolder).lastPathComponent, icon: "puzzlepiece.extension.fill", tint: .orange) {
                    if model.modFolder.isEmpty { model.chooseMod() } else { model.addMod() }
                }
                ActionButton(title: "Restore Vanilla", subtitle: "Mods folder is preserved", icon: "arrow.uturn.backward.circle.fill", tint: .red) { model.showRestoreConfirmation = true }
            }
            if !model.modFolder.isEmpty {
                HStack {
                    Button("Choose a different mod…") { model.chooseMod() }
                    Button("Install selected mod") { model.addMod() }.buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
        }
        .disabled(model.isRunning)
    }

    private var status: some View {
        HStack(spacing: 10) {
            switch model.state {
            case .ready:
                Image(systemName: "circle").foregroundStyle(.secondary); Text("Ready")
            case .running(let text):
                ProgressView().controlSize(.small); Text(text)
            case .success(let text):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(text)
            case .failure(let text):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red); Text(text)
            }
            Spacer()
        }
        .font(.callout.weight(.medium))
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var friendlyResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.diagnostics.isEmpty {
                GroupBox("System check") {
                    VStack(spacing: 0) {
                        ForEach(model.diagnostics) { item in
                            HStack {
                                Image(systemName: item.healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(item.healthy ? Color.green : Color.orange)
                                Text(item.name).fontWeight(.medium)
                                Spacer()
                                Text(item.value).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.vertical, 7)
                            if item.id != model.diagnostics.last?.id { Divider() }
                        }
                    }.padding(.horizontal, 4)
                }
            } else if !model.results.isEmpty {
                GroupBox("Progress") {
                    VStack(spacing: 0) {
                        ForEach(model.results) { item in
                            HStack(spacing: 10) {
                                resultIcon(item.kind)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).fontWeight(.medium)
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 7)
                            if item.id != model.results.last?.id { Divider() }
                        }
                    }.padding(.horizontal, 4)
                }
            }
            DisclosureGroup("Technical details") {
                ScrollView {
                    Text(model.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .frame(height: 145)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .padding(.top, 6)
            }.foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func resultIcon(_ kind: InstallerModel.ResultItem.Kind) -> some View {
        switch kind {
        case .working: ProgressView().controlSize(.small).frame(width: 18)
        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 18)
        case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).frame(width: 18)
        case .info: Image(systemName: "info.circle.fill").foregroundStyle(.blue).frame(width: 18)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.55)))
    }
}
