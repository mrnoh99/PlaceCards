# 커밋 전 검사

```
python3 Tools/checks/check.py
```

의존성 없음. 두 가지를 봅니다.

1. **괄호/중괄호/대괄호 균형** — 문자열·주석을 걷어낸 뒤
2. **번역 사전** — `.localized` 호출 중 사전에 없는 것(MISSING),
   사전에 있는데 아무도 안 쓰는 것(UNUSED), 중복 키

## 기준선 (main `dbf39e8` 기준)

```
괄호   오탐 2건 — LinkMetadataFetcher.swift, WebsiteBusinessInfoFetcher.swift
번역   MISSING 5 · UNUSED 6 · 중복 0
```

**이 숫자보다 나빠지지 않으면 통과**입니다. 괄호 2건은 정규식 리터럴 안의
`]`를 이 파서가 코드로 오인하는 **기존 오탐**이고, 번역 11건도 이전 세션에서
넘어온 것들입니다. 새로 늘어난 항목만 본인 책임입니다.

비교하려면 변경 전 상태에 대고 같은 스크립트를 돌리세요:

```sh
git archive HEAD | tar -x -C /tmp/baseline && (cd /tmp/baseline && python3 <이 스크립트 경로>)
```

## 이 검사가 못 잡는 것

**`import` 누락을 못 잡습니다.** PR #36에서 `CSVExport.swift`가
`FileDocument`(SwiftUI)를 쓰면서 `import SwiftUI`를 빼먹어 CI에서 터졌고,
188차에서도 `SettingsDetailViews.swift`의 `UniformTypeIdentifiers` 누락이
같은 이유로 여기서 안 잡혔습니다(자체 검토로 발견).

**컴파일 방어선은 CI뿐입니다.** 이 저장소에는 테스트 타깃이 없고 로컬에
Xcode도 없습니다. 큰 변경일수록 PR을 열어 CI를 기다리세요 — CI는 `main`
푸시와 pull request에서만 돌기 때문에, **브랜치에 푸시만 해서는 빌드 검증이
일어나지 않습니다.**

OCR 회귀 검사는 따로입니다: `python3 Tools/ocr-regression/check.py` (50건).
