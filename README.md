# PlaceCards

여행/나들이 중 여러 출처(지도 앱, SNS, 직접 촬영)에서 발견한 장소를 하나의 통일된 카드(PlaceCard)로 저장·관리·조회하는 iOS 앱입니다.

기획 배경과 전체 의사결정 과정은 [`00_프로젝트종합가이드_새세션용.md`](./00_프로젝트종합가이드_새세션용.md)와 `PLANNING/`, `RESEARCH/`, `IMPLEMENTATION/` 폴더에 정리되어 있습니다. 이 문서는 실제 Xcode 프로젝트(`PlaceCards/`)의 현재 구현 상태와 빌드 방법을 설명합니다.

## 현재 상태

- 기획/설계: ✅ 완료 (`00_프로젝트종합가이드_새세션용.md` 참고)
- iOS 코드: 🟢 Google Places, Naver(Local Search + Geocoding), Claude/OpenAI/Gemini/Gateway Vision이 모두 기기에서 직접 동작 — 백엔드 서버 없음 (Peragra 개발 경험을 반영해 프록시 방식을 폐기함, 아래 "아키텍처 개요" 참고)
- Kakao 연동, Export, 오프라인 동기화: 미구현 (아래 "다음 단계" 참고)

## 빌드 방법 (macOS)

```sh
git clone <this repo>
cd placecards/PlaceCards
open PlaceCards.xcodeproj
```

시뮬레이터(또는 연결된 기기)를 선택하고 `Cmd+R`로 바로 빌드/실행할 수 있습니다. 외부 의존성(SPM 패키지 등)이 없어 별도 설치 없이 바로 빌드됩니다.

- Xcode 16 이상, iOS 17.0 이상 필요
- 실제 기기 설치 시 Signing & Capabilities에서 본인의 Apple ID 팀 선택 필요

### 실행에 필요한 API 키 (BYOK)

앱 자체는 외부 서비스 키를 내장하지 않습니다(BYOK, Bring Your Own Key). 앱의 **설정** 탭에서 아래 키를 등록해야 실제 기능이 동작합니다.

