# PlaceCards 프로젝트 변경 이력

## [Unreleased]

### 2026-09-11 (122차) — 외부 링크 여러 개 지원 + 웹 검색 시 우선 확인
#### Changed
- `Models/PlaceCard.swift`: `externalLinks`를 `[String: String]`
  딕셔너리에서 `[ExternalLink]`(새 struct, `platform`/`url`) 배열로
  변경 — 같은 플랫폼 이름으로 링크를 두 개 이상 추가하면 딕셔너리
  키 충돌로 두 번째가 첫 번째를 조용히 덮어쓰던 문제를 해결하고,
  사용자가 추가한 순서도 그대로 유지되게 함(딕셔너리는 순서가
  정의되지 않음). `strippingInvisibleFormatCharacters()`도 배열
  형태에 맞게 수정.
- `ViewModels/PlaceCardViewModel.swift`,
  `Views/EditPlaceCardSheet.swift`, `Views/PlaceCardDetailView.swift`:
  위 변경에 맞춰 `externalLinks` 관련 코드 전부 갱신 — 편집 화면의
  "+ 링크 추가"는 원래도 개수 제한 없이 추가 가능했지만, 저장 시
  플랫폼 이름이 겹치면 하나로 합쳐지던 걸 이번에 고침.
#### Added
- `Services/AIProvider.swift`: `AIProvider.searchWebForDetails`에
  `knownLinks: [String]` 매개변수 추가 — 카드에 이미 저장된
  `externalLinks`를 "웹 검색으로 채우기" 실행 시 함께 전달해서, AI가
  일반 검색보다 먼저 이 카드용으로 이미 확인된 링크(정확한 Google
  Maps/Naver Map 페이지 등)부터 확인하도록 함. 저장된 링크가 없어도
  Google Maps·Naver Map·TripAdvisor·Yelp·OpenTable·Resy·TheFork·
  Tabelog·Zomato 같은 지도/리뷰/예약 플랫폼을 업체 홈페이지보다
  우선 확인하도록 프롬프트에 명시(`webDetailsSearchPrompt(for:
  knownLinks:)`) — 이런 플랫폼 정보가 대체로 더 최신이고 정확하다는
  판단(사용자 요청). `EditPlaceCardSheet`가 현재 편집 중인
  `externalLinkEntries`를 `"<플랫폼>: <URL>"` 형식으로 모아 전달.

### 2026-09-11 (121차) — 개인 평가/가격대/방문 기록/추천 메뉴/외부 링크 필드 추가
#### Added
- `Models/PlaceCard.swift`: 새 필드 6개 추가 — `myRating: Double?`(내
  평점, Google/Naver의 공개 평점 `rating`과 별개), `priceLevel:
  PriceLevel?`(Google Places API (New)의 `priceLevel`을 그대로 옮긴
  enum — `PRICE_LEVEL_FREE`~`PRICE_LEVEL_VERY_EXPENSIVE`, 공식 REST
  레퍼런스로 필드명·값을 직접 확인 후 작성), `externalLinks: [String:
  String]`(플랫폼 이름 → URL, 정해진 목록이 아니라 자유롭게
  추가/삭제하는 딕셔너리), `visitDates: [Date]`(기존 `isVisited` 토글과
  독립적으로 실제 방문 날짜들을 기록), `wouldRevisit: Bool?`(다시 방문
  의향 — `nil`은 "아직 모름"), `recommendedMenu: String?`(추천 메뉴,
  AI 스캔/웹 검색으로도 채워짐). `matchesSearch(_:)`·
  `strippingInvisibleFormatCharacters()`·`applyScannedDetails(_:)` 모두
  갱신.
- `Services/AIProvider.swift`: `PlaceWebDetails`에 `recommendedMenu:
  String?` 추가 — 사진 스캔·웹 검색 프롬프트/파서 양쪽 다 반영.
- `Services/PlaceSearchService.swift`,
  `Services/NaverPlaceSearchService.swift`: Google Places 검색 결과에
  `priceLevel` 필드 마스크·디코딩 추가(Naver는 해당 필드가 없어 항상
  `nil`).
- `ViewModels/PlaceCardViewModel.swift`: Naver Map/Google Maps 공유로
  카드를 만들 때 공유 자체의 URL(`SharedLinkParser.ParsedSharedPlace
  .url`)을 `PlaceCandidateRow.scannedMapURL`에 저장해두었다가, 저장 시
  `externalLinks["Naver Map"]`/`externalLinks["Google Maps"]`로
  반영 — 이름·좌표로 재구성한 링크(`MapOpeners.swift`)보다 정확하게
  사용자가 실제로 공유한 페이지 그대로 연결됨.
- `Views/EditPlaceCardSheet.swift`, `Views/PlaceCardDetailView.swift`:
  위 6개 필드 모두 편집/표시 UI 추가 — 내 평점·가격대는 평가 섹션에,
  다시 방문 의향은 상태 섹션에, 방문 날짜는 추가/삭제 가능한 날짜
  목록으로, 추천 메뉴는 영업 정보 섹션에, 외부 링크는 플랫폼 이름+URL
  쌍을 자유롭게 추가/삭제하는 목록과 상세보기에서 바로 여는 버튼으로
  추가.

### 2026-09-11 (120차) — AI 태그 제안을 카드 신규 생성/지도 스크린샷 추가에도 확장
#### Added
- `Models/PlaceCard.swift`: `applyScannedDetails(_:)`를
  `PlaceCardViewModel`의 private 메서드에서 `PlaceCard`의 mutating
  메서드로 옮김(전화/카테고리/영업시간/마감시간/휴무일/편의시설/예약
  방법을 빈 값일 때만 채움, 태그는 제외) — `PlaceCardViewModel`뿐 아니라
  `MapScreenshotImportSheet`도 재사용할 수 있도록.
- `ViewModels/PlaceCardViewModel.swift`: `PlaceCandidateRow.tags`(사용자가
  실제로 수락한 태그) 필드와 `acceptSuggestedTags(_:forRowID:)` 추가 —
  `createCards()`가 이제 각 행의 `tags`를 새 카드에 반영.
- `Views/AddPlaceCardView.swift`: "119차에서는 EditPlaceCardSheet(기존
  카드 수정)에서만 AI 태그를 제안했는데, 처음 만들 때를 비롯해서
  정보가 추가될 때 제안해라"는 요청 — 카드를 처음 만드는 화면(사진
  스캔으로 여러 장소를 찾아 검토하는 곳)의 각 행에도 "제안된 태그: ...
  [추가]"를 표시하도록 추가. 여기도 확인 후에만 반영됨(자동 적용 아님).
#### Fixed
- `Views/MapScreenshotImportSheet.swift`("지도에서 열기"로 최근 연 카드에
  스크린샷을 바로 추가하는 화면): AI 스캔 결과 중 이름·주소·메모만
  반영하고 전화번호·카테고리·영업시간·편의시설·예약 방법·태그는 전부
  조용히 버려지고 있던 걸 발견 — 이 화면도 "정보가 추가될 때"에
  해당하는데 실제로는 거의 아무것도 반영되지 않고 있었다.
  `PlaceCard.applyScannedDetails(_:)`로 나머지 필드를 채우고, 태그는
  다른 화면들과 동일하게 확인 알림 후 추가하도록 수정.

### 2026-09-11 (119차) — AI 태그 자동 제안 (확인 후 적용)
#### Added
- `Services/AIProvider.swift`: `PlaceWebDetails`에 `tags: [String]` 필드
  추가 — 사진 스캔(`defaultPlaceAnalysisPrompt`)·웹 검색
  (`webDetailsSearchPrompt`) 둘 다 장소에 어울릴 만한 짧은 태그를 0~5개
  제안하도록 프롬프트에 추가. 다른 필드(전화번호/카테고리/영업시간 등)와
  달리 태그는 의도적으로 자동 적용하지 않음 — 태그는 객관적 사실이라기
  보다 사용자 개인의 분류 체계에 가까워서, 잘못된 추측이 조용히 카드에
  붙는 게 다른 필드보다 거슬릴 수 있다고 판단(사용자 확인).
- `Views/EditPlaceCardSheet.swift`: `stageSuggestedTags(from:)` — AI가
  제안한 태그 중 이미 있는 태그와 안 겹치는 것만 걸러내 있으면
  "AI가 태그를 제안했습니다" 확인 알림(제안된 태그 목록 표시, "추가"/
  "취소")으로 띄움. 사진 스캔("AI로 정보 읽어오기")과 웹 검색("웹
  검색으로 채우기") 둘 다에서 동작.
- `ViewModels/PlaceCardViewModel.swift`: `applyScannedDetails`(새 카드
  생성 시 사용, `AddPlaceCardView` 경로)는 태그를 의도적으로 건드리지
  않음 — 새로 만드는 카드는 확인 절차가 없어서, 태그만큼은
  `EditPlaceCardSheet`(확인 UI가 있는 곳)에서만 제안되도록 범위를
  좁혔다.

### 2026-09-11 (118차) — 앱 시작 시 인트로 화면 추가
#### Added
- `Views/MainTabView.swift`: "앱을 열 때 백업으로 시간이 걸린다면 화면에
  intro를 보여주는 게 좋겠다"는 요청 — `startupIntroView`(앱 이름 +
  아이콘 + 스피너, 불투명 배경) 추가. 다만 인트로가 실제로 기다리는
  대상은 재설계했다: 시작 시 한 번에 도는 네 가지 작업 중 화면에 뭐가
  보일지 실제로 좌우하는 건 `restoreFromCloudIfNeeded()`(기기가 비어있을
  때 iCloud에서 게시판·장소를 복원하는 것) 하나뿐이고, 나머지 셋
  (`checkForSharedImage`/`AutoBackupService.runIfDue`/
  `CloudBackupService.backup`)은 현재 데이터를 어딘가에 내보내거나
  써두기만 할 뿐 화면에 아무 영향이 없다. 그래서 인트로는
  `restoreFromCloudIfNeeded()`가 끝나면 바로 사라지고(로컬에 이미
  데이터가 있는 평소 경우엔 이 함수가 가드 하나로 거의 즉시 반환되어
  인트로가 사실상 안 보임), 사진 바이트까지 포함되어 이제 더 오래
  걸릴 수 있는 백업 쓰기 작업(`AutoBackupService`/`CloudBackupService
  .backup`)은 별도 `Task`로 분리해 인트로를 내린 뒤에도 백그라운드에서
  계속 진행되도록 했다 — 느려진 부분 때문에 앱이 매번 인트로에 더
  오래 머무는 게 아니라, 정말 최초 실행/재설치로 실제 복원할 게 있을
  때만 잠깐 보이게 된다.

### 2026-09-11 (117차) — 백업에 사진 실제 포함
#### Changed
- `Services/BackupService.swift`: Peragra(사진/미디어 모델이 아예 없는
  자매 앱)의 백업 로직을 그대로 이식하면서 "실제 이미지 바이트는
  포함하지 않는다"는 설계 범위도 그대로 따랐던 것을 확인 — 이번에
  `BackupData`에 `mediaFiles: [String: Data]?`(파일명 → 원본 바이트,
  `Data`의 기본 Codable 동작으로 JSON 안에 base64로 인코딩) 필드를
  추가해 실제로 포함하도록 확장. zip 같은 아카이브 형식 대신 단일 JSON
  파일 구조를 그대로 유지 — 이 프로젝트가 의존하는 압축 라이브러리가
  없어서 Foundation만으로 되는 가장 단순한 방법을 택함(용량은 base64
  오버헤드만큼 더 커짐). "전체 백업"/"게시판 내보내기"/자동 폴더 백업/
  iCloud 자동 백업 전부 같은 `exportData`/`exportBoard`를 쓰므로 동일하게
  적용됨. 복원(`restore`)·게시판 가져오기(`importBoard`) 둘 다 임베드된
  사진을 원래 파일명 그대로 `MediaStore`에 다시 써서, 다른 기기에서
  복원/가져오기해도 사진이 정상적으로 보임. 이전 버전에서 만든 백업
  파일(사진 없음)은 `mediaFiles`가 없어도 그냥 nil로 디코딩되어 기존과
  동일하게 동작(카드는 복원, 사진만 없음).
- `Services/MediaStore.swift`: `loadData(fileName:)`(UIImage 디코드/
  재인코딩 없이 원본 바이트 그대로 읽기)/`writeData(_:fileName:)`(이미
  정해진 파일명으로 그대로 쓰기, 복원용) 추가.
- `Services/CloudBackupService.swift`: iCloud 자동 백업은 앱을 열고 닫을
  때마다(포그라운드/백그라운드 전환마다) 매번 재실행되는데, 이제 사진
  바이트까지 포함되면서 변경 사항이 없어도 매번 몇 MB~수십 MB를
  다시 읽고 쓰는 건 낭비라 카드 개수/최근 수정 시각 기반의 가벼운
  "변경 없으면 건너뛰기" 체크 추가. 게시판 이름만 바뀐 경우처럼 카드가
  전혀 안 바뀐 board 전용 수정은 이 체크로 못 잡을 수 있지만(다음에
  카드가 바뀌면 그때 반영됨), 매 전환마다 도는 빈도를 생각하면 감수할
  만한 트레이드오프.
- `Views/SettingsView.swift`: "사진 자체는 백업에 포함되지 않고..." 안내
  문구를 새 동작에 맞게 수정.

