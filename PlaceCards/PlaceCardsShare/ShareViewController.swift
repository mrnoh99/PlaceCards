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
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else {
            complete()
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] loadedItem, _ in
            defer { self?.complete() }

            let data: Data?
            switch loadedItem {
            case let url as URL:
                data = try? Data(contentsOf: url)
            case let image as UIImage:
                data = image.jpegData(compressionQuality: 0.9)
            case let imageData as Data:
                data = imageData
            default:
                data = nil
            }
            guard let data else { return }
            SharedImportStore.savePendingImage(data)
        }
    }

    private func complete() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
