import AppKit
import Combine
import Foundation

@MainActor
final class InstallerModel: ObservableObject {
    struct ResultItem: Identifiable {
        enum Kind { case working, success, failure, info }
        let id = UUID(); let title: String; let detail: String; let kind: Kind
    }
    struct DiagnosticItem: Identifiable {
        let id = UUID(); let name: String; let value: String; let healthy: Bool
    }
    enum State: Equatable { case ready, running(String), success(String), failure(String) }

    @Published var gameApp = ""
    @Published var modFolder = ""
    @Published var output = "Ready. Choose an action to begin."
    @Published var results: [ResultItem] = []
    @Published var diagnostics: [DiagnosticItem] = []
    @Published var isInstalled = false
    @Published var state: State = .ready
    @Published var showRestoreConfirmation = false
    private var task: Process?

    init() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice/ADanceOfFireAndIce.app").path
        if FileManager.default.fileExists(atPath: path) { gameApp = path }
        refreshInstalledState()
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

    func install() { runSetup(action: "install", label: isInstalled ? "Repairing installation" : "Installing mod loader") }
    func diagnose() { runSetup(action: "doctor", label: "Checking installation") }
    func restore() { runSetup(action: "uninstall", label: "Restoring vanilla game") }
    func addMod() {
        guard !modFolder.isEmpty else { state = .failure("Choose a mod folder first."); return }
        runSetup(action: "add-mod", label: "Adding mod", extra: ["--mod", modFolder])
    }

    private func runSetup(action: String, label: String, extra: [String] = []) {
        guard !isRunning else { return }
        guard let tools = Bundle.main.resourceURL?.appendingPathComponent("Tools"),
              FileManager.default.fileExists(atPath: tools.appendingPathComponent("setup_adofai_umm_macos.sh").path) else {
            state = .failure("Installer tools are missing from this app."); return
        }
        var arguments = [tools.appendingPathComponent("setup_adofai_umm_macos.sh").path, action]
        if !gameApp.isEmpty { arguments += ["--game-app", gameApp] }; arguments += extra
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash"); process.arguments = arguments
        process.currentDirectoryURL = tools; process.standardOutput = pipe; process.standardError = pipe; task = process
        output = "$ " + arguments.map(shellDisplay).joined(separator: " ") + "\n\n"
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
                self?.state = ok ? .success("Operation completed successfully.") : .failure("The operation could not be completed.")
            }
        }
        do { try process.run() } catch { pipe.fileHandleForReading.readabilityHandler = nil; task = nil; state = .failure(error.localizedDescription) }
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
