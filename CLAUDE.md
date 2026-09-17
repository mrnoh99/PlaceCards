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
위 표의 오류 4건 중 3건이 여러 파일을 동시에 건드린 변경에서 나왔다.

## 4. 그 밖의 프로젝트 관례

- 테스트 타깃이 없다. OCR 회귀 검사(`Tools/ocr-regression/check.py`)는
  CI가 돌리지 않으니 관련 코드를 건드렸으면 직접 실행한다.
- 화면에 보이는 한국어 문자열은 전부 `.localized`를 거치고
  `Services/Localization.swift`에 영어 대응이 있어야 한다. 단,
  `CSVExport`처럼 `.map { $0.localized }`로 일괄 번역하는 곳이 있으므로
  `"…".localized` 리터럴만 찾는 스캔은 오탐을 낸다.
- 외부 앱의 URL 스킴은 추측하지 않는다. 공식 문서로 확인되지 않으면
  그 기능을 넣지 않는다 (`NaverPlaceSearchService`의 과거 사례 참고).
- 더 자세한 배경은 `00_인수인계_현재상태.md`.
