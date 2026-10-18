// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AIWorkLog",
    defaultLocalization: "ko",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIWorkLog", targets: ["AIWorkLog"]),
        .executable(name: "worklog-cli", targets: ["worklog-cli"]),
        .library(name: "WorkLogCore", targets: ["WorkLogCore"]),
    ],
    targets: [
        .target(
            name: "WorkLogCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "AIWorkLog",
            dependencies: ["WorkLogCore"]
        ),
        .executableTarget(
            name: "worklog-cli",
            dependencies: ["WorkLogCore"]
        ),
        .testTarget(
            name: "WorkLogCoreTests",
            dependencies: ["WorkLogCore"]
        ),
    ]
)
