import Foundation
import UIKit
import ImageIO

/// Saves and loads the photos attached to PlaceCards inside the app's
/// documents directory. Only the file name is kept on `MediaItem.localPath`;
/// this type resolves it to a full URL.
struct MediaStore {
    private static let directoryName = "Media"

    /// Every list/grid cell and the detail view's photo strip call
    /// `loadImage`/`loadThumbnail` from inside their own `body` —
    /// re-evaluated on essentially every scroll frame and SwiftUI diff
    /// pass. Without a cache, that meant re-decoding a full-resolution
    /// on-device photo (routinely several thousand pixels wide, since
    /// `saveImage` keeps whatever the camera/Photos handed over) straight
    /// from disk on every single one of those passes — a major, systemic
    /// source of the whole app feeling slow, not something local to one
    /// screen. Keyed by filename for a full-size load, or
    /// `"<filename>#<maxPixelSize>"` for a thumbnail, so the two never
    /// collide.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// A modern iPhone's own camera photo can be 8000px+ on its long side —
    /// nothing in this app ever displays a photo anywhere near that large
    /// (the full-screen swipeable viewer, `PhotoViewerSheet`, is the
    /// biggest consumer, and it fits within a phone/tablet screen). Saving
    /// the original size anyway means every future load of that file pays
    /// for it: more disk space, slower reads, and a bigger source for
    /// `loadThumbnail` to downsample from — so this caps what actually
    /// gets written to disk, not just what gets displayed.
    private static let maxSavedDimension: CGFloat = 2048

    static func saveImage(_ image: UIImage, compressionQuality: CGFloat = 0.8) throws -> String {
        guard let data = downscaledIfNeeded(image, maxDimension: maxSavedDimension).jpegData(compressionQuality: compressionQuality) else {
            throw PlaceCardsError.invalidImage
        }
        return try saveImage(data: data)
    }

    /// Never upscales — a photo already smaller than `maxDimension` on its
    /// long side is returned untouched.
    private static func downscaledIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Writes already-encoded image bytes directly, with no `UIImage`
    /// round-trip — used for Google Places photo downloads, which arrive
    /// as ready-to-store JPEG data.
    static func saveImage(data: Data) throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let url = directoryURL.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    static func loadImage(fileName: String) -> UIImage? {
        let key = fileName as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let url = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// A downsampled decode for thumbnail-sized display (grid/list cells,
    /// the detail view's photo strip/hero banner) — decoding a
    /// multi-thousand-pixel photo in full just to shrink it down to a
    /// ~100pt thumbnail wastes CPU and memory for zero visible benefit.
    /// Uses ImageIO's own thumbnail generation, which downsamples while
    /// decoding, instead of `UIImage(data:)` followed by SwiftUI/Core
    /// Animation scaling the full-size result down after the fact (which
    /// still pays the full decode cost up front).
    static func loadThumbnail(fileName: String, maxPixelSize: CGFloat) -> UIImage? {
        let key = "\(fileName)#\(Int(maxPixelSize))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let url = directoryURL.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }

    /// Raw, undecoded bytes for a stored photo — used by `BackupService` to
    /// embed a card's actual photos in an exported backup with no
    /// unnecessary decode/re-encode round trip through `UIImage` (which
    /// would also silently recompress a JPEG a second time).
    static func loadData(fileName: String) -> Data? {
        try? Data(contentsOf: directoryURL.appendingPathComponent(fileName))
    }

    /// Writes bytes under an exact, already-known filename — unlike
    /// `saveImage(data:)`, which always mints a fresh UUID name for a
    /// newly captured/downloaded photo. `BackupService.restore`/
    /// `.importBoard` need this instead: a restored/imported card's
    /// `MediaItem.localPath` values are fixed at export time and must
    /// resolve to those same names afterward.
    static func writeData(_ data: Data, fileName: String) throws {
        try data.write(to: directoryURL.appendingPathComponent(fileName), options: .atomic)
    }

    static func delete(fileName: String) {
        let url = directoryURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        // NSCache has no prefix-based eviction, so a deleted file's cached
        // full-size entry and every thumbnail-size variant of it can't be
        // individually targeted — deletions are rare (user-initiated, one
        // photo at a time), so clearing the whole cache is a cheap,
        // correct trade: everything still on screen just gets re-decoded
        // once on its next redraw.
        cache.removeAllObjects()
    }
}
