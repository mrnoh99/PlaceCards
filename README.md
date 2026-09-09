# PlaceCards

손님 이름과 테이블 정보를 담은 자리 카드(place card)를 만들고 관리하는 iOS 앱입니다.
SwiftUI로 작성되었으며 기기(문서 디렉터리)에 로컬로 저장됩니다.

## 주요 기능

- 자리 카드 목록 추가/수정/삭제/순서 변경
- 손님 이름, 테이블, 메모 입력
- 접어서 테이블에 세워둘 수 있는 텐트형 카드 미리보기 (상하 반전 인쇄용 레이아웃)

## 요구 사항

- Xcode 16 이상
- iOS 17.0 이상 시뮬레이터 또는 기기

## 빌드 방법 (macOS)

```sh
git clone <this repo>
cd placecards/PlaceCards
open PlaceCards.xcodeproj
```

Xcode가 열리면 상단에서 시뮬레이터(또는 연결된 기기)를 선택한 뒤 `Cmd+R`로 바로 빌드 및 실행할 수 있습니다.
실제 기기에 설치하려면 프로젝트 설정 > Signing & Capabilities에서 본인의 Apple ID 팀을 선택하세요.

## 프로젝트 구조

```
PlaceCards/
  PlaceCards.xcodeproj/        # Xcode 프로젝트
  PlaceCards/
    PlaceCardsApp.swift        # 앱 진입점
    ContentView.swift          # 카드 목록 화면
    Models/PlaceCard.swift     # 자리 카드 모델
    Store/PlaceCardStore.swift # 로컬 JSON 저장소
    Views/                     # 편집/표시 화면
    Assets.xcassets
    Preview Content/
```
