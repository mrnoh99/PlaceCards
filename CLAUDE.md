# PlaceCards (PinSpots) — 작업 규칙

## 1. CI가 유일한 컴파일 검증이다. 초록을 보기 전에는 병합하지 않는다.

이 저장소에는 macOS 러너에서 실제로 앱을 빌드하는 CI가 있다
(`.github/workflows/ci.yml`, `pull_request`와 `main` 푸시에 모두 반응).
개발 환경에는 Xcode도 Swift 툴체인도 없고, SwiftUI·MapKit은 Linux에
존재하지 않으므로 **여기서 할 수 있는 어떤 검사도 컴파일 검증이 아니다.**

괄호 균형, 번역 누락, 잔존 참조 검사는 전부 유용하지만 타입 검사가
아니다. 다음은 그 검사들을 전부 통과하고도 CI에서 터진 실제 사례다:

| 오류 | 원인 |
|---|---|
| `Cannot find type 'MapCameraPosition' in scope` | `import SwiftUI` 누락 (MapKit만으로는 부족) |
| `Covariant 'Self' type cannot be referenced from a stored property initializer` | 저장 프로퍼티 기본값에서 `Self.` 참조 (`final class`라도 불가) |
| 트레일링 클로저가 엉뚱한 파라미터에 바인딩 | 기본값 있는 클로저 파라미터를 뒤에 추가 → 라벨 없는 트레일링 클로저는 **선언상 마지막** 클로저에 붙는다 |
| `Conflicting arguments to generic parameter 'Result' ('Void' vs. 'UUID')` | 값을 반환하는 함수를 `withAnimation { }` 같은 제네릭 클로저의 단일 표현식으로 호출. `@discardableResult`는 이 추론을 막지 못한다 |
| `expected key expression in dictionary literal` | `Localization.swift`에서 **값이 다음 줄에 오는** 두 줄짜리 항목의 key와 value 사이에 새 항목을 끼워 넣음. 괄호 수는 그대로라 균형 검사가 못 잡는다 → `Tools/localization/check.py` |

## 2. CI 상태는 **check runs**로 확인한다. commit status가 아니다.

이걸 틀리면 "CI가 없다"는 잘못된 결론에 도달한다. 실제로 그렇게 해서
빨간 PR을 병합한 적이 있다.

- GitHub Actions는 **check run**으로 보고한다.
- 레거시 **commit status** API는 이 저장소에서 **항상 비어 있다**
  (`state: pending`, `total_count: 0`). 이건 "CI 없음"이 아니다.

```
# 맞음
pull_request_read(method: "get_check_runs", pullNumber: N)
actions_list(method: "list_workflow_runs", ...)

# 틀림 — 항상 비어 있어서 오해를 부른다
pull_request_read(method: "get_status", pullNumber: N)
```

병합 전 확인할 것: `conclusion`이 `"success"`인지. `in_progress`면 기다린다.
빌드는 보통 1분 내외다. 실패하면 `get_job_logs`로 실제 컴파일 오류를 읽는다.

PR을 연 뒤 `subscribe_pr_activity`를 걸어두면 CI 결과가 이벤트로 돌아오므로
기다리는 동안 다른 일을 할 수 있다.

## 3. 큰 변경일수록 이 규칙이 중요하다

파일 하나를 한 줄 고치는 것과 12개 파일에 걸친 리팩터링은 위험이 다르다.
위 표의 오류 5건 중 4건이 여러 파일을 동시에 건드린 변경에서 나왔다.

## 4. 그 밖의 프로젝트 관례

- 테스트 타깃이 없다. `Tools/` 아래 검사들은 CI가 돌리지 않으니 관련
  코드를 건드렸으면 직접 실행한다.
  - `Tools/ocr-regression/check.py` — OCR 회귀.
  - `Tools/localization/check.py` — 번역 사전. **`Localization.swift`를
    고쳤으면 반드시 돌린다.** 사전 구조가 성한지와 번역 누락을 함께 본다
    (위 표의 다섯 번째 사례).
