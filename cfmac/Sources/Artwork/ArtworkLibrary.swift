import AppKit
import Foundation

/// Finds cfmac's bundled resources: the legal documents and the downloaded artwork.
///
/// In the app they live in `Contents/Resources`. A development build reads them from the
/// folder named by `CFMAC_RESOURCES_DIR` (the package root, which holds `Artwork/`).
public enum ArtworkLibrary {
    public static let resourcesDirectory: URL? = {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["CFMAC_RESOURCES_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        guard let bundled = Bundle.main.resourceURL else { return nil }
        let markers = ["TERMS.md", "Artwork"]
        return markers.contains { fileManager.fileExists(atPath: bundled.appendingPathComponent($0).path) } ? bundled : nil
    }()

    /// The artwork folder, if this copy of cfmac has one.
    public static var artworkDirectory: URL? {
        resourcesDirectory?.appendingPathComponent("Artwork", isDirectory: true)
    }

    /// A file inside the artwork folder, or `nil` when it is missing.
    public static func url(_ relativePath: String) -> URL? {
        guard let url = artworkDirectory?.appendingPathComponent(relativePath),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    public static func image(_ relativePath: String) -> NSImage? {
        url(relativePath).flatMap(NSImage.init(contentsOf:))
    }
}
