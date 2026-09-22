import Foundation
import UIKit
import ImageIO
import Photos

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
        // A count limit alone bounds the wrong thing: these are decoded
        // bitmaps, and one full-size entry (`maxSavedDimension` 2048px
        // square, 4 bytes/pixel) is ~16MB against a thumbnail's fraction
        // of a megabyte, so 200 of the former is gigabytes while 200 of
        // the latter is nothing. `NSCache` does evict under memory
        // pressure, but only once the system is already in trouble —
        // costing each entry by its real byte size keeps this bounded
        // before that point instead.
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

    /// Decoded size in bytes — what an entry actually costs the cache,
    /// as opposed to the compressed size of the file it came from.
    private static func cacheCost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// How many photo files are stored and what they add up to on disk.
    /// Every photo this app keeps lands here and nothing ever prunes them
    /// on its own, so without this the one number a user might actually
    /// want before deciding whether to back up or clear anything — how
    /// much of their phone this app is using — was only visible from iOS
    /// Settings, not from the app itself. Walks the directory rather than
    /// summing anything cached, so it's called from a background task, not
    /// on every render.
    static func usage() -> (fileCount: Int, totalBytes: Int64) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: Array(keys)
        ) else {
            return (0, 0)
        }
        var count = 0
        var bytes: Int64 = 0
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            count += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return (count, bytes)
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
        cache.setObject(image, forKey: key, cost: cacheCost(of: image))
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
        cache.setObject(image, forKey: key, cost: cacheCost(of: image))
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


/// 카드에 붙은 사진을 **사용자의 사진 라이브러리** 안 "PinSpots" 앨범에
/// 넣는다. 사진 앱을 열어 그 앨범을 보면 거기 있다.
///
/// **왜 이런 모양인가.** 원래 바라던 것은 "이 사진을 사진 앱에서 바로
/// 열기"였는데, iOS에는 **특정 사진을 지정해 사진 앱을 여는 공개 API가
/// 없다.** 떠도는 `photos:`·`photos-navigation:` 스킴은 리버스
/// 엔지니어링된 것이고 특정 사진 지정은 동작이 확인되지 않았다 —
/// 추측한 외부 스킴은 쓰지 않는다는 규칙(CLAUDE.md §4)에도 걸린다.
/// 그래서 "사진 앱으로 간다" 대신 **사진 앱에서 찾을 수 있게 앨범에
/// 놓아둔다**로 방향을 바꿨다.
///
/// **이 방식만의 장점.** 앱이 이미 제 안에 갖고 있는 사진 파일로
/// 만들기 때문에, 라이브러리 원본 식별자가 필요 없다. 그래서 **예전에
/// 추가한 사진에도, 공유로 들어와 라이브러리에 없던 사진에도** 똑같이
/// 된다. 식별자를 저장하는 방식(`PhotosPickerItem.itemIdentifier`)이었다면
/// 앞으로 고르는 사진만 됐을 것이다.
///
/// **대가.** 라이브러리에서 골라 온 사진은 라이브러리에 **한 장 더**
/// 생긴다. 앱이 가진 것은 원본이 아니라 제가 저장할 때 줄여 놓은
/// 사본이므로(`MediaStore.saveImage`), 그 사본이 새 사진으로 들어간다.
/// 부르는 쪽이 이 사실을 사용자에게 먼저 알린다.
enum PhotoLibraryAlbum {
    /// 사진 앱에 보이는 앨범 이름. 번역하지 않는다 — 앱 이름이다.
    static let title = "PinSpots"

    enum Outcome {
        /// 실제로 들어간 장수.
        case added(Int)
        /// 사용자가 사진 접근을 거부했다.
        case denied
        case failed(String)
    }

    /// `fileNames`는 `MediaItem.localPath`들이다.
    ///
    /// 권한은 `.readWrite`를 받는다. "추가 전용"(`.addOnly`)으로는 모자란다
    /// — 같은 이름의 앨범이 이미 있는지 **찾아보는 것 자체가 읽기**라서,
    /// 추가 전용으로는 부를 때마다 "PinSpots" 앨범이 하나씩 새로 생긴다.
    static func add(fileNames: [String]) async -> Outcome {
        guard !fileNames.isEmpty else { return .added(0) }

        let status = await requestReadWriteAuthorization()
        guard status == .authorized || status == .limited else { return .denied }

        // 파일을 먼저 전부 읽어 둔다. 아래 변경 블록은 동기적으로 돌고,
        // 그 안에서 디스크를 읽으면 사진 라이브러리의 트랜잭션을 그만큼
        // 붙잡고 있게 된다.
        let datas = fileNames.compactMap { MediaStore.loadData(fileName: $0) }
        guard !datas.isEmpty else { return .failed("사진 파일을 읽지 못했습니다.".localized) }

        do {
            let albumID = try await existingOrNewAlbumIdentifier()
            try await performChanges {
                guard let album = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [albumID], options: nil
                ).firstObject else { return }
                guard let albumChange = PHAssetCollectionChangeRequest(for: album) else { return }
                for data in datas {
                    let creation = PHAssetCreationRequest.forAsset()
                    creation.addResource(with: .photo, data: data, options: nil)
                    guard let placeholder = creation.placeholderForCreatedAsset else { continue }
                    albumChange.addAssets([placeholder] as NSArray)
                }
            }
            return .added(datas.count)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 같은 이름의 앨범이 있으면 그것을, 없으면 만들어서 그 id를 준다.
    ///
    /// 만드는 것과 사진을 넣는 것을 **다른 변경 블록으로 나눈다.** 한
    /// 블록 안에서 갓 만든 앨범의 자리표시자에 바로 넣는 것도 되지만,
    /// 그러면 "이미 있으면 재사용" 쪽과 코드가 갈라진다. 나눠 두면 넣는
    /// 코드가 한 벌뿐이다.
    private static func existingOrNewAlbumIdentifier() async throws -> String {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        let found = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: options
        )
        if let existing = found.firstObject { return existing.localIdentifier }

        let box = IdentifierBox()
        try await performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            box.value = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let created = box.value else {
            throw PlaceCardsError.saveFailed("사진 앱에 앨범을 만들지 못했습니다.".localized)
        }
        return created
    }

    /// 변경 블록이 바깥으로 값을 하나 돌려주는 통로. 지역 `var`를 탈출
    /// 클로저에서 고치는 대신 클래스 한 겹을 두는 쪽이, 이 저장소가
    /// 나중에 엄격한 동시성 검사를 켜더라도 그대로 통한다.
    private final class IdentifierBox {
        var value: String?
    }

    /// 완료 핸들러를 받는 쪽만 쓴다. async 오버로드가 있는 버전도 있지만,
    /// 여기서는 컴파일 검증이 CI뿐이라(CLAUDE.md §1) 어느 SDK에서나
    /// 확실히 있는 쪽을 고른다.
    private static func performChanges(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PlaceCardsError.saveFailed("사진 앱에 저장하지 못했습니다.".localized))
                }
            }
        }
    }

    private static func requestReadWriteAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
