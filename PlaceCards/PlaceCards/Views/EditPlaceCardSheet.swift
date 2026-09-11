import SwiftUI
import PhotosUI

/// One editable row of `PlaceCard.hoursDetail` (a day and its hours text,
/// e.g. "월요일" → "09:00-18:00") — that field is a plain `[String:
/// String]` with no fixed set of keys, so this sheet edits it as a
/// freely add/removable list rather than one fixed field per weekday.
private struct HoursEntry: Identifiable {
    let id = UUID()
    var day: String
    var hours: String
}

/// Edits a place card's own fields directly, mirroring the "Edit" action
/// in Peragra's `PlaceRowView` (which opens `EditPlaceSheet`) — scoped to
/// this app's plain fields only, since the photo/AI-fill flows Peragra's
/// own edit sheet also has already live separately in `AddPlaceCardView`
/// and aren't duplicated here. Unlike that first version, this one covers
/// every field `PlaceCard` has (down to rating/coordinates/hours), not
/// just the handful most often set by hand.
///
/// Also offers adding a photo here and reading it with AI to fill in
/// still-blank fields (`photoImportSection`) — unlike `AddPlaceCardView`,
/// which is fine turning "several places found in one photo" into
/// several new cards, this is editing one already-named card, so a photo
/// naming more than one place is treated as too ambiguous to apply at
/// all, and a name that would actually change asks for confirmation
/// first (see `handleAnalysisResults`).
struct EditPlaceCardSheet: View {
    let card: PlaceCard
    var onSave: (PlaceCard) -> Void

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: String
    @State private var address: String
    @State private var latitudeText: String
    @State private var longitudeText: String
    @State private var phone: String
    @State private var website: String
    @State private var instagramURL: String
    @State private var ratingText: String
    @State private var reviewCountText: String
    @State private var isFavorite: Bool
    @State private var isVisited: Bool
    @State private var closingTime: String
    @State private var holidays: String
    @State private var reservationInfo: String
    @State private var hoursEntries: [HoursEntry]
    @State private var tagsText: String
    @State private var amenitiesText: String
    @State private var memoText: String

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var pickedImages: [UIImage] = []
    @State private var isLoadingPhotos = false
    @State private var isAnalyzingPhotos = false
    @State private var photoAnalysisMessage: String?
    @State private var pendingExtractedPlace: AIAnalysisResult?
    @State private var isConfirmingNameChange = false

    @State private var isSearchingWeb = false
    @State private var webSearchMessage: String?

    /// Tags the AI (photo scan or web search) suggested that aren't
    /// already in `tagsText` — staged here rather than applied straight
    /// away (see `PlaceWebDetails.tags`'s own doc comment for why tags
    /// specifically get this treatment) and shown as one batch to accept
    /// or dismiss via `isConfirmingSuggestedTags`.
    @State private var pendingSuggestedTags: [String] = []
    @State private var isConfirmingSuggestedTags = false

    init(card: PlaceCard, onSave: @escaping (PlaceCard) -> Void) {
        self.card = card
        self.onSave = onSave
        _name = State(initialValue: card.name)
        _category = State(initialValue: card.category ?? "")
        _address = State(initialValue: card.address)
        _latitudeText = State(initialValue: card.coordinates.map { String($0.latitude) } ?? "")
        _longitudeText = State(initialValue: card.coordinates.map { String($0.longitude) } ?? "")
        _phone = State(initialValue: card.phone ?? "")
        _website = State(initialValue: card.website ?? "")
        _instagramURL = State(initialValue: card.instagramURL ?? "")
        _ratingText = State(initialValue: card.rating.map { String($0) } ?? "")
        _reviewCountText = State(initialValue: card.reviewCount.map { String($0) } ?? "")
        _isFavorite = State(initialValue: card.isFavorite)
        _isVisited = State(initialValue: card.isVisited)
        _closingTime = State(initialValue: card.closingTime ?? "")
        _holidays = State(initialValue: card.holidays ?? "")
        _reservationInfo = State(initialValue: card.reservationInfo ?? "")
        _hoursEntries = State(initialValue: (card.hoursDetail ?? [:]).sorted { $0.key < $1.key }.map { HoursEntry(day: $0.key, hours: $0.value) })
        _tagsText = State(initialValue: card.tags.joined(separator: ", "))
        _amenitiesText = State(initialValue: card.amenities.joined(separator: ", "))
        _memoText = State(initialValue: card.memo ?? "")
    }

