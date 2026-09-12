import UIKit
import UniformTypeIdentifiers

/// The Share Extension's entry point — lets PlaceCards appear in the
/// system share sheet for both images (a screenshot of a map app's info
/// card, taken right before switching apps) and links/text (the "share
/// this page" prompt iOS offers for a URL like maps.google.com, or Naver
/// Map's own "공유" text) — either can be handed straight to the app
/// instead of first saving a screenshot to Photos, or copying a link by
/// hand. No storyboard — its view is built in code (see `setUpUI`) purely
/// so tapping the PlaceCards row in the share sheet doesn't just flash an
/// empty screen and vanish, which read as "nothing happened" even when
/// the share saved correctly; it briefly shows a spinner, then a ✓/✗
/// before dismissing.
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let viewDidLoadTime = Date()
    /// For a link/text share, `loadItem` (`handleLinkAttachment`) usually
    /// resolves in well under a frame's time — no network I/O involved —
    /// so without this floor, `finish()` could fire before the "PlaceCards로
    /// 저장 중…" spinner/label have even been on screen long enough for a
    /// glance to register real text: reported as the popup flashing and
    /// vanishing with only the trailing "…" catching the eye. `finish()`
    /// waits out whatever's left of this floor before switching to the
    /// ✓/✗ state, so the "저장 중…" text is reliably visible first.
    private static let minimumLoadingDisplaySeconds: TimeInterval = 0.5
    /// How long the ✓/✗ result itself stays up before auto-dismissing —
    /// long enough to actually read it, short enough not to feel stuck.
    private static let resultDisplaySeconds: TimeInterval = 1.0

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

    /// Picks the one attachment this share actually is, retrying once if
    /// none turn up yet (see `handleSharedItem`), then hands it to the
    /// matching handler. Checked against `UTType.url`/`.plainText`
    /// (rather than trusting the `NSExtensionActivationRule` alone) since
    /// an item can register more type identifiers than what actually
    /// triggered the match. An image takes priority when somehow both are
    /// offered, since that's the more established flow.
    private func dispatch(attachments: [NSItemProvider]) {
        if let imageProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            handleImageAttachment(imageProvider)
            return
        }
        if let urlProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            handleLinkAttachment(urlProvider, typeIdentifier: UTType.url.identifier)
            return
        }
        if let textProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            handleLinkAttachment(textProvider, typeIdentifier: UTType.plainText.identifier)
            return
        }

        let types = attachments.flatMap(\.registeredTypeIdentifiers).joined(separator: ", ")
        SharedImportStore.recordDebugStatus("지원하는 타입의 첨부를 찾지 못함 (첨부 타입: \(types))")
        finish(success: false, message: "지원하지 않는 형식입니다")
    }

    /// Reported specifically when tapping PlaceCards in the share sheet
    /// while its own app-icon row is still populating — plausibly a race
    /// on the host app's side (its `NSExtensionItem`/attachments not
    /// fully registered yet) rather than a genuine "nothing was shared".
    /// There's no way for this extension to delay or gate *when* its own
    /// icon becomes tappable in the system share sheet — that UI belongs
    /// to iOS, not to us — but retrying once here, after a short wait,
    /// costs nothing when the guard wouldn't have failed anyway and gives
    /// a genuine race a chance to resolve before giving up.
    private func handleSharedItem(isRetry: Bool = false) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem, let attachments = item.attachments, !attachments.isEmpty else {
            guard !isRetry else {
                SharedImportStore.recordDebugStatus("공유 항목(NSExtensionItem)을 찾지 못함 (재시도 후에도 실패)")
                finish(success: false, message: "공유된 항목을 찾지 못했습니다")
                return
            }
            SharedImportStore.recordDebugStatus("공유 항목(NSExtensionItem)을 찾지 못함 — 재시도 대기")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.handleSharedItem(isRetry: true)
            }
            return
        }
        dispatch(attachments: attachments)
    }

    /// Uses `loadDataRepresentation` rather than `loadItem` — `loadItem`
    /// for an image attachment can come back as a `URL` (the common case
    /// for a Photos-library photo), a `Data`, *or* an already-decoded
    /// `UIImage`, and which one the system picks is up to the sending
    /// app/OS version, not something this code controls. The `UIImage`
    /// case was a real, silent bug: re-encoding it via
    /// `jpegData(compressionQuality:)` (the only option once it's already
    /// a `UIImage`) throws away its EXIF GPS entirely — this shared
    /// image's own `PhotoMetadata.extractLocation(from:)` (used for
    /// `PlaceCardViewModel.photoLocationHint`) would then always find
    /// nothing, for any share the OS happened to hand back this way,
    /// while the exact same photo picked in-app via `PhotosPicker`
    /// (`AddPlaceCardView.loadPhotos`, `item.loadTransferable(type:
    /// Data.self)`) kept its EXIF fine. `loadDataRepresentation` asks for
    /// this attachment's actual on-disk bytes for the image UTI
    /// directly — it never routes through `UIImage` decoding, so EXIF
    /// survives the same way the in-app picker's `Data` load already
    /// does, and it handles any security-scoping itself (unlike a raw
    /// `URL` from `loadItem`, which needed `startAccessingSecurityScoped
    /// Resource()` called by hand).
    private func handleImageAttachment(_ provider: NSItemProvider) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
            if let error {
                SharedImportStore.recordDebugStatus("loadDataRepresentation 실패: \(error.localizedDescription)")
                self?.finish(success: false, message: "이미지를 불러오지 못했습니다")
                return
            }
            guard let data else {
                SharedImportStore.recordDebugStatus("이미지 데이터를 읽지 못함")
                self?.finish(success: false, message: "이미지를 읽지 못했습니다")
                return
            }
            SharedImportStore.savePendingImage(data)
            SharedImportStore.recordDebugStatus("사진 저장 성공 (\(data.count) bytes)")
            self?.finish(success: true, message: "PlaceCards로 저장됨")
        }
    }

    /// A shared URL (the "share this page" prompt for maps.google.com) or
    /// plain text (Naver Map's own share, or a URL handed back as text) —
    /// both are handed to `SharedLinkParser`/`resolveSharedPlace` on the
    /// main app side, so this only needs to capture whichever string form
    /// comes back and hand it off as-is.
    private func handleLinkAttachment(_ provider: NSItemProvider, typeIdentifier: String) {
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] loadedItem, error in
            if let error {
                SharedImportStore.recordDebugStatus("링크 loadItem 실패: \(error.localizedDescription)")
                self?.finish(success: false, message: "링크를 불러오지 못했습니다")
                return
            }

            let text: String?
            switch loadedItem {
            case let url as URL:
                text = url.absoluteString
            case let string as String:
                text = string
            case let data as Data:
                text = String(data: data, encoding: .utf8)
            default:
                text = nil
            }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                SharedImportStore.recordDebugStatus("링크 데이터를 읽지 못함 (전달된 타입: \(String(describing: loadedItem.map { type(of: $0) })))")
                self?.finish(success: false, message: "링크를 읽지 못했습니다")
                return
            }
            SharedImportStore.savePendingLink(text)
            SharedImportStore.recordDebugStatus("링크 저장 성공 (\(text.prefix(80)))")
            self?.finish(success: true, message: "PlaceCards로 저장됨")
        }
    }

    /// Shows a brief success/failure message in place of the spinner, then
    /// dismisses on its own shortly after — so tapping PlaceCards always
    /// ends with a visible result instead of the sheet just closing. Waits
    /// out `minimumLoadingDisplaySeconds` first (see its own comment) so
    /// the "저장 중…" state isn't skipped past before it can be read.
    private func finish(success: Bool, message: String) {
        let elapsed = Date().timeIntervalSince(viewDidLoadTime)
        let remainingFloor = max(0, Self.minimumLoadingDisplaySeconds - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingFloor) { [weak self] in
            guard let self else { return }
            spinner.stopAnimating()
            spinner.isHidden = true
            statusLabel.text = (success ? "✓ " : "✗ ") + message

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.resultDisplaySeconds) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
