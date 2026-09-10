import UIKit
import UniformTypeIdentifiers

/// The Share Extension's entry point — lets PlaceCards appear in the
/// system share sheet for images, so a photo (e.g. a screenshot of a map
/// app's info card, taken right before switching apps) can be handed
/// straight to the app instead of first saving it to Photos and reopening
/// PlaceCards to pick it from there. No storyboard/UI of its own — it
/// completes immediately once the image is saved, and the main app takes
/// over from there (see `SharedImportStore`, `MainTabView`).
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedItem()
    }

    private func handleSharedItem() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            SharedImportStore.recordDebugStatus("공유 항목(NSExtensionItem)을 찾지 못함")
            complete()
            return
        }
        guard let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            let types = item.attachments?.flatMap(\.registeredTypeIdentifiers).joined(separator: ", ") ?? "없음"
            SharedImportStore.recordDebugStatus("이미지 타입의 첨부를 찾지 못함 (첨부 타입: \(types))")
            complete()
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] loadedItem, error in
            defer { self?.complete() }

            if let error {
                SharedImportStore.recordDebugStatus("loadItem 실패: \(error.localizedDescription)")
                return
            }

            let data: Data?
            switch loadedItem {
            case let url as URL:
                // A URL handed back for a Photos-library-backed image (a
                // screenshot, say, since those save straight to Photos) is
                // commonly security-scoped — reading it without this call
                // fails silently (Data(contentsOf:) just returns nil via
                // try?), so nothing gets sent and there's no error to see.
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
                data = try? Data(contentsOf: url)
            case let image as UIImage:
                data = image.jpegData(compressionQuality: 0.9)
            case let imageData as Data:
                data = imageData
            default:
                data = nil
            }
            guard let data else {
                SharedImportStore.recordDebugStatus("이미지 데이터를 읽지 못함 (전달된 타입: \(String(describing: loadedItem.map { type(of: $0) })))")
                return
            }
            SharedImportStore.savePendingImage(data)
            SharedImportStore.recordDebugStatus("사진 저장 성공 (\(data.count) bytes)")
        }
    }

    private func complete() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
