import SwiftUI

/// Edits a place card's own fields directly, mirroring the "Edit" action
/// in Peragra's `PlaceRowView` (which opens `EditPlaceSheet`) — scoped to
/// this app's plain fields only, since the photo/AI-fill flows Peragra's
/// own edit sheet also has already live separately in `AddPlaceCardView`
/// and aren't duplicated here.
struct EditPlaceCardSheet: View {
    let card: PlaceCard
    var onSave: (PlaceCard) -> Void

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: String
    @State private var address: String
    @State private var phone: String
    @State private var website: String
    @State private var instagramURL: String
    @State private var tagsText: String
    @State private var amenitiesText: String

    init(card: PlaceCard, onSave: @escaping (PlaceCard) -> Void) {
        self.card = card
        self.onSave = onSave
        _name = State(initialValue: card.name)
        _category = State(initialValue: card.category ?? "")
        _address = State(initialValue: card.address)
        _phone = State(initialValue: card.phone ?? "")
        _website = State(initialValue: card.website ?? "")
        _instagramURL = State(initialValue: card.instagramURL ?? "")
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
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        updated.phone = trimmedPhone.isEmpty ? nil : trimmedPhone
        let trimmedWebsite = website.trimmingCharacters(in: .whitespaces)
        updated.website = trimmedWebsite.isEmpty ? nil : trimmedWebsite
        let trimmedInstagram = instagramURL.trimmingCharacters(in: .whitespaces)
        updated.instagramURL = trimmedInstagram.isEmpty ? nil : trimmedInstagram
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
