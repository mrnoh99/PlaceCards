import SwiftUI

/// A searchable full-screen category picker — used wherever a category
/// filter list (`PlaceStatusFilterBar`'s own category chip, `GalleryView`'s
/// toolbar shortcut for the same filter) might grow long enough that
/// scanning a plain `Menu` by eye stops being practical. Presented as a
/// `.sheet` rather than a `Menu` specifically so it can host a real
/// `.searchable` text field — a `Menu`'s own content can't take keyboard
/// focus the way a pushed/presented screen can.
struct CategoryPickerSheet: View {
    /// Every category on offer, unfiltered — "전체" (clear the filter) is
    /// always shown first regardless of `searchQuery`, and isn't part of
    /// this list.
    let categories: [String]
    @Binding var selection: String?

    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""

    private var filteredCategories: [String] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return categories }
        return categories.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                row(title: "전체".localized, isSelected: selection == nil) {
                    selection = nil
                    dismiss()
                }
                ForEach(filteredCategories, id: \.self) { category in
                    row(title: category, isSelected: selection == category) {
                        selection = category
                        dismiss()
                    }
                }
            }
            .navigationTitle("카테고리".localized)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "카테고리 검색".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기".localized) { dismiss() }
                }
            }
        }
    }

    private func row(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

#Preview {
    CategoryPickerSheet(categories: ["카페".localized, "식당".localized, "호텔".localized], selection: .constant(nil))
}
