import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: InstallerModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $tab) {
                dashboard.tabItem { Label("Setup", systemImage: "house.fill") }.tag(0)
                installedMods.tabItem { Label("Installed Mods", systemImage: "puzzlepiece.extension.fill") }.tag(1)
                recommended.tabItem { Label("Get Mods", systemImage: "sparkles") }.tag(2)
            }.padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("Restore vanilla ADOFAI?", isPresented: $model.showRestoreConfirmation, titleVisibility: .visible) {
            Button("Restore Vanilla", role: .destructive) { model.restore() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("The loader will be removed and the original game restored. Your Mods folder is preserved.") }
        .confirmationDialog("Remove \(model.modPendingRemoval?.name ?? "this mod")?", isPresented: Binding(
            get: { model.modPendingRemoval != nil }, set: { if !$0 { model.modPendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Mod", role: .destructive) { if let mod = model.modPendingRemoval { model.removeMod(mod) }; model.modPendingRemoval = nil }
            Button("Cancel", role: .cancel) { model.modPendingRemoval = nil }
        } message: { Text("The mod will be moved to a dated backup, so it can be recovered later.") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "flame.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(.orange.gradient)
                .frame(width: 48, height: 48).background(.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) { Text("ADOFAI Mod Installer").font(.title2.bold()); Text("Native mod management for macOS").foregroundStyle(.secondary) }
            Spacer(); Text("NO WINE").font(.caption.bold()).foregroundStyle(.green).padding(.horizontal, 10).padding(.vertical, 6).background(.green.opacity(0.12), in: Capsule())
        }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18).background(.bar)
    }

    private var dashboard: some View { ScrollView { VStack(spacing: 18) { gameSection; setupActions; status; friendlyResults }.padding(24) } }
    private var gameSection: some View {
        GroupBox("Steam game") { HStack {
            Image(systemName: model.gameApp.isEmpty ? "questionmark.folder" : "checkmark.circle.fill").foregroundStyle(model.gameApp.isEmpty ? Color.secondary : Color.green)
            Text(model.gameApp.isEmpty ? "ADOFAI was not found automatically" : model.gameApp).font(.callout).lineLimit(2).truncationMode(.middle)
            Spacer(); Button("Choose…") { model.chooseGame() }
        }.padding(.vertical, 6) }
    }
    private var setupActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ActionButton(title: model.isInstalled ? "Repair or Update" : "Install", subtitle: model.isInstalled ? "Existing installation detected" : "Loader + Steam support", icon: "arrow.down.app.fill", tint: .blue) { model.install() }
                ActionButton(title: "Run Diagnostics", subtitle: "Check every component", icon: "stethoscope", tint: .purple) { model.diagnose() }
            }
            HStack(spacing: 12) {
                ActionButton(title: "Manage Mods", subtitle: "Enable, disable, add, or remove", icon: "puzzlepiece.extension.fill", tint: .orange) { tab = 1 }
                ActionButton(title: "Restore Vanilla", subtitle: "Mods folder is preserved", icon: "arrow.uturn.backward.circle.fill", tint: .red) { model.showRestoreConfirmation = true }
            }
        }.disabled(model.isRunning)
    }

    private var installedMods: some View {
        ScrollView { VStack(spacing: 16) {
            HStack { Text("Installed Mods").font(.title2.bold()); Spacer(); Button { model.loadMods() } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
            zipDropZone
            if model.installedMods.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("No mods found").font(.headline)
                    Text("Drop a UMM mod ZIP above or choose one from your Mac.").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(30)
            } else {
                VStack(spacing: 0) { ForEach(model.installedMods) { mod in
                    HStack(spacing: 12) {
                        Image(systemName: mod.enabled ? "checkmark.circle.fill" : "pause.circle.fill").font(.title2).foregroundStyle(mod.enabled ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 3) { Text(mod.name).font(.headline); Text(metadata(mod)).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Toggle("Enabled", isOn: Binding(get: { mod.enabled }, set: { model.setMod(mod, enabled: $0) })).toggleStyle(.switch).labelsHidden()
                        Button(role: .destructive) { model.modPendingRemoval = mod } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }.padding(14)
                    if mod.id != model.installedMods.last?.id { Divider() }
                } }.background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
            }
            status; friendlyResults
        }.padding(24) }.disabled(model.isRunning)
    }
    private func metadata(_ mod: InstallerModel.InstalledMod) -> String {
        [mod.version.isEmpty ? nil : "Version \(mod.version)", mod.author.isEmpty ? nil : mod.author].compactMap { $0 }.joined(separator: " · ")
    }
    private var zipDropZone: some View {
        VStack(spacing: 9) {
            Image(systemName: "doc.zipper").font(.system(size: 30)).foregroundStyle(.blue)
            Text("Drop a UMM mod ZIP here").font(.headline); Text("The installer checks the archive before adding it.").font(.caption).foregroundStyle(.secondary)
            Button("Choose ZIP…") { model.chooseZip() }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity).padding(20).background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.blue.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7])))
        .dropDestination(for: URL.self) { urls, _ in guard let url = urls.first(where: { $0.pathExtension.lowercased() == "zip" }) else { return false }; model.installZip(url); return true }
    }

    private var recommended: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text("Recommended Mods").font(.title2.bold()); Text("Known releases downloaded from their official GitHub pages and verified before installation.").foregroundStyle(.secondary)
            ForEach(model.recommendedMods) { mod in
                let installed = model.isModInstalled(mod.id); let dependencyMissing = mod.dependency.map { !model.isModInstalled($0) } ?? false
                HStack(spacing: 14) {
                    Image(systemName: installed ? "checkmark.seal.fill" : "sparkles").font(.title2).foregroundStyle(installed ? Color.green : Color.blue).frame(width: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(mod.name).font(.headline); Text("v\(mod.version)").font(.caption).foregroundStyle(.secondary) }
                        Text(mod.summary).font(.callout).foregroundStyle(.secondary)
                        if dependencyMissing { Text("Install \(mod.dependency!) first").font(.caption.bold()).foregroundStyle(.orange) }
                    }
                    Spacer()
                    if installed {
                        Button("Reinstall") { model.installRecommended(mod) }.buttonStyle(.bordered).disabled(dependencyMissing || model.isRunning)
                    } else {
                        Button("Install") { model.installRecommended(mod) }.buttonStyle(.borderedProminent).disabled(dependencyMissing || model.isRunning)
                    }
                }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5)))
            }
            status; friendlyResults
        }.padding(24) }
    }

    private var status: some View {
        HStack(spacing: 10) {
            switch model.state { case .ready: Image(systemName: "circle").foregroundStyle(.secondary); Text("Ready"); case .running(let text): ProgressView().controlSize(.small); Text(text); case .success(let text): Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(text); case .failure(let text): Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red); Text(text) }; Spacer()
        }.font(.callout.weight(.medium)).padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
    private var friendlyResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.diagnostics.isEmpty { GroupBox("System check") { VStack(spacing: 0) { ForEach(model.diagnostics) { item in HStack { Image(systemName: item.healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(item.healthy ? Color.green : Color.orange); Text(item.name).fontWeight(.medium); Spacer(); Text(item.value).foregroundStyle(.secondary).lineLimit(1) }.padding(.vertical, 7) } }.padding(.horizontal, 4) } }
            else if !model.results.isEmpty { GroupBox("Progress") { VStack(spacing: 0) { ForEach(model.results) { item in HStack(spacing: 10) { resultIcon(item.kind); VStack(alignment: .leading, spacing: 2) { Text(item.title).fontWeight(.medium); Text(item.detail).font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(.vertical, 7) } }.padding(.horizontal, 4) } }
            DisclosureGroup("Technical details") { ScrollView { Text(model.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8) }.frame(height: 130).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7)).padding(.top, 6) }.foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func resultIcon(_ kind: InstallerModel.ResultItem.Kind) -> some View {
        switch kind { case .working: ProgressView().controlSize(.small).frame(width: 18); case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 18); case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).frame(width: 18); case .info: Image(systemName: "info.circle.fill").foregroundStyle(.blue).frame(width: 18) }
    }
}

private struct ActionButton: View {
    let title: String; let subtitle: String; let icon: String; let tint: Color; let action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 12) { Image(systemName: icon).font(.title2).foregroundStyle(tint).frame(width: 32); VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(13).contentShape(Rectangle()) }.buttonStyle(.plain).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.55))) }
}
