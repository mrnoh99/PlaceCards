import SwiftUI

/// A searchable full-screen category picker — used wherever a category
/// filter list (`PlaceStatusFilterBar`'s own category chip, `GalleryView`'s
/// toolbar shortcut for the same filter) might grow long enough that
/// scanning a plain `Menu` by eye stops being practical. Presented as a
/// `.sheet` rather than a `Menu` specifically so it can host a real
/// `.searchable` text field — a `Menu`'s own content can't take keyboard
/// focus the way a pushed/presented screen can. Also where categories get
/// merged (see `isMerging`) — free-text AI-scanned categories routinely
/// fragment into near-duplicates ("식당"/"레스토랑"/"음식점") that
/// `PlaceCategoryIcon.normalizedLabel(for:)` has no hardcoded rule for
/// (it only collapses cafe variants), so this gives the user a manual way
/// to fold any set of them into one name across every card that has one.
/// 하나만 골라도 된다 — 그때는 합치는 것이 아니라 이름 바꾸기다.
struct CategoryPickerSheet: View {
    /// Every category on offer, unfiltered — "전체" (clear the filter) is
    /// always shown first regardless of `searchQuery`, and isn't part of
    /// this list.
    let categories: [String]
    @Binding var selection: String?

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    /// Multi-select mode for merging — tapping a row toggles its
    /// membership in `mergeSelection` instead of picking it as the filter
    /// and dismissing.
    @State private var isMerging = false
    @State private var mergeSelection: Set<String> = []
    @State private var isPresentingMergeNameInput = false
    @State private var mergedNameInput = ""

    private var filteredCategories: [String] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return categories }
        return categories.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !isMerging {
                    row(title: "전체".localized, isSelected: selection == nil) {
                        selection = nil
                        dismiss()
                    }
                }
                ForEach(filteredCategories, id: \.self) { category in
                    if isMerging {
                        mergeRow(category)
                    } else {
                        row(title: category, isSelected: selection == category) {
                            selection = category
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("카테고리".localized)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "카테고리 검색".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isMerging ? "취소".localized : "닫기".localized) {
                        if isMerging {
                            isMerging = false
                            mergeSelection = []
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isMerging {
                        Button(mergeActionTitle) {
                            mergedNameInput = mergeSelection.sorted().first ?? ""
                            isPresentingMergeNameInput = true
                        }
                        .disabled(mergeSelection.isEmpty)
                    } else {
                        Button("선택".localized) {
                            isMerging = true
                        }
                        .disabled(categories.isEmpty)
                    }
                }
            }
            .alert(mergeActionTitle, isPresented: $isPresentingMergeNameInput) {
                TextField("카테고리 이름".localized, text: $mergedNameInput)
                Button(mergeActionTitle, action: performMerge)
                Button("취소".localized, role: .cancel) {}
            } message: {
                Text(mergeExplanation)
            }
        }
    }

    /// 하나만 고르면 이름 바꾸기, 여럿이면 병합이다. 하는 일은 같다 —
    /// 고른 카테고리를 단 카드를 전부 새 이름으로 바꾼다. 이름을 나눠
    /// 부르는 것은 하나짜리를 "병합"이라 하면 무엇과 합치는지 알 수 없기
    /// 때문이다.
    private var mergeActionTitle: String {
        mergeSelection.count <= 1
            ? "이름 바꾸기".localized
            : "병합 (".localized + "\(mergeSelection.count)" + ")"
    }

    private var mergeExplanation: String {
        if mergeSelection.count <= 1 {
            return "이 카테고리를 단 카드가 모두 새 이름으로 바뀝니다.".localized
        }
        return "선택한 ".localized + "\(mergeSelection.count)" + "개 카테고리를 이 이름으로 합칩니다.".localized
    }

    private func row(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityLabel("선택됨".localized)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func mergeRow(_ category: String) -> some View {
        Button {
            if mergeSelection.contains(category) {
                mergeSelection.remove(category)
            } else {
                mergeSelection.insert(category)
            }
        } label: {
            HStack {
                Image(systemName: mergeSelection.contains(category) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mergeSelection.contains(category) ? Color.accentColor : .secondary)
                Text(category)
                    .foregroundStyle(.primary)
            }
        }
    }

    /// Applied by matching `PlaceCategoryIcon.normalizedLabel(for:)` —
    /// the same grouping `categories`/the filter itself already use —
    /// rather than the raw `card.category` string, so merging "카페"
    /// here also sweeps up "커피숍"/"커피전문점"/etc. that already
    /// display as the one "카페" entry being merged. Every matching
    /// card's `category` is overwritten with `mergedNameInput` outright
    /// (mirrors `GalleryView.applyCategory`'s own bulk category change).
    private func performMerge() {
        let mergedName = mergedNameInput.trimmingCharacters(in: .whitespaces)
        // 하나만 골랐으면 이름 바꾸기다. 아래 반복문이 하는 일은 같으므로
        // 따로 나누지 않는다.
        guard !mergedName.isEmpty, !mergeSelection.isEmpty else { return }

        for card in storageService.activePlaceCards {
            guard let category = card.category, !category.isEmpty,
                  mergeSelection.contains(PlaceCategoryIcon.normalizedLabel(for: category)) else { continue }
            var updated = card
            updated.category = mergedName
            storageService.save(updated)
        }

        if let selection, mergeSelection.contains(selection) {
            self.selection = mergedName
        }
        isMerging = false
        mergeSelection = []
    }
}

#Preview {
    CategoryPickerSheet(categories: ["카페".localized, "식당".localized, "호텔".localized], selection: .constant(nil))
        .environmentObject(StorageService())
}
