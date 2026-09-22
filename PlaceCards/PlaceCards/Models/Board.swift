import Foundation

/// A named collection of PlaceCards — created first, before any place card,
/// mirroring Peragra's "board" (its `Trip` model): give it a name and a
/// subtitle, then start adding place cards into it.
struct Board: Identifiable, Codable, Equatable {
    /// Outline SF Symbols only, matching the app's minimalist outline
    /// look (the app icon and category icons) — no ".fill" variants.
    static let coverIconChoices = [
        "airplane", "map", "beach.umbrella", "building.2",
        "mountain.2", "fork.knife", "camera", "tram",
    ]

    var id: String = UUID().uuidString
    var name: String
    var subtitle: String
    var coverIcon: String
    var createdAt: Date = Date()

    /// 마지막으로 고친 시각. **옵셔널인 것이 중요하다** — 이 필드가 생기기
    /// 전에 저장된 게시판에는 아예 없어서 nil로 디코딩된다. 필수로 두면
    /// 저장된 게시판이 전부 디코딩에 실패한다(CLAUDE.md §4의 `boardId`와
    /// 같은 이야기).
    ///
    /// 이게 없던 동안 기기 간 동기화는 **없는 게시판을 더하기만 하고 이름
    /// 바뀐 것은 못 옮겼다.** 어느 쪽이 나중인지 견줄 것이 없었기 때문이다.
    var updatedAt: Date?

    /// 견줄 때 쓰는 시각. 한 번도 안 고친(또는 이 필드가 생기기 전의)
    /// 게시판은 만든 때가 마지막으로 바뀐 때다.
    var changedAt: Date { updatedAt ?? createdAt }
}
