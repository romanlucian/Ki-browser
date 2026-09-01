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
            // The brand mark, so the address bar can draw it. The copy under
            // `Resources/` is exactly the small mark from
            // `docs/brand/limeghost-mark-2026-08-31/`, which stays the source of
            // truth — replace both together, and keep the *small* one here: the
            // full mark's ring turns to mud below 32 px.
            resources: [.process("Resources")],
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
