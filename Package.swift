// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LimitDude",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LimitDudeCore", targets: ["LimitDudeCore"]),
        .library(name: "LimitDudeMac", targets: ["LimitDudeMac"]),
        .executable(name: "LimitDude", targets: ["LimitDude"]),
        .executable(name: "LimitDudeClaudeCheck", targets: ["LimitDudeClaudeCheck"]),
        .executable(name: "LimitDudeCodexCheck", targets: ["LimitDudeCodexCheck"]),
        .executable(name: "LimitDudeCoreChecks", targets: ["LimitDudeCoreChecks"])
    ],
    targets: [
        .target(name: "LimitDudeCore"),
        .target(
            name: "LimitDudeMac",
            dependencies: ["LimitDudeCore"]
        ),
        .executableTarget(
            name: "LimitDude",
            dependencies: ["LimitDudeCore", "LimitDudeMac"]
        ),
        .executableTarget(
            name: "LimitDudeClaudeCheck",
            dependencies: ["LimitDudeCore", "LimitDudeMac"]
        ),
        .executableTarget(
            name: "LimitDudeCodexCheck",
            dependencies: ["LimitDudeCore", "LimitDudeMac"]
        ),
        .executableTarget(
            name: "LimitDudeCoreChecks",
            dependencies: ["LimitDudeCore"]
        )
    ]
)
