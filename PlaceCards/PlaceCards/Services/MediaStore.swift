import Foundation
import UIKit

/// Saves and loads the photos attached to PlaceCards inside the app's
/// documents directory. Only the file name is kept on `MediaItem.localPath`;
/// this type resolves it to a full URL.
struct MediaStore {
    private static let directoryName = "Media"

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func saveImage(_ image: UIImage, compressionQuality: CGFloat = 0.8) throws -> String {
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw PlaceCardsError.invalidImage
        }
        let fileName = "\(UUID().uuidString).jpg"
        let url = directoryURL.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    static func loadImage(fileName: String) -> UIImage? {
        let url = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func delete(fileName: String) {
        let url = directoryURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
}
