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
    /// Same radius/reasoning as `PlaceCardViewModel.maxPhotoLocationMatch
    /// DistanceMeters`/`EditPlaceCardSheet.maxPhotoLocationMatchDistance
    /// Meters` — a photo's own EXIF GPS reflects wherever the phone was
    /// standing, not necessarily the place's own doorstep, so this stays
    /// looser than an address-based match would need. A map app's own
    /// screenshot rarely carries GPS at all (iOS screenshots normally
    /// have none), but a photo shared through this same path could.
    private static let maxPhotoLocationMatchDistanceMeters: CLLocationDistance = 500

    @State private var card: PlaceCard
    let imageData: Data
    var onApplied: (PlaceCard) -> Void

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var isProcessing = false
    @State private var didProcess = false
    @State private var statusMessage: String?
    @State private var pendingResult: AIAnalysisResult?
    /// Carried alongside `pendingResult` across the name-change
    /// confirmation alert — see `EditPlaceCardSheet`'s identical pattern.
    @State private var pendingPhotoLocationCandidate: Coordinates?
    @State private var pendingPhotoLocationNote: String?
    @State private var isConfirmingNameChange = false
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
                        applyExtracted(
                            pendingResult, applyName: true,
                            photoLocationCandidate: pendingPhotoLocationCandidate, photoLocationNote: pendingPhotoLocationNote
                        )
                    }
                    pendingResult = nil
                    pendingPhotoLocationCandidate = nil
                    pendingPhotoLocationNote = nil
                }
                Button("이름은 유지".localized, role: .cancel) {
                    if let pendingResult {
                        applyExtracted(
                            pendingResult, applyName: false,
                            photoLocationCandidate: pendingPhotoLocationCandidate, photoLocationNote: pendingPhotoLocationNote
                        )
                    }
                    pendingResult = nil
                    pendingPhotoLocationCandidate = nil
                    pendingPhotoLocationNote = nil
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
            // Only worth checking when the card has no coordinates yet and
            // the photo resolved to exactly one place — same "too
            // ambiguous otherwise" gate `handleAnalysisResults` already
            // applies to every other field below.
            var photoLocationCandidate: Coordinates?
            var photoLocationNote: String?
            if card.coordinates == nil, results.count == 1, let photoCoordinate = PhotoMetadata.extractLocation(from: imageData) {
                (photoLocationCandidate, photoLocationNote) = await verifiedPhotoLocationCandidate(
                    photoCoordinate, placeAddress: results[0].address
                )
            }
            handleAnalysisResults(
                results, answeredBy: isFallback ? provider : nil,
                photoLocationCandidate: photoLocationCandidate, photoLocationNote: photoLocationNote
            )
        } catch {
            statusMessage = "사진을 카드에 추가했습니다. (정보 읽기 실패: ".localized + error.localizedDescription + ")"
        }
    }

    /// Cross-checks a candidate photo-GPS coordinate against the AI-
    /// identified place's own address before trusting it for auto-fill —
    /// same small, self-contained copy `EditPlaceCardSheet` and
    /// `PlaceCardViewModel` each keep, since none of these three share a
    /// common owner to call a single implementation on. Returns
    /// `(candidate, nil)` on agreement; `(candidate, note)` when there's
    /// no address to check against or it fails to geocode (nothing to
    /// contradict the photo, so it's still trusted, but the note tells
    /// the user this rests on the photo's GPS alone); and `(nil, note)`
    /// when the two disagree by more than `maxPhotoLocationMatchDistance
    /// Meters`.
    private func verifiedPhotoLocationCandidate(
        _ candidate: Coordinates, placeAddress: String?
    ) async -> (coordinates: Coordinates?, note: String?) {
        let trimmedAddress = (placeAddress ?? card.address).trimmingCharacters(in: .whitespaces)
        guard !trimmedAddress.isEmpty,
            let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty,
            let addressLocation = try? await GooglePlacesService(apiKey: apiKey).geocodeAddress(trimmedAddress)
        else {
            return (candidate, "대조할 장소 주소가 없어 사진의 위치 정보만 사용합니다.".localized)
        }

        let distance = CLLocation(latitude: addressLocation.latitude, longitude: addressLocation.longitude)
            .distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude))
        if distance <= Self.maxPhotoLocationMatchDistanceMeters {
            return (candidate, nil)
        }
        return (nil, "사진의 위치 정보가 인식된 장소 주소와 너무 멀어 사진 위치는 사용하지 않았습니다.".localized)
    }

    private func handleAnalysisResults(
        _ results: [AIAnalysisResult], answeredBy fallbackProvider: AIProviderType? = nil,
        photoLocationCandidate: Coordinates? = nil, photoLocationNote: String? = nil
    ) {
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
            // call's fallback note is stale context — skipped here. The
            // photo location candidate/note are carried along instead,
            // since `applyExtracted` still needs them once confirmed.
            pendingResult = result
            pendingPhotoLocationCandidate = photoLocationCandidate
            pendingPhotoLocationNote = photoLocationNote
            isConfirmingNameChange = true
        } else {
            applyExtracted(
                result, applyName: true, answeredBy: fallbackProvider,
                photoLocationCandidate: photoLocationCandidate, photoLocationNote: photoLocationNote
            )
        }
    }

    private func applyExtracted(
        _ result: AIAnalysisResult, applyName: Bool, answeredBy fallbackProvider: AIProviderType? = nil,
        photoLocationCandidate: Coordinates? = nil, photoLocationNote: String? = nil
    ) {
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
        if card.coordinates == nil, let photoLocationCandidate {
            card.coordinates = photoLocationCandidate
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
        if let photoLocationNote {
            statusMessage = [statusMessage, photoLocationNote].compactMap { $0 }.joined(separator: "\n")
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