- 화면에 보이는 한국어 문자열은 전부 `.localized`를 거치고
  `Services/Localization.swift`에 영어 대응이 있어야 한다. 단,
  `CSVExport`처럼 `.map { $0.localized }`로 일괄 번역하는 곳이 있으므로
  `"…".localized` 리터럴만 찾는 스캔은 오탐을 낸다.
- 외부 앱의 URL 스킴은 추측하지 않는다. 공식 문서로 확인되지 않으면
  그 기능을 넣지 않는다 (`NaverPlaceSearchService`의 과거 사례 참고).
- 문서:
  - `CHANGELOG.md` — 어떤 변경이 왜 그렇게 됐는지. 214차까지이고,
    UI 개편(PR #77·#78·#79)도 들어가 있다.
  - `00_UI개편_기초.md` — **화면을 건드린다면 먼저 읽는다.** 지금의 화면
    지도, *갈아엎어도 살아남아야 하는 동작* 목록, 그리고 이 코드베이스에서
    실제로 밟은 SwiftUI 함정들. 이름은 "개편"이지만 개편은 끝났고 지금
    상태를 적고 있다.
  - `00_다른_계정에서_이어받기.md` — 다른 Apple 계정/다른 사람이 이어받을 때
    바꿔야 하는 식별자. App Group과 iCloud 컨테이너 둘 다 entitlements
    말고 **Swift 상수까지 세 곳**이고, 빠뜨리면 공유/동기화가 조용히 죽는다.
  - `00_인수인계_현재상태.md` — 2026-09-23(214차)까지 갱신함. §4·§6이
    최신이고, §8 파일 지도만 PR #43 시점 그대로 낡았다.
  - `00_프로젝트종합가이드_새세션용.md` — 구현 전 기획서. 폐기.

## 5. **Peragra 저장소는 수정하지 않는다.**

사용자 지시(2026-09-17): "peragra는 더이상 수정 말라". 읽는 것은 상관없다.

이게 걸리는 지점이 하나 있다. "지도" 탭의 **Naver 지도 말풍선은 이 저장소에
없다.** `NaverMapWebView`는 WKWebView를 아래 페이지로 이동시키기만 하고,
마커·말풍선·버튼을 그리는 코드는 전부 그 페이지 안에 있다:

```
mrnoh99/Peragra  web/public/naver-map-embed.html
  -> https://mrnoh99.github.io/Peragra/naver-map-embed.html
```

그러므로 **Naver 말풍선의 모양·버튼·동작은 지금 바꿀 수 없다.** 손대려면
사용자에게 먼저 물어야 한다. 사본을 새로 떠서 우회하지 마라 — 한 번 그렇게
갈라놨다가(189차) 되돌린 적이 있다(190차).

이 페이지는 **Peragra의 iOS 앱도 그대로 불러온다.** 즉 이 금지가 풀리더라도
페이지를 고치면 두 앱의 말풍선이 같이 바뀐다.

바꿀 수 있는 것(전부 이 저장소 안이다):

- Swift가 페이지로 **보내는 값** — `NaverMapWebView.MarkerPlace`(마커 HTML,
  각 지도 앱 URL)와 `LocalizedStrings`(말풍선 문구). 페이지는 안 보낸 필드에
  전부 기본값이 있으므로 필드를 빼는 것도 안전하다.
- Apple 탭 말풍선(`PlacesMapView.appleMapAnnotation`), Google 탭 말풍선
  (`GoogleMapWebView`의 HTML 문자열) — 둘 다 이 저장소 안이다.

Naver만 못 고치고 나머지 둘은 고칠 수 있으므로, **세 지도를 함께 바꾸는 작업은
지금 불가능하다.** 셋은 2026-09-17 기준 같은 모양이며, 한쪽만 고치면 그
정합성이 깨진다.

(여기서 "탭"은 지도 화면 안의 Apple/Google/Naver 선택기를 말한다. 앱 자체의
탭은 갤러리·지도·설정 셋이고 별개다.)
