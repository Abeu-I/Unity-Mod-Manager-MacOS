import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class InstallerModel: ObservableObject {
    struct ResultItem: Identifiable {
        enum Kind: Equatable { case working, success, failure, info }
        let id = UUID(); let title: String; let detail: String; let kind: Kind
    }
    struct DiagnosticItem: Identifiable {
        let id = UUID(); let name: String; let value: String; let healthy: Bool
    }
    struct InstalledMod: Identifiable {
        let id: String; let name: String; let version: String; let enabled: Bool; let author: String
    }
    struct RecommendedMod: Identifiable {
        let id: String; let name: String; let version: String; let summary: String; let dependency: String?
    }
    enum State: Equatable { case ready, running(String), success(String), failure(String) }

    @Published var gameApp = ""
    @Published var modFolder = ""
    @Published var output = "Ready. Choose an action to begin."
    @Published var results: [ResultItem] = []
    @Published var diagnostics: [DiagnosticItem] = []
    @Published var installedMods: [InstalledMod] = []
    @Published var modPendingRemoval: InstalledMod?
    @Published var isInstalled = false
    @Published var state: State = .ready
    @Published var showRestoreConfirmation = false
    private var task: Process?
    let recommendedMods = [
        RecommendedMod(id: "AdofaiTweaks", name: "ADOFAI Tweaks", version: "2.9.2", summary: "Key viewer, visual tweaks, editor tools, and gameplay options.", dependency: nil),
        RecommendedMod(id: "JALib", name: "JALib", version: "1.0.0.45", summary: "Shared library required by several Jongyeol mods.", dependency: nil),
        RecommendedMod(id: "JipperResourcePack", name: "Jipper Resource Pack", version: "1.4.9.0", summary: "Custom overlays, resources, and presentation tools.", dependency: "JALib"),
        RecommendedMod(id: "JipperOverlayer", name: "Jipper Overlayer", version: "1.1.4", summary: "Modern customizable gameplay overlay for Unity 6000.", dependency: nil),
        RecommendedMod(id: "ModernUMMUI", name: "Modern UMM UI", version: "1.0.0", summary: "A cleaner, more intuitive in-game mod manager window.", dependency: nil),
        RecommendedMod(id: "MacAutoPlay", name: "Mac AutoPlay", version: "0.1.0", summary: "Local/custom-level autoplay using ADOFAI's native auto mode.", dependency: nil)
    ]

    init() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice/ADanceOfFireAndIce.app").path
        if FileManager.default.fileExists(atPath: path) { gameApp = path }
        refreshInstalledState()
        loadMods()
    }

    var isRunning: Bool { if case .running = state { return true }; return false }

    func chooseGame() {
        let panel = NSOpenPanel(); panel.title = "Choose ADanceOfFireAndIce.app"; panel.prompt = "Choose Game"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { gameApp = url.path; refreshInstalledState() }
    }
    func chooseMod() {
        let panel = NSOpenPanel(); panel.title = "Choose an unpacked UMM mod folder"; panel.prompt = "Choose Mod"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { modFolder = url.path }
    }
    func chooseZip() {
        let panel = NSOpenPanel(); panel.title = "Choose a UMM mod ZIP"; panel.prompt = "Install Mod"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        if panel.runModal() == .OK, let url = panel.url { installZip(url) }
    }

    func install() { runSetup(action: "install", label: isInstalled ? "Repairing installation" : "Installing mod loader") }
    func diagnose() { runSetup(action: "doctor", label: "Checking installation") }
    func restore() { runSetup(action: "uninstall", label: "Restoring vanilla game") }
    func addMod() {
        guard !modFolder.isEmpty else { state = .failure("Choose a mod folder first."); return }
        runSetup(action: "add-mod", label: "Adding mod", extra: ["--mod", modFolder])
    }
    func installZip(_ url: URL) { runSetup(action: "install-zip", label: "Installing ZIP mod", extra: ["--zip", url.path]) }
    func setMod(_ mod: InstalledMod, enabled: Bool) {
        runSetup(action: enabled ? "enable-mod" : "disable-mod", label: enabled ? "Enabling \(mod.name)" : "Disabling \(mod.name)", extra: ["--mod-id", mod.id])
    }
    func removeMod(_ mod: InstalledMod) { runSetup(action: "remove-mod", label: "Removing \(mod.name)", extra: ["--mod-id", mod.id]) }
    func installRecommended(_ mod: RecommendedMod) {
        if mod.id == "MacAutoPlay" {
            runScript(name: "build_mac_autoplay.sh", arguments: ["--install"], label: "Installing Mac AutoPlay")
        } else if mod.id == "ModernUMMUI" {
            runScript(name: "build_modern_umm_ui.sh", arguments: ["--install"], label: "Installing Modern UMM UI")
        } else {
            runSetup(action: "install-recommended", label: "Installing \(mod.name)", extra: ["--mod-id", mod.id])
        }
    }
    func isModInstalled(_ id: String) -> Bool { installedMods.contains { $0.id == id } }

    func loadMods() {
        guard let tools = Bundle.main.resourceURL?.appendingPathComponent("Tools"), !gameApp.isEmpty else { return }
        let script = tools.appendingPathComponent("setup_adofai_umm_macos.sh").path
        let game = gameApp
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script, "list-mods", "--game-app", game]
            process.standardOutput = pipe; process.standardError = Pipe()
            do { try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                let mods = text.split(separator: "\n").compactMap { line -> InstalledMod? in
                    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    guard fields.count >= 6, fields[0] == "MOD" else { return nil }
                    return InstalledMod(id: fields[1], name: fields[2], version: fields[3], enabled: fields[4] == "true", author: fields[5])
                }
                DispatchQueue.main.async { self?.installedMods = mods.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
            } catch { }
        }
    }

    private func runSetup(action: String, label: String, extra: [String] = []) {
        guard !isRunning else { return }
        guard let tools = Bundle.main.resourceURL?.appendingPathComponent("Tools"),
              FileManager.default.fileExists(atPath: tools.appendingPathComponent("setup_adofai_umm_macos.sh").path) else {
            state = .failure("Installer tools are missing from this app."); return
        }
        var arguments = [action]
        if !gameApp.isEmpty { arguments += ["--game-app", gameApp] }; arguments += extra
        runProcess(script: tools.appendingPathComponent("setup_adofai_umm_macos.sh").path, arguments: arguments, label: label, directory: tools)
    }

    private func runProcess(script: String, arguments: [String], label: String, directory: URL) {
        guard !isRunning else { return }
        let command = [script] + arguments
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash"); process.arguments = command
        process.currentDirectoryURL = directory; process.standardOutput = pipe; process.standardError = pipe; task = process
        var environment = ProcessInfo.processInfo.environment
        if !gameApp.isEmpty { environment["ADOFAI_GAME_APP"] = gameApp }
        process.environment = environment
        output = "$ " + command.map(shellDisplay).joined(separator: " ") + "\n\n"
        results = [ResultItem(title: label, detail: "Starting…", kind: .working)]; diagnostics = []; state = .running(label)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.output += text; self?.consume(text) }
        }
        process.terminationHandler = { [weak self] completed in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil; self?.task = nil
                let ok = completed.terminationStatus == 0; self?.finishResults(success: ok); self?.refreshInstalledState()
                self?.loadMods()
                self?.state = ok ? .success("Operation completed successfully.") : .failure("The operation could not be completed.")
            }
        }
        do { try process.run() } catch { pipe.fileHandleForReading.readabilityHandler = nil; task = nil; state = .failure(error.localizedDescription) }
    }

    private func runScript(name: String, arguments: [String], label: String) {
        guard let tools = Bundle.main.resourceURL?.appendingPathComponent("Tools") else { return }
        runProcess(script: tools.appendingPathComponent(name).path, arguments: arguments, label: label, directory: tools)
    }

    private func refreshInstalledState() {
        guard !gameApp.isEmpty else { isInstalled = false; return }
        let root = URL(fileURLWithPath: gameApp).deletingLastPathComponent()
        isInstalled = FileManager.default.fileExists(atPath: root.appendingPathComponent(".adofai-umm-macos/steam-bundle-launcher-installed.txt").path)
    }
    private func consume(_ chunk: String) {
        for raw in chunk.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines); guard !line.isEmpty else { continue }
            if line.hasPrefix("Downloading:") { addResult("Download Unity Mod Manager", "Downloading official package", .working) }
            else if line.contains("Building the native macOS components") { addResult("Build native components", "Compiling for this Mac", .working) }
            else if line == "Built native components successfully." { addResult("Build native components", "Completed", .success) }
            else if line == "Installation complete." { addResult("Install mod loader", "Completed", .success) }
            else if line.hasPrefix("Installed mod '") { addResult("Install mod", line, .success) }
            else if line.hasPrefix("ERROR:") || line.lowercased().hasPrefix("fatal error:") { addResult("Operation failed", line.replacingOccurrences(of: "ERROR: ", with: ""), .failure) }
            else if raw.hasPrefix("  "), let separator = line.firstIndex(of: ":") {
                let name = String(line[..<separator]); let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                let bad = ["not installed", "missing", "needs reinstall", "not available"].contains { value.lowercased().contains($0) }
                diagnostics.removeAll { $0.name == name }; diagnostics.append(DiagnosticItem(name: name, value: value, healthy: !bad))
            }
        }
    }
    private func addResult(_ title: String, _ detail: String, _ kind: ResultItem.Kind) {
        if let i = results.lastIndex(where: { $0.title == title }) { results[i] = ResultItem(title: title, detail: detail, kind: kind) }
        else { results.append(ResultItem(title: title, detail: detail, kind: kind)) }
    }
    private func finishResults(success: Bool) {
        for i in results.indices where results[i].kind == .working {
            let old = results[i]; results[i] = ResultItem(title: old.title, detail: success ? "Completed" : "Stopped before completion", kind: success ? .success : .failure)
        }
    }
    private func shellDisplay(_ value: String) -> String { value.contains(" ") ? "\"\(value)\"" : value }
}