### 2026-09-11 (116차) — 사용자 제보 6건 처리
#### Added
- `Models/PlaceCard.swift`: `reservationInfo`(예약 방법, 예: "캐치테이블
  예약") 필드 추가. `Services/MapOpeners.swift`: `reservationSearchURL` —
  Catch Table 등 특정 예약 플랫폼에 대한 검증된 딥링크/검색 URL 형식이
  없어(Catch Table 자체 사이트는 JS 앱이라 공개 검색 URL 문서가 없음),
  직접 연결 대신 `reservationInfo` + 장소명으로 일반 웹 검색을 여는
  방식으로 구현 — 잘못 추측한 링크가 엉뚱한 곳으로 연결되는 것보다 안전.
  `PlaceCardDetailView`의 액션 행에 "예약" 버튼 추가, `EditPlaceCardSheet`
  "영업 정보" 섹션에 편집 필드 추가.
- `Services/AIProvider.swift`: 사진 스캔(`defaultPlaceAnalysisPrompt`/
  `AIAnalysisResult`)이 지금까지 이름·주소·description·confidence만
  요청했던 것을 확인 — "google map의 영업시간을 AI로 읽어도 필드에
  포함안됨" 제보의 원인. 웹 검색 플로우(`PlaceWebDetails`)와 동일하게
  전화번호·웹사이트·카테고리·영업시간·마감시간·휴무일·편의시설·예약
  방법을 사진 스캔에도 요청하도록 확장, `PlaceCandidateRow.scannedDetails`
  로 카드 생성까지 연결(`PlaceCardViewModel.applyScannedDetails`).
- `Views/EditPlaceCardSheet.swift`: "웹 검색으로 채우기"의 필드별 결과
  메시지(`fillBlankFields`)를 사진 스캔(`applyExtractedPlace`)에도
  재사용 — "사진추가후 AI로 정보 추가할때 추가되는 정보를 작은 글씨로
  보여달라" 요청 처리. 기존에도 `.caption`(작은 글씨)였지만 내용이
  "AI가 읽은 정보를 채웠습니다"로 고정이었던 걸 "전화번호, 영업시간
  정보를 채웠습니다"처럼 실제로 채워진 필드를 나열하도록 수정.
- `Views/PlaceStatusFilterBar.swift`: "현재 위치에서 거리 표시가 안된다"
  제보 — 권한 거부(이미 알림 있음) 외에, 시스템 전체 위치 서비스 꺼짐/
  GPS 신호 없음/타임아웃처럼 nil이 반환되는 다른 모든 경우엔 아무 피드백
  없이 조용히 실패하던 부분을 발견, 별도 알림 추가. (근본 원인이 이
  경우들 중 무엇인지는 기기에서 재현하지 못해 확정 못함 — 다음 테스트에서
  어떤 알림이 뜨는지로 원인을 좁힐 수 있음)
#### Fixed
- `Services/AIProvider.swift`(`GatewayProvider.searchWebForDetails`):
  "web 검색으로 채우기 작동안한다" 제보 스크린샷에 정확한 원인이 찍혀있었음
  — `API 오류 (400): tools.0.type: Input should be 'function'`. 114차
  이전 라운드에서 "게이트웨이가 벤더별(Claude/GPT) 호스팅 검색 도구를
  그대로 전달해줄 것"이라고 추측하고 구현했던 게 이제 실제 기기 오류로
  틀렸음이 확인됨 — 이 게이트웨이의 `/chat/completions`는 어떤 벤더
  모델이든 OpenAI 함수 호출 스키마(`type: "function"`)만 엄격하게
  검증하고, 자체 호스팅 검색 도구가 전혀 없음. 잘못된 추측을 걷어내고
  기본 "지원하지 않음" 동작으로 되돌림 — 진짜로 구현하려면 이 앱에 아직
  없는 별도의 실제 웹 검색 백엔드가 필요한, 훨씬 큰 작업.

### 2026-09-11 (115차) — 사진 저장 시에도 원본 대신 축소해서 저장
#### Changed
- `Services/MediaStore.swift`(`saveImage(_:compressionQuality:)`): "사진을
  줄이면 속도가 빨라지나?" 질문에 대한 답 — 114차는 표시(로드)할 때만
  다운샘플링했을 뿐, 디스크에 저장되는 원본 자체는 여전히 촬영 그대로의
  전체 해상도(최신 아이폰이면 8000px대)였다. 그래서 매번 읽어야 하는
  파일 자체가 크다 보니 디스크 I/O가 더 걸리고, 백업/내보내기 용량도
  커지고, `loadThumbnail`이 다운샘플링할 원본 소스 자체도 불필요하게
  크다는 문제가 남아 있었다. `saveImage`가 이제 저장 전에 긴 변을
  2048px로 제한(그보다 작으면 그대로 유지, 확대는 안 함) — 앱 어디서도
  이보다 큰 해상도로 사진을 보여주는 화면이 없어서(전체화면 뷰어도
  기기 화면 안에 맞춰 그려짐) 화질 손해는 사실상 없다.

### 2026-09-11 (114차) — 전체 속도 저하(이미지 캐시/다운샘플링) + Naver/Google 라벨 항상 "Google"로 고정되던 문제
#### Added
- `Services/MediaStore.swift`: "전체적으로 속도가 너무 늦다" 제보 —
  리스트/그리드 셀, 상세보기의 히어로 배너·사진 스트립이 전부 자기
  `body`에서 직접 `MediaStore.loadImage`를 호출하고 있었는데, 캐시가
  전혀 없어서 스크롤/리렌더될 때마다(즉 사실상 매 프레임마다) 원본
  해상도(수천 픽셀짜리 사진 그대로 저장됨) JPEG를 디스크에서 다시
  디코딩하고 있었다 — 앱 전체가 느려지는 근본 원인으로 보임.
  `NSCache` 기반 인메모리 캐시를 추가하고, 작은 썸네일 용도로는
  ImageIO의 `CGImageSourceCreateThumbnailAtIndex`로 다운샘플링해서
  디코딩하는 `loadThumbnail(fileName:maxPixelSize:)`를 새로 추가 —
  전체 해상도로 디코딩한 뒤 SwiftUI가 축소해서 그리는 것보다 훨씬 싸다.
  `PlaceCardListRow`(56pt)/`PlaceCardGridCell`(그리드 셀)/
  `PlaceCardDetailView`의 히어로 배너·사진 스트립(96pt)이 이걸 쓰도록
  교체 — 전체화면 사진 뷰어(`PhotoViewerSheet`)는 확대/축소가 필요해
  원본 해상도(`loadImage`, 이제 캐시는 됨)를 그대로 유지.
- `Services/Localization.swift`: `"Naver에서 검색"`/`"Naver 지도에서
  확인됨"` 추가.
#### Fixed
- `Views/AddPlaceCardView.swift`: "naver로 보내도 구글에서 찾고 있다"
  제보를 조사하다가, 실제 검증은 113차 수정 이후 제대로 Naver로 가고
  있을 가능성이 높은데도 이 화면의 "Google에서 검색" 버튼/"Google
  지도에서 확인됨" 라벨이 항상 고정 문구였다는 걸 발견 — 실제로 어느
  쪽으로 검증됐는지와 무관하게 무조건 "Google"이라고 표시하고 있어서,
  사용자 입장에선 (실제로 Naver로 갔더라도) Google로만 가는 것처럼
  보일 수밖에 없었다. `row.originSource`를 기준으로 Naver 공유
  출처면 "Naver에서 검색"/"Naver 지도에서 확인됨"으로 표시하도록
  수정 — 다음 테스트에서 실제로 어느 쪽이 쓰이는지 화면에서 바로
  확인 가능.

### 2026-09-11 (113차) — 네이버 공유인데 네이버 검색결과가 없다고 나오던 문제 수정
#### Fixed
- `ViewModels/PlaceCardViewModel.swift`(`search(rowID:)`): 네이버 지도에서
  공유했는데 "검색결과가 없습니다"가 뜨고, 다시 시도하면 Google 검색이
  나오는 제보 — 두 가지가 겹쳐 있었다.
  1. **재시도가 조용히 Google로 새는 회귀 버그(112차에서 유입)**: 검색이
     끝나면 행의 이름을 깨끗한 `resolved.name`으로 덮어쓰도록 고쳤는데,
     그 결과 "[네이버지도]" 태그/URL이 이름 필드에서 사라져서 — 같은 행을
     다시 검색하면 `SharedLinkParser`가 더 이상 네이버 공유로 인식하지
     못하고 소스 없음으로 떨어져 Google로 검증하게 됨. 행에
     `originSource`를 처음 한 번만 기록해두고 이후 검색은 전부 그 값을
     쓰도록 수정 — 이름이 정리된 뒤에도 원래 출처를 계속 기억한다.
  2. **네이버 자체 검색에서도 못 찾을 만한 과도하게 구체적인 쿼리**: 이름
     + 전체 도로명주소(동/호수까지)를 그대로 합쳐서 검색어로 보내고
     있었는데, 네이버 지역 검색은 Google Text Search만큼 느슨하게
     매칭해주지 않는 것으로 보임 — 네이버 지도에서 직접 공유한 장소를
     네이버 자체 검색에서 못 찾는 건 애초에 이상한 결과였다(사용자 지적).
     이름+주소 쿼리가 빈 결과로 돌아오면 이름만으로 한 번 더 재시도하도록
     추가.

### 2026-09-11 (112차) — 사용자 제보 4건 수정 (Naver API HUB 엔드포인트, 왼쪽 잘림 재발, 공유 화면 안 뜸, 첫 공유시 상세보기 안 뜸)
#### Fixed
- `Services/NaverPlaceSearchService.swift`: "유효하지 않은 API 키입니다" +
  "네이버 API 관리에서 당일 사용량이 없다고 나온다" 제보로 확인 — NAVER API
  HUB는 단순히 발급 화면만 옮겨간 게 아니라, 실제 호출 엔드포인트/인증
  헤더 자체가 완전히 다른 걸로 바뀌었다(WebSearch로 공식 이관 가이드
  확인: `openapi.naver.com` 구버전은 2026-07-31부로 신규 발급 중단,
  기존 키도 2027-06-30 만료 예정). 이 앱은 여전히 옛 엔드포인트
  (`openapi.naver.com/v1/search/local.json`)와 옛 헤더
  (`X-Naver-Client-Id`/`X-Naver-Client-Secret`)를 쓰고 있어서, API HUB에서
  발급받은 키로는 애초에 그 서버에 요청이 정상적으로 도달하지 못했던 것 —
  그래서 사용량도 0으로 찍힌 것. 엔드포인트를
  `https://naverapihub.apigw.ntruss.com/search/v1/local`로, 헤더를
  `X-NCP-APIGW-API-KEY-ID`/`X-NCP-APIGW-API-KEY`로 교체. 응답 필드명(title/
  address/roadAddress/mapx/mapy/category 등)은 동일하게 유지된다고 확인.
- `Views/PlaceCardDetailView.swift`: 111차의 `.frame(maxWidth: .infinity,
  alignment: .leading)`로도 "사진에 따라 아래가 넓어지는 것"이 계속
  재현된다는 제보 — `maxWidth: .infinity`는 "제안받은 만큼만 채우고 그
  이상은 요구하지 않기"일 뿐, 어떤 자식이 이미 더 넓은 크기를 요구하고
  있다면 이를 막지 못한다는 게 진짜 이유로 보임. `GeometryReader`로 실제
  뷰포트 폭을 측정해 `.frame(width: proxy.size.width, alignment: .leading)`
  로 정확한 값을 강제 — 이번엔 어떤 자식도 그 이상 넓어질 수 없는 하드
  제약이라 근본적으로 막힘.
- `Views/MainTabView.swift`(`checkForSharedImage()`): "보내고 받을 때 처음엔
  화면이 안 뜨다가 포커스를 바꿨다 돌아오면 뜬다"는 제보 — 포그라운드
  전환과 같은 런루프 틱에서 시트 `isPresented`를 바로 `true`로 바꾸면
  상태는 바뀌어도 실제 시트가 안 뜨는 경우가 있는 것으로 보임(윈도우가
  아직 완전히 준비되지 않은 상태). 실제 프레젠테이션 트리거만
  `presentShortly(_:)`로 한 틱 늦춰서 우회.
#### Added
- `Views/GalleryView.swift`: "처음 보낼 때는 placedetail이 안 뜨고
  리스트가 뜬다"는 제보 — `navigation.pendingDetailCardID`를 `.onChange`
  로만 소비했는데, 이 세션에서 갤러리 탭을 한 번도 연 적이 없는 상태로
  처음 공유하면 `AddPlaceCardView`가 그 값을 세팅하는 시점에 `GalleryView`
  가 아직 화면에 나타난 적이 없어 `.onChange`가 못 잡는 경우가 있는
  것으로 보임(`currentHomeBoardID`가 이미 `.onAppear`+`.onChange` 둘 다
  쓰는 이유와 동일한 종류의 경합). `consumePendingDetailCardID()`로
  추출해 `.onAppear`에서도 동일하게 호출하도록 추가.

### 2026-09-11 (111차) — 왼쪽 글자 잘림 버그, 진짜 원인 찾아서 수정 (105/110차는 잘못된 진단이었음)
#### Fixed
- `Views/PlaceCardDetailView.swift`: 105차/110차는 "Google/Naver API 응답에
  섞인 보이지 않는 유니코드 문자" 때문이라고 추정하고 고쳤는데, 이번에
  사용자가 "사진을 지우면 정상적으로 보이게됨"이라고 정확히 재현해준 덕에
  진짜 원인을 찾았다 — 이름뿐 아니라 카테고리/주소/평점, 심지어
  "사진"/"태그"처럼 코드에 고정으로 박혀 있는(API와 전혀 무관한) 문구까지
  똑같이 왼쪽이 잘려 보였던 게 결정적 단서. 즉 텍스트 내용의 문제가 아니라,
  카드에 첨부된 사진 때문에 상세보기의 `ScrollView` 콘텐츠 폭이 화면보다
  넓어지고, SwiftUI가 그 넓어진 콘텐츠를 화면 가운데로 정렬해버리면서
  모든 줄의 왼쪽 끝이 균등하게 화면 밖으로 잘려나간 것 — 사진을 지우면
  그 폭 초과가 사라지니 정상으로 보인 것도 이걸로 설명됨. `ScrollView` 안
  콘텐츠 `VStack`에 `.frame(maxWidth: .infinity, alignment: .leading)`을
  추가해 자식 뷰에 제안되는 폭을 실제 화면 폭으로 명시적으로 고정 —
  어떤 자식이 폭을 과다하게 요구하든 애초에 화면보다 넓어질 수 없게
  막는 방식이라 정확한 내부 원인(사진 크기 관련 SwiftUI 레이아웃 특성으로
  추정)을 100% 특정하지 못해도 증상 자체는 근본적으로 차단된다.
  105/110차의 유니코드 문자 제거 자체는 (이 버그의 원인은 아니었지만)
  Google Places API가 실제로 그런 문자를 넣는 건 알려진 사실이라 무해한
  방어 코드로 남겨둠.

### 2026-09-11 (110차) — 왼쪽 글자 잘림 버그, 이미 저장된 카드까지 실제로 고치기
#### Fixed
- `Services/PlaceSearchService.swift`(`GooglePlace.toSearchResult()`)/
  `Services/NaverPlaceSearchService.swift`(`NaverLocalItem.toSearchResult()`):
  105차에서 name/address만 `strippingInvisibleFormatCharacters()`를 적용하고
  category("패밀리 레스토랑" 등)는 빠뜨렸던 걸 확인 — "빕스 아주대점" 카드
  스크린샷에서 제목/주소뿐 아니라 카테고리("밀리 레스토랑" ← "패밀리
  레스토랑")까지 왼쪽이 잘려 보이는 걸로 재확인됨. category도 마저 적용.
#### Added
- `Models/PlaceCard.swift`: `strippingInvisibleFormatCharacters() -> PlaceCard`
  추가 — name/address/category/memo/closingTime/holidays/tags/amenities/
  hoursDetail 전부에 적용.
- `Services/StorageService.swift`(`loadPlaceCards()`): 디코딩 직후 모든
  카드에 위 함수를 적용하고 바로 다시 저장하도록 변경. 105차 수정은 그
  이후에 "새로" 들어오는 데이터만 청소했을 뿐, 이미 저장돼 있던 카드
  (스크린샷의 "빕스 아주대점"이 그런 경우로 보임)는 계속 예전 그대로
  잘려 보일 수밖에 없었던 근본 원인 — 이제 앱을 켤 때마다 저장된 카드
  전체를 한 번씩 청소하므로, 언제 만들어진 카드든 결국 고쳐진다.

### 2026-09-11 (109차) — 108차에서 생긴 크래시(AppNavigation environmentObject 누락) 수정
#### Fixed
- `Views/SharedLinkBoardPickerSheet.swift`/`Views/SharedPhotoBoardPickerSheet.swift`/
  `Views/GalleryView.swift`/`Views/MainTabView.swift`: 108차에서 `AddPlaceCardView`에
  `@EnvironmentObject private var navigation: AppNavigation`를 추가했는데,
  실제 기기에서 공유 링크로 장소를 추가하자 "Fatal error: No ObservableObject
  of type AppNavigation found"로 크래시(사용자 제보 로그로 확인). `AppNavigation`은
  `StorageService`와 달리 앱 루트가 아니라 `MainTabView` 자신의 body에서만
  주입되는데(`TabView(...).environmentObject(navigation)`), `MainTabView` →
  `SharedLinkBoardPickerSheet`(시트) → `AddPlaceCardView`(그 안의 또 다른 시트)처럼
  시트 안에 시트가 중첩되면 `@EnvironmentObject`가 두 번째 시트까지 안정적으로
  전달되지 않는 SwiftUI의 잘 알려진 함정이었다. `SharedLinkBoardPickerSheet`/
  `SharedPhotoBoardPickerSheet`가 `navigation`을 직접 받아 자신의
  `AddPlaceCardView` 시트에 `.environmentObject(navigation)`으로 다시 주입하도록
  수정. `MainTabView`의 1단계 시트, `GalleryView`의 자체 "장소 추가" 시트에도
  같은 문제를 예방하기 위해 동일하게 명시적으로 재주입.

### 2026-09-11 (108차) — 공유로 들어온 정보로 카드를 만들면 그 카드로 바로 이동
#### Added
- `Services/AppNavigation.swift`: `pendingDetailCardID`/`showCardDetail(_:)`
  추가 — Gallery 탭으로 전환하면서 특정 카드의 상세보기를 한 번 push하도록
  요청한다(`galleryCategoryFilter`와 같은 1회성 소비 패턴).
- `Views/GalleryView.swift`: `navigation.pendingDetailCardID`를
  `.onChange`로 소비해 해당 id의 카드를 찾아 `selectedCard`로 세팅(=
  `navigationDestination`으로 상세보기 push), 곧바로 `nil`로 되돌린다.
#### Changed
- `Views/AddPlaceCardView.swift`: 공유 확장(Share Extension)으로 들어온
  링크/사진으로 열린 화면인지(`cameFromSharedInfo`, `initialLinkText`/
  `initialImageData`로 열렸는지로 판별)를 기억해뒀다가, "추가" 버튼으로
  카드를 저장했을 때 정확히 1개 카드만 만들어졌으면
  `navigation.showCardDetail(_:)`을 호출 — 시트가 전부 닫히고 나면 방금
  공유해서 만든 그 장소 카드가 바로 뜬다. 여러 장소가 한 번에 만들어진
  경우(스크린샷 하나에 여러 장소가 잡힌 경우)엔 어느 하나를 열 근거가
  없으므로 기존처럼 그냥 닫히기만 한다.

### 2026-09-11 (107차) — 공유 링크로 추가한 장소의 이름 필드가 원문 그대로 남던 문제 수정
#### Fixed
- `ViewModels/PlaceCardViewModel.swift`(`search(rowID:)`): 네이버 지도 공유
  텍스트나 링크를 붙여넣으면 `resolveSharedPlace`가 태그/이름/주소/URL을
  잘 분리해내는데도, 분리된 깨끗한 이름(`resolved.name`)을 행의 `name`
  필드에 다시 써주지 않아서 "이름" 칸엔 "[네이버지도] 백상어수산 수원
  경기 수원시 영통구 매여울로 26 1층 https://n..." 같은 원문 전체가 계속
  남아 있었다(주소 칸은 정상적으로 채워졌었음 — 캡처로 확인). 검색이
  끝나면 행의 이름을 `resolved.name`으로 갱신하도록 한 줄 추가.

### 2026-09-11 (106차) — 홈페이지 링크에서 업체 정보(이름/주소/전화/영업시간) 추출
#### Added
- `Services/WebsiteBusinessInfoFetcher.swift`(신규) — 일반 업체 홈페이지 링크의
  schema.org JSON-LD 구조화 데이터(`<script type="application/ld+json">`)를
  파싱해 이름/주소/전화/영업시간을 추출한다. `LocalBusiness` 등 고정된
  `@type` 목록으로 제한하지 않고, `name`과 (`address` 또는 `telephone`)이
  둘 다 있는 객체를 실제 업체 정보로 인정 — schema.org의 LocalBusiness
  하위 타입이 계속 늘어나는 상황에 안전하도록. 전화/영업시간은 별도
  필드가 아니라 카드 메모(`note`)에 합쳐 넣는다 — 홈페이지 자체가 적어둔
  값이라 Google/Naver 검색 결과처럼 검증된 값이 아니기 때문.
- `Services/LinkMetadataFetcher.swift`: 기존 `fetchTitle(for:userAgent:session:)`의
  "크롤러 UA로 먼저 시도, 실패하면 모바일 Safari UA로 재시도" 로직을
  `fetchHTML(for:session:)`(내부용 `fetchHTML(for:userAgent:session:)` 분리)로
  뽑아내 제목 파싱과 분리 — `WebsiteBusinessInfoFetcher`가 페이지 전체
  HTML이 필요해서 같은 fallback 로직을 중복 없이 재사용하도록.
- `Services/Localization.swift`: `"전화번호: "`/`"영업시간(홈페이지): "` 추가.
#### Changed
- `ViewModels/PlaceCardViewModel.swift`(`resolveSharedPlace(from:)`): 네이버/구글
  지도 공유가 아닌 일반 URL(예: 구글맵에 없는 업체의 홈페이지 링크)을
  붙여넣거나 공유받으면, 기존처럼 원본 URL 텍스트를 그대로 이름으로 쓰던
  것 대신 `WebsiteBusinessInfoFetcher`로 먼저 시도하고, 실패하면
  `LinkMetadataFetcher.fetchTitle`(제목만)로 폴백한다. 인스타그램 링크는
  제외(게시물 페이지엔 업체 정보가 없고 Instagram 자체의 Organization
  블록만 있어 오탐 소지). `ResolvedSharedPlace`/`PlaceCandidateRow`에
  `website` 필드 추가, `createManualPlaceCard`/`createPlaceCard(from:)`가
  이를 받아 카드의 `website` 필드로 저장한다(검색으로 찾은 결과 자체에
  website가 있으면 그쪽이 우선).

### 2026-09-11 (105차) — 상세보기에서 왼쪽 글자가 잘리던 문제 (추정) 수정
#### Added
- `Services/TextSanitizing.swift`(신규) — `String.strippingInvisibleFormatCharacters()`.
  유니코드 "format"(Cf) 카테고리 문자(제로폭 공백/조인터, BOM, 양방향
  방향 제어 문자 LRM/RLM/임베딩/오버라이드/아이솔레이트 등)를 전부
  제거한다. 이 문자들은 원래 안 보이는 게 정상이라 제거해도 텍스트
  내용은 절대 안 바뀌지만, 문자열 맨 앞에 하나 끼어 있으면 SwiftUI
  `Text`가 그 부분을 화면 왼쪽 밖으로 밀어낸 것처럼 이상하게 그리는
  경우가 있다.
#### Fixed
- `Services/PlaceSearchService.swift`(`GooglePlace.toSearchResult()`)/
  `Services/NaverPlaceSearchService.swift`(`NaverLocalItem.toSearchResult()`)/
  `Services/SharedLinkParser.swift`(`parseNaverText`): 사용자가 "네이버에서
  받아서 구글로 읽어온 카드만 상세보기에서 왼쪽 글자가 잘린다"고 제보한
  것을 근거로 추정한 원인 — Google Places API는 한글+영문/숫자가 섞인
  주소·이름 텍스트에 브라우저용 양방향 표시 제어 문자(LRM 등)를 끼워
  넣는 것으로 알려져 있는데, 브라우저에선 안 보이지만 SwiftUI `Text`에선
  그 지점에서 이상하게 그려질 수 있다. Google Places/Naver 지역 검색
  결과의 name/address, 그리고 네이버 공유 텍스트를 줄 단위로 쪼개는
  지점에 `strippingInvisibleFormatCharacters()`를 적용. 기기에서 직접
  재현하지 못한 상태로 제보 내용을 근거로 추정한 수정이라, 실제로
  해결됐는지 확인 필요.

### 2026-09-11 (104차) — Naver 검색 API 발급 안내 수정 (NAVER API HUB로 이전됨)
#### Fixed
- `Views/SettingsView.swift`/`Services/Localization.swift`/
  `Services/NaverPlaceSearchService.swift`/`Services/KeychainService.swift`:
  92차에서 "Naver 검색 API"를 Naver Developers(developers.naver.com/apps)에서
  발급받으라고 안내했는데, 사용자가 실제로 애플리케이션 등록 화면을
  캡처해서 확인해주신 결과 그 화면엔 로그인 관련 API(네이버 로그인/
  인증서/전자문서/카페/캘린더/캡차 등)만 있고 "검색"은 아예 없었다.
  찾아보니 검색 오픈API(지역 검색 포함)는 NAVER Cloud Platform의
  "NAVER API HUB"로 옮겨간 상태였다 — 콘솔(console.ncloud.com) →
  Menu → All Services → Application Services → NAVER API HUB →
  Application 등록 시 "검색" API 선택 → 등록된 Application의 "인증 정보"
  팝업에서 Client ID/Secret 확인. Settings 화면 안내 문구와 관련 코드
  주석을 전부 이 경로로 정정.

### 2026-09-11 (103차) — 카테고리 병합 기능 추가, 필터 바 두 줄로 분리
#### Added
- `Views/CategoryPickerSheet.swift`: 카테고리 병합 기능(신규) — "선택"으로
  다중 선택 모드에 들어가 2개 이상 고른 뒤 "병합"을 누르면 최종 이름을
  입력받아, 그 카테고리들에 속한 모든 카드의 `category`를 한 번에
  그 이름으로 바꾼다. 자유 텍스트 카테고리("식당"/"레스토랑"/"음식점" 등)는
  자연스럽게 갈라지기 마련인데, `PlaceCategoryIcon.normalizedLabel(for:)`는
  카페 계열만 하드코딩으로 묶어주고 나머지는 손대지 않으므로, 그 외의
  경우를 사용자가 직접 정리할 수 있게 함. 매칭은 `normalizedLabel` 기준이라
  "카페"를 병합 대상으로 고르면 이미 그 라벨로 보이는 "커피숍" 등도 함께
  묶임.
#### Changed
- `Views/PlaceStatusFilterBar.swift`: 정렬/기준/카테고리 메뉴와 전체·즐겨찾기·
  방문 칩이 한 줄에 다 들어가 있던 걸 두 줄로 분리했다. 카테고리 이름이
  길거나 메뉴가 여러 개 동시에 보일 때 한 줄에 다 밀어 넣으면 상태 칩이
  스크롤해도 안 보일 정도로 밀려날 수 있었음.

### 2026-09-11 (102차) — 사진 삭제·대표사진 지정, 태그는 추가/삭제 즉시 저장
#### Added
- `Models/PlaceCard.swift`: `coverPhotoID`(신규, Optional) — 사용자가 명시적으로
  고른 대표사진의 `MediaItem.id`. `coverPhoto`(신규 계산 프로퍼티)로 정리 —
  `coverPhotoID`가 있고 그 사진이 아직 남아있으면 그걸, 아니면 기존처럼
  공식 사진 우선(`officialPhotos.first ?? allItems.first`)으로 폴백.
  `PlaceCardListRow`/`PlaceCardGridCell`/`PlaceCardDetailView.heroPhotoItem`
  세 곳에 중복돼 있던 동일 로직을 이걸로 통일.
- `Views/PlaceCardDetailView.swift`: 사진 뷰어(`PhotoViewerSheet`)에 "..."
  메뉴(대표사진으로 설정 / 삭제)를 추가. 삭제는 확인 다이얼로그를 거치고,
  `MediaStore`에서 파일도 같이 지우며, 지운 사진이 대표사진이었으면
  `coverPhotoID`도 같이 비움(자동 폴백으로 복귀). 마지막 사진을 지우면
  뷰어가 자동으로 닫히고, 선택 인덱스가 범위를 벗어나면 보정.
  - `PhotoViewerSheet`가 이제 `MediaItem` 배열과 `selection`을 바인딩으로
    받도록 바뀌어(기존엔 미리 디코딩한 `UIImage` 배열 + 1회성 `@State`),
    삭제 후 부모가 선택 인덱스를 보정할 수 있게 됨.
#### Changed
- `Views/PlaceCardDetailView.swift`: 태그 편집을 "추가/삭제하면 바로
  저장"으로 단순화 — 별도 "저장" 버튼과 작업 사본(`tagsDraft`)을 없애고
  `card.tags`에 직접 반영 + 즉시 `storageService.save(card)`. 이전
  드래프트 방식은 "편집" 시트를 거치면 재동기화가 안 돼 방금 편집한
  내용을 조용히 덮어쓰는 버그가 있었는데, 드래프트 자체를 없애 근본적으로
  해결.

### 2026-09-11 (101차) — 태그 저장 안 되던 문제 수정, 공유 확장 첫 시도 실패에 재시도 추가
#### Fixed
- `Views/PlaceCardDetailView.swift`: 새로 추가한 태그 편집기(`tagsDraft`)가
  "편집" 시트(`EditPlaceCardSheet`에도 별도의, 쉼표로 구분해 입력하는
  기존 태그 필드가 있었음)를 통해 `card`가 바뀔 때 재동기화되지 않던 버그.
  "편집" 시트에서 태그를 바꾸고 돌아오면 상세보기의 태그 편집기는 여전히
  옛날 값을 들고 있었고, 그 상태에서 "저장"을 누르면 방금 편집 시트에서
  바꾼 내용을 조용히 옛날 값으로 덮어써버렸다(= "태그가 저장이 안 된다"로
  보임). 편집 시트의 저장 콜백에서 `tagsDraft`도 같이 갱신하도록 수정.
- `PlaceCardsShare/ShareViewController.swift`: 공유 시트의 앱 아이콘 목록이
  아직 다 로딩되기 전에 PlaceCards를 선택하면 빈 화면(신고 내용)이
  뜬다는 재현 정보를 받아, `NSExtensionItem`/첨부를 못 찾는 경우 즉시
  실패 처리하는 대신 0.4초 뒤 한 번 더 확인하도록 재시도를 추가했다.
  다만 공유 시트 자체의 아이콘이 언제 눌릴 수 있게 되는지는 iOS 쪽 UI라
  이 확장에서 직접 막거나 지연시킬 방법은 없음 — 호스트 앱 쪽의 첨부
  등록이 늦어서 생기는 경우라면 이 재시도로 자연히 해결될 것.

### 2026-09-11 (100차) — 공유 확장 팝업이 "..."만 보이고 사라지던 문제
#### Fixed
- `PlaceCardsShare/ShareViewController.swift`: 구글맵에서 공유 → PlaceCards를
  선택했을 때, 뜨고 내려가는 팝업에 "..."만 언뜻 보이고 사라진다는 신고.
  링크/텍스트 공유는 네트워크 요청이 없어서 `loadItem`이 프레임 한 번보다도
  빨리 끝나는 경우가 흔한데, 그러면 `finish()`가 거의 즉시 호출되어
  "PlaceCards로 저장 중…" 스피너/문구가 실제로 글자를 읽을 수 있을 만큼도
  화면에 떠 있지 못하고 바로 "✓ 저장됨"으로 넘어가버렸다(그마저도 0.7초 뒤
  바로 닫힘) — 그 순간에 눈에 남는 건 문구 끝의 말줄임표뿐이었을 것.
  `finish()`가 최소 0.5초는 "저장 중…" 상태를 유지하도록 최소 표시 시간을
  두고, 완료 상태도 0.7초 → 1.0초로 늘려서 실제로 읽을 수 있게 함.

### 2026-09-11 (99차) — 위치 권한 거부 시 안내 추가, 상세보기에 태그 편집 필드 추가
#### Added
- `Services/LocationService.swift`: `isAuthorizationDenied()`(신규) —
  `currentLocation()`이 nil을 반환한 이유가 "아직 응답 대기 중"이 아니라
  "권한이 거부/제한됨"(다시 눌러도 절대 안 풀림)인지 구분.
- `Views/PlaceStatusFilterBar.swift`: 위 판별로 "현재 위치"를 눌렀는데
  권한이 거부 상태면 "설정 열기" 버튼이 있는 알림을 띄우도록 함 — 지금까지는
  권한이 거부돼 있으면 아무 안내 없이 거리만 계속 안 나와서, 기능 자체가
  고장난 것처럼 보였음.
- `Views/PlaceCardDetailView.swift`: 상세보기에 태그 편집 필드(`tagsSection`,
  신규) 추가 — 기존엔 태그가 하나라도 있어야 보이는 읽기 전용 목록이었는데,
  이제 항상 보이고 그 자리에서 추가·삭제할 수 있다. 메모 필드(포커스
  잃을 때 자동 저장)와 달리, 태그는 여러 개 추가/삭제하다가 한 번에
  커밋하는 편이 자연스러워서 명시적 "저장" 버튼(바뀐 내용이 있을 때만
  나타남)으로 반영.
  - `WrapTagsView`(읽기 전용 캡슐 목록, 편의시설 표시에도 씀)에 선택적
    `onRemove` 클로저를 추가해 태그 편집에서만 "x" 버튼이 나타나도록 하고,
    다른 호출부(편의시설)는 그대로 읽기 전용으로 유지.

### 2026-09-11 (98차) — 키보드가 떠 있는 상태에서 내릴 수 있게 함
#### Added
- `Services/KeyboardDismiss.swift`(신규): `View.keyboardDoneButton()` — 키보드
  바로 위에 "완료" 버튼을 붙여, 포커스된 필드가 무엇이든
  `resignFirstResponder`를 보내 키보드를 내림(개별 `TextField`마다
  `@FocusState`를 따로 연결할 필요 없음).
#### Changed
- 텍스트 입력이 있는 화면 6곳(`AddPlaceCardView`, `EditPlaceCardSheet`,
  `AddBoardSheet`, `EditBoardSheet`, `SettingsView`, `PlaceCardDetailView`)의
  `Form`/`ScrollView`에 `.scrollDismissesKeyboard(.interactively)`(스크롤
  내려서 키보드 내리기)와 `.keyboardDoneButton()`(항상 보이는 "완료" 버튼,
  내용이 짧아 스크롤이 안 되는 화면에서도 확실히 작동)을 함께 적용 —
  지금까지는 리턴 키가 없는 필드(여러 줄 메모 등)에서 키보드를 내릴 방법이
  없었음.

### 2026-09-11 (97차) — 장소 추가의 "출처" Picker 제거
#### Removed
- `Views/AddPlaceCardView.swift`: 사진 선택 섹션의 "출처" `Picker`(인스타그램
  스크린샷/구글 지도 스크린샷/네이버 지도 스크린샷/현장 촬영)를 없앴다.
  이전에 분석한 대로, 이 값은 AI 분석 프롬프트에 전혀 영향을 주지 않고
  (`analyzeImages`는 `source` 인자를 아예 안 씀), 유일한 실제 효과인
  `MediaBundle`의 4개 사진 버킷 분류도 앱 어디에도 노출되지 않는 죽은
  분류였다. 사용자가 보지도 못할 버킷을 고르게 하는 대신, 저장 시
  고정값(`SourceType.onsitePhoto`)을 그대로 씀.
- `Services/Localization.swift`: 이제 아무 데서도 안 쓰는 "출처" 키 정리.

### 2026-09-11 (96차) — Home에서 보드 선택 시 갤러리로 바로 이동, 리스트 화면 제거
#### Removed
- `Views/BoardDetailView.swift`(삭제): Home에서 보드를 누르면 이 화면(리스트
  전용, 별도 화면)으로 들어가던 흐름을 없앴다. 이미 여러 차수에 걸쳐 갤러리
  탭에 중복 찾기·내보내기·선택 모드·그리드/리스트 전환까지 이 화면과 동일한
  기능을 전부 옮겨뒀던 터라, "게시판 하나만 보기"는 이제 갤러리를 보드로
  스코프하는 것만으로 완전히 대체 가능해짐.
#### Added
- `Services/AppNavigation.swift`: `showBoardInGallery(_:)`(신규) — 보드
  ID로 `currentHomeBoardID`를 설정하고 갤러리 탭으로 전환. 기존에
  `BoardDetailView`가 자기 `.onAppear`에서 설정하던 것을, 이제 Home의 보드
  행 탭이 대신 설정.
- `Views/GalleryView.swift`: 보드로 스코프된 상태에서만 보이는 툴바 버튼 2개
  추가 — "전체 보기"(스코프 해제, `currentHomeBoardID = nil`)와 "장소
  추가"(그 보드로 `AddPlaceCardView` 열기, 기존 `BoardDetailView`의 "+" 버튼
  대체). 리스트 화면이 없어지면서 유일하게 빠지는 기능이었던 "이 보드에
  새 장소 추가하기"를 갤러리 쪽에 이식.
#### Changed
- `Views/HomeView.swift`: 보드 행의 `NavigationLink { BoardDetailView(...) }`를
  `.onTapGesture { navigation.showBoardInGallery(board.id) }`로 교체
  (스와이프 액션은 그대로 유지). 더 이상 신뢰할 수 없어진(보드 스코프 진입이
  더는 Home 자신의 NavigationStack push/pop이 아니라 탭 전환으로 바뀌어서,
  Home 안에서 검색 결과를 열었다 뒤로 가기만 해도 스코프가 잘못 풀릴 수
  있었음) `.onAppear { currentHomeBoardID = nil }` 자동 초기화를 제거 —
  대신 갤러리의 "전체 보기" 버튼이 스코프 해제의 유일한 경로가 됨.
- `Services/Localization.swift`: `BoardDetailView` 전용이었던 빈 상태 문구
  4개(신규 unused 검사에서 확인됨) 정리.

### 2026-09-11 (95차) — 버그 수정: 카드를 눌러 들어가면 사진 뷰어가 저절로 열리는 문제
#### Fixed
- `Views/PlaceCardDetailView.swift`: 갤러리/리스트에서 카드를 눌러 상세보기로
  들어가면, 가끔 "..."가 잠깐 뜨고 사라진 뒤 사진 뷰어가 저절로 열리는
  현상. 카드 목록 쪽은 (`NavigationLink`가 행 안의 즐겨찾기 등 버튼을
  가로채는 문제 때문에) `NavigationLink` 대신
  `.contentShape(Rectangle()).onTapGesture { selectedCard = card }` +
  `.navigationDestination(item:)`로 내비게이션한다. 이 방식은 `Button`/
  `NavigationLink`만큼 터치를 확실히 소비하지 않아서, 카드를 연 그 터치가
  화면 전환 도중 새로 밀려 들어온 상세보기 화면의 같은 위치에 있던 요소로
  새어 들어갈 수 있다 — 이번에 화면 맨 위·가장 큰 영역을 차지하는
  `heroPhotoSection`(사진 배너)이 그 대상이 된 것.
  - 화면이 뜬 뒤 400ms 동안 `heroPhotoSection`의 탭을 막는
    `isHeroPhotoTappable` 플래그(신규)를 추가 — 전환에서 새어 들어온
    터치는 걸러내고, 실제 사용자가 의도적으로 누르는 탭은 이 정도
    지연으로는 전혀 체감되지 않음.

### 2026-09-11 (94차) — 버그 수정: 상세보기 지도 미리보기가 빈 칸으로 남는 문제
#### Fixed
- `Views/PlaceCardDetailView.swift`: 좌표 미리보기용 `Map`이 구버전(iOS 17 이전)
  API인 `Map(coordinateRegion: .constant(...), annotationItems:)`로 되어 있었다.
  이 API는 `ScrollView`(리스트가 아닌) 안에서 타일이 다 로드되지 못하고 빈
  칸으로 멈추는 문제가 알려져 있는데, 이 미리보기는 `allowsHitTesting(false)`로
  아예 상호작용이 막혀 있어서(사용자가 지도를 만지작거릴 일이 없는 순수
  미리보기 목적) 한 번 멈추면 재시도를 유발할 제스처 자체가 없어 그대로
  영구히 빈 칸으로 남는다. 더 안정적인 렌더링 경로를 쓰는 최신 컴포저블 API
  `Map(initialPosition: .region(...))` + `Marker`로 교체.

### 2026-09-11 (93차) — 인스타그램 공유 링크는 캡처로 유도
#### Added
- `Services/SharedLinkParser.swift`: `isInstagramLink(_:)`(신규) — 공유 텍스트에서
  뽑아낸 URL의 호스트가 `instagram.com`인지만 확인. 인스타그램은 게시물/릴스
  URL 하나만 공유하고 그 안에 장소 정보가 전혀 없어서(구글 공유 링크의
  경로처럼 이름·좌표가 들어있지도 않고, 네이버 공유 텍스트처럼 이름·주소가
  텍스트로 오지도 않음), 자동으로 풀어낼 방법이 없다고 판단해 자동 파싱을
  시도하지 않기로 함.
- `Views/MainTabView.swift`: `checkForSharedImage()`가 대기 중인 공유 링크가
  인스타그램이면 기존의 게시판 선택 시트(`SharedLinkBoardPickerSheet`) 대신
  "인스타그램 링크는 자동으로 인식할 수 없어요 — 게시물을 캡처해서 '장소
  추가'의 사진 선택으로 다시 추가해주세요" 안내 알림(신규
  `isPresentingInstagramGuidanceAlert`)을 띄움. 실패할 게 뻔한 raw URL을
  후보 행에 넣고 검색을 시도하는 대신, 이미 안정적으로 동작하는 스크린샷 +
  AI 스캔 경로로 곧장 안내.

