import SwiftUI
import CoreLocation

/// Shown when a photo shared back into PlaceCards (through the Share
/// Extension) arrives soon after the user tapped "지도에서 열기" on a
/// specific card — the assumption is that they went to Google/Naver/
/// Kakao Map, found something worth capturing about that same place, and
/// shared the screenshot back, so this offers adding it straight to that
/// card (and reading it with AI to fill in blanks) instead of routing
/// through the normal "pick a board, create a new card" flow
/// (`SharedPhotoBoardPickerSheet`). See `MapOpenContext` for how the card
/// is identified.
struct MapScreenshotImportSheet: View {
    /// Used only by `warnIfNotOnsitePhoto` — the card's own name+address
    /// are already established there (not a first guess this app is
    /// trying to confirm), so a photo held against them deserves the same
    /// tight standard `PlaceCardViewModel.maxAddressMatchDistanceMeters`
    /// uses for an address match elsewhere, rather than the looser radius
    /// this app uses for an unconfirmed photo-GPS hint.
    private static let maxAddressMatchDistanceMeters: CLLocationDistance = 100

    @State private var card: PlaceCard
    let imageData: Data
    var onApplied: (PlaceCard) -> Void

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var isProcessing = false
    @State private var didProcess = false
    @State private var statusMessage: String?
    @State private var pendingResult: AIAnalysisResult?
    @State private var isConfirmingNameChange = false
    /// A shared-in photo's own EXIF GPS, staged for the confirmation
    /// alert below rather than applied outright — unlike every other
    /// field this sheet fills in, a coordinate is trusted evidence about
    /// where the photo itself was taken, not about what the AI read off
    /// it, so this is asked about directly instead of silently applied
    /// or silently discarded (see `process()`).
    @State private var pendingPhotoCoordinate: Coordinates?
    @State private var isConfirmingPhotoCoordinate = false
    /// Staged, not applied outright — same "confirm before applying" rule
    /// `EditPlaceCardSheet`'s own tag suggestions follow (see
    /// `PlaceWebDetails.tags`'s own doc comment for why).
    @State private var pendingSuggestedTags: [String] = []
    @State private var isConfirmingSuggestedTags = false

    init(card: PlaceCard, imageData: Data, onApplied: @escaping (PlaceCard) -> Void) {
        _card = State(initialValue: card)
        self.imageData = imageData
        self.onApplied = onApplied
    }

