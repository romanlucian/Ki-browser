import Foundation

extension BrandMark {
    /// Where the Mac app's copy of the artwork lives: the package's own
    /// resource bundle, which `Package.swift` fills from `Resources/`.
    ///
    /// Mac-only on purpose. `Bundle.module` exists only for a SwiftPM target
    /// with resources, so the phone answers the same question in
    /// `ios/Sources/IOSBrandMarkArtwork.swift`.
    static var artworkURL: URL? {
        Bundle.module.url(forResource: "limeghost-mark-small", withExtension: "png")
    }
}