### 2026-09-11 (92차) — 네이버 링크는 Naver 검색 API로, 구글 링크는 Google Places로 검증
#### Added
- `Services/NaverPlaceSearchService.swift`(신규): 네이버 "검색 오픈API - 지역"
  (`openapi.naver.com/v1/search/local.json`)을 호출해 이름/주소/카테고리/전화/좌표를
  가져온다. 평점·리뷰수·사진은 이 API가 아예 제공하지 않아 `nil`로 남김.
  - `mapx`/`mapy`를 위경도로 바꿀 때, 네이버 공식 문서는 KATECH(TM128)라고
    설명하지만 실제 운영 중인 엔드포인트는 WGS84 좌표에 10,000,000을 곱한
    값을 그대로 돌려주는 것으로 확인되어(문서와 실동작이 어긋나는, 꽤 알려진
    케이스) 그 값을 신뢰해 10,000,000으로 나눔 — 다만 결과가 한반도 위경도
    범위(대략 위도 33~39.5, 경도 124~132) 밖이면 그 가정이 틀렸다는 뜻이므로
    좌표를 버리고 `nil` 처리해 잘못된 좌표가 저장되는 일을 막음.
  - `Services/KeychainService.swift`: `naverSearchClientId`/`naverSearchClientSecret`
    (신규) — 지도 탭 표시용 `naverMapClientId`(NCP Maps)와는 완전히 별개로,
    Naver Developers(developers.naver.com/apps)에서 발급받는 검색 API
    애플리케이션의 Client ID/Secret.
  - `Views/SettingsView.swift`/`ViewModels/SettingsViewModel.swift`: "Naver
    검색 API (선택)" 섹션(신규) 추가 — 설정하지 않으면 기존처럼 Google로만
    검증됨(하위 호환).
#### Changed
- `ViewModels/PlaceCardViewModel.swift`: `search(rowID:)`가 이제 공유 출처에
  따라 검증 대상을 나눈다 — `resolveSharedPlace`가 알아낸 출처가
  네이버 공유(`.naverMapShare`)이고 Naver 검색 API 키가 설정돼 있으면
  `NaverPlaceSearchService`로, 그 외(구글 공유·직접 입력·Naver 키 미설정)는
  기존처럼 `searchViaGoogle`(새로 분리한 private 메서드, 로직은 동일)로 검증.
  - Google 경로의 주소/좌표 기반 100m 거리 필터 로직은 그대로 유지, 다만
    "찾았지만 그 주소 근처는 아님" vs "아예 없음" 에러 메시지 분기를 위해
    `SearchOutcome`(신규 private struct)으로 결과와 함께 반환하도록 정리.

### 2026-09-11 (91차) — 공유받은 링크에서 이름 외의 정보도 전부 추출
#### Changed
- `Services/SharedLinkParser.swift`: `ParsedSharedPlace`에 `address`/`coordinates`/
  `note` 필드를 추가하고, 구글·네이버 각각에서 실제로 뽑아낼 수 있는 정보를
  전부 채우도록 확장했다.
  - 네이버: 지금까지 태그 줄을 뗀 첫 줄(이름)만 쓰고 나머지 줄(주소, 기타
    상세정보)은 버렸는데, 이제 두 번째 줄을 주소로, 세 번째 줄부터는
    note로 담는다(그 안에 섞여 들어올 수 있는 URL 줄은 제외).
  - 구글: 공유되는 건 URL 하나뿐이지만, 축약되지 않은 전체 링크
    (`.../maps/place/<이름>/@<위도>,<경도>,<줌>z/...`)는 장소 이름과 정확한
    좌표를 URL 경로 자체에 이미 담고 있어서, 페이지를 따로 요청하지 않고도
    그 자리에서 바로 꺼낼 수 있다(`goo.gl` 축약 링크나 이 형식에 안 맞는
    링크는 기존처럼 `LinkMetadataFetcher`로 폴백).
- `ViewModels/PlaceCardViewModel.swift`: `resolveSearchQuery(from:) -> String`를
  `resolveSharedPlace(from:) -> ResolvedSharedPlace`(name/address/coordinates/note)로
  교체하고, `search(rowID:)`가 이 정보로 행의 빈 주소·메모 필드를 채운 뒤
  검색하도록 변경.
  - 위치 기준(ground truth)을 기존 "주소 문자열을 지오코딩"에서 "구글
    URL에서 뽑은 정확한 좌표가 있으면 그걸 우선 사용, 없으면 기존처럼
    주소를 지오코딩"으로 일반화 — 동명이인 장소를 걸러내는
    100m 반경 필터가 구글 공유 링크에서는 지오코딩 오차 없이 정확한
    좌표로 작동한다.
  - 이 변경은 `search(rowID:)`를 쓰는 모든 경로(수동으로 링크 붙여넣기 +
    "Google에서 검색", 지난 차수에서 추가한 공유 링크 자동 검색)에
    공통 적용됨 — 네이버든 구글이든 동일하게 동작.

### 2026-09-11 (90차) — 공유받은 링크를 열면 자동으로 검색·선택
#### Changed
- `Views/AddPlaceCardView.swift`: 구글맵/네이버맵에서 "공유"로 넘어온 링크가
  지금까지는 raw URL/텍스트가 그대로 이름 필드에 채워진 채로, 사용자가 직접
  "Google에서 검색"을 누르고 결과를 골라야 했다. 이미 구글/네이버 지도
  앱에서 장소를 특정해 보낸 것이므로 이 두 단계(검색 누르기·결과 고르기)를
  자동화했다.
  - `initialLinkRowID`(신규 `@State`)에 공유로 seed된 행의 ID를 기록해두고,
    화면이 뜨자마자 `.task`에서 `autoResolveInitialLinkIfNeeded()`가
    `PlaceCardViewModel.search(rowID:)`(수동 "Google에서 검색"과 완전히
    같은 경로 — `SharedLinkParser`/`LinkMetadataFetcher`로 이름을 알아낸
    뒤 Google Places로 검색)를 자동 실행.
  - 검색 결과가 정확히 1건일 때만 자동으로 그 결과를 선택
    (`chooseResult`) — 여러 건이면 이름만으로는 특정하기 부족하다는
    뜻이므로 기존처럼 사용자가 직접 고르게 둔다(동명이인 장소를 다른 곳으로
    잘못 저장하는 사고를 피하기 위함).
  - 사진 스캔이나 "+ 장소 추가"로 연 경우는 `initialLinkRowID`가 `nil`이라
    영향 없음.

### 2026-09-11 (89차) — Gateway에서도 선택한 모델에 따라 웹 검색으로 채우기 시도
#### Changed
- `Services/AIProvider.swift`: `GatewayProvider.searchWebForDetails`를 추가했다.
  Gateway 자체가 호스팅 웹 검색을 지원하는지는 여전히 문서화되어 있지 않지만
  (Peragra의 동일 게이트웨이 클라이언트도 `tools` 필드를 전혀 쓰지 않는 것으로
  확인됨), `GatewayModels.all`에 나열된 모델들은 게이트웨이 고유 모델이 아니라
  실제 벤더 모델(Claude, GPT 계열)을 하나의 chat-completions 엔드포인트로
  프록시한 것이므로, 선택된 모델 이름을 보고 그 벤더 고유의 웹 검색 도구
  정의를 요청에 함께 실어 보내도록 했다.
  - 모델 이름이 `claude`로 시작하면 `ClaudeProvider.searchWebForDetails`와
    동일한 `web_search` 도구 정의를 사용.
  - 모델 이름이 `gpt`로 시작하면 `OpenAIProvider.searchWebForDetails`와
    동일한 `web_search` 도구 정의를 사용.
  - 둘 다 아닌 커스텀/알 수 없는 모델은 기준으로 삼을 벤더가 없으므로
    기존과 같이 "지원하지 않음" 오류로 처리(기본값 유지).
  - 게이트웨이가 이 도구 필드를 실제로 인식해서 벤더에 전달해주는지는
    검증되지 않았다 — 반영이 안 되면 모델이 검색 없이 답을 지어낼 수
    있다는 점은 여전한 리스크이지만, 프로토콜 기본 문서 주석과 클래스 문서
    주석에 이 가정과 근거를 명시해두었다.
  - 프로토콜의 `searchWebForDetails` 문서 주석과 기본 구현의 오류 메시지도
    "Gateway는 아직 지원 안 함" 같은 단정적 문구 대신, 이제 Gateway가
    조건부로 지원됨을 반영하도록 갱신.

