// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "diarprobe",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
    ],
    targets: [
        .executableTarget(name: "diarprobe", dependencies: [
            .product(name: "FluidAudio", package: "FluidAudio"),
            .product(name: "SpeakerKit", package: "argmax-oss-swift"),
        ]),
    ]
)
