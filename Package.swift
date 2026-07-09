// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoopedWhisper",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LoopedWhisper", targets: ["Whisper"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "1.0.0"),
        .package(url: "https://github.com/soniqo/speech-swift", from: "0.0.21"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Whisper",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "ParakeetASR", package: "speech-swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/Whisper",
            // tools-version 6.0 (needed for .macOS(.v15)) defaults to the
            // Swift 6 language mode; the app is written against Swift 5
            // concurrency rules, so keep that mode until migrated.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WhisperTests",
            dependencies: ["Whisper"],
            path: "Tests/WhisperTests"
        )
    ]
)