| 키 | 용도 | 발급처 |
|---|---|---|
| Google Places API 키 | 장소 검색/평점/영업시간 등 보강 (필수), "지도" 탭의 Google 지도 표시 | Google Cloud Console → **Places API (New)** + **Maps JavaScript API** 활성화 |
| AI 제공자 API 키 (Claude/OpenAI/Gemini/Gateway 중 택1) | 스크린샷/사진에서 장소명 추출 (Vision) | Anthropic/OpenAI/Google 각 콘솔, Gateway는 factchat-cloud.mindlogic.ai 계정 |
| Naver Client ID/Secret (선택) | Naver Local Search로 한글 장소명 검색 보강 | [openapi.naver.com](https://developers.naver.com) → 검색 API |
| Naver NCP Client ID/Secret (선택) | 주소만 있는 장소의 좌표 보강 (Geocoding) | [NAVER Cloud Platform](https://www.ncloud.com) → Maps → Geocoding |

키는 Keychain에만 저장되며 iCloud로 동기화되지 않습니다. Naver 관련 두 쌍은 서로 다른 개발자 콘솔에서 발급되는 별개의 키입니다.

#### Google 키 하나가 두 가지 방식으로 호출됩니다

Google 키는 **API 두 개**를 켜야 온전히 동작합니다. 장소 검색·상세·사진은
Places API (New)를 `URLSession`으로 호출하고(`Services/PlaceSearchService.swift`),
"지도" 탭의 Google 지도는 **Maps JavaScript API를 `WKWebView`에 띄워서**
그립니다(`Views/GoogleMapWebView.swift`). Maps JavaScript API를 켜지 않으면
지도 탭의 Google 옵션만 10초 뒤 오류 문구로 바뀝니다 — 나머지 기능은 멀쩡해서
원인을 찾기 어렵습니다. 별도의 Geocoding API는 **쓰지 않습니다**(주소→좌표도
Places의 `searchText`로 해결하므로 활성화할 필요가 없습니다).

그래서 **이 키에는 애플리케이션 제한을 걸지 않습니다.** REST 호출은
`X-Ios-Bundle-Identifier` 헤더로 "iOS 앱" 제한에 걸리고, 웹뷰의 지도는 referer로
"HTTP 리퍼러" 제한에 걸리는데, 키 하나에는 제한을 **한 종류만** 지정할 수
있습니다. "iOS 앱"을 고르면 Google 지도 탭이 백지가 됩니다. 권장 설정은:

| 항목 | 값 |
|---|---|
| API 제한 | Places API (New), Maps JavaScript API **둘 다** 선택 |
| 애플리케이션 제한 | **없음** |
| 일일 할당량 | 아래 표대로 API별로 직접 제한 |

할당량은 Cloud Console → *APIs & Services → Places API (New) → Quotas & System
Limits*에서 메서드별로 잡습니다. 쓰지 않는 메서드를 0으로 내리는 것이
핵심입니다(기본값이 수십만 회라 그대로 두면 노출 금액이 큽니다).

| 할당량 (per day) | 권장값 | 비고 |
|---|---|---|
| `SearchTextRequest` | 200 | 장소 검색 **과 주소→좌표 변환이 함께** 소비. 자동 검증 1행 = 2회 |
| `GetPlaceRequest` | 50 | 기본값 125,000 |
| `GetPhotoMediaRequest` | 200 | |
| `AutocompletePlacesRequest` | 0 | 미사용 |
| `SearchNearbyRequest` | 0 | 미사용 |
| `SearchMediaRequest` | 0 | 미사용 |
| `SearchReviewPostsRequest` | 0 | 미사용 |
| Maps JavaScript API → *Map loads per day* | 200 | 해당 API의 Quotas 탭에 이 항목이 보이면 함께 제한 |

키 유출에 대한 방어가 "제한"이 아니라 "할당량"이라는 뜻이므로, 결제 계정에
예산 알림(예: $5, 50/90/100%)을 함께 걸어두길 권합니다. 키를 둘로 나눠
(지도용은 리퍼러 제한, Places용은 iOS 앱 제한) 양쪽 다 제한을 거는 구성도
가능하지만, 앱이 현재 키 입력을 하나만 받으므로 코드 수정이 필요합니다.

## 프로젝트 구조

```
PlaceCards/
  PlaceCards.xcodeproj/
  PlaceCards/
    PlaceCardsApp.swift        # 앱 진입점
    ContentView.swift          # 온보딩 ↔ 메인 탭 분기
    Models/                    # Board, PlaceCard, MediaBundle, SourceRecord 등
    Services/                  # Keychain, 로컬 저장, Google/Naver/AI 클라이언트
    ViewModels/                # Settings/PlaceCard/Gallery/Map ViewModel
    Views/                     # Onboarding, Home(게시판 목록), 게시판 상세, Gallery, Map, Settings
    Assets.xcassets
    Preview Content/
```

### 아키텍처 개요

- **홈 화면 = 게시판(Board) 목록**: Peragra의 "Trip(보드)" 구조를 반영해, 장소 카드를 바로 추가하는 게 아니라 먼저 **게시판**(이름 + 부제목 + 커버 아이콘)을 만들고, 그 게시판 안에서 장소 카드를 추가하는 흐름으로 변경됨. `PlaceCard`는 이제 항상 `boardId`를 가지며, 비어있는 게시판만 삭제할 수 있음(Peragra와 동일하게 장소가 있는 게시판은 스와이프 삭제가 나타나지 않음). 갤러리/지도 탭은 게시판과 무관하게 전체 장소 카드를 보여주는 뷰로 유지됨.
- **UI**: SwiftUI + MVVM (`06_아키텍처_단순화.md`의 Service/ViewModel 계층 구조를 따름)
- **저장**: 로컬 JSON 파일(`StorageService`) — SwiftData/CoreData 선택은 기획 문서에서 미결 항목(`07_미해결항목.md` 3.2)으로 남아 있어, iOS 버전 제약이 없고 스키마가 자주 바뀌는 현재 단계에 맞춰 단순한 방식을 선택함
- **지도 API**: Google Places API (New)와 Naver(Local Search + Geocoding) 모두 **앱에서 직접 호출**(BYOK), 백엔드 서버 없음. 처음에는 "Naver Client Secret은 앱에 넣을 수 없다"는 전제로 프록시 서버를 계획했지만, 같은 팀의 다른 앱(Peragra)이 사용자 본인의 Client ID/Secret으로 NCP·Naver Developers API를 기기에서 직접 호출하고 있는 것을 확인하고 그 방식으로 교체함 — 네이티브 `URLSession` 요청은 웹처럼 CORS 제약이 없고, 이건 앱 공용 비밀키가 아니라 사용자가 스스로 발급받아 넣는 BYOK 키이기 때문에 안전한 절충. 자세한 내용은 `Services/NaverLocalSearchService.swift`, `Services/NaverGeocodingService.swift` 주석 참고.
- **AI 이미지 분석**: Claude, OpenAI(GPT-4o), Gemini, 그리고 Peragra가 기본으로 쓰는 서드파티 게이트웨이(factchat-cloud.mindlogic.ai)까지 네 가지 제공자를 각 사용자 API 키로 기기에서 직접 호출하도록 구현됨(Peragra의 멀티 프로바이더 접근 방식을 그대로 반영). 기본 선택값은 여전히 Claude이고, Gateway는 설정 화면에서 선택 가능한 추가 옵션임 — 그 게이트웨이는 Peragra 자체 계정에 종속된 서드파티 인프라이므로 실제 사용 여부는 사용자 판단.
- **Kakao**: 기획 문서의 최종 결정(`00_프로젝트종합가이드_새세션용.md` §2️⃣)에 따라 저장 정책 리스크를 피하기 위해 이번 구현에서 제외함

### 기획 문서와 다른 점 (의도적 단순화)

원본 기획 문서 대부분은 iOS 15.0을 최소 버전으로 가정했지만, 이번 구현은 `PhotosPicker`, `ContentUnavailableView`, iOS 17의 `onChange(of:)` 2-파라미터 API 등을 사용하기 위해 **iOS 17.0**을 최소 배포 타깃으로 설정했습니다. 이는 문서에서도 미결 항목으로 남아 있던 부분이며(`07_미해결항목.md` 3.2), 실제 기기 지원 범위를 넓히려면 재검토가 필요합니다.

## 다음 단계

`07_미해결항목.md`의 액션 플랜을 기준으로, 이번 세션에서 다루지 않은 것들:

1. **Export 기능** — JSON/CSV 내보내기, Notion/Google Sheets 연동
2. **테스트** — 단위/통합 테스트 (기획 문서 `06_아키텍처_단순화.md` §10 참고)
3. **앱 이름 상표 조사, App Store 심사 준비물** — `07_미해결항목.md` §7.1, §7.4
4. **`placecards://` 딥링크** — 지도 앱에서 공유 시 바로 앱이 열리는 기능은 아직 미구현 (`IMPLEMENTATION/외부지도앱연동_가져오기기획.md` 참고)
