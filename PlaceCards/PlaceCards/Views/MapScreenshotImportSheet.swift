import SwiftUI

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
                    Text("이 카드에 추가할까요?")
                } footer: {
                    Text("\"지도에서 열기\"로 최근에 연 카드예요. 방금 공유한 사진을 이 카드에 추가하고, AI로 읽어 비어 있는 이름·주소를 채웁니다.")
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("사진 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isProcessing {
                        ProgressView()
                    } else if didProcess {
                        Button("완료") { dismiss() }
                    } else {
                        Button("추가하기") { Task { await process() } }
                    }
                }
            }
            .alert(
                "이름이 다릅니다",
                isPresented: $isConfirmingNameChange
            ) {
                Button("변경") {
                    if let pendingResult {
                        applyExtracted(pendingResult, applyName: true)
                    }
                    pendingResult = nil
                }
                Button("이름은 유지", role: .cancel) {
                    if let pendingResult {
                        applyExtracted(pendingResult, applyName: false)
                    }
                    pendingResult = nil
                }
            } message: {
                Text("사진에서는 \"\(pendingResult?.placeName ?? "")\"(으)로 보이는데, 현재 이름 \"\(card.name)\"과 다릅니다. 이름을 바꿀까요?")
            }
        }
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
            statusMessage = "사진을 카드에 추가했습니다."
            return
        }

        let providerType = SettingsViewModel.currentAIProviderType()
        guard let apiKey = KeychainService.load(providerType.keychainKey), !apiKey.isEmpty else {
            statusMessage = "사진을 카드에 추가했습니다."
            return
        }

        let provider = await AIProviderFactory.create(type: providerType, apiKey: apiKey)
        do {
            let results = try await provider.analyzePlaces(imageDatas: [jpegData], prompt: defaultPlaceAnalysisPrompt)
            handleAnalysisResults(results)
        } catch {
            statusMessage = "사진을 카드에 추가했습니다. (정보 읽기 실패: \(error.localizedDescription))"
        }
    }

    private func handleAnalysisResults(_ results: [AIAnalysisResult]) {
        guard !results.isEmpty else {
            statusMessage = "사진을 카드에 추가했습니다. (장소 정보는 찾지 못했습니다.)"
            return
        }
        guard results.count == 1 else {
            let names = results.map(\.placeName).joined(separator: ", ")
            statusMessage = "사진을 카드에 추가했습니다. 사진에서 여러 장소(\(names))가 발견되어 정보는 채우지 않았습니다."
            return
        }

        let result = results[0]
        let extractedName = result.placeName.trimmingCharacters(in: .whitespaces)
        let currentName = card.name.trimmingCharacters(in: .whitespaces)
        if !extractedName.isEmpty, !currentName.isEmpty, extractedName != currentName {
            pendingResult = result
            isConfirmingNameChange = true
        } else {
            applyExtracted(result, applyName: true)
        }
    }

    private func applyExtracted(_ result: AIAnalysisResult, applyName: Bool) {
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
        storageService.save(card)
        onApplied(card)
        statusMessage = "AI가 읽은 정보를 채웠습니다."
    }
}

#Preview {
    MapScreenshotImportSheet(
        card: PlaceCard(boardId: "preview", name: "샘플 카페", address: "서울시 강남구"),
        imageData: Data()
    ) { _ in }
    .environmentObject(StorageService())
}
