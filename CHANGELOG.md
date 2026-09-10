# PlaceCards 프로젝트 변경 이력

## [Unreleased]

### 2026-09-10 — Gateway 모델 선택 기능 추가
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
