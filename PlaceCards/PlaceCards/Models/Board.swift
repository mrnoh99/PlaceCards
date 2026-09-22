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

    /// 목록에서의 차례. `updatedAt`과 같은 이유로 **옵셔널이다** — 이 필드가
    /// 생기기 전에 저장된 게시판에는 없다.
    ///
    /// 예전에는 차례가 곧 배열의 자리였고, 그래서 **어디에도 실리지 않아**
    /// 기기 사이를 못 건넜다. 이제 차례를 값으로 들고 다닌다.
    ///
    /// nil은 "아직 손으로 차례를 정한 적 없음"이다. 그런 게시판은 만든
    /// 순서로 선다(`orderedBefore`) — 차례를 한 번도 안 바꾼 사용자에게는
    /// 예전과 똑같이 보인다.
    var sortIndex: Int?

    /// 견줄 때 쓰는 시각. 한 번도 안 고친(또는 이 필드가 생기기 전의)
    /// 게시판은 만든 때가 마지막으로 바뀐 때다.
    var changedAt: Date { updatedAt ?? createdAt }

    /// 목록에 세우는 규칙. 두 기기가 **같은 차례**를 보려면 이게 완전해야
    /// 한다 — 비기는 자리가 남으면 정렬이 기기마다 달라진다.
    ///
    /// 1. 차례를 정한 것이 먼저, 안 정한 것이 뒤.
    /// 2. 둘 다 정했으면 그 번호순.
    /// 3. 둘 다 안 정했으면 만든 순.
    /// 4. 만든 시각까지 같으면 id — 기기가 달라도 결과가 같아야 하므로
    ///    마지막에는 반드시 값으로 갈리는 것이 와야 한다.
    static func orderedBefore(_ lhs: Board, _ rhs: Board) -> Bool {
        switch (lhs.sortIndex, rhs.sortIndex) {
        case let (l?, r?):
            if l != r { return l < r }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id < rhs.id
    }
}
