import SwiftUI

/// Scans one board's place cards for likely duplicates (`DuplicatePlaces`)
/// and lets the user review each group before merging it — picking which
/// copy stays as the "primary" (keeping its own info, but filling in
/// anything only a duplicate had) and removing the rest. Mirrors Peragra's
/// `FindDuplicatesSheet`.
struct FindDuplicatesSheet: View {
    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [[PlaceCard]]
    @State private var primaryIDByGroup: [Int: String] = [:]
    @State private var mergedGroupIndexes: Set<Int> = []

    init(cards: [PlaceCard]) {
        _groups = State(initialValue: DuplicatePlaces.findDuplicateGroups(cards))
    }

    /// Skips auto-detection entirely — for when the user has manually
    /// selected 2+ cards to merge (`BoardDetailView`'s select mode)
    /// rather than merging an automatically found duplicate group. Reuses
    /// the exact same review-and-merge UI either way.
    init(manualGroup: [PlaceCard]) {
        _groups = State(initialValue: manualGroup.count > 1 ? [manualGroup] : [])
    }

    private var remainingCount: Int {
        groups.indices.filter { !mergedGroupIndexes.contains($0) }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("중복이 없습니다", systemImage: "checkmark.circle")
                    } description: {
                        Text("이름이 같고 위치나 주소가 가까워야 중복으로 표시됩니다.")
                    }
                } else if remainingCount == 0 {
                    ContentUnavailableView {
                        Label("모두 병합했습니다", systemImage: "checkmark.circle")
                    } description: {
                        Text("찾아낸 중복을 모두 병합했습니다.")
                    }
                } else {
                    List {
                        Section {
                            Text("같은 장소가 두 번 이상 저장된 것으로 보이는 \(remainingCount)개 그룹을 찾았습니다. 남길 카드를 고른 뒤 병합하세요 — 나머지의 전화번호·링크·사진은 남는 카드로 옮겨진 뒤 삭제됩니다.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                            if !mergedGroupIndexes.contains(groupIndex) {
                                groupSection(groupIndex: groupIndex, group: group)
                            }
                        }
                    }
                }
            }
            .navigationTitle("중복 찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func primaryID(groupIndex: Int, group: [PlaceCard]) -> String {
        primaryIDByGroup[groupIndex] ?? group[0].id
    }

    private func groupSection(groupIndex: Int, group: [PlaceCard]) -> some View {
        let selectedID = primaryID(groupIndex: groupIndex, group: group)
        return Section {
            ForEach(group) { card in
                Button {
                    primaryIDByGroup[groupIndex] = card.id
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: card.id == selectedID ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(card.id == selectedID ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.name)
                                .foregroundStyle(.primary)
                            if !card.address.isEmpty {
                                Text(card.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Button("\"\(group.first(where: { $0.id == selectedID })?.name ?? "")\"(으)로 병합") {
                merge(groupIndex: groupIndex, group: group)
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private func merge(groupIndex: Int, group: [PlaceCard]) {
        let primaryID = primaryID(groupIndex: groupIndex, group: group)
        guard var primary = group.first(where: { $0.id == primaryID }) else { return }
        let duplicates = group.filter { $0.id != primaryID }
        primary.merge(with: duplicates)
        storageService.save(primary)
        for duplicate in duplicates {
            storageService.removeMergedDuplicate(duplicate)
        }
        mergedGroupIndexes.insert(groupIndex)
    }
}

#Preview {
    FindDuplicatesSheet(cards: [])
        .environmentObject(StorageService())
}
