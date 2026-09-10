# PlaceCards 프로젝트 변경 이력

## [Unreleased]

### 2026-09-10 (7차) — 카테고리 아이콘을 미니멀 외곽선으로 추가
#### Added
- `Services/PlaceCategoryIcon.swift`(신규): 카테고리 텍스트(Google Places의
  자유 텍스트라 고정 목록이 없음)를 키워드로 매칭해 outline SF Symbol로
  변환(`.fill`이 아닌 일반 버전만 사용 — 카페→`cup.and.saucer`,
  식당→`fork.knife`, 호텔→`bed.double`, 술집→`wineglass`, 쇼핑→`bag`,
  박물관→`building.columns`, 공원→`tree`, 그 외→`tag`).
- 카드 셀의 카테고리 캡슐과 상세화면의 카테고리 표시에 이 아이콘을 추가
  (기존엔 텍스트만 있었음) — 방금 바꾼 미니멀 외곽선 앱 아이콘과 톤을
  맞춤.

### 2026-09-10 (6차) — "거리" 정렬에 현재 위치(Here) 추가
#### Added
- "거리" 정렬 선택 시 기준 장소 메뉴 맨 위에 **현재 위치** 항목 추가 —
  선택하면 그 순간 기기의 GPS 위치를 가져와 그 지점부터 가까운 순으로
  정렬함. 저장된 장소 대신 지금 있는 곳 기준으로 정렬하고 싶을 때 사용.
- `Services/LocationService.swift`(신규): 1회성 위치 조회. Peragra의
  `LocationService`(사진 촬영 위치 기록용)를 이번 용도에 맞게 단순화해
  포팅 — 권한 미결정 시 요청, 8초 타임아웃, 거부/실패 시 조용히 nil
  반환(정렬을 막지 않고 그냥 저장된 장소 기준 선택으로 유지됨).
- `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` 추가 — 위치 권한을
  처음 요청할 때 필요.
- `PlaceCardSorting.swift`의 거리 정렬이 이제 특정 카드 대신 순수 좌표
  기준으로 동작하도록 일반화(`DistanceReference` enum: `.here`/`.card`).

### 2026-09-10 (5차) — Sort By 추가 (Peragra의 PlaceFilterBar 참조)
#### Added
- `Services/PlaceCardSorting.swift`(신규): `PlaceSortMode`(카테고리별/이름/거리)와
  정렬 로직. Peragra의 `PlaceSortMode`/`TripDetailView.sortedByMode`를 포팅
  — 즐겨찾기한 카드는 정렬 모드와 무관하게 항상 위로 올라오는 동작까지
  동일하게 반영(`sortedPlaces`의 "favorites float to top" 규칙).
  - 카테고리별: PlaceCards엔 Peragra의 고정 카테고리 enum이 없어(Google
    Places의 자유 텍스트 카테고리이므로) 카테고리 이름 알파벳순 → 그룹 내
    이름순으로 대체.
  - 거리: 기준 장소를 하나 선택하면 그 장소로부터 가까운 순으로 정렬.
- `PlaceStatusFilterBar`에 정렬 메뉴 + "기준: <장소명>" 메뉴(거리 정렬일
  때만 표시)를 추가 — Peragra의 `PlaceFilterBar.sortMenu`/
  `referencePlaceMenu` 스타일과 배치 순서를 그대로 반영.
- 게시판 상세 화면과 갤러리 화면 모두에 적용.

### 2026-09-10 (4차) — 전체/즐겨찾기/방문 필터 칩 (Peragra 참조)
#### Added
- `Views/PlaceStatusFilterBar.swift`(신규): 장소 목록 상단에 "전체 (n) /
  ⭐ 즐겨찾기 (n) / ✅ 방문 (n)" 칩을 가로 스크롤로 표시. Peragra의
  `TripDetailView.collectionFilterBar`("All (n)" + Favorites/Visited
  기본 리스트 칩)와 `PlaceFilterBar`의 `FilterChip` 스타일을 그대로 반영,
  PlaceCards엔 범용 리스트 시스템이 없어 `isFavorite`/`isVisited` 두 플래그
  기준의 3단 필터로 단순화함.
