import SwiftUI

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
    @State private var hoursEntries: [HoursEntry]
    @State private var tagsText: String
    @State private var amenitiesText: String

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
        _hoursEntries = State(initialValue: (card.hoursDetail ?? [:]).sorted { $0.key < $1.key }.map { HoursEntry(day: $0.key, hours: $0.value) })
        _tagsText = State(initialValue: card.tags.joined(separator: ", "))
        _amenitiesText = State(initialValue: card.amenities.joined(separator: ", "))
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
                Section("기본 정보") {
                    TextField("이름", text: $name)
                    HStack {
                        TextField("카테고리", text: $category)
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
                    TextField("주소", text: $address)
                }

                Section {
                    TextField("위도", text: $latitudeText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("경도", text: $longitudeText)
                        .keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("좌표")
                } footer: {
                    Text("둘 다 비우면 좌표가 삭제됩니다. 하나만 채워지면 원래 값이 그대로 유지됩니다.")
                }

                Section("연락처") {
                    TextField("전화번호", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("웹사이트 URL", text: $website)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("인스타그램 URL", text: $instagramURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section("평가") {
                    TextField("평점 (0~5)", text: $ratingText)
                        .keyboardType(.decimalPad)
                    TextField("리뷰 수", text: $reviewCountText)
                        .keyboardType(.numberPad)
                }

                Section("상태") {
                    Toggle("즐겨찾기", isOn: $isFavorite)
                    Toggle("방문함", isOn: $isVisited)
                }

                Section {
                    ForEach($hoursEntries) { $entry in
                        HStack {
                            TextField("요일", text: $entry.day)
                                .frame(width: 70)
                            Divider()
                            TextField("영업시간 (예: 09:00-18:00)", text: $entry.hours)
                        }
                    }
                    .onDelete { hoursEntries.remove(atOffsets: $0) }
                    Button("+ 요일 추가") {
                        hoursEntries.append(HoursEntry(day: "", hours: ""))
                    }
                    TextField("마감 시간", text: $closingTime)
                    TextField("휴무일", text: $holidays)
                } header: {
                    Text("영업 정보")
                }

                Section {
                    TextField("쉼표로 구분", text: $tagsText, axis: .vertical)
                } header: {
                    Text("태그")
                }

                Section {
                    TextField("쉼표로 구분", text: $amenitiesText, axis: .vertical)
                } header: {
                    Text("편의시설")
                }
            }
            .navigationTitle("장소 정보 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(!canSave)
                }
            }
        }
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

        storageService.save(updated)
        onSave(updated)
        dismiss()
    }
}

#Preview {
    EditPlaceCardSheet(card: PlaceCard(boardId: "preview", name: "샘플 카페", address: "서울시 강남구")) { _ in }
        .environmentObject(StorageService())
}
