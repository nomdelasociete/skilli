// swift-tools-version: 6.2

import PackageDescription

// SwiftPM covers the platform-independent core so `swift test` runs fast.
// The app itself is built from `project.yml` (XcodeGen → Skilli.xcodeproj).
let package = Package(
    name: "Skilli",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "SkilliCore", targets: ["SkilliCore"])
    ],
    targets: [
        .target(
            name: "SkilliCore",
            path: "Sources/SkilliCore"
        ),
        .testTarget(
            name: "SkilliCoreTests",
            dependencies: ["SkilliCore"],
            path: "Tests/SkilliCoreTests"
        )
    ]
)