    /// Other categories already used in this card's board — offered as
    /// quick picks alongside typing a new one, since PlaceCards has no
    /// fixed category taxonomy (unlike Peragra's `PlaceCategory` enum).
    private var existingCategories: [String] {
        let categories = storageService.placeCards(inBoard: card.boardId)
            .compactMap { $0.category }
            .filter { !$0.isEmpty && $0 != category }
        return Array(Set(categories)).sorted()
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                photoImportSection
                basicInfoSection
                webSearchSection
                coordinatesSection
                contactSection
                ratingSection
                statusSection
                businessHoursSection
                tagsSection
                amenitiesSection
                memoSection
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("장소 정보 수정".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장".localized) { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: photoPickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await loadPhotos(newItems)
                    photoPickerItems = []
                }
            }
            .alert(
                "이름이 다릅니다".localized,
                isPresented: $isConfirmingNameChange
            ) {
                Button("변경".localized) {
                    if let pendingExtractedPlace {
                        applyExtractedPlace(pendingExtractedPlace)
                    }
                    pendingExtractedPlace = nil
                }
                Button("취소".localized, role: .cancel) { pendingExtractedPlace = nil }
            } message: {
                Text(nameChangeAlertMessage)
            }
            .alert(
                "AI가 태그를 제안했습니다".localized,
                isPresented: $isConfirmingSuggestedTags
            ) {
                Button("추가".localized) {
                    addSuggestedTags()
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
        let extractedName = pendingExtractedPlace?.placeName ?? ""
        let prefix = "사진에서는 \"".localized
        let middle = "\"(으)로 보이는데, 현재 이름 \"".localized
        let suffix = "\"과 다릅니다. 이름을 바꿀까요?".localized
        return prefix + extractedName + middle + name + suffix
    }

    /// Each of these used to be inline in `body`'s `Form { ... }` — split
    /// out (same pattern `photoImportSection`/`webSearchSection` already
    /// used) because the Swift compiler couldn't type-check `body` as one
    /// single expression once nearly every literal in it became a
    /// non-literal `String` via `.localized` ("unable to type-check this
    /// expression in reasonable time").
    @ViewBuilder
    private var basicInfoSection: some View {
        Section("기본 정보".localized) {
            TextField("이름".localized, text: $name)
            HStack {
                TextField("카테고리".localized, text: $category)
                if !existingCategories.isEmpty {
                    Menu {
                        ForEach(existingCategories, id: \.self) { option in
                            Button(option) { category = option }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                }
            }
            TextField("주소".localized, text: $address)
        }
    }

    @ViewBuilder
    private var coordinatesSection: some View {
        Section {
            TextField("위도".localized, text: $latitudeText)
                .keyboardType(.numbersAndPunctuation)
            TextField("경도".localized, text: $longitudeText)
                .keyboardType(.numbersAndPunctuation)
        } header: {
            Text("좌표".localized)
        } footer: {
            Text("둘 다 비우면 좌표가 삭제됩니다. 하나만 채워지면 원래 값이 그대로 유지됩니다.".localized)
        }
    }

    @ViewBuilder
    private var contactSection: some View {
        Section("연락처".localized) {
            TextField("전화번호".localized, text: $phone)
                .keyboardType(.phonePad)
            TextField("웹사이트 URL".localized, text: $website)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            TextField("인스타그램 URL".localized, text: $instagramURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
    }

    @ViewBuilder
    private var ratingSection: some View {
        Section("평가".localized) {
            TextField("평점 (0~5)".localized, text: $ratingText)
                .keyboardType(.decimalPad)
            TextField("리뷰 수".localized, text: $reviewCountText)
                .keyboardType(.numberPad)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("상태".localized) {
            Toggle("즐겨찾기".localized, isOn: $isFavorite)
            Toggle("방문함".localized, isOn: $isVisited)
        }
    }

    @ViewBuilder
    private var businessHoursSection: some View {
        Section {
            ForEach($hoursEntries) { $entry in
                HStack {
                    TextField("요일".localized, text: $entry.day)
                        .frame(width: 70)
                    Divider()
                    TextField("영업시간 (예: 09:00-18:00)".localized, text: $entry.hours)
                }
            }
            .onDelete { hoursEntries.remove(atOffsets: $0) }
            Button("+ 요일 추가".localized) {
                hoursEntries.append(HoursEntry(day: "", hours: ""))
            }
            TextField("마감 시간".localized, text: $closingTime)
            TextField("휴무일".localized, text: $holidays)
            TextField("예약 방법 (예: 캐치테이블 예약)".localized, text: $reservationInfo)
        } header: {
            Text("영업 정보".localized)
        } footer: {
            Text("특정 예약 플랫폼으로 바로 연결되는 링크는 지원하지 않아, 상세보기의 \"예약\" 버튼은 여기 적은 내용으로 웹 검색을 열어줍니다.".localized)
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        Section {
            TextField("쉼표로 구분".localized, text: $tagsText, axis: .vertical)
        } header: {
            Text("태그".localized)
        }
    }

    @ViewBuilder
    private var amenitiesSection: some View {
        Section {
            TextField("쉼표로 구분".localized, text: $amenitiesText, axis: .vertical)
        } header: {
            Text("편의시설".localized)
        }
    }

    @ViewBuilder
    private var memoSection: some View {
        Section {
            TextField("메모".localized, text: $memoText, axis: .vertical)
        } header: {
            Text("메모".localized)
        } footer: {
            Text("위 항목 어디에도 맞지 않는 정보를 자유롭게 적어두는 곳입니다.".localized)
        }
    }

    /// Add a photo here and, optionally, have AI read it to fill in
    /// whatever's still blank — separate from `AddPlaceCardView`'s own
    /// AI step since the ambiguity handling here is different (see the
    /// type's own doc comment).
    @ViewBuilder
    private var photoImportSection: some View {
        Section {
            if !pickedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pickedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Button {
                                    pickedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(4)
                            }
                        }
                    }
                }
            }

            PhotosPicker(selection: $photoPickerItems, matching: .images) {
                if isLoadingPhotos {
                    ProgressView()
                } else {
                    Label(pickedImages.isEmpty ? "사진 추가".localized : "사진 더 추가".localized, systemImage: "photo.badge.plus")
                }
            }
            .disabled(isLoadingPhotos)

            if !pickedImages.isEmpty {
                Button {
                    Task { await analyzePickedPhotos() }
                } label: {
                    if isAnalyzingPhotos {
                        ProgressView()
                    } else {
                        Text("AI로 정보 읽어오기".localized)
                    }
                }
                .disabled(isAnalyzingPhotos)
            }

            if let photoAnalysisMessage {
                Text(photoAnalysisMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("사진 추가".localized)
        } footer: {
            Text("사진은 저장 시 카드에 추가됩니다. \"AI로 정보 읽어오기\"는 비어 있는 이름·주소를 채우는데, 사진에서 여러 장소가 발견되면 적용하지 않고 알려드리고, 이름이 바뀌는 경우엔 확인 후 적용됩니다.".localized)
        }
    }

    /// Fills in whatever's still blank — phone, website, category, hours,
    /// amenities, and anything else worth a memo note — by having AI
    /// search the web for this place, instead of reading a photo. Not
    /// every AI provider supports this (see `AIProvider
    /// .searchWebForDetails`'s doc comment); unsupported providers show
    /// that method's own "not supported" error rather than this section
    /// pretending the button isn't there.
    @ViewBuilder
    private var webSearchSection: some View {
        Section {
            Button {
                Task { await searchWebForDetails() }
            } label: {
                if isSearchingWeb {
                    ProgressView()
                } else {
                    Label("웹 검색으로 채우기".localized, systemImage: "magnifyingglass")
                }
            }
            .disabled(isSearchingWeb || name.trimmingCharacters(in: .whitespaces).isEmpty)

            if let webSearchMessage {
                Text(webSearchMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("이름·주소로 AI가 웹을 검색해 전화번호·웹사이트·영업시간 등 비어 있는 항목만 채웁니다. 이미 값이 있는 항목은 바뀌지 않습니다.".localized)
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                pickedImages.append(image)
            }
        }
    }

    private func analyzePickedPhotos() async {
        isAnalyzingPhotos = true
        photoAnalysisMessage = nil
        defer { isAnalyzingPhotos = false }

        let imageDatas = pickedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
        guard !imageDatas.isEmpty else { return }

        let providerType = SettingsViewModel.currentAIProviderType()
        guard let apiKey = KeychainService.load(providerType.keychainKey), !apiKey.isEmpty else {
            photoAnalysisMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        let provider = await AIProviderFactory.create(type: providerType, apiKey: apiKey)
        do {
            let results = try await provider.analyzePlaces(imageDatas: imageDatas, prompt: defaultPlaceAnalysisPrompt())
            handleAnalysisResults(results)
        } catch {
            photoAnalysisMessage = error.localizedDescription
        }
    }

    /// Unlike `AddPlaceCardView` (where several places found in one photo
    /// just become several rows to review), this is editing one specific,
    /// already-named card — a photo naming more than one place is too
    /// ambiguous to apply to it at all, so that case is reported and
    /// nothing is changed. A single result whose name doesn't match the
    /// current one is applied only after asking, since overwriting an
    /// existing name is a real behavior change; everything else (filling
    /// a blank name/address) applies immediately, matching how every
    /// other "fill in" action elsewhere in this app already behaves.
    private func handleAnalysisResults(_ results: [AIAnalysisResult]) {
        guard !results.isEmpty else {
            photoAnalysisMessage = "사진에서 장소 정보를 찾지 못했습니다.".localized
            return
        }
        guard results.count == 1 else {
            let names = results.map(\.placeName).joined(separator: ", ")
            photoAnalysisMessage = "사진에서 여러 장소(".localized + names + ")가 발견되어 적용하지 않았습니다. 한 장소가 나온 사진으로 다시 시도해주세요.".localized
            return
        }

        let result = results[0]
        let extractedName = result.placeName.trimmingCharacters(in: .whitespaces)
        let currentName = name.trimmingCharacters(in: .whitespaces)
        if !extractedName.isEmpty, !currentName.isEmpty, extractedName != currentName {
            pendingExtractedPlace = result
            isConfirmingNameChange = true
        } else {
            applyExtractedPlace(result)
        }
    }

    /// Reports back exactly which fields got filled (name/address/memo,
    /// plus whatever `fillBlankFields(from:)` picked up from `result
    /// .details` — phone/website/category/hours/amenities, the same
    /// fields a Google Maps screenshot's own info card routinely shows)
    /// instead of a generic "정보를 채웠습니다.", the same reasoning
    /// `applyWebDetails` below already follows for a web search's result.
    private func applyExtractedPlace(_ result: AIAnalysisResult) {
        var filledFields: [String] = []

        let extractedName = result.placeName.trimmingCharacters(in: .whitespaces)
        if !extractedName.isEmpty {
            name = extractedName
            filledFields.append("이름".localized)
        }
        if address.trimmingCharacters(in: .whitespaces).isEmpty,
           let extractedAddress = result.address?.trimmingCharacters(in: .whitespaces), !extractedAddress.isEmpty {
            address = extractedAddress
            filledFields.append("주소".localized)
        }
        if let details = result.details {
            filledFields.append(contentsOf: fillBlankFields(from: details))
            stageSuggestedTags(from: details.tags)
        }
        if let combined = PlaceCard.combinedMemo(memoText.isEmpty ? nil : memoText, appending: result.description), combined != memoText {
            memoText = combined
            filledFields.append("메모".localized)
        }

        photoAnalysisMessage = filledFields.isEmpty
            ? "사진에서 새로 채울 정보를 찾지 못했습니다.".localized
            : filledFields.joined(separator: ", ") + " 정보를 채웠습니다.".localized
    }

    private func searchWebForDetails() async {
        isSearchingWeb = true
        webSearchMessage = nil
        defer { isSearchingWeb = false }

        let providerType = SettingsViewModel.currentAIProviderType()
        guard let apiKey = KeychainService.load(providerType.keychainKey), !apiKey.isEmpty else {
            webSearchMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        let provider = await AIProviderFactory.create(type: providerType, apiKey: apiKey)
        do {
            let details = try await provider.searchWebForDetails(name: name, address: address)
            applyWebDetails(details)
        } catch {
            webSearchMessage = error.localizedDescription
        }
    }

    /// Fills only whatever's currently blank from `details` — phone/
    /// website/category/hours/amenities — and returns the localized names
    /// of exactly which fields got filled. Shared by `applyWebDetails`
    /// (from a web search) and `applyExtractedPlace` (from a photo scan —
    /// `AIAnalysisResult.details` is the exact same shape), so both report
    /// precisely what changed instead of a generic "정보를 채웠습니다."
    /// that says nothing about what actually happened.
    private func fillBlankFields(from details: PlaceWebDetails) -> [String] {
        var filledFields: [String] = []

        if phone.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.phone, !value.isEmpty {
            phone = value
            filledFields.append("전화번호".localized)
        }
        if website.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.website, !value.isEmpty {
            website = value
            filledFields.append("웹사이트".localized)
        }
        if category.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.category, !value.isEmpty {
            category = value
            filledFields.append("카테고리".localized)
        }
        if hoursEntries.isEmpty, let hoursDetail = details.hoursDetail, !hoursDetail.isEmpty {
            hoursEntries = hoursDetail.sorted { $0.key < $1.key }.map { HoursEntry(day: $0.key, hours: $0.value) }
            filledFields.append("영업시간".localized)
        }
        if closingTime.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.closingTime, !value.isEmpty {
            closingTime = value
            filledFields.append("마감 시간".localized)
        }
        if holidays.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.holidays, !value.isEmpty {
            holidays = value
            filledFields.append("휴무일".localized)
        }
        if reservationInfo.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.reservationInfo, !value.isEmpty {
            reservationInfo = value
            filledFields.append("예약 방법".localized)
        }
        if !details.amenities.isEmpty {
            let existing = Set(amenitiesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            let newOnes = details.amenities.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !existing.contains($0) }
            if !newOnes.isEmpty {
                amenitiesText = amenitiesText.trimmingCharacters(in: .whitespaces).isEmpty
                    ? newOnes.joined(separator: ", ")
                    : amenitiesText + ", " + newOnes.joined(separator: ", ")
                filledFields.append("편의시설".localized)
            }
        }

        return filledFields
    }

    /// Never overwrites a value the user (or another source) already set —
    /// and reports back exactly which fields it touched, since a silent
    /// "done" wouldn't say whether anything actually changed.
    private func applyWebDetails(_ details: PlaceWebDetails) {
        var filledFields = fillBlankFields(from: details)
        stageSuggestedTags(from: details.tags)
        if let combined = PlaceCard.combinedMemo(memoText.isEmpty ? nil : memoText, appending: details.note), combined != memoText {
            memoText = combined
            filledFields.append("메모".localized)
        }

        webSearchMessage = filledFields.isEmpty
            ? "웹 검색에서 새로 채울 정보를 찾지 못했습니다.".localized
            : filledFields.joined(separator: ", ") + " 정보를 채웠습니다.".localized
    }

    /// Narrows `suggested` down to tags not already in `tagsText`, and — if
    /// any remain — stages them for `isConfirmingSuggestedTags`'s alert
    /// rather than adding them outright (see `PlaceWebDetails.tags`'s own
    /// doc comment for why). A no-op when there's nothing new to offer, so
    /// this never pops an empty confirmation.
    private func stageSuggestedTags(from suggested: [String]) {
        guard !suggested.isEmpty else { return }
        let existing = Set(tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let newTags = suggested.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !existing.contains($0) }
        guard !newTags.isEmpty else { return }
        pendingSuggestedTags = newTags
        isConfirmingSuggestedTags = true
    }

    private func addSuggestedTags() {
        guard !pendingSuggestedTags.isEmpty else { return }
        tagsText = tagsText.trimmingCharacters(in: .whitespaces).isEmpty
            ? pendingSuggestedTags.joined(separator: ", ")
            : tagsText + ", " + pendingSuggestedTags.joined(separator: ", ")
    }

    private func save() {
        var updated = card
        updated.name = name.trimmingCharacters(in: .whitespaces)
        let trimmedCategory = category.trimmingCharacters(in: .whitespaces)
        updated.category = trimmedCategory.isEmpty ? nil : trimmedCategory
        updated.address = address.trimmingCharacters(in: .whitespaces)

        let trimmedLatitude = latitudeText.trimmingCharacters(in: .whitespaces)
        let trimmedLongitude = longitudeText.trimmingCharacters(in: .whitespaces)
        if trimmedLatitude.isEmpty && trimmedLongitude.isEmpty {
            updated.coordinates = nil
        } else if let latitude = Double(trimmedLatitude), let longitude = Double(trimmedLongitude) {
            updated.coordinates = Coordinates(latitude: latitude, longitude: longitude)
        }

        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        updated.phone = trimmedPhone.isEmpty ? nil : trimmedPhone
        let trimmedWebsite = website.trimmingCharacters(in: .whitespaces)
        updated.website = trimmedWebsite.isEmpty ? nil : trimmedWebsite
        let trimmedInstagram = instagramURL.trimmingCharacters(in: .whitespaces)
        updated.instagramURL = trimmedInstagram.isEmpty ? nil : trimmedInstagram

        let trimmedRating = ratingText.trimmingCharacters(in: .whitespaces)
        updated.rating = trimmedRating.isEmpty ? nil : Double(trimmedRating)
        let trimmedReviewCount = reviewCountText.trimmingCharacters(in: .whitespaces)
        updated.reviewCount = trimmedReviewCount.isEmpty ? nil : Int(trimmedReviewCount)

        updated.isFavorite = isFavorite
        updated.isVisited = isVisited

        let trimmedClosingTime = closingTime.trimmingCharacters(in: .whitespaces)
        updated.closingTime = trimmedClosingTime.isEmpty ? nil : trimmedClosingTime
        let trimmedHolidays = holidays.trimmingCharacters(in: .whitespaces)
        updated.holidays = trimmedHolidays.isEmpty ? nil : trimmedHolidays
        let trimmedReservationInfo = reservationInfo.trimmingCharacters(in: .whitespaces)
        updated.reservationInfo = trimmedReservationInfo.isEmpty ? nil : trimmedReservationInfo

        var hoursDetail: [String: String] = [:]
        for entry in hoursEntries {
            let day = entry.day.trimmingCharacters(in: .whitespaces)
            let hours = entry.hours.trimmingCharacters(in: .whitespaces)
            guard !day.isEmpty, !hours.isEmpty else { continue }
            hoursDetail[day] = hours
        }
        updated.hoursDetail = hoursDetail.isEmpty ? nil : hoursDetail

        updated.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        updated.amenities = amenitiesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let trimmedMemo = memoText.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.memo = trimmedMemo.isEmpty ? nil : trimmedMemo

        for image in pickedImages {
            if let fileName = try? MediaStore.saveImage(image) {
                updated.media.onsitePhotos.append(MediaItem(localPath: fileName, source: .onsitePhoto))
            }
        }

        storageService.save(updated)
        onSave(updated)
        dismiss()
    }
}

#Preview {
    EditPlaceCardSheet(card: PlaceCard(boardId: "preview", name: "샘플 카페".localized, address: "서울시 강남구".localized)) { _ in }
        .environmentObject(StorageService())
}