- 게시판 상세 화면과 갤러리 화면 모두에 적용 — 각 카운트는 검색/태그 등
  다른 필터가 이미 적용된 결과 기준으로 계산됨(Peragra의
  `preCategoryFiltered`와 동일한 이유: 칩 옆 숫자가 다른 필터와 무관하게
  고정되어 헷갈리지 않도록).
- 게시판 상세: 게시판에 카드가 있지만 필터 결과가 0개인 경우와, 게시판에
  카드가 아예 없는 경우를 구분해서 서로 다른 안내 문구를 보여줌.

### 2026-09-10 (3차) — 카드 셀에 정보 추가 (Peragra의 PlaceRowView 참조)
#### Added
- 게시판 상세/갤러리의 장소 카드 셀에 정보 추가 (기존의 간결함과 "탭하면
  상세 열림" 동작은 그대로 유지):
  - 카테고리 캡슐, 방문(체크) / 즐겨찾기(별) 뱃지를 썸네일 위에 오버레이로
    표시 — 별/체크는 그 자리에서 바로 토글 가능(Peragra의 `PlaceRowView`가
    행에서 직접 favorite/visited를 토글하는 것과 동일)
  - 전화·지도 열기(Google/Naver/Kakao/Tmap 메뉴)·웹사이트·인스타그램 아이콘
    버튼을 카드 하단에 한 줄로 추가 — 해당 정보가 있을 때만 표시
  - 모든 추가 버튼은 `.buttonStyle(.plain)`이라 `NavigationLink` 안에 있어도
    카드 탭(상세 열기)과 충돌하지 않음
- `Models/PlaceCard.swift`: `isFavorite`, `isVisited`, `instagramURL` 필드
  추가 (Peragra의 `Place.favorite`/`Place.visited`/`instagramURLString`에
  대응).
- `Services/MapOpeners.swift`(신규): Peragra의 `GoogleMapsOpener`/
  `NaverMapOpener`/`KakaoMapOpener`/`TmapOpener`/`KoreaRegion`을 PlaceCard
  모델에 맞춰 포팅. Naver/Kakao/Tmap은 한국 밖 데이터가 거의 없어 좌표가
  한국 영역 안에 있을 때만 링크를 만듦(Peragra와 동일한 판단).

### 2026-09-10 (2차) — 게시판(Board) 구조 도입, Peragra 참조
#### Changed
- **홈 화면을 게시판 목록으로 전면 개편.** Peragra의 `Trip`/`TripsListView`/
  `AddTripSheet` 구조를 참조. 이제 장소 카드를 만들기 전에 먼저 **게시판**을
  만들어야 함(이름 + 부제목 + 커버 이모지 아이콘, `Board.coverEmojiChoices`는
  Peragra의 `Trip.coverEmojiChoices`를 그대로 포팅).
- `PlaceCard`에 `boardId`(필수) 필드 추가 — 모든 장소 카드는 이제 하나의
  게시판에 속함.
- `PlaceCardViewModel`이 `boardId`를 생성자에서 받아, 그 게시판 안에서만
  카드를 생성하도록 변경.
- `StorageService`가 게시판(`boards.json`)과 장소 카드(`placecards.json`)를
  함께 관리. `deleteBoard`는 게시판 안의 카드와 사진 파일까지 함께 정리(카드
  삭제 시에도 이제 사진 파일을 지우도록 함께 수정 — 이전엔 파일이 남았음).

#### Added
- `Models/Board.swift` — 게시판 모델.
- `Views/AddBoardSheet.swift` — 새 게시판 만들기(Peragra의 `AddTripSheet`
  구조를 그대로 반영: 이름/부제목 입력 + 이모지 그리드 선택).
- `Views/BoardDetailView.swift` — 게시판 안의 장소 카드 목록 + 장소 추가
  (Peragra의 `TripDetailView`를 단순화한 버전).
- 홈 화면에서 스와이프 삭제는 **비어있는 게시판에서만** 나타남(Peragra와
  동일한 안전장치 — 장소가 있는 게시판을 실수로 통째로 삭제하는 것을 방지).

#### Notes
- 갤러리/지도 탭은 게시판 구분 없이 전체 장소 카드를 보여주는 뷰로 유지함
  (Peragra의 "All Places"에 대응).

### 2026-09-10 (1차) — Gateway 모델 선택 기능 추가
#### Added
- 설정 화면의 AI 제공자를 Gateway로 선택하면 모델 Picker가 추가로 나타남
  (Claude Sonnet 5/Opus 5/Fable 5.1/5, GPT-5.6 Luna/Terra/Sol, GPT-5.5 중
  선택, 목록에 없는 모델은 "직접 입력…"으로 모델 ID를 직접 입력). Peragra의
  `SettingsSheet.ModelPickerProviderFields`(목록 선택 + Custom… 텍스트필드
  패턴)를 그대로 반영.
- `GatewayModels.Model`이 이제 `id`/`label`을 함께 갖는 구조체로 바뀜(기존엔
  ID 문자열 배열뿐이라 Picker에 표시할 이름이 없었음) — Peragra의
  `GatewayModels.swift`와 동일한 구조.
- `SettingsViewModel.gatewayModel`을 UserDefaults에 저장(민감정보가 아니므로
  Keychain 대신)하고, `AIProviderFactory`가 Gateway 프로바이더를 만들 때 이
  값을 실제로 사용하도록 연결.

### 2026-09-09 (6차) — Peragra의 Gateway 프로바이더 추가
#### Added
- `GatewayProvider`: Peragra가 기본 AI 프로바이더로 쓰는 서드파티 OpenAI 호환
  게이트웨이(factchat-cloud.mindlogic.ai)를 AI 제공자 옵션에 추가. Peragra의
  `AIExtractionService`가 쓰는 것과 동일한 엔드포인트(`/v1/gateway/chat/completions/`,
  트레일링 슬래시 필수)·요청 형식을 그대로 반영.
- `GatewayModels`: 게이트웨이에서 제공하는 모델 ID 목록 (Peragra의
  `GatewayModels.swift`를 포팅).
- `AIProviderType`에 `.gateway` 케이스 추가 (설정 화면의 "제공자" Picker에
  자동으로 노출됨, UI 코드 변경 없음).
- `OpenAIProvider`와 `GatewayProvider`가 같은 OpenAI 호환 요청 로직
  (`performOpenAICompatibleChatRequest`)을 공유하도록 정리.

#### Notes
- 기본 프로바이더는 여전히 Claude — 게이트웨이는 선택 가능한 추가 옵션으로만
  넣었고, Peragra처럼 기본값으로 바꾸지는 않음.

### 2026-09-09 (5차) — Keychain 빌드 오류 수정
#### Fixed
- `KeychainService`에서 실제로 존재하지 않는 `kSecService`/`kSecAccount` 상수를
  사용해 Xcode에서 "Cannot find in scope" 오류가 발생하던 문제. 올바른 이름인
  `kSecAttrService`/`kSecAttrAccount`로 수정 (Peragra의 실제 동작하는
  `KeychainService.swift`와 대조해 확인).
- 프로젝트 `LastUpgradeCheck`/`LastSwiftUpdateCheck`를 1700으로 갱신.

### 2026-09-09 (4차) — Peragra 조사 반영: Naver 직접 접근 + AI 멀티 프로바이더
#### Changed
- **Naver: 백엔드 프록시 폐기, 기기에서 직접 호출.** Peragra의 `NaverGeocodingService`를
  조사한 결과, Naver Client Secret도 사용자 본인의 BYOK 키라면 네이티브
  `URLSession`으로 기기에서 직접 호출해도 문제없다는 것을 확인함(웹처럼 CORS 제약이
  없음). 기존 `NaverProxyService`(존재하지 않는 백엔드를 호출하던 죽은 코드)를
  제거하고 두 개의 새 서비스로 교체:
  - `NaverLocalSearchService` — openapi.naver.com의 지역 검색 API를
    `X-Naver-Client-Id`/`X-Naver-Client-Secret` 헤더로 직접 호출
  - `NaverGeocodingService` — Peragra의 구현을 거의 그대로 포팅. NAVER Cloud
    Platform(NCP)의 Geocoding API로 주소를 좌표로 변환 (Local Search의
    mapx/mapy 스케일이 불확실한 문제를 회피하는 더 신뢰할 수 있는 대안)
  - 설정 화면의 "Naver 프록시 URL" 필드를 Client ID/Secret 두 쌍(Local Search용,
    NCP Geocoding용— 서로 다른 콘솔에서 발급됨)으로 교체
  - `PlaceCardViewModel.search`가 이제 실제로 Naver를 먼저 조회해 이름을
    보정한 뒤 Google로 상세정보를 보강함(기획 문서의 "Naver 발견 + Google
    보강" 하이브리드 전략을 처음으로 실제 동작하게 함). `createManualPlaceCard`는
    이제 NCP 키가 있으면 주소로 좌표를 자동 보강함(비동기로 변경됨).
- **AI: OpenAI/Gemini Vision 실제 구현.** Peragra의 `AIExtractionService`가
  Anthropic/OpenAI/Gemini를 각각 어떤 요청/응답 형식으로 직접 호출하는지 조사해
  반영. 기존에 `notImplemented` 오류만 던지던 `OpenAIProvider`/`GeminiProvider`를
  실제 동작하는 구현으로 교체 (OpenAI: `chat/completions` + `image_url` base64
  data URL, Gemini: `generateContent` + `inline_data`). 401/429 응답을
  각각 `apiKeyInvalid`/`rateLimited`로 구분하는 에러 처리도 세 프로바이더에
  공통으로 적용.
  - Peragra가 기본으로 쓰는 서드파티 게이트웨이(factchat-cloud.mindlogic.ai)는
    Peragra 자체 계정에 종속된 인프라라 포팅하지 않음.

### 2026-09-09 (3차) — Peragra 개발 경험 반영 (공유 링크 파싱)
#### Added
- `LinkMetadataFetcher`: Google Maps 공유 링크처럼 이름이 없는 URL에서 페이지의
  `og:title`/`<title>`을 읽어 장소명을 알아내는 서비스. Peragra 개발 중 확인된
  "크롤러용 User-Agent를 먼저 시도하고, 차단되면 모바일 Safari UA로 재시도" 전략을
  그대로 적용함 (Google Maps는 크롤러에게는 장소명이 박힌 정적 페이지를,
  일반 브라우저에게는 JS 셸을 내려줌).
- `SharedLinkParser`: 지도 앱마다 공유 데이터 형식이 다른 문제(Google Maps는
  이름 없는 URL만, Naver Map은 `[네이버 지도]` 같은 태그 줄 + 줄바꿈으로 구분된
  텍스트)를 처리하는 파서.
- `PlaceCardViewModel.search(placeName:)`가 위 두 서비스로 입력을 먼저 완전히
  해석(resolve)한 뒤에만 검색을 수행하도록 변경 — Peragra에서 "열렸지만 비어있음"
  버그의 원인이었던 반쪽짜리 상태 노출을 피하기 위한 atomic take-resolve-pass
  패턴을 적용함. 기존 "장소명" 입력창에 Google/Naver 지도 공유 링크나 텍스트를
  붙여넣으면 자동으로 해석됨 (UI 변경 없음).

#### Notes
- Peragra의 Share Extension/App Groups/딥링크 UI 자체는 이번에 가져오지 않음
  (사용자가 UI는 적용하지 말라고 요청함). 필요해지면 `IMPLEMENTATION/외부지도앱연동_가져오기기획.md`의
  `placecards://` URL Scheme 설계를 참고해 별도로 진행.

### 2026-09-09 (2차) — iOS 1차 구현
#### Added
- `PlaceCards/` Xcode 프로젝트 생성 (SwiftUI, iOS 17.0+, 외부 의존성 없음)
- 데이터 모델: `PlaceCard`, `Coordinates`, `MediaBundle`/`MediaItem`, `SourceRecord`, `SourceType`, `DiscoverySource`
- Service 계층: `KeychainService`, `StorageService`(로컬 JSON), `MediaStore`, `GooglePlacesService`, `NaverProxyService`, `ClaudeProvider`/`AIProviderFactory`
- ViewModel 계층: `SettingsViewModel`, `PlaceCardViewModel`, `GalleryViewModel`, `MapViewModel`
- View 계층: `OnboardingView`, `MainTabView`(홈/갤러리/지도/설정), `AddPlaceCardView`(사진 선택 → AI 분석 → Google 검색/확정 → 저장), `PlaceCardDetailView`, `SettingsView`(API 키 관리)
- 저장소 루트에 기획 문서 이동: `00_프로젝트종합가이드_새세션용.md`, `PLANNING/`, `RESEARCH/`, `IMPLEMENTATION/`

#### Notes / Deviations from planning docs
- 최소 iOS 버전을 15.0 → **17.0**으로 상향 (`PhotosPicker`, `ContentUnavailableView` 등 사용, 기획 문서의 미결 항목이었음)
- 로컬 저장은 SwiftData/CoreData 대신 **JSON 파일** 기반 `StorageService` 사용 (기획 문서 미결 항목)
- Kakao 연동은 저장 정책 리스크로 이번 구현에서 **제외**
- Naver는 클라이언트 코드만 존재, 백엔드 프록시는 미구현 (배포된 프록시가 없으면 호출 실패)
- AI 분석은 Claude만 실제 동작, OpenAI/Gemini는 선택 UI만 있고 호출 시 `notImplemented` 오류

#### Status
- 기획 단계: ✅ 완료
- iOS 1차 구현: ✅ 완료 (Google 검색/보강 + Claude Vision 분석 + 갤러리/지도/설정)
- 백엔드(Naver 프록시): ⏳ 미착수
- 테스트/배포: ⏳ 미착수

### 2026-09-09 (1차)
#### Added
- 프로젝트 초기 설정
- README.md: 프로젝트 전체 개요 및 폴더 구조
- PLANNING 폴더 생성 및 7개 상세 기획 문서 작성
  - 01_프로젝트개요.md: 목표, 기능, 환경, 현황
  - 02_데이터모델.md: Swift 데이터 모델, 필드 매핑, 검증 규칙
  - 03_지도API비교.md: Google/Naver/Kakao 상세 비교, 하이브리드 전략
  - 04_인스타그램전략.md: Claude API 기반 인스타그램 발견 전략
  - 05_AI정책_BYOK.md: BYOK 모델, Keychain 저장, 온보딩 흐름
  - 06_아키텍처개요.md: 시스템 다이어그램, Service 계층, MVVM 구조
  - 07_미해결항목.md: 우선순위별 미해결 사항, 액션 플랜

#### Status
- 기획 단계: ✅ 완료
- 설계 단계: 🔄 진행중 (DESIGN, ARCHITECTURE 폴더 대기)
- 개발 단계: ⏳ 대기 (코드 작업 미시작)

---

## Version Roadmap

### v0.1 (기획 & 설계)
- [x] 전체 기획 문서 작성
- [ ] UI/UX 와이어프레임 완성
- [ ] 아키텍처 상세 설계
- [ ] 백엔드 프록시 프로토타입

### v1.0 (MVP)
- [x] 기본 PlaceCard 생성 (사진 → AI 분석 → Google 검증)
- [x] Google Places API 통합
- [x] SwiftUI 기본 화면 (Home, Gallery, Map, Settings)
- [x] Keychain API 키 저장
- [x] 로컬 저장 (JSON)
- [ ] TestFlight 배포

### v1.1 (Enhancement)
- [ ] Naver 백엔드 프록시 구현 및 배포
- [ ] OpenAI/Gemini Vision 연동
- [ ] 고급 검색/필터링
- [ ] Export (JSON/CSV)

### v2.0 (Advanced)
- [ ] 온라인 동기화 (iCloud/Firebase)
- [ ] 공유 기능
- [ ] 협업 (다중 사용자)
- [ ] 안드로이드 포트 검토

---

*최종 업데이트: 2026-09-09*
