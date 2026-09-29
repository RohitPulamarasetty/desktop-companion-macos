// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopCompanion",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "Core",
            path: "Sources/Core",
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedLibrary("z")]
        ),
        // Dependency-free test runner (XCTest needs full Xcode).
        .executableTarget(
            name: "CoreTestsRunner",
            dependencies: ["Core"],
            path: "Sources/CoreTestsRunner",
        ),
        .target(name: "PlatformMac", dependencies: ["Core"], path: "Sources/Platform/macOS"),
        .target(name: "Diagnostics", dependencies: ["Core"], path: "Sources/Diagnostics"),
        .executableTarget(
            name: "DesktopCompanionApp",
            dependencies: ["Core", "PlatformMac", "Diagnostics"],
            path: "Sources/App",
            exclude: ["Info.plist", "AppIcon.icns"]
        ),
    ]
)
