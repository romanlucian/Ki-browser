// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LimeghostBrowser",
    platforms: [
        .macOS(.v14),
        // iOS 17 is the floor: `WKWebsiteDataStore(forIdentifier:)`,
        // `.focusable` on iOS, and `onChange(of:initial:)` all arrive there.
        .iOS(.v17)
    ],
    products: [
        .executable(name: "LimeghostBrowser", targets: ["LimeghostBrowser"]),
        // The iOS app is an Xcode target that consumes these two as a local
        // package; SwiftPM cannot build an iOS app itself.
        .library(name: "LimeghostShared", targets: ["LimeghostShared"])
    ],
    targets: [
        .target(name: "LimeghostCore"),
        .target(
            name: "LimeghostShared",
            dependencies: ["LimeghostCore"],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech")
            ]
        ),
        .executableTarget(
            name: "LimeghostBrowser",
            dependencies: ["LimeghostCore", "LimeghostShared"],
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
            name: "LimeghostSharedTests",
            dependencies: ["LimeghostShared", "LimeghostCore"]
        ),
        .testTarget(
            name: "BrowserBehaviorTests",
            dependencies: ["LimeghostBrowser", "LimeghostCore", "LimeghostShared"]
        )
    ],
    swiftLanguageModes: [.v5]
)
