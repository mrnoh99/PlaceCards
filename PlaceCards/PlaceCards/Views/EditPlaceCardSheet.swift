import SwiftUI
import PhotosUI
import CoreLocation

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
    /// Same radius/reasoning as `PlaceCardViewModel.maxPhotoLocationMatch
    /// DistanceMeters` — a photo's own EXIF GPS reflects wherever the
    /// phone was standing, not necessarily the place's own doorstep, so
    /// this stays looser than an address-based match would need.
    private static let maxPhotoLocationMatchDistanceMeters: CLLocationDistance = 500

    /// Tighter than `maxPhotoLocationMatchDistanceMeters` — used only for
    /// `warnIfNotOnsitePhoto`, where this card's own name+address are
    /// already established (not a first guess this app is trying to
    /// confirm), so a newly added photo held against them deserves the
    /// same tight standard `PlaceCardViewModel.maxAddressMatchDistance
    /// Meters` uses for an address match elsewhere.
    private static let maxAddressMatchDistanceMeters: CLLocationDistance = 100

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
    @State private var myRatingText: String
    @State private var priceLevel: PriceLevel?
    @State private var isFavorite: Bool
    @State private var isVisited: Bool
    @State private var wouldRevisit: Bool?
    @State private var visitDates: [Date]
    @State private var closingTime: String
    @State private var holidays: String
    @State private var reservationInfo: String
    @State private var recommendedMenu: String
    @State private var suggestedDuration: String
    @State private var admissionFee: String
    @State private var hoursEntries: [HoursEntry]
    @State private var externalLinkEntries: [ExternalLink]
    @State private var tagsText: String
    @State private var amenitiesText: String
    @State private var awardsText: String
    @State private var dietaryOptionsText: String
    @State private var memoText: String

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var pickedImages: [UIImage] = []
    /// The original, unmodified bytes for each of `pickedImages` (same
    /// index) — kept alongside since EXIF (read for `analyzePickedPhotos()`'s
    /// own photo-GPS auto-fill) doesn't survive being decoded into a
    /// `UIImage`. Mirrors `AddPlaceCardView.pickedImageDatas`.
    @State private var pickedImageDatas: [Data] = []
    @State private var isLoadingPhotos = false
    @State private var isAnalyzingPhotos = false
    @State private var photoAnalysisMessage: String?
    @State private var pendingExtractedPlace: AIAnalysisResult?
    /// Whatever `applyOrWarnPhotoLocation(_:placeAddress:)` reported for
    /// this batch, carried alongside `pendingExtractedPlace` across the
    /// name-change confirmation alert since `applyExtractedPlace` (where
    /// it's actually surfaced) only runs once the user picks "변경" — the
    /// coordinate fields themselves are written immediately in
    /// `analyzePickedPhotos()`, independent of that decision.
    @State private var pendingPhotoLocationNote: String?
    @State private var isConfirmingNameChange = false
    /// Off by default — a coordinate is trusted evidence about where a
    /// photo was taken, not about what the AI read off it, so this app
    /// only acts on a photo's GPS for location purposes at all once the
    /// user opts in here. See `applyOrWarnPhotoLocation(_:placeAddress:)`.
    @State private var usePhotoGPSForLocation = false

    @State private var isSearchingWeb = false
    @State private var webSearchMessage: String?

    @State private var isRefreshingGoogleDetails = false
    @State private var googleRefreshMessage: String?

    @State private var isGeocodingAddress = false
    @State private var geocodeMessage: String?

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
        _myRatingText = State(initialValue: card.myRating.map { String($0) } ?? "")
        _priceLevel = State(initialValue: card.priceLevel)
        _isFavorite = State(initialValue: card.isFavorite)
        _isVisited = State(initialValue: card.isVisited)
        _wouldRevisit = State(initialValue: card.wouldRevisit)
        _visitDates = State(initialValue: card.visitDates)
        _closingTime = State(initialValue: card.closingTime ?? "")
        _holidays = State(initialValue: card.holidays ?? "")
        _reservationInfo = State(initialValue: card.reservationInfo ?? "")
        _recommendedMenu = State(initialValue: card.recommendedMenu ?? "")
        _suggestedDuration = State(initialValue: card.suggestedDuration ?? "")
        _admissionFee = State(initialValue: card.admissionFee ?? "")
        _hoursEntries = State(initialValue: (card.hoursDetail ?? [:]).sorted { $0.key < $1.key }.map { HoursEntry(day: $0.key, hours: $0.value) })
        _externalLinkEntries = State(initialValue: card.externalLinks)
        _tagsText = State(initialValue: card.tags.joined(separator: ", "))
        _amenitiesText = State(initialValue: card.amenities.joined(separator: ", "))
        _awardsText = State(initialValue: card.awards.joined(separator: ", "))
        _dietaryOptionsText = State(initialValue: card.dietaryOptions.joined(separator: ", "))
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
                Group {
                    photoImportSection
                    basicInfoSection
                    webSearchSection
                    googleRefreshSection
                    coordinatesSection
                    contactSection
                    externalLinksSection
                    ratingSection
                }
                Group {
                    statusSection
                    visitDatesSection
                    businessHoursSection
                    recommendedMenuSection
                    attractionInfoSection
                }
                Group {
                    awardsSection
                    dietaryOptionsSection
                    tagsSection
                    amenitiesSection
                    memoSection
                }
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
                        applyExtractedPlace(pendingExtractedPlace, photoLocationNote: pendingPhotoLocationNote)
                    }
                    pendingExtractedPlace = nil
                    pendingPhotoLocationNote = nil
                }
                Button("취소".localized, role: .cancel) {
                    pendingExtractedPlace = nil
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

    /// A card with no `googlePlaceId` (Naver-verified, or saved without
    /// ever searching — see `createManualPlaceCard`) has no way to get
    /// coordinates other than typing them in by hand, until now: this
    /// turns whatever's in the 주소 field into a coordinate the same
    /// non-AI way `createManualPlaceCard` already does at creation time
    /// (`GooglePlacesService.geocodeAddress(_:)`) — meant to close the
    /// loop after using `PlaceCardDetailView`'s "지도에서 열기" (now
    /// available even with no coordinates yet, since Google Maps only
    /// needs a name/address text query) to find the real place and copy
    /// its confirmed address back here. Always overwrites on tap, unlike
    /// every other "fill in" action on this screen — this one only ever
    /// runs when the user explicitly asks it to re-derive coordinates
    /// from whatever address is currently typed, not as a background
    /// fill-blanks step.
    @ViewBuilder
    private var coordinatesSection: some View {
        Section {
            TextField("위도".localized, text: $latitudeText)
                .keyboardType(.numbersAndPunctuation)
            TextField("경도".localized, text: $longitudeText)
                .keyboardType(.numbersAndPunctuation)

            Button {
                Task { await geocodeFromAddress() }
            } label: {
                if isGeocodingAddress {
                    ProgressView()
                } else {
                    Label("주소로 좌표 확인".localized, systemImage: "location.magnifyingglass")
                }
            }
            .disabled(isGeocodingAddress || address.trimmingCharacters(in: .whitespaces).isEmpty)

            if let geocodeMessage {
                Text(geocodeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("위치정보에 사진 GPS 사용".localized, isOn: $usePhotoGPSForLocation)
        } header: {
            Text("좌표".localized)
        } footer: {
            Text("둘 다 비우면 좌표가 삭제됩니다. 하나만 채워지면 원래 값이 그대로 유지됩니다. \"주소로 좌표 확인\"은 AI 없이 Google Places로 위 주소를 좌표로 바꿔줍니다 — 상세보기의 \"지도에서 열기\"로 정확한 주소를 먼저 확인한 뒤 여기 채우고 눌러보세요. \"위치정보에 사진 GPS 사용\"을 켜두면, 위도·경도가 비어 있을 때 새로 추가하는 사진의 GPS를 좌표로 저장합니다(주소와 100m 이상 차이 나면 저장하지 않고 알려드립니다). 이미 채워져 있으면 새 사진이 그 위치에서 찍힌 게 맞는지만 확인합니다.".localized)
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
    private var externalLinksSection: some View {
        Section {
            ForEach($externalLinkEntries) { $entry in
                HStack {
                    TextField("플랫폼 (예: Trip Advisor)".localized, text: $entry.platform)
                        .frame(width: 110)
                    Divider()
                    TextField("URL", text: $entry.url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .onDelete { externalLinkEntries.remove(atOffsets: $0) }
            Button("+ 링크 추가".localized) {
                externalLinkEntries.append(ExternalLink(platform: "", url: ""))
            }
        } header: {
            Text("외부 링크".localized)
        } footer: {
            Text("Google 지도, Naver 지도, Trip Advisor 등 이 장소의 페이지 링크를 추가해두면 상세보기에서 바로 열 수 있습니다.".localized)
        }
    }

    @ViewBuilder
    private var ratingSection: some View {
        Section("평가".localized) {
            TextField("평점 (0~5)".localized, text: $ratingText)
                .keyboardType(.decimalPad)
            TextField("리뷰 수".localized, text: $reviewCountText)
                .keyboardType(.numberPad)
            TextField("내 평점 (0~5)".localized, text: $myRatingText)
                .keyboardType(.decimalPad)
            Picker("가격대".localized, selection: $priceLevel) {
                Text("설정 안 함".localized).tag(PriceLevel?.none)
                ForEach(PriceLevel.allCases, id: \.self) { level in
                    Text(level.symbol).tag(PriceLevel?.some(level))
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("상태".localized) {
            Toggle("즐겨찾기".localized, isOn: $isFavorite)
            Toggle("방문함".localized, isOn: $isVisited)
            Picker("다시 방문 의향".localized, selection: $wouldRevisit) {
                Text("모름".localized).tag(Bool?.none)
                Text("다시 갈래요".localized).tag(Bool?.some(true))
                Text("다시 안 갈래요".localized).tag(Bool?.some(false))
            }
        }
    }

    @ViewBuilder
    private var visitDatesSection: some View {
        Section {
            ForEach(Array(visitDates.enumerated()), id: \.offset) { index, _ in
                DatePicker(
                    "방문 날짜".localized, selection: $visitDates[index], displayedComponents: .date
                )
            }
            .onDelete { visitDates.remove(atOffsets: $0) }
            Button("+ 방문 날짜 추가".localized) {
                visitDates.append(Date())
            }
        } header: {
            Text("방문 날짜".localized)
        } footer: {
            Text("위 \"방문함\"과 별개로, 실제로 방문한 날짜들을 기록해둡니다.".localized)
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
    private var recommendedMenuSection: some View {
        Section {
            TextField("추천 메뉴".localized, text: $recommendedMenu, axis: .vertical)
        } header: {
            Text("추천 메뉴".localized)
        }
    }

    /// Both fields here mainly matter for attractions/museums (not
    /// restaurants), same reasoning as `PlaceCard.suggestedDuration`'s
    /// own doc comment — grouped into one small section rather than two,
    /// since each is a single short line.
    @ViewBuilder
    private var attractionInfoSection: some View {
        Section {
            TextField("추천 소요 시간 (예: 1~2시간)".localized, text: $suggestedDuration)
            TextField("입장료 (예: 성인 15,000원)".localized, text: $admissionFee)
        } header: {
            Text("관광 정보".localized)
        }
    }

    @ViewBuilder
    private var awardsSection: some View {
        Section {
            TextField("쉼표로 구분".localized, text: $awardsText, axis: .vertical)
        } header: {
            Text("수상/인증".localized)
        } footer: {
            Text("미쉐린 별점, TripAdvisor Travelers' Choice, 블루리본서베이 등 제3자가 부여한 인증을 적어둡니다.".localized)
        }
    }

    @ViewBuilder
    private var dietaryOptionsSection: some View {
        Section {
            TextField("쉼표로 구분".localized, text: $dietaryOptionsText, axis: .vertical)
        } header: {
            Text("식이 옵션".localized)
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
                                    pickedImageDatas.remove(at: index)
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
                .disabled(isAnalyzingPhotos || !AIProviderChain.hasAnyConfiguredProvider())

                if !AIProviderChain.hasAnyConfiguredProvider() {
                    Text(AIProviderChain.unconfiguredHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            .disabled(isSearchingWeb || name.trimmingCharacters(in: .whitespaces).isEmpty || !AIProviderChain.hasAnyConfiguredProvider())

            if !AIProviderChain.hasAnyConfiguredProvider() {
                Text(AIProviderChain.unconfiguredHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let webSearchMessage {
                Text(webSearchMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("이름·주소로 AI가 웹을 검색해 전화번호·웹사이트·영업시간 등 비어 있는 항목만 채웁니다. 이미 값이 있는 항목은 바뀌지 않습니다.".localized)
        }
    }

    /// AI가 전혀 필요 없는 대안 — 이 카드가 만들어질 때 검증됐던 바로
    /// 그 Google Places 장소(`card.googlePlaceId`)의 공식 상세 정보를
    /// 다시 조회해 비어 있는 항목만 채운다. Google Places API 키만
    /// 있으면 되고, AI 제공자가 하나도 등록되어 있지 않아도 항상 쓸 수
    /// 있음 — `googlePlaceId`가 없는 카드(Naver로 검증됐거나 수동으로
    /// 만든 카드)에는 아예 표시하지 않는다.
    @ViewBuilder
    private var googleRefreshSection: some View {
        if card.googlePlaceId != nil {
            Section {
                Button {
                    Task { await refreshFromGooglePlaceDetails() }
                } label: {
                    if isRefreshingGoogleDetails {
                        ProgressView()
                    } else {
                        Label("Google에서 새로고침".localized, systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshingGoogleDetails)

                if let googleRefreshMessage {
                    Text(googleRefreshMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("AI 없이 Google Places API로 이 장소의 영업시간·평점·전화번호·웹사이트 등 비어 있는 항목만 다시 확인합니다.".localized)
            }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        var newPhotoDatas: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                pickedImages.append(image)
                pickedImageDatas.append(data)
                newPhotoDatas.append(data)
            }
        }
        let photoCoordinates = newPhotoDatas.compactMap(PhotoMetadata.extractLocation)
        let candidate = photoCoordinates.count > 1 ? Coordinates.average(photoCoordinates) : photoCoordinates.first
        if let note = await applyOrWarnPhotoLocation(candidate) {
            photoAnalysisMessage = note
        }
    }

    /// Only ever does anything when `usePhotoGPSForLocation` is checked —
    /// otherwise this app doesn't act on a photo's GPS for location
    /// purposes at all, and this returns `nil` immediately. Called both
    /// right when a photo is picked (`loadPhotos`, no `placeAddress`) and
    /// after AI confirms a single place (`analyzePickedPhotos`, passing
    /// the AI's own extracted address).
    ///
    /// When this card's coordinate fields are both blank, this is the one
    /// thing that actually fills them: cross-checked against
    /// `placeAddress` (or, when that's blank, this card's own current
    /// `address` field), geocoded — a match within `maxPhotoLocationMatch
    /// DistanceMeters` applies it; disagreeing warns and leaves the
    /// fields blank rather than trusting a photo that might not even be
    /// of this place. No address to check against at all still applies
    /// it (nothing to contradict it), with a note that it rests on the
    /// photo's GPS alone. When the fields are already filled, nothing is
    /// applied — this instead becomes a pure sanity check against them
    /// (the strongest ground truth available, so held to the tighter
    /// `maxAddressMatchDistanceMeters`): a newly added photo whose own
    /// EXIF GPS lands far from those coordinates is likely not actually a
    /// photo taken there at all (saved from elsewhere, someone else's
    /// photo, a mislabeled screenshot), worth flagging even though
    /// nothing is changed.
    private func applyOrWarnPhotoLocation(_ candidate: Coordinates?, placeAddress: String? = nil) async -> String? {
        guard usePhotoGPSForLocation, let candidate else { return nil }

        if let latitude = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
           let longitude = Double(longitudeText.trimmingCharacters(in: .whitespaces)) {
            let distance = CLLocation(latitude: latitude, longitude: longitude)
                .distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude))
            guard distance > Self.maxAddressMatchDistanceMeters else { return nil }
            return "추가한 사진이 이 장소에서 촬영된 것 같지 않습니다 (사진 GPS가 주소에서 100m 이상 떨어져 있습니다).".localized
        }

        let trimmedAddress = (placeAddress ?? address).trimmingCharacters(in: .whitespaces)
        guard !trimmedAddress.isEmpty,
            let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty,
            let addressLocation = try? await GooglePlacesService(apiKey: apiKey).geocodeAddress(trimmedAddress)
        else {
            latitudeText = String(candidate.latitude)
            longitudeText = String(candidate.longitude)
            return "대조할 장소 주소가 없어 사진의 위치 정보만 사용합니다.".localized
        }

        let distance = CLLocation(latitude: addressLocation.latitude, longitude: addressLocation.longitude)
            .distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude))
        guard distance <= Self.maxPhotoLocationMatchDistanceMeters else {
            return "사진의 위치 정보가 인식된 장소 주소와 너무 멀어 사진 위치는 사용하지 않았습니다.".localized
        }
        latitudeText = String(candidate.latitude)
        longitudeText = String(candidate.longitude)
        return "사진의 위치 정보로 좌표를 저장했습니다.".localized
    }

    private func analyzePickedPhotos() async {
        isAnalyzingPhotos = true
        photoAnalysisMessage = nil
        defer { isAnalyzingPhotos = false }

        let imageDatas = pickedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
        guard !imageDatas.isEmpty else { return }

        guard AIProviderChain.hasAnyConfiguredProvider() else {
            photoAnalysisMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        do {
            let (results, provider, isFallback) = try await AIProviderChain.run {
                try await $0.analyzePlaces(imageDatas: imageDatas, prompt: defaultPlaceAnalysisPrompt())
            }
            // Only ever computed for a confirmed single-place result — see
            // `handleAnalysisResults`, which applies nothing at all when
            // the batch resolves to several places, so there's no risk of
            // this candidate being misattributed across different places'
            // rows the way `PlaceCardViewModel.analyzeImages` had to guard
            // against.
            var photoLocationNote: String?
            if results.count == 1 {
                let photoCoordinates = pickedImageDatas.compactMap(PhotoMetadata.extractLocation)
                let candidate = photoCoordinates.count > 1 ? Coordinates.average(photoCoordinates) : photoCoordinates.first
                photoLocationNote = await applyOrWarnPhotoLocation(candidate, placeAddress: results[0].address)
            }
            handleAnalysisResults(results, answeredBy: isFallback ? provider : nil, photoLocationNote: photoLocationNote)
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
    private func handleAnalysisResults(
        _ results: [AIAnalysisResult], answeredBy fallbackProvider: AIProviderType? = nil, photoLocationNote: String? = nil
    ) {
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
            // The name-change confirmation happens on a later tap (the
            // alert's own button), by which point this call's fallback
            // note would be stale context to carry along — skipped here,
            // same as every other detail this branch already defers. The
            // photo location note is carried along instead, since
            // `applyExtractedPlace` still needs it once confirmed — the
            // coordinate fields themselves were already written (or not)
            // by `applyOrWarnPhotoLocation` regardless of this decision.
            pendingExtractedPlace = result
            pendingPhotoLocationNote = photoLocationNote
            isConfirmingNameChange = true
        } else {
            applyExtractedPlace(result, answeredBy: fallbackProvider, photoLocationNote: photoLocationNote)
        }
    }

    /// Reports back exactly which fields got filled (name/address/memo,
    /// plus whatever `fillBlankFields(from:)` picked up from `result
    /// .details` — phone/website/category/hours/amenities, the same
    /// fields a Google Maps screenshot's own info card routinely shows)
    /// instead of a generic "정보를 채웠습니다.", the same reasoning
    /// `applyWebDetails` below already follows for a web search's result.
    private func applyExtractedPlace(
        _ result: AIAnalysisResult, answeredBy fallbackProvider: AIProviderType? = nil, photoLocationNote: String? = nil
    ) {
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
        if let fallbackProvider {
            photoAnalysisMessage? += fallbackProvider.fallbackNoteSuffix
        }
        if let photoLocationNote {
            photoAnalysisMessage = [photoAnalysisMessage, photoLocationNote].compactMap { $0 }.joined(separator: "\n")
        }
    }

    private func searchWebForDetails() async {
        isSearchingWeb = true
        webSearchMessage = nil
        defer { isSearchingWeb = false }

        guard AIProviderChain.hasAnyConfiguredProvider() else {
            webSearchMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        do {
            let (details, provider, isFallback) = try await AIProviderChain.run {
                try await $0.searchWebForDetails(name: name, address: address, knownLinks: knownLinks)
            }
            applyWebDetails(details, answeredBy: isFallback ? provider : nil)
        } catch {
            webSearchMessage = error.localizedDescription
        }
    }

    /// The non-AI counterpart to `searchWebForDetails()` above — re-fetches
    /// this exact place's own Google Places details (only possible when
    /// `card.googlePlaceId` is set — see `googleRefreshSection`) and fills
    /// whatever's still blank, same "never overwrite" rule as every other
    /// fill-in action here.
    private func refreshFromGooglePlaceDetails() async {
        guard let placeId = card.googlePlaceId else { return }
        isRefreshingGoogleDetails = true
        googleRefreshMessage = nil
        defer { isRefreshingGoogleDetails = false }

        guard let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty else {
            googleRefreshMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        do {
            let details = try await GooglePlacesService(apiKey: apiKey).details(placeId: placeId)
            let filledFields = fillBlankFields(from: details)
            googleRefreshMessage = filledFields.isEmpty
                ? "Google에서 새로 채울 정보를 찾지 못했습니다.".localized
                : filledFields.joined(separator: ", ") + " 정보를 채웠습니다.".localized
        } catch {
            googleRefreshMessage = error.localizedDescription
        }
    }

    /// Re-derives coordinates from whatever's currently in the 주소
    /// field, entirely non-AI — the same `geocodeAddress(_:)` call
    /// `createManualPlaceCard`/`searchViaGoogle` already use elsewhere,
    /// just triggered by hand here instead of automatically at creation
    /// time. The one way to give a card coordinates after the fact when
    /// it has no `googlePlaceId` to refresh from (`refreshFromGooglePlace
    /// Details()` above needs one) — meant to follow up on manually
    /// confirming the real address via `PlaceCardDetailView`'s "지도에서
    /// 열기" (Google Maps opens off name/address text alone, no
    /// coordinate needed, so it's reachable even before this ever runs).
    private func geocodeFromAddress() async {
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        guard !trimmedAddress.isEmpty else { return }
        isGeocodingAddress = true
        geocodeMessage = nil
        defer { isGeocodingAddress = false }

        guard let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty else {
            geocodeMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        do {
            guard let coordinates = try await GooglePlacesService(apiKey: apiKey).geocodeAddress(trimmedAddress) else {
                geocodeMessage = "주소로 좌표를 찾지 못했습니다.".localized
                return
            }
            latitudeText = String(coordinates.latitude)
            longitudeText = String(coordinates.longitude)
            geocodeMessage = "좌표를 확인했습니다.".localized
        } catch {
            geocodeMessage = error.localizedDescription
        }
    }

    /// This card's own `externalLinks`, formatted as `"<platform>:
    /// <url>"` for `AIProvider.searchWebForDetails` to check first —
    /// blank rows (still being typed in, or never filled in) are dropped
    /// rather than sent as noise.
    private var knownLinks: [String] {
        externalLinkEntries.compactMap { entry in
            let platform = entry.platform.trimmingCharacters(in: .whitespaces)
            let url = entry.url.trimmingCharacters(in: .whitespaces)
            guard !platform.isEmpty, !url.isEmpty else { return nil }
            return "\(platform): \(url)"
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
        if recommendedMenu.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.recommendedMenu, !value.isEmpty {
            recommendedMenu = value
            filledFields.append("추천 메뉴".localized)
        }
        if suggestedDuration.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.suggestedDuration, !value.isEmpty {
            suggestedDuration = value
            filledFields.append("추천 소요 시간".localized)
        }
        if admissionFee.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.admissionFee, !value.isEmpty {
            admissionFee = value
            filledFields.append("입장료".localized)
        }
        if let merged = mergeCommaList(details.amenities, into: amenitiesText) {
            amenitiesText = merged
            filledFields.append("편의시설".localized)
        }
        if let merged = mergeCommaList(details.awards, into: awardsText) {
            awardsText = merged
            filledFields.append("수상/인증".localized)
        }
        if let merged = mergeCommaList(details.dietaryOptions, into: dietaryOptionsText) {
            dietaryOptionsText = merged
            filledFields.append("식이 옵션".localized)
        }

        return filledFields
    }

    /// The `PlaceDetails` counterpart to `fillBlankFields(from:
    /// PlaceWebDetails)` above, for `refreshFromGooglePlaceDetails()` —
    /// a different (smaller, Google-specific) shape than `PlaceWebDetails`
    /// (it also carries rating/review count, which no AI-sourced result
    /// does, since that's already covered at card-creation time from the
    /// search result itself).
    private func fillBlankFields(from details: PlaceDetails) -> [String] {
        var filledFields: [String] = []

        if ratingText.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.rating {
            ratingText = String(value)
            filledFields.append("평점".localized)
        }
        if reviewCountText.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.reviewCount {
            reviewCountText = String(value)
            filledFields.append("리뷰 수".localized)
        }
        if phone.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.phone, !value.isEmpty {
            phone = value
            filledFields.append("전화번호".localized)
        }
        if website.trimmingCharacters(in: .whitespaces).isEmpty, let value = details.website, !value.isEmpty {
            website = value
            filledFields.append("웹사이트".localized)
        }
        if hoursEntries.isEmpty, let hoursDetail = details.hoursDetail, !hoursDetail.isEmpty {
            hoursEntries = hoursDetail.sorted { $0.key < $1.key }.map { HoursEntry(day: $0.key, hours: $0.value) }
            filledFields.append("영업시간".localized)
        }
        if let merged = mergeCommaList(details.amenities, into: amenitiesText) {
            amenitiesText = merged
            filledFields.append("편의시설".localized)
        }
        if latitudeText.trimmingCharacters(in: .whitespaces).isEmpty,
           longitudeText.trimmingCharacters(in: .whitespaces).isEmpty,
           let coordinates = details.coordinates {
            latitudeText = String(coordinates.latitude)
            longitudeText = String(coordinates.longitude)
            filledFields.append("좌표".localized)
        }

        return filledFields
    }

    /// Merges `newValues` into a comma-separated text field, keeping
    /// whatever's already there and skipping anything already present —
    /// shared by every comma-list field (amenities/awards/dietary
    /// options) both `fillBlankFields` overloads above fill the same way.
    /// Returns `nil` when there's nothing new to add, so a caller can
    /// tell "merged" apart from "no-op" without re-checking itself.
    private func mergeCommaList(_ newValues: [String], into text: String) -> String? {
        guard !newValues.isEmpty else { return nil }
        let existing = Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let newOnes = newValues.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !existing.contains($0) }
        guard !newOnes.isEmpty else { return nil }
        return text.trimmingCharacters(in: .whitespaces).isEmpty
            ? newOnes.joined(separator: ", ")
            : text + ", " + newOnes.joined(separator: ", ")
    }

    /// Never overwrites a value the user (or another source) already set —
    /// and reports back exactly which fields it touched, since a silent
    /// "done" wouldn't say whether anything actually changed. `answeredBy`
    /// is set only when a higher-priority provider failed first and this
    /// result came from a fallback (`AIProviderChain.run(_:)`'s
    /// `isFallback`) — appended as a visible note rather than switching
    /// providers silently under the user.
    private func applyWebDetails(_ details: PlaceWebDetails, answeredBy fallbackProvider: AIProviderType? = nil) {
        var filledFields = fillBlankFields(from: details)
        stageSuggestedTags(from: details.tags)
        if let combined = PlaceCard.combinedMemo(memoText.isEmpty ? nil : memoText, appending: details.note), combined != memoText {
            memoText = combined
            filledFields.append("메모".localized)
        }

        webSearchMessage = filledFields.isEmpty
            ? "웹 검색에서 새로 채울 정보를 찾지 못했습니다.".localized
            : filledFields.joined(separator: ", ") + " 정보를 채웠습니다.".localized
        if let fallbackProvider {
            webSearchMessage? += fallbackProvider.fallbackNoteSuffix
        }
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
        let trimmedMyRating = myRatingText.trimmingCharacters(in: .whitespaces)
        updated.myRating = trimmedMyRating.isEmpty ? nil : Double(trimmedMyRating)
        updated.priceLevel = priceLevel

        updated.isFavorite = isFavorite
        updated.isVisited = isVisited
        updated.wouldRevisit = wouldRevisit
        updated.visitDates = visitDates

        let trimmedClosingTime = closingTime.trimmingCharacters(in: .whitespaces)
        updated.closingTime = trimmedClosingTime.isEmpty ? nil : trimmedClosingTime
        let trimmedHolidays = holidays.trimmingCharacters(in: .whitespaces)
        updated.holidays = trimmedHolidays.isEmpty ? nil : trimmedHolidays
        let trimmedReservationInfo = reservationInfo.trimmingCharacters(in: .whitespaces)
        updated.reservationInfo = trimmedReservationInfo.isEmpty ? nil : trimmedReservationInfo
        let trimmedRecommendedMenu = recommendedMenu.trimmingCharacters(in: .whitespaces)
        updated.recommendedMenu = trimmedRecommendedMenu.isEmpty ? nil : trimmedRecommendedMenu
        let trimmedSuggestedDuration = suggestedDuration.trimmingCharacters(in: .whitespaces)
        updated.suggestedDuration = trimmedSuggestedDuration.isEmpty ? nil : trimmedSuggestedDuration
        let trimmedAdmissionFee = admissionFee.trimmingCharacters(in: .whitespaces)
        updated.admissionFee = trimmedAdmissionFee.isEmpty ? nil : trimmedAdmissionFee

        var hoursDetail: [String: String] = [:]
        for entry in hoursEntries {
            let day = entry.day.trimmingCharacters(in: .whitespaces)
            let hours = entry.hours.trimmingCharacters(in: .whitespaces)
            guard !day.isEmpty, !hours.isEmpty else { continue }
            hoursDetail[day] = hours
        }
        updated.hoursDetail = hoursDetail.isEmpty ? nil : hoursDetail

        updated.externalLinks = externalLinkEntries.compactMap { entry in
            let platform = entry.platform.trimmingCharacters(in: .whitespaces)
            let url = entry.url.trimmingCharacters(in: .whitespaces)
            guard !platform.isEmpty, !url.isEmpty else { return nil }
            return ExternalLink(id: entry.id, platform: platform, url: url)
        }

        updated.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        updated.amenities = amenitiesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        updated.awards = awardsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        updated.dietaryOptions = dietaryOptionsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

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
