// swift-tools-version: 5.9
// whisper.cpp 1.9.5 (MIT, ggml-org): the engine of the recorder's "Better
// transcription" (docs/meeting-recorder.md, "Transcription"). The
// project's own XCFramework (Metal built in), fetched by Xcode and checked
// by its checksum; its build b5454 is the v1.9.5 commit (d1be6fd). Linked
// by skil.li Transcriber only, never by the app.
import PackageDescription

let package = Package(
    name: "WhisperCpp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperCpp", targets: ["whisper"]),
    ],
    targets: [
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
            checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"
        ),
    ]
)