### 2026-09-11 (88차) — 웹 검색으로 채우기, Claude 외 다른 AI 제공자도 지원
#### Changed
- `Services/AIProvider.swift`: `searchWebForDetails`(수정 화면 "웹 검색으로
  채우기" 버튼이 호출하는 기능)를 그동안 `ClaudeProvider`만 실제로
  구현하고 있었는데, `OpenAIProvider`와 `GeminiProvider`에도 각각 호스팅된
  웹 검색 도구를 사용하는 실제 구현을 추가했다.
  - `OpenAIProvider`: Chat Completions가 아니라 Responses API
    (`POST /v1/responses`)를 별도로 호출하고 `tools: [{"type":
    "web_search"}]`를 지정, 응답의 `output` 배열에서 `type: "message"`인
    항목의 `content` 중 `type: "output_text"` 텍스트를 읽어 파싱한다.
  - `GeminiProvider`: `analyzePlaces`가 쓰는 `generateContent`가 더 이상
    grounding 도구를 문서화하지 않아, 새 Interactions API
    (`POST /v1beta/interactions`)를 대신 호출하고 `tools: [{"type":
    "google_search"}]`를 지정, 응답의 `steps` 중 `type: "model_output"`인
    항목들의 `content`에서 `type: "text"`인 마지막 텍스트를 파싱한다
    (도구를 여러 번 호출하는 turn에서 최종 답변은 마지막 텍스트 블록이라는,
    이미 Claude 쪽에 있던 것과 같은 규칙).
  - `GatewayProvider`는 의도적으로 그대로 두었다(기본 구현이 "지원하지
    않음" 오류를 던짐). 이 프록시가 실제로 어떤 기능을 지원하는지
    문서화되어 있지 않은 상태에서 `web_search` 같은 도구 필드를 추측해서
    보내면, 지원하지 않는 필드는 조용히 무시되고 모델이 검색 없이 지어낸
    답을 마치 실제로 웹 검색한 것처럼 반환할 위험이 있다고 판단했다.
    이러면 명확한 오류보다 오히려 더 나쁘다.
  - 프로토콜의 `searchWebForDetails` 문서 주석과 기본 구현의 오류 메시지도
    위 내용에 맞게 갱신.

### 2026-09-11 (87차) — 메모 필드를 별도 편집 모드 없이 바로 입력 가능하게
#### Changed
- `Views/PlaceCardDetailView.swift`: `memoSection`을 "편집" 연필
  버튼 + `MemoEditSheet`(신규 시트를 열어야 고칠 수 있던 방식)에서,
  화면에 있는 `TextField`(`axis: .vertical`)에 바로 타이핑할 수
  있는 방식으로 변경 — 이 화면의 다른 필드들과 달리 편집 모드 진입
  없이 그 자리에서 바로 입력됨. 매 글자마다 저장하면
  `storageService.save(card)`가 전체 JSON을 다시 쓰게 돼 낭비이므로,
  `@FocusState`로 필드가 포커스를 잃는 순간(다른 곳을 탭)에만 저장.
  포커스를 잃지 않은 채 화면을 벗어나는 경우(뒤로가기 등)를 대비해
  `.onDisappear`에도 안전장치로 저장을 한 번 더 걸어둠.
- `Views/PlaceCardDetailView.swift`: 이제 안 쓰는 `MemoEditSheet`
  구조체 삭제.
- `Services/Localization.swift`: 이제 안 쓰는 "메모 편집" 항목 제거.

### 2026-09-11 (86차) — 장소 상세 화면 맨 위에 대표 사진 추가
#### Added
- `Views/PlaceCardDetailView.swift`: `heroPhotoSection`(신규) — 이름/
  카테고리/주소가 나오기도 전, 화면 맨 위에 가로 전체 폭 배너로 대표
  사진 하나를 보여줌. `PlaceCardGridCell`/`PlaceCardListRow`가 이미
  쓰는 것과 같은 규칙(`officialPhotos.first ?? allItems.first`)으로
  고름. 탭하면 기존 `photosSection` 썸네일과 같은 전체화면
  스와이프 뷰어가, 그 사진이 실제 있는 위치(`heroPhotoIndex`)부터
  열림. 아래쪽 "사진" 가로 스크롤 목록(`photosSection`)은 그대로 두어
  전체 사진을 계속 훑어볼 수 있음 — 사진이 하나도 없으면 배너 자체가
  안 보임.

### 2026-09-11 (85차) — Home에 "카테고리별 보기", 갤러리에 리스트/그리드 전환
#### Added
- `Views/HomeView.swift`: 보드 목록 위에 "카테고리별 보기" 칩 행
  추가(`categoryBrowseSection`, 신규) — 모든 게시판을 통틀어 존재하는
  카테고리를 보여주고, 탭하면 갤러리 탭으로 이동하면서 그 카테고리로
  바로 필터링됨(어느 게시판 소속인지와 무관하게 전체에서).
- `Services/AppNavigation.swift`: `galleryCategoryFilter`(신규)와
  `showInGallery(category:)`(신규) — `mapFilterIDs`/`showOnMap(_:)`와
  같은 구조의 1회성 신호. `GalleryView`가 `.onChange`로 소비한 뒤 곧장
  nil로 되돌려서, 이후 갤러리 탭에 다시 들어올 때 필터가 멋대로
  재적용되지 않게 함.
- `Views/GalleryView.swift`: 툴바에 그리드/리스트 전환 버튼 추가
  (`GalleryLayout`, 신규 — `@AppStorage`로 유지). 리스트 레이아웃은
  `BoardDetailView.cardRow(_:)`와 동일한 상호작용(선택 모드 체크
  버튼, 스와이프 삭제)의 `listRow(_:)`(신규)를 사용 — 정렬·필터·
  선택은 레이아웃과 무관하게 그대로 유지됨. 카테고리 없이(즉 툴바
  탭이나 검색이 아니라 그냥) 갤러리에 들어오면 지금까지처럼 전체
  PlaceCard가 보임.

### 2026-09-11 (84차) — 버그 수정: 거리순 정렬 "현재 위치"에서 거리 안 뜨던 문제
#### Fixed
- `Services/LocationService.swift`: `LocationService` 클래스에
  `@MainActor` 추가 — `currentLocation()`/`fetch()`가 그 자체로는
  격리돼 있지 않아서, 이미 메인 액터에서 실행 중인 호출부
  (`PlaceStatusFilterBar`의 `Task { hereCoordinate = await
  LocationService.currentLocation() }`)에서 `await`하는 순간 Swift
  Concurrency 협력 스레드 풀의 임의 백그라운드 스레드로 넘어가
  `CLLocationManager`가 생성·구동됐음. `CLLocationManager`는 애플이
  메인 스레드에서 계속 다루도록 안내하는 API라, 그 스레드를 벗어나면
  delegate 콜백(권한 변경, 위치 업데이트)이 아예 안 불릴 수 있음 —
  이게 "거리순 정렬 → 현재 위치 선택"에서 거리가 끝내 안 나타나던
  실제 원인. 위치를 못 구하면 그냥 8초 타임아웃으로 조용히 nil
  처리되니 에러도 없이 증상만 있었음.

### 2026-09-11 (83차) — 검색창을 항상 표시, "이름/주소로 검색" 문구 정리
#### Changed
- `Views/HomeView.swift`/`GalleryView.swift`/`BoardDetailView.swift`/
  `PlacesMapView.swift`: `.searchable`에 `placement:
  .navigationBarDrawer(displayMode: .always)`를 명시 — 기본값
  (`.automatic`)은 스크롤하거나 아래로 당겨야 검색창이 나타나는데,
  이제 네 화면 모두 검색창이 항상 보임.
- `Views/BoardDetailView.swift`/`GalleryView.swift`의 검색창
  placeholder를 "이름, 주소로 검색"에서 "카드 검색"(Home과 동일한
  문구)으로 변경 — 검색 로직은 이미 81차에서 이름·주소만이 아니라
  카드 전체 필드를 단어 단위로 보도록 바뀌었는데 문구만 옛날 그대로
  남아있었음. 결과적으로 갤러리(그리드)와 게시판 상세(리스트)는
  이제 레이아웃 말고는 검색·툴바·선택 기능이 동일함.
- `Services/Localization.swift`: 이제 안 쓰는 "이름, 주소로 검색"
  항목 제거.

### 2026-09-11 (82차) — 갤러리에 게시판 상세와 동일한 중복찾기·내보내기·선택 추가
#### Added
- `Views/GalleryView.swift`: `BoardDetailView`의 툴바/선택 기능을
  그대로 이식 — "중복 찾기"(카드가 2개 이상일 때), "내보내기"
  (텍스트로 복사/파일로 공유), "선택"(다중 선택 모드 토글)을 툴바에
  추가. 선택 모드에서는 하단에 `bulkActionBar`가 뜨고 전체선택/해제·
  삭제·카테고리 변경·게시판 이동·지도에서 보기·병합을 지원 —
  `BoardDetailView.bulkActionBarControls`와 동일한 구성. 다만 갤러리는
  한 게시판에 묶여 있지 않으므로 "게시판 이동"은 (현재 보드 제외한
  "다른 게시판"이 아니라) 전체 게시판 목록을 보여줌. 그리드 셀도
  `BoardDetailView.cardRow(_:)`와 같은 이유로 `NavigationLink` 대신
  `.onTapGesture` + `.navigationDestination(item:)`로 전환(선택 모드가
  생기면서 탭의 의미가 두 가지가 됐고, 셀 자체의 즐겨찾기/방문 버튼도
  계속 독립적으로 눌려야 하기 때문).
- `ViewModels/GalleryViewModel.swift`: `scopedCards`를 `private`에서
  풀어 `GalleryView`가 "중복 찾기"에 쓸 수 있게 함(검색/상태/카테고리
  필터와 무관하게 현재 범위의 카드 전체를 봐야 하므로 — `filteredPlaceCards`가 아니라 이걸 사용).

#### Removed
- `Views/GalleryView.swift`: 80차에서 추가했던 툴바 "카테고리" 버튼
  제거 — 화면 상단의 `PlaceStatusFilterBar` 자체 카테고리 필터만
  남김.

### 2026-09-10 (81차) — 모든 검색을 카드 전체 필드·단어 단위 매칭으로 통일
#### Added
- `Models/PlaceCard.swift`: `matchesSearch(_:)`(신규) — 이름·주소뿐
  아니라 카테고리·메모·태그·편의시설·전화번호까지 합쳐서, 검색어를
  공백 기준으로 단어로 쪼갠 뒤 그 중 **하나라도** 카드 어딘가에
  있으면 매칭되게 함(예: "강남 카페"라고 치면 이름에 "카페"만 있고
  주소에 "강남"만 있어도 찾아짐 — 두 단어가 한 필드에 붙어있을
  필요가 없음).

#### Changed
- `Services/StorageService.swift`의 `search(query:tags:)`,
  `Views/BoardDetailView.swift`의 `searchFilteredCards`,
  `Views/HomeView.swift`의 `searchResultsBeforeCategoryFilter`,
  `Views/PlacesMapView.swift`의 `visibleCards` — 전부 이름/주소만
  보던 개별 필터 로직을 지우고 `PlaceCard.matchesSearch(_:)` 하나로
  통일. 결과적으로 갤러리·게시판 상세·Home 카드검색·지도 검색 네
  곳 모두 같은 기준으로 검색됨.

### 2026-09-10 (80차) — 카테고리 메뉴 안에 검색 추가
#### Added
- `Views/CategoryPickerSheet.swift`(신규): 카테고리 목록이 길어지면
  `Menu`를 눈으로 훑기 힘들어지는 문제를 해결 — `.searchable`이 붙은
  전체화면 `List`로, 타이핑하면 카테고리 이름을 바로 필터링. "전체"
  항목은 검색과 무관하게 항상 맨 위에 고정.

#### Changed
- `Views/PlaceStatusFilterBar.swift`의 `categoryMenu`, `Views/
  GalleryView.swift`의 툴바 "카테고리" 버튼 — 기존 `Menu` 대신 이
  `CategoryPickerSheet`를 `.sheet`로 띄우도록 변경(`Menu`는 콘텐츠가
  실제 텍스트 입력 포커스를 받을 수 없어서 검색창을 넣을 수 없었음).
  둘 다 같은 `categoryFilter` 상태를 바인딩하므로 동작은 그대로.

### 2026-09-10 (79차) — 갤러리 오른쪽 상단에도 카테고리 메뉴 추가
#### Added
- `Views/GalleryView.swift`: 기존 "태그" 메뉴(오른쪽 상단 툴바)
  옆에 "카테고리" 메뉴를 추가 — 같은 스타일로 "전체" + 카테고리별
  버튼을 나열, `viewModel.categoryFilter`를 그대로 사용해 화면 상단의
  `PlaceStatusFilterBar` 카테고리 필터와 동일한 상태를 공유함(둘 중
  아무 데서나 바꿔도 서로 반영됨). 카테고리가 하나도 없으면(카드가
  없거나 전부 카테고리 미지정) 숨김. 태그 아이콘과 구분되도록
  "square.grid.2x2" 아이콘 사용.

### 2026-09-10 (78차) — Home의 검색을 게시판 검색에서 카드 검색으로 변경
#### Changed
- `Views/HomeView.swift`: 게시판 이름으로 게시판 목록을 필터링하던
  검색을 없애고, 검색어를 입력하면 **모든 게시판을 통틀어 이름·주소가
  일치하는 장소 카드**를 찾아 보여주도록 변경(`searchResultsList`,
  신규) — 결과가 있으면 `PlaceCategoryIcon.normalizedLabel`로 정규화한
  카테고리 칩(`searchCategoryChips`, 신규)이 목록 위에 나타나 그 검색
  결과 안에서 다시 카테고리로 좁힐 수 있음(`searchCategoryFilter`).
  카드를 탭하면 `PlaceCardDetailView`로 이동 — `BoardDetailView`가
  이미 쓰던 방식대로 `NavigationLink`로 행을 감싸지 않고
  `.onTapGesture` + `.navigationDestination(item:)`을 사용(그래야
  `PlaceCardListRow`의 즐겨찾기/방문 버튼이 `NavigationLink`에 눌림을
  뺏기지 않음). 검색어가 비어 있을 때는 기존처럼 전체 게시판 목록을
  보여줌. `Services/Localization.swift`: 이제 안 쓰는 "게시판 검색"
  항목 제거, 새 검색창 placeholder "카드 검색" 번역 추가.

### 2026-09-10 (77차) — 같은 빌드 오류를 SettingsView에서 선제적으로 수정
#### Fixed
- `Views/SettingsView.swift`: 75·76차와 같은 유형("unable to
  type-check this expression in reasonable time")이 날 것으로 예상돼
  선제적으로 수정 — `.localized` 호출이 57곳으로 이 프로젝트에서
  두 번째로 많고, 유일한 `var body`에 `Section`이 8개나 인라인으로
  들어있어 위험도가 가장 높은 파일이었음. `Form` 안의 각 `Section`을
  `appLanguageSection`/`googlePlacesAPISection`/`naverMapSection`/
  `aiImageAnalysisSection`/`scanResponseLanguageSection`/
  `backupSection`/`autoBackupSection`/`infoSection`(전부 신규,
  `@ViewBuilder`)로 분리. 원본과 새 파일에서 `.localized`로 감싸인
  문자열 목록을 뽑아 정확히 같은 집합인지 diff로 대조해 내용 유실이
  없음을 확인.

### 2026-09-10 (76차) — 빌드 오류 수정: BoardDetailView body 타입체크 시간 초과
#### Fixed
- `Views/BoardDetailView.swift`: 같은 "unable to type-check this
  expression in reasonable time" 오류가 `body`에서 발생. `Group { if
  allCards.isEmpty {...} else {...} }`를 `mainContent`(신규,
  `@ViewBuilder`)로, `List`의 `ForEach` 행 내용을 `cardRow(_:)`(신규)
  로, `.toolbar { ... }` 안의 여러 `ToolbarItem`을 `toolbarContent`
  (신규, `@ToolbarContentBuilder`)로 분리. 두 `confirmationDialog`의
  `"\"이름\"을 삭제할까요?"`/`"N개 ...` 문자열도(75차와 같은 `+` 체인
  패턴) `deleteCardConfirmationTitle`/`bulkDeleteConfirmationTitle`/
  `bulkDeleteConfirmationButtonTitle` 계산 프로퍼티로 분리. `body`
  자체는 이제 이 조각들을 조합하는 모디파이어 체인만 남음.

### 2026-09-10 (75차) — 빌드 오류 수정: body 타입체크 시간 초과
#### Fixed
- `Views/EditPlaceCardSheet.swift`, `Views/MapScreenshotImportSheet.swift`:
  Xcode에서 "The compiler is unable to type-check this expression in
  reasonable time" 오류 발생. 두 파일 모두 `.alert`의 `message:`에서
  `"고정 문구".localized + 변수 + "고정 문구".localized + ...` 식으로
  `+`를 여러 번 이어붙인 표현이 있었는데, 리터럴이던 문자열이
  `.localized`(비-리터럴 `String`)로 바뀌면서 컴파일러의 오버로드
  추론 부담이 커진 게 원인으로 보임 — 각각 `nameChangeAlertMessage`
  계산 프로퍼티로 빼서 `let`으로 한 단계씩 나눠 대입하도록 변경.
  `EditPlaceCardSheet.swift`는 추가로 `body`의 `Form { ... }` 안에
  있던 나머지 9개 `Section`도 전부 `basicInfoSection`/
  `coordinatesSection`/`contactSection`/`ratingSection`/
  `statusSection`/`businessHoursSection`/`tagsSection`/
  `amenitiesSection`/`memoSection`(신규, 전부 `@ViewBuilder`)로
  분리 — 기존에 이미 있던 `photoImportSection`/`webSearchSection`과
  같은 패턴. `body` 자체는 이제 이 서브뷰들을 나열만 하는 짧은
  표현이라 타입체크 부담이 훨씬 작음.

### 2026-09-10 (74차) — 빌드 오류 수정: AutoBackupService의 actor 격리
#### Fixed
- `Services/AutoBackupService.swift`: `resolveFolderURL()`에 `@MainActor`
  추가 — `BackupFolderSettings`(`@MainActor` `ObservableObject`)의
  `folderBookmark`/`setNeedsReauthorization(_:)`/`setFolder(bookmark:
  displayName:)`를 호출하면서 정작 자신은 격리되지 않은 `private
  static func`라서, Xcode에서 실제로 빌드하니 "Main actor-isolated
  property/method ... can not be referenced from a nonisolated context"
  3건이 발생함. 유일한 호출부인 `runNow(storageService:)`가 이미
  `@MainActor`라 이 변경으로 새로 퍼지는 격리 요구사항은 없음.

### 2026-09-10 (73차) — Google Places 검색 결과도 "앱 언어"를 따르게
#### Changed
- `Services/PlaceSearchService.swift`: `GooglePlacesService.search(query:
  coordinates:)`(요청 body)와 `.details(placeId:)`(쿼리 파라미터)에
  Google Places API (New)의 `languageCode`를 명시적으로 추가 —
  `AppLanguage.current().googlePlacesLanguageCode`(신규 private
  extension, 한국어→"ko", English→"en"). 이전에는 이 필드가 비어 있어
  Google이 요청의 `Accept-Language` 헤더(iOS 시스템 언어를 따라
  `URLSession`이 자동으로 붙이는 값, 이 앱의 설정과 무관)에 맡겨져,
  "앱 언어"를 English로 바꿔도 검색으로 채워지는 가게 이름·주소는
  기기 시스템 언어를 따라가던 불일치가 있었음. 이제 앱 화면·AI
  응답·Google 검색 결과 세 경로 모두 이 앱 자체의 언어 설정을 따름.

### 2026-09-10 (72차) — 앱 UI 자체의 언어도 변경 가능하게
#### Added
- `Services/Localization.swift`(신규): `AppLanguage`(한국어/English) —
  앱 화면 전체의 언어. `LocalizationObserver`(싱글턴 `ObservableObject`)
  는 `ContentView`가 `.id(localization.language)`로 구독해, 언어를
  바꾸면 앱 전체 뷰 트리를 즉시 다시 마운트 — 재실행 없이 바로 반영됨.
  `String.localized`(신규 extension) — 어디서든 `"한글 문구".localized`
  로 호출하면 현재 `AppLanguage`에 맞는 번역, 없으면 원문(한국어)을
  반환. `Localization.englishTranslations`에 앱 전역 약 280개 한국어
  UI 문구 전체의 영어 번역을 보관.
  Xcode 없이 검증해야 하는 이 환경 특성상 String Catalog(`.xcstrings`)
  대신 평범한 Swift 딕셔너리로 구현 — 스키마 실수가 조용히 무시되는
  대신 이 환경이 실제로 검사할 수 있는 형태(중괄호/괄호 균형, 중복
  선언 스캔)를 유지하기 위함.
- `Views/SettingsView.swift`: 맨 위에 "앱 언어" Picker 섹션 추가.

#### Changed
- 21개 View 파일 + 다수 Service/ViewModel 파일: 하드코딩되어 있던
  한국어 UI 문구(네비게이션 타이틀, 버튼, 라벨, 섹션 헤더/푸터, 알림,
  플레이스홀더, 탭 이름 등) 전부에 `.localized` 적용. 이름/주소/메모
  등 사용자가 입력한 실제 데이터는 그대로 두고 건드리지 않음.
  `Views/GoogleMapWebView.swift`/`NaverMapWebView.swift`: WKWebView에
  내장된 HTML/JS 안의 안내 문구·버튼 라벨(지도를 못 불러왔을 때 표시,
  "카드 보기", "Google/Naver/Kakao/Tmap에서 열기")도 Swift 쪽에서
  `.localized`로 번역해 JSON으로 주입하도록 변경.
- `Services/PlaceCardSorting.swift`: `PlaceSortMode`의 `rawValue`(정렬
  기준 식별자, 유지되어야 함)는 그대로 두고, 화면에 보여줄 `displayName`
  (신규, `rawValue.localized`)을 따로 추가 — enum의 raw value 자체는
  컴파일타임 상수여야 해서 `.localized`를 직접 쓸 수 없었음.
- `PlaceCards.xcodeproj/project.pbxproj`: `Localization.swift` 등록.

#### Note
- 자동 변환 스크립트로 1차 처리한 뒤, 이스케이프된 따옴표나 문자열
  보간이 섞인 ~45곳은 전부 손으로 다시 확인·수정 — 그 과정에서
  `PlaceSortMode`의 raw value에 `.localized`가 잘못 붙어 컴파일이 깨질
  뻔한 문제, 그리고 자동 변환 스크립트 자체의 정규식이 이스케이프된
  따옴표를 오인식해 문자열이 깨질 뻔한 사례 몇 건을 발견해 바로잡음.

### 2026-09-10 (71차) — 설정에 "AI 응답 언어" 추가
#### Added
- `Services/AIProvider.swift`: `ScanResultLanguage`(신규, 한국어/영어/
  일본어/중국어) — 사진 스캔·웹 검색으로 채워지는 카테고리·메모 같은
  자유 텍스트를 어떤 언어로 쓸지 결정. `UserDefaults`에 저장, 인스턴스
  없이 `.current()`로 조회하는 방식은 `SettingsViewModel
  .currentAIProviderType()`와 동일한 패턴. 앱 화면 자체의 언어(한국어
  하드코딩)는 이번 범위에 포함하지 않음 — 30개 이상 View 파일의 전면
  현지화는 실제 빌드/시뮬레이터 없이는 검증이 사실상 불가능한 별개의
  큰 작업이라 판단.
- `Views/SettingsView.swift`: "AI 응답 언어" Picker 섹션 추가(별도
  저장 버튼 없이 선택 즉시 저장 — API 키처럼 확인이 필요한 값이
  아니므로).

#### Changed
- `Services/AIProvider.swift`: `defaultPlaceAnalysisPrompt`(상수) →
  `defaultPlaceAnalysisPrompt()`(함수)로 변경 — 매번 현재
  `ScanResultLanguage`를 반영해 프롬프트 끝에 언어 지시문을 덧붙임
  (한국어 선택 시엔 원래 프롬프트가 이미 한국어 응답을 전제하므로
  아무것도 덧붙이지 않음). JSON 키 이름은 그대로 두고 값만 대상
  언어로 쓰도록 명시. 호출부 3곳(`PlaceCardViewModel.analyzeImages`,
  `EditPlaceCardSheet.analyzePickedPhotos`,
  `MapScreenshotImportSheet`)을 `defaultPlaceAnalysisPrompt()` 호출로
  갱신.
- `Services/AIProvider.swift`: `webDetailsSearchPrompt(for:)`도 같은
  방식으로 언어 지시문을 덧붙이도록 변경.
- `ViewModels/SettingsViewModel.swift`: `scanResultLanguage` 프로퍼티
  추가, `didSet`에서 즉시 저장.

### 2026-09-10 (70차) — Naver 지도 마커 아래에도 이름 표시
#### Changed
- `Views/PlacesMapView.swift`: `naverMarkerContentHTML(for:)`(신규) —
  카테고리 배지(`PlaceCategoryIcon.markerGlyphHTML`) 아래에 장소
  이름을 캡슐 라벨로 추가. Naver 지도는 PlaceCards 소유가 아닌
  Peragra 저장소가 호스팅하는 공용 페이지(`naver-map-embed.html`)를
  그대로 쓰고 있어서(이번에 Peragra 저장소는 건드리지 않기로 함) —
  그 페이지가 고정된 24×24 박스에 raw HTML로 끼워 넣는 방식이라,
  배지는 이전과 동일한 24×24 `position: relative` 박스에 그대로 두고
  라벨은 `position: absolute; top: 100%`로 그 박스 아래에 얹는 방식을
  써서, 페이지 쪽의 앵커 좌표·정렬 계산을 전혀 건드리지 않고도
  라벨을 붙임.
- `Views/NaverMapWebView.swift`: `MarkerPlace.emoji`의 문서 주석을
  실제로 채우는 함수(`PlacesMapView.naverMarkerContentHTML`)에 맞게
  갱신.

### 2026-09-10 (69차) — Google 지도 마커 아래에도 이름 표시
#### Changed
- `Views/GoogleMapWebView.swift`: `NameLabelOverlay`(JS, 신규) — Apple
  지도처럼 각 마커 핀 아래에 장소 이름을 작은 캡슐 라벨로 항상
  표시. `Marker.label`은 핀 안에 짧은 글자만 넣을 수 있어(이름 전체를
  핀 아래에 두는 용도로는 못 씀) 별도의 `google.maps.OverlayView`
  텍스트 오버레이를 마커마다 하나씩 추가하는 방식으로 구현 —
  클릭은 `pointer-events: none`으로 그대로 핀에 통과되어, 탭하면
  뜨는 기존 정보창(이름/주소/"카드 보기") 동작은 그대로 유지됨.

### 2026-09-10 (68차) — Apple 지도 마커도 Google·Naver처럼 탭하면 정보 팝업부터
#### Changed
- `Views/PlacesMapView.swift`: Apple 지도에서 마커를 탭하면 바로
  전체 카드가 열리던 것을, Google/Naver 지도(WKWebView 페이지의
  마커 정보창)와 같은 2단계 흐름으로 변경 — 먼저 이름·주소와 "카드
  보기" 버튼이 있는 작은 팝업(콜아웃)이 뜨고, 그 버튼을 눌러야 전체
  화면 카드가 열림. 같은 마커를 다시 탭하면 팝업이 접힘.

### 2026-09-10 (67차) — 지도에서 카드 선택 시 전체화면으로 열기
#### Changed
- `Views/PlacesMapView.swift`: 마커를 탭해 `PlaceCardDetailView`를 열
  때 `.sheet` 대신 `.fullScreenCover`를 사용 — 위쪽에 지도가 살짝
  보이던 카드형 시트 대신 화면 전체를 채워서 열림. `fullScreenCover`
  는 스와이프로 닫히지 않아서 "닫기" 버튼을 추가함(갤러리·게시판
  상세에서 여는 건 push 방식이라 영향 없음).

### 2026-09-10 (66차) — 상세보기에서 메모 바로 편집
#### Added
- `Views/PlaceCardDetailView.swift`: `memoSection`이 메모가 없어도
  항상 표시되도록 바뀌고("메모 없음" 플레이스홀더), 옆에 편집(연필)
  버튼이 생김 — 눌러서 나오는 `MemoEditSheet`(신규)로 메모만 바로
  작성/수정하고 저장. 전체 편집 시트(`EditPlaceCardSheet`)를 열지
  않고도 메모 한 줄을 고칠 수 있게 함.

### 2026-09-10 (65차) — Unsplash 연동 삭제
#### Removed
- `Services/UnsplashImageService.swift` 파일 삭제.
- `ViewModels/PlaceCardViewModel.swift`: `fetchOfficialPhoto`에서
  Unsplash 폴백(마지막 수단 썸네일 검색) 제거 — Google 사진만 시도.
  `hasExistingPhoto` 파라미터는 Unsplash 게이트에만 쓰였어서 같이
  제거. `createManualPlaceCard`는 (`googlePhotoName`이 항상 nil이라)
  이 함수 호출 자체가 Unsplash 전용이었으므로 호출을 통째로 제거하고,
  더 이상 await할 게 없어진 함수 자체도 `async` 제거.
- `Services/KeychainService.swift`: `KeychainKey.unsplashAccessKey` 제거.
- `ViewModels/SettingsViewModel.swift`: `unsplashAccessKey`,
  `currentUnsplashAccessKey()`, `saveUnsplashAccessKey()` 제거.
- `Views/SettingsView.swift`: "Unsplash 이미지 검색 (선택)" 섹션 제거.

#### Changed
- `Models/MediaModels.swift`: `SourceType.unsplashSearch`는 케이스
  자체는 유지(신규 생성 경로는 전부 제거됐지만, 이미 저장된 카드에
  이 값을 가진 사진이 있으면 non-optional `MediaItem.source` 디코드가
  실패해 `StorageService.loadPlaceCards()`가 카드 배열 전체를 조용히
  비워버림 — 이전 세션들에서 반복 확인된 것과 같은 decode-safety
  원칙). 문서 주석에 레거시 전용이라는 점과 그 이유를 명시.

### 2026-09-10 (64차) — 상세보기에 사진 표시, 정보 출처·추가한 날짜 제거
#### Added
- `Views/PlaceCardDetailView.swift`: "사진" 섹션(신규) — 카드의 모든
  미디어(`media.allItems` — 지도 스크린샷/공식 사진/현장 촬영/전달받은
  사진 전부)를 가로 스크롤 썸네일로 표시. 탭하면 `PhotoViewerSheet`
  (신규)로 전체화면 스와이프 뷰어가 열림. 지금까지 상세보기 화면
  어디에도 사진이 전혀 표시되지 않고 있었음.

#### Removed
- `Views/PlaceCardDetailView.swift`: "정보 출처" 섹션(`card.sources`/
  `discoverySource` 표시)과 메타 푸터의 "추가한 날짜" 줄 제거.
  "수정한 날짜"는 그대로 유지.

### 2026-09-10 (63차) — 장소 단위 공유·게시판 가져오기·조용한 iCloud 백업 (Peragra 이식 마무리)
#### Added
- `Services/SharePlaces.swift`(신규) — Peragra의 `SharePlaces`를 이식.
  `BackupService`와 별도의, 개인정보를 뺀 가벼운 공유 포맷
  (id·좌표·방문/즐겨찾기·태그·미디어 제외 — name/category/address/
  phone/notes(=memo)/linkURL(=website)만). `BoardDetailView` 툴바의
  "내보내기" 메뉴(신규, 텍스트로 복사 / 파일로 공유)에서 사용 —
  현재 필터링된 `cards`를 대상으로 함.
- `Services/BackupService.swift`: `decode(_:)`(신규, app 태그 확인
  포함, `restore`도 이걸 재사용하도록 정리)와 `importBoard(_:storageService:)`
  (신규) 추가. `importBoard`는 게시판·장소 전부에 새 UUID를 부여하는
  추가(additive) 가져오기 — "백업에서 복원"(전체 교체)과 달리 기존
  데이터를 건드리지 않음. Peragra의 `importBoard(_:context:)` 이식.
- `Views/ImportBoardSheet.swift`(신규) — Peragra의 `ImportBoardSheet`
  이식. 텍스트 붙여넣기 또는 파일 선택 → 게시판별 장소 개수 미리보기
  → 확인 후 가져오기. 홈 화면 "추가" 메뉴(기존 "새 게시판" 버튼을
  메뉴로 변경)에 "게시판 가져오기"로 진입.
- `Services/CloudBackupService.swift`(신규) — Peragra의
  `CloudBackupService` 이식. 사용자가 누르는 버튼 없이, 앱의 iCloud
  컨테이너에 `placecards_auto_backup.json` 스냅샷을 계속 덮어씀
  (포그라운드/백그라운드 전환마다). 콜드 스타트 시 로컬에 게시판이
  하나도 없을 때만 자동 복원 시도(정상적으로 비어있는 첫 설치를
  잘못 덮어쓰지 않도록) — 복원되면 "iCloud에서 복원됨" 알림 표시.
  이 기능은 iCloud 컨테이너 entitlement가 실제로 프로비저닝되어
  있어야 동작하며, 안 되어 있으면 각 호출이 조용히 아무 일도
  하지 않음(App Group 때와 같은 종류의 Xcode/Apple Developer 계정
  설정이 필요 — Signing & Capabilities에서 iCloud 추가 및 팀 지정).
- `PlaceCards.entitlements`/`project.pbxproj`: iCloud 컨테이너
  (`iCloud.com.mrnoh99.PlaceCards`, CloudDocuments) entitlement와
  `com.apple.iCloud` SystemCapabilities 추가(PlaceCards 앱 타겟에만
  — 공유 확장에는 불필요).
- `Views/MainTabView.swift`: `.task`/`.onChange(of: scenePhase)`에서
  콜드 스타트 시 `restoreFromCloudIfNeeded()`, 포그라운드·백그라운드
  전환마다 `CloudBackupService.backup` 호출 — Peragra의
  `TripsListView`와 동일한 트리거 지점.

### 2026-09-10 (62차) — 내보내기·백업/복원·자동 백업 (Peragra 이식)
#### Added
- `Services/BackupService.swift`(신규) — Peragra의 `BackupService`를
  이식. `BackupData`(app/version 태그 + `[Board]`/`[PlaceCard]`,
  ISO8601·pretty-printed·sortedKeys JSON)를 중심으로 `exportData`
  (전체 백업), `exportBoard`(게시판 하나만, "내보내기"용),
  `restore`(전체 교체 — app 태그만 확인하고 version은 강제하지 않음,
  Peragra와 동일). `Board`/`PlaceCard`가 이미 plain `Codable`이라
  Peragra처럼 별도 Backup 전용 구조체로 필드를 일일이 재선언할 필요는
  없었음. `BackupDocument: FileDocument`(신규)로 `.fileExporter` 연동.
  Peragra와 마찬가지로 사진 파일 자체는 포함하지 않음(같은 기기에서
  복원할 때만 정상 표시 — Peragra는 애초에 미디어 모델이 없어 이
  경계가 명확하지 않았던 부분이라 문서 주석·설정 화면 문구로 명시).
- `Services/StorageService.swift`: `replaceAll(boards:placeCards:)`
  (신규) — 복원 전용. 복원된 데이터가 더 이상 가리키지 않는 미디어
  파일만 삭제(같은 기기 복원 시 아직 남아있는 사진을 실수로 지우지
  않도록).
- `Models/BackupFolderSettings.swift`(신규) — Peragra의
  `BackupFolderSettings`를 이식(`@Observable` 대신 이 앱의 다른
  설정 클래스들과 같은 `ObservableObject` 싱글턴). 폴더의 보안
  스코프 북마크, 자동 백업 on/off, 주기(일/주), 마지막 백업 시각,
  재인증 필요 여부를 UserDefaults에 저장.
- `Services/AutoBackupService.swift`(신규) — Peragra의
  `AutoBackupService`를 이식. `runNow`/`runIfDue`. Peragra처럼
  `BGTaskScheduler`/진짜 백그라운드 실행은 쓰지 않고(둘 다 관련
  entitlement가 없음), 앱이 열릴 때(콜드 스타트·포그라운드 전환)
  마지막 백업 이후 설정한 주기가 지났는지만 확인.
- `Views/MainTabView.swift`: `.task`/`.onChange(of: scenePhase)`에서
  `AutoBackupService.runIfDue` 호출 — Peragra의 `TripsListView`와
  동일한 트리거 지점.
- `Views/SettingsView.swift`: "데이터"(전체 백업/복원,
  `.fileExporter`+`.fileImporter`+되돌릴 수 없다는 확인 다이얼로그)와
  "자동 백업"(폴더 선택 `.fileImporter(allowedContentTypes: [.folder])`
  로 보안 스코프 북마크 생성, 토글, 주기 세그먼트, 마지막 백업 표시,
  지금 백업/폴더 변경/끄기 버튼) 섹션 추가 — Peragra의 `SettingsSheet`
  구조를 그대로 따름.
- `Views/HomeView.swift`: 게시판 행에 "내보내기"(신규, leading
  swipe action) — Peragra의 `ExportBoardMenu`를 이식. 텍스트로
  복사(pasteboard) / 파일로 공유(`ShareLink`, `BackupService
  .exportBoard`로 만든 게시판 단위 JSON) 메뉴.
- 이번에 이식한 범위는 요청한 3가지(내보내기/백업·복원/자동 백업
  예약)로 한정 — Peragra에 더 있는 장소 단위 공유(`SharePlaces`)·
  게시판 가져오기(`ImportBoardSheet`)·조용한 iCloud 안전망
  (`CloudBackupService`)은 이번엔 포함하지 않음.

### 2026-09-10 (61차) — 홈·게시판 상세·지도에 검색 추가
#### Added
- `Views/HomeView.swift`: `.searchable`(신규) — 게시판 이름/부제목으로
  검색. 갤러리는 이미 검색이 있었고(`GalleryView`), Settings을 제외한
  나머지 화면(홈·게시판 상세·지도)에는 없었던 것을 채움.
- `Views/BoardDetailView.swift`: `.searchable`(신규) — 이름/주소로
  검색. `GalleryViewModel`과 동일하게 검색 결과가 상태 칩 개수에도
  반영되고(카테고리 선택지 자체는 검색과 무관하게 그대로 유지),
  결과가 없으면 `ContentUnavailableView.search` 표시.
- `Views/PlacesMapView.swift`: `.searchable`(신규) — 이름/주소로
  지도 위 마커를 좁힘(기존 게시판 범위/"지도에서 보기" 필터 위에
  추가로 적용). Apple 지도는 첫 번째 일치 결과로 카메라도 이동함 —
  Google/Naver 지도는 WKWebView라 이 화면에서 카메라를 직접 움직일
  방법이 없어 마커가 좁혀지는 것만 적용됨.

### 2026-09-10 (60차) — 갤러리·지도가 홈의 현재 게시판을 따라감
#### Added
- `Services/AppNavigation.swift`: `currentHomeBoardID`(신규) — 홈 탭이
  현재 어느 게시판 안에 들어가 있는지(게시판 목록이면 nil) 추적.
  `HomeView`(목록으로 돌아올 때 비움)와 `BoardDetailView`(들어갈 때
  채움)가 각자의 `.onAppear`로 갱신 — 게시판 안에서 장소 상세보기로
  더 들어가도(그 화면이 `BoardDetailView`를 덮는 것일 뿐 홈 목록
  자체가 다시 나타나는 게 아니므로) 게시판 범위가 풀리지 않음.
- `ViewModels/GalleryViewModel.swift`: `boardScopeID`(신규) — 설정되면
  검색·태그·카테고리·거리 기준 등 모든 파생 목록이 그 게시판으로
  좁혀짐(칩 개수까지 일관되게).
- `Views/GalleryView.swift`: 탭이 보일 때마다(`onAppear`/`onChange`)
  `navigation.currentHomeBoardID`를 `viewModel.boardScopeID`로 동기화.
  범위가 있으면 내비게이션 타이틀에 게시판 이름 표시("갤러리 ·
  게시판명").
- `Views/PlacesMapView.swift`: `visibleCards`가 기존 `mapFilterIDs`
  (게시판의 "지도에서 보기" 일회성 액션, 여전히 우선)에 이어
  `currentHomeBoardID`도 확인하도록 확장. 범위가 있으면 타이틀에
  게시판 이름 표시.
- 결과: 홈에서 특정 게시판에 들어가 있으면 갤러리·지도 탭도 그
  게시판의 장소만 보여주고, 홈이 게시판 목록(전체)이면 갤러리·지도도
  전체를 보여줌.

### 2026-09-10 (59차) — 카드 편집에 "웹 검색으로 채우기" 추가
#### Added
- `Services/AIProvider.swift`: `AIProvider.searchWebForDetails(name:address:)`
  (신규, 프로토콜에 기본 구현 포함) — 사진을 읽는 게 아니라 이름/주소로
  AI가 웹을 검색해 전화번호·웹사이트·카테고리·영업시간·휴무일·편의시설·
  그 외 메모거리를 찾아오는 새 경로. `ClaudeProvider`만 실제로 구현
  (Anthropic Messages API의 호스팅 `web_search` 툴 — `web_search_20260209`
  — 이용). 이 앱이 대화형 채팅 완성 요청으로 통신하는 나머지 세
  제공자(OpenAI/Gemini/Gateway)는 이 모양의 웹 검색 툴이 문서화되어
  있지 않아, 기본 구현이 "이 제공자는 지원하지 않음, Claude로 바꿔달라"는
  명확한 에러를 던짐 — 조용히 아무 것도 안 채우는 대신.
- `Views/EditPlaceCardSheet.swift`: "웹 검색으로 채우기" 섹션(신규) —
  이름/주소로 검색해 **비어 있는 항목만** 채우고(이미 값이 있으면
  건드리지 않음) 실제로 채운 항목 목록을 알려줌. 검색 결과의 그 외
  정보는 사진 스캔과 동일하게 `PlaceCard.combinedMemo`로 메모에 합쳐짐.

### 2026-09-10 (58차) — 사진 스캔의 이름/주소 외 정보를 메모로 수집
#### Added
- `Services/AIProvider.swift`: `defaultPlaceAnalysisPrompt`가
  이름/주소로 담기지 않는, 나중에 참고할 만한 내용(해시태그, 한줄평·
  추천 이유 등, 예: "#한끼식사됨")을 `description`에 담도록 명시적으로
  요청하도록 수정. 이 필드는 이미 AI 응답에서 추출되고 있었지만
  지금까지는 어디에도 쓰이지 않고 버려지고 있었음 — 스캔의 목적이
  이름/주소 확인만이 아니라 카드에 남길 만한 정보를 최대한 모으는
  것이므로, 그 정보가 갈 곳(메모 필드)을 만듦.
- `Models/PlaceCard.swift`: `combinedMemo(_:appending:)`(신규) — 스캔한
  메모를 기존 메모에 새 줄로 덧붙이되(덮어쓰지 않음) 이미 있는
  내용이면 중복 추가하지 않는 공용 로직. 아래 세 곳에서 재사용.
- `ViewModels/PlaceCardViewModel.swift`: `PlaceCandidateRow.scannedNote`
  (신규) — AI가 스캔한 추가 정보를 담고, "장소 추가" 화면에서 수정도
  가능. `createCards()`가 이 값을 `createPlaceCard(from:...:note:)`/
  `createManualPlaceCard(...:note:)`에 전달해 최종 카드의 `memo`로
  저장함. Google 검색 결과를 선택한 경우 이름·주소·좌표 등은 Google
  쪽 정보가 우선하고, 사진에서 스캔한 메모만 별도로 합쳐짐.
- `Views/AddPlaceCardView.swift`: 후보 행마다 "메모 (선택)" 입력란
  추가 — AI가 채워주거나, 직접 입력/수정 가능.
- `Views/EditPlaceCardSheet.swift`/`Views/MapScreenshotImportSheet.swift`:
  카드 편집 중 사진으로 AI 정보를 읽어올 때도 `description`을 메모에
  같은 방식으로 합침(기존엔 두 곳 다 이름/주소만 채우고 나머지는
  버렸음).

### 2026-09-10 (57차) — 장소 검색에 주소 기반 100m 거리 검증 추가
#### Changed
- `ViewModels/PlaceCardViewModel.swift`: `search(rowID:)`가 이름만으로
  검색하면 너무 넓은 지역(동명의 다른 지점 등)이 걸린다는 피드백에
  따라, 행에 주소가 있으면 (1) 검색어 자체에 주소를 붙여
  ("이름 주소") Google이 더 정확히 좁혀 찾도록 하고 (2) 그 주소를
  따로 지오코딩해 각 검색 결과와의 거리를 계산, 100m
  (`maxAddressMatchDistanceMeters`) 밖이면 결과에서 제외함. 필터링
  후 결과가 비면 "\"주소\" 근처 100m 이내에서 찾지 못했습니다"로
  원인을 명확히 표시. 주소가 비어 있으면 기존과 동일하게 이름만으로
  검색(동작 변화 없음).
- `Services/PlaceSearchService.swift`: `GooglePlacesService
  .geocodeAddress(_:)`(신규) — 주소 문자열의 좌표를 얻기 위해 별도의
  Geocoding API 대신 이미 쓰고 있는 Text Search(`searchText`)를
  재사용해, 추가 API 활성화 없이 동작함.

### 2026-09-10 (56차) — Naver 지도 마커를 미니멀 아웃라인 아이콘으로 변경
#### Changed
- `Services/PlaceCategoryIcon.swift`: `emoji(for:)`를
  `markerGlyphHTML(for:)`로 교체 — 컬러 이모지(☕🍴🏨🍷🛍️🖼️🌳📍)가
  지도 위에서 잘 안 보인다는 피드백에 따라, 앱 다른 곳의 SF Symbol과
  같은 스타일(얇은 선, 채우기 없음)의 인라인 SVG 아이콘으로 교체하고,
  지도 배경과 대비되도록 흰 원형 배지 안에 넣음. `naver-map-embed.html`
  이 이 필드를 raw HTML로 그대로 이어붙이는 구조라 이모지 문자
  대신이어도 동일하게 동작함(필드명 `emoji`는 그 페이지의 payload
  형태를 맞추기 위해 그대로 유지).
- `Views/NaverMapWebView.swift`/`Views/PlacesMapView.swift`: 새 함수
  이름에 맞춰 호출부·문서 주석 갱신.

### 2026-09-10 (55차) — 지도 탭 Naver 지도에 "undefined" 마커 라벨 표시 수정
#### Fixed
- `Views/NaverMapWebView.swift`: `MarkerPlace`에 `emoji` 필드가 없어서,
  Peragra가 호스팅 중인 공용 임베드 페이지(`naver-map-embed.html`)가
  마커 아이콘 HTML에 `place.emoji`를 그대로 이어붙이며 모든 마커에
  문자 그대로 "undefined"가 찍혔음(정보 팝업의 이름/주소는 별도
  필드라 정상 표시됨). 그 페이지는 Peragra용으로 작성되어 이 필드가
  없을 수 있다는 걸 가정하지 않음.
- `Services/PlaceCategoryIcon.swift`: `emoji(for:)`(신규) — 기존
  `symbolName(for:)`와 같은 카테고리 분류를 SF Symbol 대신 실제
  이모지 문자로 반환. 마커 아이콘이 일반 HTML 문자열이라 SwiftUI
  `Image`를 못 쓰는 이 한 곳을 위한 것.
- `Views/PlacesMapView.swift`: `naverMarker(for:)`가 `emoji:
  PlaceCategoryIcon.emoji(for: card.category)`를 채우도록 수정.

### 2026-09-10 (54차) — 공유 확장에 링크(URL/텍스트) 공유 지원 추가
#### Added
- `PlaceCardsShare/Info.plist`: `NSExtensionActivationRule`에
  `NSExtensionActivationSupportsWebURLWithMaxCount`/
  `NSExtensionActivationSupportsText` 추가 — 지금까지는 이미지만
  받도록 되어 있어서, "구글에서 열기"로 지도를 연 상태에서 스크린샷을
  찍으면 iOS가 자동으로 띄우는 "이 페이지(maps.google.com) 공유"
  시트(이미지가 아니라 URL을 공유하는, 스크린샷 공유와는 다른 별도
  흐름)에는 PlaceCards가 아예 뜨지 않았음(Peragra는 이미 지원해서
  뜸). 이제 그 시트에서도 PlaceCards가 표시됨.
- `PlaceCardsShare/ShareViewController.swift`: 첨부가 이미지인지
  URL/텍스트인지에 따라 `handleImageAttachment`/`handleLinkAttachment`
  로 분기하도록 재구성. 링크·텍스트는 문자열 그대로
  `SharedImportStore.savePendingLink`에 저장.
- `Services/SharedImportStore.swift`: `savePendingLink`/`takePendingLink`
  (신규) — 이미지용 pending 슬롯과 별도 파일이라 이미지 공유와 링크
  공유가 연달아 와도 서로 덮어쓰지 않음.
- `Views/SharedLinkBoardPickerSheet.swift`(신규): `SharedPhotoBoardPickerSheet`
  와 동일한 구조로, 공유받은 링크를 추가할 게시판을 고르면
  `AddPlaceCardView`를 그 링크가 이미 채워진 채로 엶.
- `Views/AddPlaceCardView.swift`: `initialLinkText` 파라미터(신규) —
  받은 링크를 새 행의 "장소명" 필드에 그대로 넣어, 이미 있던 "링크를
  직접 붙여넣고 Google에서 검색" 흐름(`PlaceCardViewModel.search(rowID:)`
  → `SharedLinkParser`)을 그대로 재사용함. 새로운 파싱 로직을 따로
  만들지 않음.
- `Views/MainTabView.swift`: `checkForSharedImage()`가 대기 중인 링크도
  함께 확인해 `SharedLinkBoardPickerSheet`를 띄우도록 확장. 사진
  흐름과 달리 `MapOpenContext`(최근에 "지도에서 열기"한 카드에 바로
  반영)는 적용하지 않음 — 링크는 장소 *이름*으로 해석되는 데이터라
  기존 카드의 특정 필드에 채워 넣을 대상이 명확하지 않고, 새 카드를
  만드는 기존 흐름과 훨씬 자연스럽게 맞아서.

### 2026-09-10 (53차) — 공유 확장이 아예 실행되지 않던 근본 원인 수정
#### Fixed
- `PlaceCardsShare/Info.plist`: `NSExtensionPrincipalClass`가
  `ShareViewController`로만 되어 있었음 — Swift 클래스는 기본적으로
  모듈명이 붙은 이름(`PlaceCardsShare.ShareViewController`)으로
  컴파일되는데, 접두사 없는 문자열로는 iOS가 `NSClassFromString`으로
  실제 클래스를 찾지 못해 확장 프로세스가 `ShareViewController`를
  아예 생성하지 못했음. 그 결과 공유 시트에서 PlaceCards를 눌러도
  `viewDidLoad`가 전혀 실행되지 않아 — 52차에서 추가한 스피너/상태
  메시지도, 진단 로그도 전혀 안 나온 것으로 설명됨(둘 다 그 안의
  코드라 애초에 실행된 적이 없었음). 코드사인(51차)과는 별개의,
  진짜 근본 원인이었던 것으로 보임. Xcode가 확장 타겟을 자동
  생성할 때 쓰는 표준 형식인 `$(PRODUCT_MODULE_NAME).ShareViewController`
  로 수정.

### 2026-09-10 (52차) — 공유 확장에 진행 상태 표시 추가
#### Changed
- `PlaceCardsShare/ShareViewController.swift`: 확장이 화면에 아무것도
  그리지 않고 바로 닫혀서, 공유 시트에서 PlaceCards를 눌러도 "빈
  화면이 잠깐 뜨고 사라짐 = 아무 일도 없는 것처럼" 보인다는 보고에
  대해, 코드로 최소한의 UI(스피너 → "PlaceCards로 저장 중…" →
  성공/실패에 따라 "✓ PlaceCards로 저장됨" 또는 "✗ ..." 메시지를
  0.7초 보여준 뒤 닫힘)를 추가. 처리 자체(사진 저장/`recordDebugStatus`
  기록)는 그대로이고, 사용자에게 보이는 결과만 추가됨.

### 2026-09-10 (51차) — 공유 확장이 공유 시트에 아예 안 보이던 문제 수정
#### Fixed
- `PlaceCards.xcodeproj/project.pbxproj`: "Embed Foundation Extensions"
  복사 단계에서 `PlaceCardsShare.appex`를 내장할 때 `RemoveHeadersOnCopy`
  만 있고 `CodeSignOnCopy` 속성이 빠져 있었음 — Xcode가 "New Target"
  마법사로 확장을 만들면 이 속성이 자동으로 붙는데, `project.pbxproj`를
  손으로 편집해 타겟을 추가하면서 빠뜨렸던 것으로 보임. 이 속성이
  없으면 앱을 빌드할 때 내장된 `.appex`가 최종 서명(코드사인)을
  다시 받지 못해서, 실기기에서 iOS가 이 확장을 아예 등록하지 못하고
  — 스크린샷을 찍은 뒤 뜨는 공유 시트에서 "더보기"를 열어도 PlaceCards
  자체가 보이지 않는 증상으로 나타남(시뮬레이터는 서명 검증이
  느슨해 이 문제가 잘 드러나지 않을 수 있음). `settings = {ATTRIBUTES
  = (RemoveHeadersOnCopy, CodeSignOnCopy, ); }`로 수정.

### 2026-09-10 (50차) — 공유 확장 진단 로그 추가
#### Added
- `Services/SharedImportStore.swift`: `recordDebugStatus(_:)`/
  `lastDebugStatus()`(신규) — App Group 컨테이너는 연결되어("연결됨"
  으로 표시) 있는데도 사진이 여전히 안 들어오는 것으로 보고되어,
  공유 확장이 실제로 어느 단계에서 실패하는지(첨부에서 이미지
  타입을 못 찾음/loadItem 실패/데이터를 못 읽음/저장 성공) 기기에서
  바로 확인할 수 있도록 App Group에 타임스탬프가 찍힌 상태 문자열을
  기록. 확장 프로세스는 기기에 설치된 뒤엔 콘솔을 볼 방법이 없어서
  실패 지점을 추측하는 대신 직접 기록해 확인하기 위함.
- `PlaceCardsShare/ShareViewController.swift`: `handleSharedItem()`의
  모든 분기(NSExtensionItem 없음 / 이미지 타입 첨부 없음 / loadItem
  에러 / 데이터 읽기 실패 / 저장 성공)에서 `recordDebugStatus` 호출
  추가.
- `Views/SettingsView.swift`: "정보" 섹션에 "마지막 공유 시도" 표시
  추가 — 위 상태 문자열을 그대로 노출.

### 2026-09-10 (49차) — 상세보기에 메모 필드 추가
#### Added
- `Models/PlaceCard.swift`: `memo: String?`(신규) — 어떤 항목에도
  맞지 않는 자유 형식 정보를 모아두는 필드. Peragra의
  `Place.notes`에 대응. Optional로 선언(디코드 안전성 — 이 구조체에
  이 필드가 추가되기 전 저장된 카드는 JSON에 `memo` 키가 없는데,
  `Decodable` 합성 구현은 non-Optional 프로퍼티에 대해선 키가 없을 때
  기본값을 적용하지 않고 `keyNotFound`로 디코드 전체를 실패시킴 —
  `StorageService.loadPlaceCards()`가 `try?`로 실패를 조용히
  무시하므로, non-Optional로 추가했다면 기존에 저장된 카드가 전부
  화면에서 사라졌을 것).
- `PlaceCard.merge(with:)`: 병합 시 현재 카드의 메모가 비어 있으면
  중복 카드들 중 비어 있지 않은 첫 메모를 가져오도록 로직 추가.
- `Views/PlaceCardDetailView.swift`: 편의시설/태그 옆에 메모 표시
  블록 추가(값이 있을 때만 표시).
- `Views/EditPlaceCardSheet.swift`: "메모" 섹션(여러 줄 입력) 추가
  — 태그/편의시설 섹션과 동일한 패턴. 저장 시 공백만 있으면 `nil`로
  정리.

### 2026-09-10 (48차) — 설정에 App Group 연결 상태 진단 표시
#### Added
- `Services/SharedImportStore.swift`: `isAppGroupAvailable`(신규) —
  App Group 컨테이너가 실제로 연결되는지 여부. 안 될 경우
  `savePendingImage`/`takePendingImage` 둘 다 조용히 아무 일도 안
  해서, 지금까지는 "공유는 성공한 것처럼 보이는데 PlaceCards엔 사진이
  안 와 있음" 증상의 원인을 기기에서 확인할 방법이 없었음.
- `Views/SettingsView.swift`의 "정보" 섹션에 "공유로 사진
  가져오기: 연결됨/연결 안 됨" 표시 추가 — 연결 안 됨이면 Xcode에서
  PlaceCards·PlaceCardsShare 두 타겟 모두 Signing & Capabilities에
  팀을 지정하고 "App Groups"에 group.com.mrnoh99.PlaceCards가 켜져
  있는지 확인하라는 안내도 함께 표시. Xcode 없이 이 원인 하나(가장
  유력한 원인 — 이 타겟을 Xcode의 "New Target" 마법사가 아니라 직접
  project.pbxproj를 편집해 추가했어서, App Groups 기능이 Apple
  Developer 계정에 실제로 프로비저닝된 적이 없을 가능성이 큼)를
  기기에서 바로 확인할 수 있게 함.

### 2026-09-10 (47차) — 공유 확장에서 사진이 안 보내지던 문제 수정
#### Fixed
- `PlaceCardsShare/ShareViewController.swift`: 공유 항목이 `URL`로
  전달될 때(사진 라이브러리에 저장된 이미지, 즉 스크린샷을 공유할 때
  흔한 경우) `startAccessingSecurityScopedResource()` 없이 읽고 있어
  `Data(contentsOf:)`가 조용히 실패(`try?`라 에러도 안 남음)하던 문제
  수정 — 아무 사진도 전달되지 않았는데 겉으론 아무 일도 없었던 것처럼
  보였던 원인.

### 2026-09-10 (46차) — "지도" 탭에서 Apple/Google/Naver 지도 선택
#### Added
- `Views/PlacesMapView.swift`: 내비게이션 바에 세그먼트 피커(Apple/
  Google/Naver) 추가, 선택은 `@AppStorage`로 기억됨. 기존 Apple 지도
  (MapKit `Map`)는 그대로 유지.
- `Views/GoogleMapWebView.swift`, `Views/NaverMapWebView.swift`(둘 다
  신규): PERAGRA의 동명 파일을 PlaceCards 모델에 맞게 포팅 — Google/
  Naver 모두 iOS 네이티브 SwiftUI 지도 뷰가 없고, 두 회사의 네이티브
  SDK를 붙이면 검토 불가능한 바이너리 의존성이 생기므로, 두 SDK 모두
  이 앱이 이미 avoid하고 있는 방식(WebKit `WKWebView`에 JS 지도
  API를 띄우는 방식)으로 구현:
  - `GoogleMapWebView`: `loadHTMLString`으로 완전히 자체 포함된 HTML을
    로드 — Google Places API 키(설정의 기존 키 재사용, Google Cloud
    콘솔에서 "Maps JavaScript API"만 추가로 활성화하면 됨)만 있으면
    바로 동작.
  - `NaverMapWebView`: PERAGRA가 이미 배포해 둔 데이터 기반(클라이언트
    ID·장소 목록을 JS로 주입받는) 임베드 페이지
    (`mrnoh99.github.io/Peragra/naver-map-embed.html`)를 그대로 재사용
    — Naver 지도 타일 서버가 페이지의 실제 origin을 검증해서
    `loadHTMLString`으로는 타일이 안 뜨기 때문(PERAGRA에서 이미 확인된
    제약). **다만 PlaceCards 자신의 NCP Maps 애플리케이션의 Web
    Service URL에 `mrnoh99.github.io`를 등록해줘야 실제로 동작합니다.**
- `Services/KeychainService.swift`, `ViewModels/SettingsViewModel.swift`,
  `Views/SettingsView.swift`: "Naver 지도 표시 (선택)" 설정 섹션(신규)
  — NCP Maps Client ID만 저장(Secret 불필요, JS 지도 렌더링 전용이라
  REST API 키와는 별개). Google/Naver 키가 없으면 지도 탭에 안내 화면이
  뜸.

### 2026-09-10 (45차) — 지도에서 찍은 스크린샷을 원래 카드로 돌려받기
#### Added
- `Services/MapOpenContext.swift`(신규): "지도에서 열기"를 누른 카드의
  ID를 `UserDefaults`에 기록(30분간 유효). 지도 앱에서 스크린샷을 찍어
  공유 확장으로 PlaceCards에 돌아왔을 때, 이 기록이 있으면 새 카드를
  만드는 대신 그 카드로 바로 연결하기 위함.
- `Views/PlaceCardDetailView.swift`, `Views/PlaceCardListRow.swift`,
  `Views/GalleryView.swift`: "지도에서 열기" 메뉴의 모든 버튼(Google
  Maps/Apple 지도/Naver Map/Kakao Map/Tmap)이 탭하는 순간 해당 카드를
  `MapOpenContext`에 기록.
- `Views/MapScreenshotImportSheet.swift`(신규): 공유로 받은 사진이
  도착했을 때 최근 "지도에서 열기" 기록이 남아있으면(그리고 그 카드가
  아직 존재하면) 이 시트가 대신 뜸 — 사진을 그 카드에 추가하고, AI로
  읽어 비어 있는 이름·주소를 채움(여러 장소가 발견되면 적용하지 않고
  알림, 이름이 바뀌는 경우엔 확인 후 적용 — `EditPlaceCardSheet`의
  사진 가져오기와 동일한 처리).
- `Views/MainTabView.swift`: `checkForSharedImage()`가 이제
  `MapOpenContext.recentCardID()`를 먼저 확인해 위 시트로 보낼지,
  기존의 게시판 선택 후 새 카드 생성 흐름(`SharedPhotoBoardPickerSheet`)
  으로 보낼지 분기하고, 처리 후 기록을 지움.

### 2026-09-10 (44차) — "지도에서 열기"에 Naver/Kakao/Tmap 다시 추가 (한국 주소 한정)
#### Added
- `Services/MapOpeners.swift`: `KoreaRegion`, `NaverMapOpener`,
  `KakaoMapOpener`, `TmapOpener` 복원(39차에서 제거했던 것). 정보
  소스(Naver Local Search/Geocoding API 연동)는 39차 결정대로 계속
  제거된 상태로 두고, 이번엔 "지도에서 열기" 메뉴에만 다시 추가 —
  카드의 좌표가 한국 영역 안일 때만 각 opener가 링크를 만들어내므로,
  한국 밖 장소는 지금처럼 Google Maps/Apple 지도만 뜸.
- `Views/PlaceCardDetailView.swift`, `Views/PlaceCardListRow.swift`,
  `Views/GalleryView.swift`: "지도에서 열기"/지도 메뉴가 Google Maps·
  Apple 지도에 이어 (한국 내 장소일 때) Naver Map·Kakao Map·Tmap도
  보여줌.

### 2026-09-10 (43차) — 빌드 오류 수정: 확장의 Info.plist에 CFBundleIdentifier 누락
#### Fixed
- `PlaceCardsShare/Info.plist`: "Embedded binary's bundle identifier is
  not prefixed with the parent app's bundle identifier" 오류 수정 —
  `GENERATE_INFOPLIST_FILE = NO`로 직접 제공하는 Info.plist에는 Xcode가
  자동으로 채워주지 않는 `CFBundleIdentifier`(`$(PRODUCT_BUNDLE_IDENTIFIER)`)와
  `CFBundleExecutable`/`CFBundleName`/`CFBundlePackageType`/
  `CFBundleShortVersionString`/`CFBundleVersion`/`CFBundleDevelopmentRegion`가
  빠져 있었음 — 빌드 설정에 지정한 `com.mrnoh99.PlaceCards.Share`가
  실제로는 적용되지 않고 있었던 것. 표준 보일러플레이트 키를 모두 추가.

### 2026-09-10 (42차) — 빌드 오류 수정: SharedPhotoBoardPickerSheet
#### Fixed
- `Views/SharedPhotoBoardPickerSheet.swift`: `.sheet(item:onDismiss:)`에
  `dismiss`(타입 `DismissAction`)를 클로저 자리에 그대로 넘겨 생긴 빌드
  오류("Cannot convert value of type 'DismissAction' to expected
  argument type '() -> Void'") 수정 — `{ dismiss() }`로 감싸서 전달.

### 2026-09-10 (41차) — 편집 화면에서 사진 추가 + AI로 정보 보완
#### Added
- `Views/EditPlaceCardSheet.swift`: "사진 추가" 섹션(신규) — 사진을
  고르면 저장 시 카드에 추가되고, "AI로 정보 읽어오기"를 누르면
  `AddPlaceCardView`와 같은 AI 장소 추출을 그 사진에 돌려 비어 있는
  이름·주소를 채움. `AddPlaceCardView`와의 차이점(이미 존재하는 특정
  카드를 고치는 중이라는 점)을 반영한 처리:
  - 사진에서 장소가 **여러 개** 발견되면 적용하지 않고 알리기만 하고
    중단(어느 장소를 이 카드에 적용해야 할지 알 수 없으므로).
  - 장소가 하나만 발견됐는데 그 이름이 **현재 이름과 다르면** 바로
    덮어쓰지 않고 확인 알림을 띄운 뒤, 승인해야만 적용.
  - 이름이 같거나 비어 있으면(또한 주소가 비어 있으면) 곧바로 채움 —
    앱의 다른 "빈 칸만 채우기" 동작들과 동일.

### 2026-09-10 (40차) — 공유 확장(Share Extension)으로 사진 바로 가져오기
#### Added
- `PlaceCardsShare` 타겟(신규): iOS 공유 시트에 "PlaceCards"가 뜨도록
  하는 Share Extension. 다른 앱(지도 앱, 사진 앱 등)에서 이미지를
  "공유" → PlaceCards를 고르면, 스크린샷을 먼저 사진 앱에 저장하고
  PlaceCards로 돌아와 갤러리에서 다시 골라야 했던 기존 절차 없이 바로
  넘어옴.
  - `PlaceCardsShare/ShareViewController.swift`: 스토리보드 없는
    최소 구현 — 공유된 이미지를 받아 App Group 공유 컨테이너에 저장하고
    즉시 완료 처리.
  - `Services/SharedImportStore.swift`(신규, 앱·확장 양쪽 타겟에 포함):
    확장과 앱이 별도 프로세스라 직접 데이터를 주고받을 수 없어, App
    Group(`group.com.mrnoh99.PlaceCards`) 공유 컨테이너의 파일을 통해
    전달.
  - `Views/SharedPhotoBoardPickerSheet.swift`(신규): 앱이 활성화될 때
    대기 중인 공유 사진을 발견하면(`MainTabView`) 이 시트로 어느
    게시판에 추가할지 물은 뒤, 그 사진이 이미 선택된 상태로
    `AddPlaceCardView`(신규 `initialImageData` 파라미터)를 엶.
  - 앱 타겟에 `PlaceCards.entitlements`, 확장 타겟에
    `PlaceCardsShare.entitlements` 추가(둘 다 같은 App Group 등록).
- ⚠️ **Xcode에서 직접 확인이 필요한 부분**: 이 기능은 새 Xcode
  타겟(확장 프로그램)을 추가하는 작업이라 `project.pbxproj`를 직접
  편집했음 — 이 환경엔 Xcode가 없어 실제 빌드로 검증하지 못했음.
  구조적 정합성(참조 무결성, 빌드 단계, 타겟 의존성)은 스크립트로
  확인했지만, 다음은 Xcode를 열어야만 가능:
  1. 두 타겟(PlaceCards, PlaceCardsShare) 모두 Signing & Capabilities에서
     팀 선택 및 "App Groups" 활성화(Apple Developer 계정에
     `group.com.mrnoh99.PlaceCards` 그룹이 등록돼 있어야 함).
  2. 한 번 빌드해서 구성이 실제로 컴파일/서명되는지 확인.
  3. 실기기에서 공유 시트에 PlaceCards가 뜨는지, 사진이 넘어오는지 테스트.

### 2026-09-10 (39차) — Naver 제거: 정보는 Google+사진 스캔, 지도는 Google+Apple만 사용
#### Removed
- Naver를 정보 소스·지도 제공자 양쪽에서 완전히 제거 — 이번 세션에서
  겪은 Naver 설정 관련 혼란(콘솔 두 개가 서로 다른 API를 제공하는 등)을
  근본적으로 없애기 위해, 정보는 이제 기본적으로 **Google Places 검색
  + 사용자가 올리는 사진의 AI 스캔** 두 경로로만 얻고, 지도는
  **Google Maps + Apple 지도** 두 개만 지원.
- `Services/NaverLocalSearchService.swift`, `Services/NaverGeocodingService.swift`
  (삭제): Naver 검색/좌표보강 API 연동 전체 제거.
- `Services/MapOpeners.swift`: `NaverMapOpener`, `KakaoMapOpener`,
  `TmapOpener`, `KoreaRegion`(이들만 썼음) 제거. 대신 `AppleMapsOpener`
  (신규, `MKMapItem` 기반)를 추가 — `PlaceCard.hasAnyMapLink`도
  Google/Apple 기준으로 재정의.
- `Views/PlaceCardDetailView.swift`, `Views/PlaceCardListRow.swift`,
  `Views/GalleryView.swift`: "지도에서 열기"/길찾기 메뉴가 이제
  Google Maps + Apple 지도만 표시. 상세화면의 "Naver 지도에서 정보
  보완" 버튼과 관련 로직도 함께 제거.
- `ViewModels/PlaceCardViewModel.swift`: `search(rowID:)`의 "Naver
  발견 + Google 상세정보" 하이브리드 쿼리 보정 단계 제거(이제 이름을
  그대로 Google에 검색). `createManualPlaceCard`의 Naver Geocoding
  좌표 보강 fallback도 제거 — 수동 입력 카드는 이제 "Google에서 검색"
  으로 결과를 고르지 않는 한 좌표가 채워지지 않음.
- `ViewModels/SettingsViewModel.swift`, `Views/SettingsView.swift`,
  `Services/KeychainService.swift`: Naver 관련 BYOK 설정 UI·자격증명
  저장/조회 코드·키체인 키 전부 제거.
- `SourceType`(`Models/MediaModels.swift`)의 Naver/Kakao 관련 케이스는
  기기에 이미 저장된 카드가 그 값을 갖고 있을 수 있어(디코딩 안전성)
  그대로 유지 — 새로 만들어지지만 않을 뿐, 열거형 자체는 손대지 않음.
  같은 이유로 `SharedLinkParser`(공유 링크에서 이름만 뽑아 Google로
  넘기는 로컬 파싱, Naver API 호출 없음)와 "네이버 지도 스크린샷" 업로드
  옵션(사진 스캔 경로 중 하나일 뿐)도 그대로 둠.

### 2026-09-10 (38차) — "지도에서 열기"를 Google/Naver/Kakao/Tmap 메뉴로 통일 (PERAGRA 참조)
#### Changed
- `Services/MapOpeners.swift`: `MapProvider`(기본 지도 앱 설정) 완전
  제거. PERAGRA의 `PlaceRowView`는 사용자별 기본 지도 설정이 따로 없이
  항상 Google/Naver/Kakao/Tmap 중 쓸 수 있는 것을 메뉴로 보여주는데,
  PlaceCards도 이제 동일하게 동작 — 상세화면 지도 미리보기 아래의
  "지도에서 열기"가 더 이상 설정에서 고른 앱 하나(Apple 지도 포함)로
  직행하지 않고, 기존에 액션 행에 따로 있던 "길찾기" 메뉴와 통합돼
  하나의 메뉴가 됨(중복 제거).
- `Views/SettingsView.swift`, `ViewModels/SettingsViewModel.swift`:
  이제 안 쓰는 "기본 지도 앱" 설정 섹션과 관련 코드(`mapProvider`,
  `saveMapProvider`, `currentMapProvider`) 제거.
#### Fixed
- `Services/MapOpeners.swift`: `GoogleMapsOpener`가 이제 앱이 설치돼
  있으면 `comgooglemaps://` 스킴으로 먼저 열고, 실패했을 때만(앱이
  없을 때) 기존의 `https://www.google.com/maps/...` 웹 링크로 대신
  열도록 함(`GoogleMapsOpener.open(for:using:)`, SwiftUI의
  `openURL(_:completion:)` 사용) — 이 웹 링크를 곧바로 여는 기존
  방식이 실제로는(Google Maps 앱이 없을 때) Apple 지도가 열리는 것으로
  이어지는 경우가 있었음("설정에서 Google 지도앱을 선택해도 Apple
  지도가 열린다" 리포트). Google Maps로 여는 모든 지점(상세화면 메뉴,
  리스트/갤러리의 지도 메뉴)이 이 방식을 함께 사용하도록 변경.

### 2026-09-10 (37차) — API 키 저장 시 공백/줄바꿈 제거
#### Fixed
- `Services/KeychainService.swift`: `save(_:for:)`가 이제 저장 전에
  값의 앞뒤 공백·줄바꿈을 제거함 — 개발자 콘솔 웹페이지에서 키를
  복사할 때 끝에 줄바꿈/공백이 같이 붙는 경우가 흔한데, 지금까지는
  그걸 그대로 저장해서 서버가 "유효하지 않은 API 키"로 거부해도 원인을
  알기 어려웠음(예: Naver 지도 정보 보완에서 401). 모든 BYOK 키(Google,
  Naver 검색/Geocoding, Unsplash, AI 제공자)가 한 곳에서 공통으로 이
  혜택을 받음.

### 2026-09-10 (36차) — 편집 화면에서 카드의 모든 필드 수정 가능
#### Changed
- `Views/EditPlaceCardSheet.swift`: 기존엔 이름·카테고리·주소·전화번호·
  웹사이트·인스타그램·태그·편의시설만 수정 가능했는데, `PlaceCard`의
  나머지 필드도 모두 폼에 추가 — 좌표(위도/경도, 둘 다 비우면 삭제),
  평점·리뷰 수, 즐겨찾기·방문 상태(토글), 영업시간(요일별 항목을
  자유롭게 추가/삭제하는 리스트)·마감시간·휴무일. `boardId`(게시판
  이동은 `BoardDetailView`의 선택 모드가 이미 담당)와 `sources`/
  `discoverySource`/생성·수정일(둘 다 자동 기록되는 메타데이터)은
  편집 대상에서 제외.

### 2026-09-10 (35차) — 상세화면 맨 위 사진 캐러셀 제거
#### Changed
- `Views/PlaceCardDetailView.swift`: 화면 맨 위의 사진 슬라이드
  (`TabView`) 제거. 사진 자체는 여전히 카드 리스트/갤러리 썸네일과
  `officialPhotos` 우선순위 로직에 그대로 남아 있고, 이 화면에서만
  보여주지 않음.

### 2026-09-10 (34차) — 상세화면에서 Naver 지도로 정보 보완
#### Added
- `Views/PlaceCardDetailView.swift`: "Naver 지도에서 정보 보완" 버튼(신규)
  — Google 검색으론 채워지지 않은 주소·전화번호·카테고리·좌표를
  Naver Local Search로 다시 찾아 빈 칸만 채움(이미 있는 값은 절대
  덮어쓰지 않음). 채운 항목은 `sources`에 `.naverDirectLookup` 기록으로
  남김. 네 항목이 이미 다 채워져 있으면 버튼 자체가 보이지 않음.
  `PlaceCardViewModel.refineWithNaver`(장소 추가 시 이름 보정용)와 같은
  Naver Local Search 자격 증명(설정)을 사용하되, 이미 저장된 카드에
  적용한다는 점이 다름.

### 2026-09-10 (33차) — 카드 상세화면에 전체 정보와 PERAGRA 스타일 액션 추가
#### Added
- `Views/PlaceCardDetailView.swift`: 그동안 모델엔 있었지만 화면에 전혀
  나오지 않던 필드를 모두 표시 — 즐겨찾기/방문 토글(제목 옆 별/체크
  아이콘), 전화·길찾기(Google/Naver/Kakao/Tmap 메뉴)·웹사이트·인스타그램
  액션 행(PERAGRA `PlaceRowView`의 액션 세트를 그대로 참조), 영업시간
  상세(`hoursDetail`)·마감시간(`closingTime`)·휴무일(`holidays`),
  정보 출처(`sources`, 발견 경로 `discoverySource`), 추가/수정 날짜.
  기존의 "지도에서 열기"(설정에서 고른 기본 지도 앱) 버튼은 그대로 유지.
- `Views/EditPlaceCardSheet.swift`(신규): 상세화면 툴바의 "편집" 버튼으로
  여는 편집 폼 — 이름·카테고리(같은 게시판의 다른 카테고리를 메뉴로
  제안)·주소·전화번호·웹사이트·인스타그램 URL·태그·편의시설을 직접
  수정. PERAGRA의 `EditPlaceSheet`를 참조했으나, 사진/AI 채움·지도
  스크린샷 인식 등은 이미 `AddPlaceCardView`에 별도로 있어 이 시트에는
  포함하지 않음.
- `card`가 이제 `@State`라 편집/토글 결과가 상세화면에 바로 반영됨
  (이전엔 `let card`라 표시만 가능했음).

### 2026-09-10 (32차) — 사진이 전혀 없을 때 Unsplash 검색으로 폴백
#### Added
- `Services/UnsplashImageService.swift`(신규): 참고용으로 업로드된 별개
  스타터 프로젝트의 `ImageSearchService.searchImageUnsplash` 아이디어를
  가져와 단순화 — 장소명(+카테고리)으로 Unsplash 검색 후 첫 결과의
  이미지를 다운로드. 캐싱은 없음(다운로드한 결과 자체를 `MediaStore`가
  파일로 영구 저장하므로 불필요).
- `Models/MediaModels.swift`: `SourceType.unsplashSearch`(신규) 케이스 추가.
- `Services/KeychainService.swift`, `ViewModels/SettingsViewModel.swift`,
  `Views/SettingsView.swift`: 다른 BYOK 키들과 같은 방식으로 Unsplash
  Access Key를 키체인에 저장하는 설정 섹션 추가("Unsplash 이미지 검색
  (선택)").
- `ViewModels/PlaceCardViewModel.swift`: `fetchOfficialPhoto`가 이제
  Google 사진(있으면 항상 우선)을 먼저 시도하고, 그마저 없고 사용자가
  올린 사진도 전혀 없는 카드에 한해서만 Unsplash 검색으로 최종
  폴백 — `createPlaceCard`(Google 검색 결과 기반)와
  `createManualPlaceCard`(수동 입력) 양쪽 모두에서 동작.

### 2026-09-10 (31차) — 카드 리스트 썸네일에 Google 사진 우선 사용
#### Added
- `Services/PlaceSearchService.swift`: 검색 필드 마스크에 `places.photos`
  추가, `PlaceSearchResult.photoName`(신규)에 첫 번째 Google 사진의
  리소스 이름을 담음. `GooglePlacesService.photoData(photoName:)`(신규)로
  Photo Media 서브리소스(`GET /v1/{photo}/media?skipHttpRedirect=true`)를
  통해 실제 이미지 바이트를 받아옴.
- `Services/MediaStore.swift`: `saveImage(data:)`(신규) — 이미 인코딩된
  바이트를 `UIImage` 왕복 없이 그대로 파일로 저장(Google에서 받은
  사진은 이미 JPEG라 재인코딩이 불필요).
- `ViewModels/PlaceCardViewModel.swift`: `createPlaceCard(from:images:source:)`가
  `async throws`로 변경 — Google 검색 결과에 사진이 있으면
  best-effort로 다운로드해 `card.media.officialPhotos`에 추가(카드
  생성 자체를 막지 않도록 실패해도 무시).
- `Views/PlaceCardListRow.swift`, `Views/GalleryView.swift`
  (`PlaceCardGridCell`): 리스트/갤러리 썸네일이 이제
  `officialPhotos.first ?? allItems.first` 순으로 우선 — 사용자가 직접
  올린 스크린샷이 없어도 Google에서 찾은 사진이 있으면 그걸 먼저
  보여줌. 카드 상세 화면의 전체 사진 갤러리(`PlaceCardDetailView`)는
  이미 `allItems` 전체를 보여주므로 변경 없음.

### 2026-09-10 (30차) — 사진 EXIF GPS로 Google 검색 범위 좁히기 (PERAGRA 참조)
#### Added
- `Services/PhotoMetadata.swift`(신규): 사진의 EXIF GPS 좌표를 추출 —
  PERAGRA의 `PhotoMetadata.extract(from:)`를 참조(PERAGRA는 온사이트
  GPS 실시간 캡처 흐름을 위해 촬영 시각·정확도도 함께 읽지만,
  PlaceCards엔 그 흐름이 없어 좌표만 추출). `UIImage`로 디코드 후
  재인코딩하면 EXIF가 사라지므로, 반드시 원본 바이트에서 읽어야 함.
- 장소 추가 화면에서 사진을 고를 때 원본 바이트(`pickedImageDatas`)를
  `UIImage`와 별도로 함께 보관 — AI 분석 시(`analyzeImages`) 이 중
  첫 번째로 GPS가 있는 사진의 좌표를 `PlaceCardViewModel.photoLocationHint`
  로 저장하고, 이후 각 행의 "Google에서 검색"이 이 좌표를
  `GooglePlacesService.search`의 `locationBias`로 넘겨 검색 범위를
  좁힘(기존엔 항상 `nil`이라 위치 힌트 없이 이름만으로 검색했음). 여러
  장의 사진에서 여러 장소가 나올 수 있어 특정 사진과 특정 장소를 1:1로
  매칭할 수 없으므로, 배치 안에서 찾은 첫 GPS를 모든 행이 공유.

### 2026-09-10 (29차) — 게시판 이름·부제목 수정 기능 추가
#### Added
- 홈 화면의 게시판 목록에서 행을 오른쪽으로 밀면(왼쪽 스와이프 액션)
  "수정" 버튼이 나오고, `EditBoardSheet`(신규)에서 이름·부제목·아이콘을
  바꿀 수 있음 — PERAGRA의 `TripsListView`(왼쪽 스와이프로 여는
  `EditTripSheet`)를 그대로 참조. 오른쪽 스와이프의 기존 "삭제"는
  그대로 유지.

### 2026-09-10 (28차) — 선택 모드에 "지도에서 보기" 추가
#### Added
- 게시판 다중 선택 모드의 하단 액션 바에 "지도에서 보기" 추가 — 선택한
  장소만 지도 탭에 표시하고 자동으로 지도 탭으로 전환됨. PERAGRA의
  `PlaceListingView`의 `onViewSelectedOnMap`을 참조했지만, PlaceCards의
  지도는 PERAGRA(트립 안에 있는 화면 내 지도)와 달리 앱 전체가 공유하는
  별도 탭이라 탭을 가로질러 전달해야 함.
- `Services/AppNavigation.swift`(신규): `selectedTab`/`mapFilterIDs`를
  들고 있는 앱 전역 내비게이션 상태. `MainTabView`에서 한 번 만들어서
  탭들에 `.environmentObject`로 주입 — 어느 화면에서든(게시판 상세 등)
  이걸 통해 지도 탭으로 전환하면서 보여줄 장소를 좁힐 수 있음.
- 지도 탭(`PlacesMapView`)이 `mapFilterIDs`가 있으면 그 장소들만 표시하고
  제목도 "선택한 장소"로 바뀌며, 툴바에 "전체 보기" 버튼이 나타나
  필터를 해제할 수 있음.

### 2026-09-10 (27차) — 게시판 아이콘을 이모지에서 미니멀 외곽선으로 변경
#### Changed
- 게시판 커버가 이모지(✈️🗺️🏖️🏙️⛰️🍜🎡🚆)에서 미니멀 외곽선 SF Symbol
  (`airplane`, `map`, `beach.umbrella`, `building.2`, `mountain.2`,
  `fork.knife`, `camera`, `tram`)로 변경 — 앱 아이콘·카테고리 아이콘과
  같은 톤으로 통일. 게시판 만들기 화면의 아이콘 선택 그리드, 홈 화면의
  게시판 행, "게시판 이동" 메뉴 항목 전부 반영.
- `Board.coverEmoji`/`coverEmojiChoices`를 `coverIcon`/`coverIconChoices`로
  이름 변경(더 이상 이모지가 아니므로).

### 2026-09-10 (26차) — 게시판에 다중 선택(Select) 모드 추가 (PERAGRA 참조)
#### Added
- 게시판 상세화면 툴바에 "선택"/"취소" 버튼 추가 — PERAGRA의
  `PlaceListingView`(`isSelecting`/`selectedIDs`/하단 bulk action bar)를
  참조. 선택 모드에서는 각 행 앞에 체크 표시가 붙고, 행을 탭하면
  상세화면 대신 선택/해제되며, 화면 하단에 액션 바가 나타남:
  - **전체 선택/해제**: 현재 필터·정렬로 보이는 카드 전체를 토글.
  - **삭제**: 선택한 카드를 전부 삭제(확인 다이얼로그 거침).
  - **카테고리 변경**: 이 게시판에 있는 기존 카테고리 목록에서 고르거나
    "직접 입력…"으로 새 카테고리를 타이핑해 선택한 카드 전부에 적용
    (PERAGRA는 고정된 `PlaceCategory` enum이라 목록만 골랐지만, PlaceCards는
    자유 텍스트라 직접 입력도 추가).
  - **게시판 이동**: 다른 게시판으로 선택한 카드를 전부 옮김(다른
    게시판이 하나도 없으면 메뉴 자체가 숨겨짐).
  - **병합**: 2개 이상 선택했을 때만 활성화 — 기존 "중복 찾기"와 같은
    `FindDuplicatesSheet`를 재사용(자동 탐지 없이 선택한 카드들을 그대로
    한 그룹으로 넘기는 새 초기화 방법 `init(manualGroup:)` 추가)해서 남길
    카드를 고르고 병합.
  선택 모드일 때는 "장소 추가"/"중복 찾기" 툴바 버튼을 숨겨 화면이
  복잡해지지 않도록 함.

### 2026-09-10 (25차) — 즐겨찾기 여부가 정렬에 영향을 주지 않도록 변경
#### Changed
- 지금까지는 정렬 모드와 무관하게 즐겨찾기한 카드가 항상 맨 위로
  뜨도록 되어 있었는데, 이 동작을 제거 — 이제 즐겨찾기 on/off는 목록에
  보이는지(필터) 여부에만 영향을 주고, 정렬 순서에는 전혀 영향을 주지
  않음(카테고리별/이름/거리 순서 그대로). 거리 정렬에서 기준으로 고른
  카드를 맨 위에 고정하는 동작은 그대로 유지(즐겨찾기와는 무관한 별개
  로직).

### 2026-09-10 (24차) — 즐겨찾기·방문 칩을 AND로 동시 토글 가능하게 변경
#### Changed
- 맨 윗줄의 "전체/⭐ 즐겨찾기/✅ 방문" 칩이 지금까지는 셋 중 하나만 고를
  수 있는 단일 선택이었는데, 즐겨찾기와 방문을 각각 독립적으로
  켜고 끌 수 있게 바꿈 — 둘 다 켜면 "즐겨찾기이면서 방문한" 카드만
  AND로 필터링됨. PERAGRA의 `activeCollectionIDs`(내장 즐겨찾기/방문
  리스트도 그냥 하나의 멤버십이라 `allSatisfy`로 AND 결합됨)를 참조.
  "전체" 칩은 이제 별도 선택지가 아니라 두 토글이 다 꺼졌을 때의 상태를
  가리키는 표시/리셋 버튼. `PlaceStatusFilter`를
  `enum { all, favorite, visited }`에서
  `struct { favoriteOnly, visitedOnly }`로 변경.

### 2026-09-10 (23차) — "중복 찾기" 추가 (PERAGRA의 FindDuplicatesSheet 참조)
#### Added
- 게시판 안에 카드가 2개 이상이면 툴바에 "중복 찾기" 버튼이 나타남 —
  PERAGRA의 `DuplicatePlaces`/`FindDuplicatesSheet`/`Place.merge`를 그대로
  참조해 포팅.
- `Services/DuplicatePlaces.swift`(신규): 이름을 대소문자·공백·구두점
  제거 후 비교해서 같고, 그 위에 좌표가 150m 이내로 가깝거나, 좌표가
  없으면 주소가 같거나 서로 포함 관계이거나, 좌표·주소 둘 다 없으면
  이름 일치만으로 "같은 곳을 두 번 저장한 것"으로 판단(union-find로
  A-B, B-C가 겹치면 셋을 한 그룹으로 묶음).
- `PlaceCard.merge(with:)`(신규, `Models/PlaceCard.swift`): 남길 카드에
  없는 정보(전화번호·웹사이트·인스타그램·카테고리·평점·리뷰수·주소·좌표)를
  중복 카드에서 채워넣고, 즐겨찾기·방문 여부는 하나라도 켜져 있으면
  유지, 태그·편의시설·사진(모든 미디어)·소스 기록은 합침. PERAGRA의
  `Place.merge(with:context:)`를 참조했지만 PERAGRA엔 없는 사진 병합
  로직이 추가됨(PlaceCards는 카드에 사진을 직접 모델링하기 때문).
- `Views/FindDuplicatesSheet.swift`(신규): 찾아낸 중복 그룹마다 남길
  카드를 라디오 버튼으로 고르고 "OO(으)로 병합" 버튼으로 확정 —
  PERAGRA의 시트와 동일한 흐름.
- `StorageService.removeMergedDuplicate(_:)`(신규): 병합으로 사라지는
  카드를 저장소에서 제거하되, 기존 `delete(_:)`와 달리 사진 파일은
  지우지 않음 — `merge`가 그 사진들의 `MediaItem`을 이미 남는 카드로
  옮겨놨기 때문에, 지우면 남는 카드가 참조하는 파일까지 함께 사라짐.

### 2026-09-10 (22차) — 카페/커피숍/커피전문점 카테고리를 "카페"로 통합
#### Changed
- Google Places 등에서 카테고리가 "Cafe", "Coffee shop", "카페", "커피숍",
  "커피전문점" 등 제각각 다른 문구로 들어와도 전부 "카페" 한 카테고리로
  보이고 필터링되도록 통합. `PlaceCategoryIcon.normalizedLabel(for:)`를
  추가해 카드 셀·리스트 행·상세화면의 카테고리 표시, 카테고리 필터
  드롭다운 생성, 카테고리 필터 매칭, "카테고리별" 정렬의 그룹핑까지
  전부 이 기준으로 통일. 카페 외 다른 카테고리는 원문 그대로 유지(고정
  분류 체계가 없어 카페만 명시적으로 요청받은 대로 좁게 처리).

### 2026-09-10 (21차) — 기준 장소를 맨 위로 고정 + "현재 위치" 거리 안 나오던 버그 수정
#### Changed
- "거리" 정렬에서 다른 저장된 장소를 기준으로 고르면, 그 기준 장소가
  즐겨찾기 여부와 무관하게 항상 리스트 맨 위에 고정되고, 나머지는
  기존처럼(즐겨찾기 우선 → 거리순) 정렬됨 — 기준 장소는 "측정의 원점"이라
  일반 항목처럼 즐겨찾기 정렬에 밀릴 이유가 없음. `PlaceCardSorting`에
  `pinnedID` 매개변수를 추가해 게시판 리스트와 갤러리 그리드 양쪽에 적용.
#### Fixed
- "현재 위치"를 기준으로 고르면 거리가 전혀 표시되지 않던 버그 수정 —
  `LocationService`가 위치 권한이 아직 결정되지 않은 상태(`.notDetermined`)
  에서도 8초 타임아웃을 바로 시작해버려서, 시스템 권한 팝업에 사람이
  응답하는 데 8초가 넘게 걸리면(흔한 일) 타임아웃이 먼저 nil로
  끝나버렸고, 그 후 실제로 권한이 허용되어 위치를 받아도 이미 끝난
  continuation이라 조용히 버려졌음. 이제 타임아웃은 실제로 위치 요청을
  시작한 뒤(권한이 이미 있거나, 막 허용된 뒤)에만 시작하도록 수정.

### 2026-09-10 (20차) — "거리" 정렬 시 기준으로부터의 거리 표시 + 필터바 순서 조정
#### Added
- "거리" 정렬로 기준을 고르면, 게시판 리스트 행(`PlaceCardListRow`)과
  갤러리 그리드 셀(`PlaceCardGridCell`) 모두에 카테고리 옆에
  "250m"/"1.3km" 형태로 기준으로부터의 거리가 표시됨 — PERAGRA의
  `PlaceRowView`("N km away")를 참조. `Coordinates.distanceText(from:to:)`
  헬퍼를 `PlaceCardSorting.swift`에 추가해 두 화면이 같은 로직을 공유.
  카드에 좌표가 없거나 거리 정렬 중이 아니면 자동으로 숨겨짐.
#### Changed
- `PlaceStatusFilterBar`에서 "거리" 정렬 시 나오는 기준 선택 메뉴를
  카테고리 메뉴보다 앞(정렬 메뉴 바로 다음)으로 이동.

### 2026-09-10 (19차) — 게시판 리스트 행 탭 방식을 PERAGRA처럼 NavigationLink 없이 재구성
#### Fixed
- 직전(18차) 커밋의 "보이지 않는 NavigationLink를 겹쳐두는" 방식도
  여전히 제대로 동작하지 않았음(List 안에서는 NavigationLink가 있으면
  보이든 안 보이든 행 전체를 셀 단위 선택 탭으로 가져가버려 안쪽 버튼과
  계속 충돌). PERAGRA의 `PlaceListingView`/`PlaceRowView`를 참고해
  구조를 바꿈 — PERAGRA는 행에 NavigationLink를 전혀 쓰지 않고
  즐겨찾기·방문 버튼을 일반 `.buttonStyle(.plain)` 버튼으로만 두고,
  상세 편집은 별도의 명시적 버튼(시트)으로 연다.
- `BoardDetailView`도 이제 행에 NavigationLink를 아예 두지 않고,
  `PlaceCardListRow`에 `.onTapGesture`만 달아 `selectedCard` 상태를
  통해 `.navigationDestination(item:)`으로 상세화면을 연다 — 버튼이
  없는 영역을 탭했을 때만 이 제스처가 걸리므로 즐겨찾기·방문·전화·지도
  등 행 안의 모든 버튼이 정상적으로 눌림.
- `PlaceCardListRow`에 자동으로 없어진 디스클로저 화살표를 대신할
  `chevron.right` 아이콘을 오른쪽에 직접 추가.

### 2026-09-10 (18차) — 게시판 리스트에서 방문/즐겨찾기 토글 버튼이 안 눌리는 문제 수정
#### Fixed
- 게시판 장소 목록(`BoardDetailView`)에서 `PlaceCardListRow`를
  `NavigationLink`의 label로 그대로 감쌌던 게 원인 — `List` 안에서는
  NavigationLink가 행 전체를 탭 영역으로 가져가버려서, 행 안의
  방문/즐겨찾기 버튼을 눌러도 토글 대신 상세화면으로 넘어가거나 아예
  반응이 없었음. 보이지 않는(`opacity(0)`) NavigationLink를
  `PlaceCardListRow`와 같은 `ZStack`에 겹쳐 두는 방식으로 변경 — 행의
  디스클로저 화살표·"다른 곳 탭하면 상세화면 열림" 동작은 그대로
  유지되면서, 행 자체의 버튼이 우선적으로 탭을 받도록 함.
#### Changed
- `PlaceCardListRow`의 평점 표시(주소 아래)에서 별 아이콘을 빼고 숫자만
  표시하도록 변경(`Label(..., systemImage: "star")` → 그냥 `Text`).

### 2026-09-10 (17차) — "거리" 정렬에서 거리 같은 카드는 카테고리순으로
#### Changed
- "거리" 정렬 시, 기준으로부터의 거리가 같은 카드끼리는(대표적으로
  좌표가 없어 전부 같은 값으로 취급되는 카드들) 순서가 뒤섞여 있던 것을,
  "카테고리별" 정렬과 같은 규칙(카테고리→이름)으로 정렬되도록 변경.
  `PlaceCardSorting.swift`에 `isByCategoryAscending` 비교 함수를 추출해
  `.byCategory`와 `.distance`(동률 시) 양쪽에서 재사용.

### 2026-09-10 (16차) — 게시판 장소 목록에 스와이프 삭제 추가
#### Added
- 게시판(BoardDetailView) 장소 목록에서 행을 왼쪽으로 밀면(swipe) "삭제"
  버튼이 나오고, 확인 다이얼로그("\"OO\"을 삭제할까요?")를 거쳐야 실제로
  삭제됨 — 게시판 목록(HomeView)의 기존 삭제 확인 방식과 동일한 패턴.
  지금까지는 카드를 삭제할 방법이 화면에 전혀 없었음.

### 2026-09-10 (15차) — "거리" 정렬 기준 선택에 좌표 없는 장소도 노출
#### Changed
- "거리" 정렬 선택 시 나오는 기준 장소 드롭다운이 지금까지는 좌표가
  확보된(`coordinates != nil`) 카드만 이름으로 보여줬는데, 이제 카테고리
  등 다른 필터와 무관하게 현재 목록의 카드를 전부 이름으로 보여줌 — 아직
  좌표가 없는 카드도 목록엔 뜨고, 그걸 기준으로 고르면
  `PlaceCardSorting`이 이미 가지고 있던 대로 그냥 정렬 없이 원래 순서를
  유지함(에러 없음).
- `PlaceStatusFilterBar`/`GalleryViewModel`/`BoardDetailView`의
  `locatableCards`를 `referenceCandidates`로 이름 변경 — 더 이상 "좌표
  있는 카드"만이 아니라서 기존 이름이 부정확해짐.

### 2026-09-10 (14차) — 게시판 안 장소 목록을 그리드에서 리스트로
#### Changed
- 게시판(BoardDetailView) 안의 장소 목록을 사진 그리드(LazyVGrid +
  PlaceCardGridCell)에서 일반 `List`(한 줄씩, `PlaceCardListRow`)로 변경.
  "갤러리" 탭은 처음부터 계속 그리드였고 그대로 유지 — 이번 변경은 게시판
  안 장소 목록에만 적용.
- `PlaceCardListRow.swift`(신규): 작은 썸네일 + 이름/카테고리/주소/평점,
  즐겨찾기·방문 토글, 전화·지도·웹사이트·인스타그램 액션 아이콘까지
  그리드 셀과 같은 정보를 한 줄짜리 리스트 행 레이아웃으로 재구성.
- `PlaceCard.callURL`/`hasAnyMapLink`/`hasAnyAction`을 `MapOpeners.swift`의
  `PlaceCard` extension으로 옮겨 그리드 셀과 새 리스트 행이 같은 로직을
  공유하도록 정리(기존엔 `PlaceCardGridCell` 안에 private으로만 있었음).

### 2026-09-10 (13차) — Gateway 모델 조회의 MainActor 격리 오류 수정
#### Fixed
- Xcode 오류: `AIProvider.swift:81:88 Call to main actor-isolated static
  method 'currentGatewayModel()' in a synchronous nonisolated context`.
  `SettingsViewModel`이 `@MainActor` 클래스라 그 정적 메서드
  `currentGatewayModel()`도 MainActor 격리되는데, 이를 호출하는
  `AIProviderFactory.create(type:apiKey:)`는 격리되지 않은 일반 정적
  메서드였던 것이 원인. 유일한 호출부인
  `PlaceCardViewModel.analyzeImages`가 이미 `@MainActor`이므로
  `create(type:apiKey:)`에 `@MainActor`를 붙여 해결.

### 2026-09-10 (12차) — 장소 추가: 스크린샷 여러 장 업로드 + 한 번에 여러 카드 생성
#### Changed
- 장소 추가 화면을 PERAGRA의 `AddPlaceSheet`(여러 행 검토 리스트, "+ Add
  Place", "Add N" 확인 버튼) 구조로 재구성. 스크린샷 한 장에 여러 장소의
  이름·주소가 담겨 있거나, 여러 장의 스크린샷을 한꺼번에 올린 경우 모두
  AI가 찾아낸 개수만큼 카드가 만들어질 수 있도록 함.
- 사진 선택이 여러 장 가능(`PhotosPicker(maxSelectionCount:)`, 최대
  10장)으로 바뀌고, 고른 사진들은 썸네일 목록으로 보여지며 개별 삭제 가능.
  "AI로 장소 분석하기" 한 번의 요청에 선택한 사진을 전부 함께 보내
  Claude/OpenAI/Gemini/Gateway가 여러 이미지를 한 번에 보고 이미지(들)에
  등장하는 모든 장소를 배열로 추출하도록 프롬프트/요청 형식을 변경
  (`AIProvider.analyzePlaces(imageDatas:)`가 `analyzeImage(imageData:)`를
  대체, 응답 형식도 `{"placeName": ...}` 단일 객체에서
  `{"places": [...]}` 배열로 변경 — PERAGRA의
  `AIExtractionService.extractPlaces(images:)`와 같은 구조).
- AI가 찾은 장소 각각이 편집 가능한 "행"이 되어(이름/주소 텍스트필드,
  선택 체크박스, 행별 "Google에서 검색" → 결과 탭해서 확정), 기존의
  분리된 "장소 검색"/"직접 입력" 섹션 두 개를 이 하나의 리스트로 통합.
  "+ 장소 추가"로 AI 없이 빈 행을 직접 추가하는 것도 그대로 가능. 스와이프로
  행 삭제 가능.
- 저장 시 선택된 행 전부가 각자 별도의 카드로 생성됨(`createCards`) —
  Google 결과를 고른 행은 그 결과로, 아니면 이름/주소 그대로(Naver
  Geocoding으로 좌표 보강) 저장. 이번에 선택했던 스크린샷들은 특정 행에
  매칭시킬 방법이 없어 생성되는 모든 카드에 각자 별도 파일로 복사해 첨부
  (한 파일을 여러 카드가 같이 참조하면 카드 하나만 삭제해도
  `StorageService.delete`가 그 파일을 지워버려 다른 카드가 사진을 잃게
  되므로 반드시 각자 복사).

### 2026-09-10 (11차) — Naver 기본 지도 제한 기준을 "찾는 장소"로 정정
#### Fixed
- 직전(10차) 커밋에서 기기의 `Locale.current.region`(기기 지역)이 한국이
  아니면 설정에서 Naver Map을 아예 선택할 수 없게 막았던 것을 되돌림 —
  실제로 맞아야 하는 기준은 기기 지역이 아니라 "찾는 장소(카드)가 한국인지"
  였음. 설정의 "기본 지도 앱"에는 다시 Apple/Google/Naver 세 개가 항상
  나열되고, 안내 문구도 "Naver Map은 찾는 장소가 한국 밖이면 사용할 수
  없어 그 경우 Google Maps로 대신 열립니다"로 정정.
- 실제 제한은 원래부터 있던 장소별 로직(`NaverMapOpener.url(for:)`이
  `KoreaRegion.contains`로 그 카드의 좌표를 확인 → 한국 밖이면 nil →
  `PlaceCardDetailView.openInPreferredMap`이 Google Maps로 대체)이 그대로
  담당 — 이번 변경은 거기에 잘못 얹은 기기-지역 기반 제한만 제거한 것.

### 2026-09-10 (10차) — 설정에 기본 지도 앱(Apple/Google/Naver) 선택 추가
#### Added
- 설정 화면에 "기본 지도 앱" 섹션 추가 — Apple 지도(기본값)/Google
  Maps/Naver Map 중 선택. 키 입력이 없는 단순 선택이라 별도 저장 버튼
  없이 선택 즉시 저장됨(`SettingsViewModel.saveMapProvider()`,
  UserDefaults).
- `Services/MapOpeners.swift`에 `MapProvider` enum(apple/google/naver)
  추가 — 게시판/갤러리 카드 셀의 지도 메뉴(Google/Naver/Kakao/Tmap 항상
  전부 제공)는 그대로 두고, 상세화면의 "지도에서 열기" 버튼만 이 기본값을
  따르도록 변경. Naver는 한국 밖에서는 쓸 수 있는 데이터가 없어(기존
  `KoreaRegion` 체크) 그 경우 Google Maps로 대체.

### 2026-09-10 (9차) — Sort By 옆에 카테고리 필터 드롭다운 추가
#### Added
- `PlaceStatusFilterBar`의 "정렬" 메뉴 옆에 "카테고리" 드롭다운을 추가 —
  현재 목록(게시판 상세는 그 보드, 갤러리는 검색/태그 필터까지 반영된
  전체)에 실제로 존재하는 카테고리만 선택지로 나열하고, "전체"로
  초기화 가능. 카테고리가 하나도 없으면 드롭다운 자체가 나타나지 않음.
- `GalleryViewModel.categoryFilter`/`allCategories`, `BoardDetailView`의
  `categoryFilter`/`categories`를 추가해 각 화면의 카드 목록에 카테고리
  필터를 적용 — `PlaceCard.category`가 자유 텍스트(Google Places
  카테고리)라 Peragra의 고정 `PlaceCategory` enum 대신 데이터에 실제
  존재하는 값만 동적으로 모아서 씀.

### 2026-09-10 (8차) — 나머지 화면 아이콘도 외곽선 톤으로 통일
#### Changed
- 카드 셀/상세화면/필터바/온보딩의 장식용(순수 표시용) 아이콘을
  `.fill`에서 외곽선으로 변경 — 방금 바꾼 앱 아이콘·카테고리 아이콘과
  톤을 맞춤.
  - `GalleryView.swift`: 전화 `phone.fill`→`phone`, 지도 `map.fill`→`map`,
    인스타그램 `camera.fill`→`camera`.
  - `PlaceCardDetailView.swift`: 평점 `star.fill`→`star`.
  - `PlaceStatusFilterBar.swift`: "현재 위치" `location.fill`→`location`.
  - `OnboardingView.swift`: API 키 안내 단계 `key.fill`→`key`.
#### Kept (의도적으로 유지)
- 즐겨찾기/방문 토글 아이콘(`star`/`star.fill`,
  `checkmark.circle`/`checkmark.circle.fill`)은 그대로 둠 — 채워짐 여부가
  곧 on/off 상태를 나타내는 유일한 신호이므로 외곽선으로 통일하면 상태
  구분이 사라짐.
- `PlacesMapView.swift`의 지도 마커(`mappin.circle.fill`)도 그대로 둠 —
  지도 배경 위에서 눈에 잘 띄어야 하는 지도 앱 공통 관례이며, UI 크롬
  아이콘과는 다른 성격의 예외로 판단.

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
