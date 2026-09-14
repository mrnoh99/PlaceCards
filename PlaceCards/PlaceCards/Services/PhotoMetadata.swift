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
        let coordinate = Coordinates(
            latitude: latitudeRef == "S" ? -latitude : latitude,
            longitude: longitudeRef == "W" ? -longitude : longitude
        )
        // Some photo export/edit pipelines keep the GPS IFD structure but
        // write 0 for both latitude and longitude instead of omitting the
        // block entirely when there's no real location fix — no genuine
        // photo is actually taken at 0°N, 0°E (open ocean off the coast
        // of Africa, nicknamed "Null Island"), so this is treated the
        // same as no GPS data at all rather than a real coordinate that
        // would otherwise enable "GPS로 촬영위치찾기"/location-hint
        // features on a photo with no actual location in it.
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else {
            return nil
        }
        return coordinate
    }
}
