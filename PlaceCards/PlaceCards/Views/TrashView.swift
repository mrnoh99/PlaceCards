import Foundation
import SwiftUI

/// "삭제됨" — 지운 카드가 진짜로 사라지기 전에 머무는 곳.
///
/// 여기 있는 카드는 보드에서도 "모든 카드"에서도 지도에서도 검색에서도
/// 빠져 있지만, 보드 목록은 그대로 들고 있다. 되돌리면 있던 자리로
/// 그대로 돌아간다는 뜻이다 — `StorageService.restore(_:)`는 표시만
/// 지운다.
///
/// 사진 파일은 `purge(_:)`를 거칠 때까지 디스크에 남는다. 그래서 앱이
/// 뜰 때마다 `purgeExpiredTrash()`가 기한이 지난 것을 치운다.
struct TrashView: View {
    @EnvironmentObject private var storageService: StorageService

    @State private var cardPendingPurge: PlaceCard?
    @State private var isConfirmingEmpty = false

    private var cards: [PlaceCard] { storageService.deletedPlaceCards }

    /// "30일 뒤 지워집니다". 보존 기간을 화면에 그대로 적지 않고
    /// `StorageService`의 값에서 끌어와야, 기간을 바꿨을 때 문구가 거짓말을
    /// 하지 않는다.
    private var retentionNotice: String {
        let days = Int(trashRetention / (24 * 60 * 60))
        return "삭제됨의 카드는 ".localized + "\(days)" + "일 뒤 저절로 지워집니다.".localized
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView {
                    Label("삭제됨이 비어 있습니다".localized, systemImage: "trash")
                } description: {
                    Text(retentionNotice)
                }
            } else {
                List {
                    Section {
                        ForEach(cards) { card in
                            TrashRow(card: card)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        storageService.restore(card)
                                    } label: {
                                        Label("되돌리기".localized, systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.blue)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        cardPendingPurge = card
                                    } label: {
                                        Label("지우기".localized, systemImage: "trash")
                                    }
                                }
                        }
                    } footer: {
                        Text(retentionNotice)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .listRowBackground(Theme.panel)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.panel)
            }
        }
        .navigationTitle("삭제됨".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !cards.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("비우기".localized, role: .destructive) {
                        isConfirmingEmpty = true
                    }
                }
            }
        }
        // 되돌릴 수 없는 두 가지에만 확인을 붙인다. 되돌리기에는 없다 —
        // 잘못 눌러도 다시 지우면 그만이다.
        .confirmationDialog(
            "\"" + (cardPendingPurge?.name ?? "") + "\"을(를) 완전히 지울까요?".localized,
            isPresented: Binding(
                get: { cardPendingPurge != nil },
                set: { if !$0 { cardPendingPurge = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("지우기".localized, role: .destructive) {
                if let card = cardPendingPurge { storageService.purge(card) }
                cardPendingPurge = nil
            }
            Button("취소".localized, role: .cancel) { cardPendingPurge = nil }
        } message: {
            Text("사진까지 함께 지워지며 되돌릴 수 없습니다.".localized)
        }
        .confirmationDialog(
            "삭제됨을 비울까요?".localized,
            isPresented: $isConfirmingEmpty,
            titleVisibility: .visible
        ) {
            Button("비우기".localized, role: .destructive) { storageService.emptyTrash() }
            Button("취소".localized, role: .cancel) { }
        } message: {
            Text("사진까지 함께 지워지며 되돌릴 수 없습니다.".localized)
        }
    }
}

/// 삭제됨의 한 줄. 갤러리의 목록 행과 달리 전화·지도 같은 버튼이 없다 —
/// 여기서 할 수 있는 일은 되돌리기와 지우기뿐이다.
private struct TrashRow: View {
    @Environment(\.mediaGeneration) private var mediaGeneration

    let card: PlaceCard

    private var deletedText: String {
        guard let deletedAt = card.deletedAt else { return "" }
        return "삭제 ".localized + deletedAt.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Theme.tileCorner))

            VStack(alignment: .leading, spacing: 3) {
                Text(card.name)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(card.address)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Text(deletedText)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        // 사진 파일이 모델보다 늦게 도착하면 다시 그린다(`mediaGeneration`).
        let _ = mediaGeneration
        if let item = card.coverPhoto,
           let image = MediaStore.loadThumbnail(fileName: item.localPath, maxPixelSize: 200) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Theme.tile
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
