import UIKit
import UniformTypeIdentifiers

/// The Share Extension's entry point — lets PlaceCards appear in the
/// system share sheet for images, so a photo (e.g. a screenshot of a map
/// app's info card, taken right before switching apps) can be handed
/// straight to the app instead of first saving it to Photos and reopening
/// PlaceCards to pick it from there. No storyboard — its view is built in
/// code (see `setUpUI`) purely so tapping the PlaceCards row in the share
/// sheet doesn't just flash an empty screen and vanish, which read as
/// "nothing happened" even when the photo saved correctly; it briefly
/// shows a spinner, then a ✓/✗ before dismissing.
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpUI()
        handleSharedItem()
    }

    private func setUpUI() {
        view.backgroundColor = .systemBackground

        statusLabel.text = "PlaceCards로 저장 중…"
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])

        preferredContentSize = CGSize(width: 280, height: 140)
    }

    private func handleSharedItem() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            SharedImportStore.recordDebugStatus("공유 항목(NSExtensionItem)을 찾지 못함")
            finish(success: false, message: "공유된 항목을 찾지 못했습니다")
            return
        }
        guard let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            let types = item.attachments?.flatMap(\.registeredTypeIdentifiers).joined(separator: ", ") ?? "없음"
            SharedImportStore.recordDebugStatus("이미지 타입의 첨부를 찾지 못함 (첨부 타입: \(types))")
            finish(success: false, message: "이미지를 찾지 못했습니다")
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] loadedItem, error in
            if let error {
                SharedImportStore.recordDebugStatus("loadItem 실패: \(error.localizedDescription)")
                self?.finish(success: false, message: "이미지를 불러오지 못했습니다")
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
                self?.finish(success: false, message: "이미지를 읽지 못했습니다")
                return
            }
            SharedImportStore.savePendingImage(data)
            SharedImportStore.recordDebugStatus("사진 저장 성공 (\(data.count) bytes)")
            self?.finish(success: true, message: "PlaceCards로 저장됨")
        }
    }

    /// Shows a brief success/failure message in place of the spinner, then
    /// dismisses on its own shortly after — so tapping PlaceCards always
    /// ends with a visible result instead of the sheet just closing.
    private func finish(success: Bool, message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            spinner.stopAnimating()
            spinner.isHidden = true
            statusLabel.text = (success ? "✓ " : "✗ ") + message

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
