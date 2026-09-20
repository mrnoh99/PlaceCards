import SwiftUI

/// Lightroom을 본뜬 어두운 팔레트와 치수.
///
/// 화면마다 색을 직접 적는 대신 여기를 거친다. 개편이 여러 PR에 걸쳐
/// 진행되므로, 아직 안 고친 화면과 고친 화면이 같은 값을 쓰게 하려는
/// 것이 목적이다.
///
/// 값은 전부 리터럴이다 — 서로를 참조하지 않는다. 저장 프로퍼티
/// 기본값에서 `Self.`를 참조하면 컴파일이 막히는 사례를 이 저장소에서
/// 이미 겪었고(`CLAUDE.md` §1), 정적 상수끼리도 얽히면 읽기 어려워진다.
enum Theme {

    // MARK: - 배경
    //
    // 넷을 구분하는 기준은 "사진이 놓이는 곳일수록 어둡다"다. 사진
    // 격자는 순수 검정 위에 놓여야 썸네일 가장자리가 배경에 묻히지
    // 않는다.

    /// 사진 격자·사진 한 장이 놓이는 바닥. 순수 검정.
    static let canvas = Color(red: 0.00, green: 0.00, blue: 0.00)

    /// 상단 바·하단 탭바·시트. 바닥보다 한 단 밝다.
    static let chrome = Color(red: 0.11, green: 0.11, blue: 0.11)

    /// 목록·사이드바처럼 사진이 주인공이 아닌 면.
    static let panel = Color(red: 0.08, green: 0.08, blue: 0.08)

    /// 목록에서 선택된 행. 파랑이 아니라 밝기로만 표시한다.
    static let rowSelected = Color(red: 0.18, green: 0.18, blue: 0.18)

    /// 목록 행 왼쪽의 아이콘 칸.
    static let tile = Color(red: 0.23, green: 0.23, blue: 0.23)

    /// 구분선.
    static let separator = Color(red: 0.20, green: 0.20, blue: 0.20)

    // MARK: - 글자

    static let primaryText = Color(red: 1.00, green: 1.00, blue: 1.00)

    /// 개수·날짜·주소처럼 딸려 나오는 글자.
    static let secondaryText = Color(red: 0.63, green: 0.63, blue: 0.63)

    // MARK: - 강조
    //
    // 화면에서 유채색은 이 파랑 하나뿐이다. `AccentColor` 에셋에도 같은
    // 값을 넣어 뒀으므로, 기존 `Color.accentColor` 호출 스물두 군데도
    // 저절로 이 색이 된다. 새로 쓰는 코드는 이 상수를 쓴다.

    /// Adobe 파랑 (#1473E6).
    static let accent = Color(red: 0.078, green: 0.451, blue: 0.902)

    // MARK: - 치수

    /// 격자 칸 사이. Lightroom은 거의 붙여 놓는다.
    static let gridGutter: CGFloat = 2

    /// 아이콘 칸 모서리.
    static let tileCorner: CGFloat = 8

    /// 목록 행 선택 표시 모서리.
    static let rowCorner: CGFloat = 10

    /// 사진 위에 얹는 글자를 읽히게 하는 그림자. 사진이 밝으면 흰
    /// 글씨가 그냥 사라지므로, 스크림 대신 이 그림자를 쓴다 — 스크림은
    /// 격자가 촘촘할 때 화면 전체를 탁하게 만든다.
    static let overlayTextShadow: CGFloat = 3
}
