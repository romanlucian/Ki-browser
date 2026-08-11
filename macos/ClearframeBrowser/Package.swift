// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClearframeBrowser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClearframeBrowser", targets: ["ClearframeBrowser"])
    ],
    targets: [
        .target(name: "ClearframeCore"),
        .executableTarget(
            name: "ClearframeBrowser",
            dependencies: ["ClearframeCore"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "ClearframeCoreTests",
            dependencies: ["ClearframeCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
