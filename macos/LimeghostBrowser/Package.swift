// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LimeghostBrowser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LimeghostBrowser", targets: ["LimeghostBrowser"])
    ],
    targets: [
        .target(name: "LimeghostCore"),
        .executableTarget(
            name: "LimeghostBrowser",
            dependencies: ["LimeghostCore"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "LimeghostCoreTests",
            dependencies: ["LimeghostCore"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "BrowserBehaviorTests",
            dependencies: ["LimeghostBrowser", "LimeghostCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
