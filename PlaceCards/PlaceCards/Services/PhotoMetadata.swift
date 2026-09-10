import Foundation
import ImageIO

/// Best-effort extraction of a photo's own embedded GPS coordinate (EXIF)
/// — used to narrow ("locationBias") the Google Places search when adding
/// a place from an on-site photo that has one, instead of a blind text
/// search. Ported from Peragra's `PhotoMetadata` (there also reads capture
/// time/accuracy for its own on-site GPS-capture flow, which PlaceCards
/// doesn't have, so only the coordinate is extracted here).
enum PhotoMetadata {
    /// `data` must be the original, unmodified bytes as picked — EXIF
    /// doesn't survive being decoded into a `UIImage` and re-encoded
    /// (e.g. via `UIImage.jpegData(compressionQuality:)`).
    static func extractLocation(from data: Data) -> Coordinates? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
            let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
            let longitude = gps[kCGImagePropertyGPSLongitude] as? Double,
            let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        else {
            return nil
        }
        return Coordinates(
            latitude: latitudeRef == "S" ? -latitude : latitude,
            longitude: longitudeRef == "W" ? -longitude : longitude
        )
    }
}
