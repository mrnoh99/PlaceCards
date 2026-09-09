# PlaceCards

여행/나들이 중 여러 출처(지도 앱, SNS, 직접 촬영)에서 발견한 장소를 하나의 통일된 카드(PlaceCard)로 저장·관리·조회하는 iOS 앱입니다.

기획 배경과 전체 의사결정 과정은 [`00_프로젝트종합가이드_새세션용.md`](./00_프로젝트종합가이드_새세션용.md)와 `PLANNING/`, `RESEARCH/`, `IMPLEMENTATION/` 폴더에 정리되어 있습니다. 이 문서는 실제 Xcode 프로젝트(`PlaceCards/`)의 현재 구현 상태와 빌드 방법을 설명합니다.

## 현재 상태

- 기획/설계: ✅ 완료 (`00_프로젝트종합가이드_새세션용.md` 참고)
- iOS 코드: 🟡 1차 구현 (Phase 4 시작) — Google Places 검색/보강, Claude Vision 기반 이미지 분석, 갤러리/지도/설정 UI까지 동작
- 백엔드(Naver 프록시), Kakao 연동, OpenAI/Gemini 연동, Export, 오프라인 동기화: 미구현 (아래 "다음 단계" 참고)

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
| Google Places API 키 | 장소 검색/평점/영업시간 등 보강 | Google Cloud Console → Places API (New) 활성화 |
| Claude API 키 | 스크린샷/사진에서 장소명 추출 (Vision) | console.anthropic.com |
| Naver 프록시 URL | Naver 지역 검색 (선택, 별도 백엔드 필요) | 아래 "다음 단계" 참고 |

키는 Keychain에만 저장되며 iCloud로 동기화되지 않습니다.

## 프로젝트 구조

```
PlaceCards/
  PlaceCards.xcodeproj/
  PlaceCards/
    PlaceCardsApp.swift        # 앱 진입점
    ContentView.swift          # 온보딩 ↔ 메인 탭 분기
    Models/                    # PlaceCard, MediaBundle, SourceRecord 등
    Services/                  # Keychain, 로컬 저장, Google/Naver/AI 클라이언트
    ViewModels/                # Settings/PlaceCard/Gallery/Map ViewModel
    Views/                     # Onboarding, Home, Gallery, Map, Settings, 카드 추가/상세
    Assets.xcassets
    Preview Content/
```

### 아키텍처 개요

- **UI**: SwiftUI + MVVM (`06_아키텍처_단순화.md`의 Service/ViewModel 계층 구조를 따름)
- **저장**: 로컬 JSON 파일(`StorageService`) — SwiftData/CoreData 선택은 기획 문서에서 미결 항목(`07_미해결항목.md` 3.2)으로 남아 있어, iOS 버전 제약이 없고 스키마가 자주 바뀌는 현재 단계에 맞춰 단순한 방식을 선택함
- **지도 API**: Google Places API (New)를 앱에서 직접 호출(BYOK). Naver는 Client Secret을 앱에 넣을 수 없어 별도 백엔드 프록시를 거치도록 클라이언트만 구현되어 있고, 실제 프록시 서버는 아직 없음(설정 화면에서 프록시 URL은 입력할 수 있지만 배포된 서버가 없으면 호출이 실패함)
- **AI 이미지 분석**: Claude Vision(Anthropic Messages API)을 사용자의 API 키로 직접 호출하도록 구현됨. OpenAI/ChatGPT, Gemini는 선택 UI만 있고 실제 호출은 `notImplemented` 오류를 반환함(향후 추가 예정)
- **Kakao**: 기획 문서의 최종 결정(`00_프로젝트종합가이드_새세션용.md` §2️⃣)에 따라 저장 정책 리스크를 피하기 위해 이번 구현에서 제외함

### 기획 문서와 다른 점 (의도적 단순화)

원본 기획 문서 대부분은 iOS 15.0을 최소 버전으로 가정했지만, 이번 구현은 `PhotosPicker`, `ContentUnavailableView`, iOS 17의 `onChange(of:)` 2-파라미터 API 등을 사용하기 위해 **iOS 17.0**을 최소 배포 타깃으로 설정했습니다. 이는 문서에서도 미결 항목으로 남아 있던 부분이며(`07_미해결항목.md` 3.2), 실제 기기 지원 범위를 넓히려면 재검토가 필요합니다.

## 다음 단계

`07_미해결항목.md`의 액션 플랜을 기준으로, 이번 세션에서 다루지 않은 것들:

1. **Naver 프록시 백엔드** — Node.js/Express 프록시 서버 구현 및 배포 (Client Secret은 절대 클라이언트에 넣지 않음)
2. **OpenAI/Gemini Vision 연동** — 현재는 Claude만 실제로 동작
3. **Export 기능** — JSON/CSV 내보내기, Notion/Google Sheets 연동
4. **테스트** — 단위/통합 테스트 (기획 문서 `06_아키텍처_단순화.md` §10 참고)
5. **앱 이름 상표 조사, App Store 심사 준비물** — `07_미해결항목.md` §7.1, §7.4
