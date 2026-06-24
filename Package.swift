// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoopedWhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LoopedWhisper", targets: ["Whisper"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Whisper",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/Whisper"
        ),
        .testTarget(
            name: "WhisperTests",
            dependencies: ["Whisper"],
            path: "Tests/WhisperTests"
        )
    ]
)
