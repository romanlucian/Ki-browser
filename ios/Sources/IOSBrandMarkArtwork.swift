import Foundation

extension BrandMark {
    /// Where the phone's copy of the artwork lives: the app bundle itself.
    ///
    /// The Mac reads the same drawing out of its package's resource bundle
    /// (`BrandMarkArtwork.swift`). The phone's project copies that very file,
    /// `limeghost-mark-small.png`, into its own bundle by reference, so there
    /// is one drawing and not two.
    static var artworkURL: URL? {
        Bundle.main.url(forResource: "limeghost-mark-small", withExtension: "png")
    }
}
