import AppKit
import Combine
import Foundation

@MainActor
final class InstallerModel: ObservableObject {
    enum State: Equatable {
        case ready, running(String), success(String), failure(String)
    }

    @Published var gameApp = ""
    @Published var modFolder = ""
    @Published var output = "Ready. Choose an action to begin."
    @Published var state: State = .ready
    @Published var showRestoreConfirmation = false

    private var task: Process?

    init() {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice/ADanceOfFireAndIce.app").path
        if FileManager.default.fileExists(atPath: defaultPath) {
            gameApp = defaultPath
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func chooseGame() {
        let panel = NSOpenPanel()
        panel.title = "Choose ADanceOfFireAndIce.app"
        panel.prompt = "Choose Game"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            gameApp = url.path
        }
    }

    func chooseMod() {
        let panel = NSOpenPanel()
        panel.title = "Choose an unpacked UMM mod folder"
        panel.prompt = "Choose Mod"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            modFolder = url.path
        }
    }

    func install() { runSetup(action: "install", label: "Installing mod loader") }
    func diagnose() { runSetup(action: "doctor", label: "Checking installation") }
    func restore() { runSetup(action: "uninstall", label: "Restoring vanilla game") }

    func addMod() {
        guard !modFolder.isEmpty else {
            state = .failure("Choose a mod folder first.")
            return
        }
        runSetup(action: "add-mod", label: "Adding mod", extra: ["--mod", modFolder])
    }

    private func runSetup(action: String, label: String, extra: [String] = []) {
        guard !isRunning else { return }
        guard let tools = Bundle.main.resourceURL?.appendingPathComponent("Tools"),
              FileManager.default.fileExists(atPath: tools.appendingPathComponent("setup_adofai_umm_macos.sh").path) else {
            state = .failure("Installer tools are missing from this app.")
            return
        }

        var arguments = [tools.appendingPathComponent("setup_adofai_umm_macos.sh").path, action]
        if !gameApp.isEmpty { arguments += ["--game-app", gameApp] }
        arguments += extra

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.currentDirectoryURL = tools
        process.standardOutput = pipe
        process.standardError = pipe
        task = process
        output = "$ " + arguments.map(shellDisplay).joined(separator: " ") + "\n\n"
        state = .running(label)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.output += text }
        }

        process.terminationHandler = { [weak self] completed in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.task = nil
                if completed.terminationStatus == 0 {
                    self?.state = .success(label.replacingOccurrences(of: "ing", with: "ed") + ".")
                } else {
                    self?.state = .failure("The operation failed. See the details below.")
                }
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            task = nil
            state = .failure(error.localizedDescription)
        }
    }

    private func shellDisplay(_ value: String) -> String {
        value.contains(" ") ? "\"\(value)\"" : value
    }
}