    private var previewImage: UIImage? { UIImage(data: imageData) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.name)
                                .font(.headline)
                            if !card.address.isEmpty {
                                Text(card.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("이 카드에 추가할까요?".localized)
                } footer: {
                    if AIProviderChain.hasAnyConfiguredProvider() {
                        Text("\"지도에서 열기\"로 최근에 연 카드예요. 방금 공유한 사진을 이 카드에 추가하고, AI로 읽어 비어 있는 이름·주소를 채웁니다.".localized)
                    } else {
                        Text("\"지도에서 열기\"로 최근에 연 카드예요. 방금 공유한 사진을 이 카드에 추가합니다. (AI 제공자가 등록되어 있지 않아 정보는 자동으로 읽지 않습니다 — 설정에서 등록하면 이용할 수 있습니다.)".localized)
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("사진 가져오기".localized)
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
                    if let pendingResult {
                        applyExtracted(pendingResult, applyName: true)
                    }
                    pendingResult = nil
                }
                Button("이름은 유지".localized, role: .cancel) {
                    if let pendingResult {
                        applyExtracted(pendingResult, applyName: false)
                    }
                    pendingResult = nil
                }
            } message: {
                Text(nameChangeAlertMessage)
            }
            .alert(
                "AI가 태그를 제안했습니다".localized,
                isPresented: $isConfirmingSuggestedTags
            ) {
                Button("추가".localized) {
                    for tag in pendingSuggestedTags where !card.tags.contains(tag) {
                        card.tags.append(tag)
                    }
                    storageService.save(card)
                    onApplied(card)
                    pendingSuggestedTags = []
                }
                Button("취소".localized, role: .cancel) { pendingSuggestedTags = [] }
            } message: {
                Text(pendingSuggestedTags.joined(separator: ", "))
            }
            .alert(
                "사진의 위치 정보".localized,
                isPresented: $isConfirmingPhotoCoordinate
            ) {
                Button("이 위치로 저장".localized) {
                    if let pendingPhotoCoordinate {
                        card.coordinates = pendingPhotoCoordinate
                        storageService.save(card)
                        onApplied(card)
                    }
                    pendingPhotoCoordinate = nil
                }
                Button("사용 안 함".localized, role: .cancel) { pendingPhotoCoordinate = nil }
            } message: {
                Text(photoCoordinateAlertMessage)
            }
        }
    }

    /// Broken into separate statements (rather than one long chain of
    /// `+` on the `.alert`'s `message:` closure) since the compiler
    /// choked on type-checking that chain directly inside the view body
    /// ("unable to type-check this expression in reasonable time").
    private var nameChangeAlertMessage: String {
        let extractedName = pendingResult?.placeName ?? ""
        let prefix = "사진에서는 \"".localized
        let middle = "\"(으)로 보이는데, 현재 이름 \"".localized
        let suffix = "\"과 다릅니다. 이름을 바꿀까요?".localized
        return prefix + extractedName + middle + card.name + suffix
    }

    private var photoCoordinateAlertMessage: String {
        let prefix = "사진에 위치 정보(GPS)가 있습니다. 이 위치를 \"".localized
        let suffix = "\"의 좌표로 저장할까요?".localized
        return prefix + card.name + suffix
    }

    /// Always saves the photo itself first (that part never fails or
    /// needs a decision), then best-effort reads it with AI — same
    /// "found nothing / found several / found one" handling as
    /// `EditPlaceCardSheet`'s own photo import.
    private func process() async {
        isProcessing = true
        defer {
            isProcessing = false
            didProcess = true
        }

        if let fileName = try? MediaStore.saveImage(data: imageData) {
            card.media.mapScreenshots.append(MediaItem(localPath: fileName, source: .googleMapScreenshot))
        }
        storageService.save(card)
        onApplied(card)

        // Checked right away, independent of whether AI analysis below
        // ever runs. A missing coordinate is asked about directly (see
        // `pendingPhotoCoordinate`'s own comment) rather than silently
        // filled or silently discarded; an already-set one is instead
        // sanity-checked and only reported via `statusMessage`, appended
        // at every exit from this function, since nothing needs deciding
        // there.
        let photoCoordinate = PhotoMetadata.extractLocation(from: imageData)
        var onsiteWarning: String?
        if card.coordinates == nil, let photoCoordinate {
            pendingPhotoCoordinate = photoCoordinate
            isConfirmingPhotoCoordinate = true
        } else {
            onsiteWarning = warnIfNotOnsitePhoto(photoCoordinate)
        }
        defer {
            if let onsiteWarning {
                statusMessage = [statusMessage, onsiteWarning].compactMap { $0 }.joined(separator: "\n")
            }
        }

        guard let jpegData = previewImage?.jpegData(compressionQuality: 0.8) else {
            statusMessage = "사진을 카드에 추가했습니다.".localized
            return
        }

        guard AIProviderChain.hasAnyConfiguredProvider() else {
            statusMessage = "사진을 카드에 추가했습니다.".localized
            return
        }

        do {
            let (results, provider, isFallback) = try await AIProviderChain.run {
                try await $0.analyzePlaces(imageDatas: [jpegData], prompt: defaultPlaceAnalysisPrompt())
            }
            handleAnalysisResults(results, answeredBy: isFallback ? provider : nil)
        } catch {
            statusMessage = "사진을 카드에 추가했습니다. (정보 읽기 실패: ".localized + error.localizedDescription + ")"
        }
    }

    /// Called only when this card already has coordinates — `process()`
    /// asks about a missing one instead (see `pendingPhotoCoordinate`), so
    /// this is purely a sanity check on an already-established location: a
    /// newly added photo whose own EXIF GPS lands far from the card's
    /// coordinates is likely not actually a photo taken there at all
    /// (saved from elsewhere, someone else's photo, a mislabeled
    /// screenshot), worth flagging even though the card's location data
    /// itself is left untouched. `nil` when there's nothing to flag — no
    /// photo GPS, no established name+address, or the photo is close
    /// enough.
    private func warnIfNotOnsitePhoto(_ photoCoordinate: Coordinates?) -> String? {
        guard let photoCoordinate, let groundTruth = card.coordinates else { return nil }
        let trimmedName = card.name.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = card.address.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedAddress.isEmpty else { return nil }

        let distance = CLLocation(latitude: groundTruth.latitude, longitude: groundTruth.longitude)
            .distance(from: CLLocation(latitude: photoCoordinate.latitude, longitude: photoCoordinate.longitude))
        guard distance > Self.maxAddressMatchDistanceMeters else { return nil }
        return "추가한 사진이 이 장소에서 촬영된 것 같지 않습니다 (사진 GPS가 주소에서 100m 이상 떨어져 있습니다).".localized
    }

    private func handleAnalysisResults(_ results: [AIAnalysisResult], answeredBy fallbackProvider: AIProviderType? = nil) {
        guard !results.isEmpty else {
            statusMessage = "사진을 카드에 추가했습니다. (장소 정보는 찾지 못했습니다.)".localized
            return
        }
        guard results.count == 1 else {
            let names = results.map(\.placeName).joined(separator: ", ")
            statusMessage = "사진을 카드에 추가했습니다. 사진에서 여러 장소(".localized + names + ")가 발견되어 정보는 채우지 않았습니다.".localized
            return
        }

        let result = results[0]
        let extractedName = result.placeName.trimmingCharacters(in: .whitespaces)
        let currentName = card.name.trimmingCharacters(in: .whitespaces)
        if !extractedName.isEmpty, !currentName.isEmpty, extractedName != currentName {
            // Same scope cut as `EditPlaceCardSheet`: the confirm alert's
            // own button applies the result later, by which point this
            // call's fallback note is stale context — skipped here.
            pendingResult = result
            isConfirmingNameChange = true
        } else {
            applyExtracted(result, applyName: true, answeredBy: fallbackProvider)
        }
    }

    private func applyExtracted(_ result: AIAnalysisResult, applyName: Bool, answeredBy fallbackProvider: AIProviderType? = nil) {
        if applyName {
            let extractedName = result.placeName.trimmingCharacters(in: .whitespaces)
            if !extractedName.isEmpty {
                card.name = extractedName
            }
        }
        if card.address.trimmingCharacters(in: .whitespaces).isEmpty,
           let extractedAddress = result.address?.trimmingCharacters(in: .whitespaces), !extractedAddress.isEmpty {
            card.address = extractedAddress
        }
        card.memo = PlaceCard.combinedMemo(card.memo, appending: result.description)
        // Phone/category/hours/closing time/holidays/amenities/reservation
        // info, when the screenshot's own info card shows them — this used
        // to only ever apply name/address/memo, silently discarding
        // everything else `analyzePlaces` already extracts.
        card.applyScannedDetails(result.details)
        storageService.save(card)
        onApplied(card)
        statusMessage = "AI가 읽은 정보를 채웠습니다.".localized
        if let fallbackProvider {
            statusMessage? += fallbackProvider.fallbackNoteSuffix
        }

        if let tags = result.details?.tags, !tags.isEmpty {
            let newTags = tags.filter { !card.tags.contains($0) }
            if !newTags.isEmpty {
                pendingSuggestedTags = newTags
                isConfirmingSuggestedTags = true
            }
        }
    }
}

#Preview {
    MapScreenshotImportSheet(
        card: PlaceCard(boardId: "preview", name: "샘플 카페".localized, address: "서울시 강남구".localized),
        imageData: Data()
    ) { _ in }
    .environmentObject(StorageService())
}
