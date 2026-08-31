// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ADOFAIModInstaller",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ADOFAIModInstaller", targets: ["ADOFAIModInstaller"])],
    targets: [
        .executableTarget(
            name: "ADOFAIModInstaller",
            path: "Sources/ADOFAIModInstaller"
        )
    ]
)
