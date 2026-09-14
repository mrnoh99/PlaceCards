import SwiftUI
import CoreLocation

/// Shown when a link (or plain text, e.g. Naver Map's own "공유") shared
/// back into PlaceCards through the Share Extension arrives soon after the
/// user tapped "지도에서 열기" on a specific card — mirrors
/// `MapScreenshotImportSheet` exactly, but for a shared Google/Naver Map
/// link instead of a screenshot: the assumption is the same (went to
/// Google/Naver Map, found or confirmed this same place, shared it back),
/// so this offers merging whatever the link itself carries (name, address,
/// exact coordinates, its own map URL) straight into that card instead of
/// routing through "pick a board, create a new card"
/// (`SharedLinkBoardPickerSheet`). See `MapOpenContext` for how the card
/// is identified.
struct MapLinkImportSheet: View {
    /// A place found on the map app itself (rather than a photo's loose
    /// EXIF GPS) is precise ground truth — held to the same tight standard
    /// `PlaceCardViewModel.maxAddressMatchDistanceMeters` uses elsewhere,
    /// not the looser radius a photo's GPS gets.
    private static let maxAddressMatchDistanceMeters: CLLocationDistance = 100

    @State private var card: PlaceCard
    let linkText: String
    var onApplied: (PlaceCard) -> Void

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var isProcessing = false
    @State private var didProcess = false
    @State private var statusMessage: String?
    @State private var pendingParsed: ParsedSharedPlace?
    @State private var isConfirmingNameChange = false

    init(card: PlaceCard, linkText: String, onApplied: @escaping (PlaceCard) -> Void) {
        _card = State(initialValue: card)
        self.linkText = linkText
        self.onApplied = onApplied
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.name)
                            .font(.headline)
                        if !card.address.isEmpty {
                            Text(card.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("이 카드에 추가할까요?".localized)
                } footer: {
                    Text("\"지도에서 열기\"로 최근에 연 카드예요. 방금 공유한 지도 링크의 정보(이름·주소·좌표)를 이 카드에 채웁니다.".localized)
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("지도 링크 가져오기".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isProcessing {
                        ProgressView()
                    } else if didProcess {
                        Button("완료".localized) { dismiss() }
                    } else {
                        Button("추가하기".localized) { Task { await process() } }
                    }
                }
            }
            .alert(
                "이름이 다릅니다".localized,
                isPresented: $isConfirmingNameChange
            ) {
                Button("변경".localized) {
                    if let pendingParsed {
                        applyParsed(pendingParsed, applyName: true)
                    }
                    pendingParsed = nil
                }
                Button("이름은 유지".localized, role: .cancel) {
                    if let pendingParsed {
                        applyParsed(pendingParsed, applyName: false)
                    }
                    pendingParsed = nil
                }
            } message: {
                Text(nameChangeAlertMessage)
            }
        }
    }

    private var nameChangeAlertMessage: String {
        let extractedName = pendingParsed?.name ?? ""
        let prefix = "공유한 링크에서는 \"".localized
        let middle = "\"(으)로 보이는데, 현재 이름 \"".localized
        let suffix = "\"과 다릅니다. 이름을 바꿀까요?".localized
        return prefix + extractedName + middle + card.name + suffix
    }

    /// Parses the shared link/text (falling back to a page-title fetch for
    /// a URL-only Google Maps share, same as
    /// `PlaceCardViewModel.resolveSharedPlace`'s own fallback), then
    /// applies it with the same "found none / one, needs confirmation" shape
    /// `MapScreenshotImportSheet.process()`'s photo scan already uses.
    private func process() async {
        isProcessing = true
        defer {
            isProcessing = false
            didProcess = true
        }

        guard var parsed = SharedLinkParser.parse(linkText) else {
            statusMessage = "공유한 링크에서 장소 정보를 찾지 못했습니다.".localized
            return
        }
        // A page's own <title>/og:title (for a shortened goo.gl link) can
        // carry stray formatting the same way a Google Maps URL's own
        // name segment can — stripped for the same reason
        // `SharedLinkParser.parseGoogleMapsURLPath` strips its own.
        if parsed.name == nil, let url = parsed.url, let title = await LinkMetadataFetcher.fetchTitle(for: url) {
            parsed.name = title.strippingInvisibleFormatCharacters()
        }
        guard let extractedName = parsed.name?.trimmingCharacters(in: .whitespaces).strippingInvisibleFormatCharacters(),
              !extractedName.isEmpty else {
            statusMessage = "공유한 링크에서 장소 이름을 찾지 못했습니다.".localized
            return
        }

        let currentName = card.name.trimmingCharacters(in: .whitespaces)
        if !currentName.isEmpty, extractedName != currentName {
            pendingParsed = parsed
            isConfirmingNameChange = true
        } else {
            applyParsed(parsed, applyName: true)
        }
    }

    private func applyParsed(_ parsed: ParsedSharedPlace, applyName: Bool) {
        if applyName, let extractedName = parsed.name?.trimmingCharacters(in: .whitespaces), !extractedName.isEmpty {
            card.name = extractedName
        }
        if card.address.trimmingCharacters(in: .whitespaces).isEmpty,
           let extractedAddress = parsed.address?.trimmingCharacters(in: .whitespaces), !extractedAddress.isEmpty {
            card.address = extractedAddress
        }
        card.memo = PlaceCard.combinedMemo(card.memo, appending: parsed.note)

        let coordinateNote = parsed.coordinates.flatMap(applyOrWarnCoordinate)

        if let url = parsed.url {
            let platform = parsed.source == .naverMapShare ? "Naver Map" : "Google Maps"
            let alreadyLinked = card.externalLinks.contains { $0.url == url.absoluteString }
            if !alreadyLinked {
                card.externalLinks.append(ExternalLink(platform: platform, url: url.absoluteString))
            }
        }

        storageService.save(card)
        onApplied(card)
        statusMessage = [
            "공유한 지도 정보를 카드에 채웠습니다.".localized, coordinateNote
        ].compactMap { $0 }.joined(separator: "\n")
    }

    /// Same "fill when blank, sanity-check when already set" shape as
    /// `MapScreenshotImportSheet.applyOrWarnPhotoCoordinate(_:)` — but
    /// applied outright rather than behind a toggle, since a map app's own
    /// confirmed place is real ground truth, not a loose GPS guess a
    /// photo's EXIF might carry.
    private func applyOrWarnCoordinate(_ coordinate: Coordinates) -> String? {
        guard let existing = card.coordinates else {
            card.coordinates = coordinate
            return "지도 링크의 좌표를 카드에 저장했습니다.".localized
        }
        let distance = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        guard distance > Self.maxAddressMatchDistanceMeters else { return nil }
        return "공유한 지도 링크의 위치가 카드의 기존 좌표와 100m 이상 떨어져 있어 좌표는 바꾸지 않았습니다.".localized
    }
}

#Preview {
    MapLinkImportSheet(
        card: PlaceCard(boardId: "preview", name: "샘플 카페".localized, address: "서울시 강남구".localized),
        linkText: "https://maps.google.com/example"
    ) { _ in }
    .environmentObject(StorageService())
}
