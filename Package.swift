// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SoundTranslatorMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SoundTranslator", targets: ["SoundTranslatorApp"]),
        .library(name: "SoundTranslatorCore", targets: ["SoundTranslatorCore"])
    ],
    targets: [
        .target(
            name: "SoundTranslatorCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "SoundTranslatorApp",
            dependencies: ["SoundTranslatorCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "SoundTranslatorCoreTests",
            dependencies: ["SoundTranslatorCore"]
        )
    ]
)
