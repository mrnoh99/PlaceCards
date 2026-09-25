# TestFlight 배포

이 저장소에서 할 수 있는 준비는 **끝났다.** 남은 것은 전부 Xcode와 App Store
Connect에서 사람이 하는 일이다. 아래는 그 순서다.

이 문서를 만든 계기: 2026-09-24/25에 **앱이 실행 직후 사라졌고**, 크래시 리포트도
jetsam 기록도 남지 않았다. 지우고 다시 설치하니 고쳐졌다. 그 증상은
**개발 프로비저닝 프로파일 만료**다 — Xcode에서 직접 꽂아 넣은 빌드는 프로파일
수명이 다하면 아이콘을 눌러도 그냥 닫힌다. 코드 문제가 아니므로 고칠 것이 없고,
**TestFlight로 옮기는 것이 유일한 해결**이다(TestFlight 빌드는 90일 유효하고,
만료되면 만료됐다고 말해 준다).

---

## 1. 먼저 확인할 것 — **Team ID가 어긋나 있다**

| 어디 | 값 |
|---|---|
| `project.pbxproj`의 `DEVELOPMENT_TEAM` (빌드 13부터 지금까지) | `492X57LLB4` |
| 실기기 빌드 50의 크래시 리포트 `codeSigningTeamID` | `9AWEB9NYHH` |

**같아야 하는데 다르다.** 저장소가 적어 둔 팀이 아닌 다른 팀으로 서명된 빌드가
기기에 들어가 있었다는 뜻이다(`CODE_SIGN_STYLE = Automatic`이라 Xcode가 쓸 수
있는 팀으로 갈아탄 것으로 보인다).

**이게 맞지 않으면 배포가 안 된다.** App Store Connect의 앱 레코드는 한 팀에
속하고, 아카이브를 서명한 팀이 그 팀이어야 업로드가 받아들여진다.

확인: Xcode → 타깃 `PlaceCards` → **Signing & Capabilities** → Team 드롭다운에
실제로 선택돼 있는 팀. 그 팀의 ID는 <https://developer.apple.com/account> →
Membership에서 본다.

- 실제로 쓰는 팀이 `9AWEB9NYHH`라면 `project.pbxproj`의 `DEVELOPMENT_TEAM`
  **네 줄**을 그것으로 바꾼다(앱 타깃 둘 + 공유 확장 둘).
- `492X57LLB4`가 맞다면 Xcode 계정에 그 팀이 들어 있는지 확인한다.

둘 중 어느 쪽인지는 **계정 사정이라 코드에서 알 수 없다.** 그래서 이 저장소는
아무것도 바꾸지 않았다.

---

## 2. Apple Developer에 식별자 넷을 등록한다

번들 ID는 `PinSpots`인데 **App Group과 iCloud 컨테이너는 `PlaceCards` 이름
그대로다.** 헷갈려서 `...PinSpots`로 새로 만들면 **공유 확장과 동기화가 조용히
죽는다** — 이름이 Swift 상수에도 박혀 있다(`00_다른_계정에서_이어받기.md`).

| 종류 | 식별자 |
|---|---|
| App ID (앱) | `com.mrnoh99.PinSpots` |
| App ID (공유 확장) | `com.mrnoh99.PinSpots.Share` |
| App Group | `group.com.mrnoh99.PlaceCards` |
| iCloud Container | `iCloud.com.mrnoh99.PlaceCards` |

앱 App ID에 켜야 하는 것: **iCloud**(CloudKit + CloudDocuments, 위 컨테이너 지정),
**App Groups**(위 그룹). 공유 확장 App ID에는 **App Groups**만.

`PlaceCards.entitlements`와 `PlaceCardsShare.entitlements`가 요구하는 것이
정확히 이것이고, 하나라도 빠지면 아카이브 서명이 실패한다.

---

## 3. App Store Connect에 앱 레코드를 만든다

<https://appstoreconnect.apple.com> → 앱 → **+** → 새로운 앱

| 칸 | 값 |
|---|---|
| 플랫폼 | iOS |
| 이름 | PinSpots (App Store에서 유일해야 한다 — 이미 쓰이면 다른 이름) |
| 기본 언어 | 한국어 |
| 번들 ID | `com.mrnoh99.PinSpots` |
| SKU | 아무 문자열. `pinspots-ios`면 충분하다 |

TestFlight만 쓸 거면 스크린샷·설명·심사 자료는 **아직 필요 없다.** 내부 테스터
(같은 팀 계정 최대 100명)는 심사 없이 바로 받는다. 외부 테스터는 첫 빌드에
한 번 베타 심사를 거친다.

---

## 4. Xcode에서 아카이브해 올린다

1. 스킴 `PlaceCards`, 실행 대상을 **Any iOS Device (arm64)** 로 바꾼다.
   (시뮬레이터가 골라져 있으면 Archive 메뉴가 회색이다.)
2. **Product → Archive**
3. Organizer가 열리면 **Distribute App → TestFlight & App Store → Upload**
4. 서명은 **Automatically manage signing**으로 둔다. §1·§2가 맞으면 여기서
   프로파일이 저절로 만들어진다.

올라가면 App Store Connect의 **TestFlight** 탭에 "처리 중"으로 뜨고, 보통
5–15분 뒤 테스트할 수 있게 된다.

**업로드가 거부되는 가장 흔한 두 가지:**

- **빌드 번호 중복.** App Store Connect는 같은
  `MARKETING_VERSION`+`CURRENT_PROJECT_VERSION` 짝을 **두 번 받지 않는다.**
  올릴 때마다 빌드 번호를 올려야 한다 — 마침 이 저장소에는 "코드가 바뀌면 빌드
  번호를 올린다"는 규칙이 이미 있다(CLAUDE.md §4).
- **팀 불일치.** §1.

---

## 5. App Store Connect에서 "앱 개인정보 보호"를 채운다

이건 저장소의 `PrivacyInfo.xcprivacy`와 **별개**다. 그 파일은 "어떤 API를 왜
쓰는가"이고, 이쪽은 "사용자 자료를 무엇을 어떻게 다루는가"다. **첫 외부 테스터
초대 전에 채워야 한다.**

이 앱의 사실관계:

- **서버가 없다.** 자료는 기기와 사용자 제 iCloud에만 있다.
- **위치** — 지도에 내 위치를 찍고 거리순 정렬에 쓴다. 기기를 벗어나지 않는다.
- **사진** — 카드에 붙인다. 기기와 사용자 제 iCloud에만 있다.
- **바깥으로 나가는 것 둘.** 사용자가 제 API 키를 넣었을 때만 일어난다.
  - OpenAI — 사진에서 장소 정보를 읽을 때 그 **사진과 텍스트**가 나간다.
  - Google Places — 장소를 찾을 때 **검색어와 좌표**가 나간다.

  이건 개발자가 모으는 것이 아니라 **사용자가 제 계정으로 제3자에게 보내는**
  것이다. 설문에서 이걸 어떻게 밝힐지는 판단이 필요하다 — 안전한 쪽은
  "제3자에게 전달됨"으로 밝히는 것이다.
- **추적 없음.** 광고 식별자도, 분석 SDK도 없다(외부 패키지 의존성이 아예 없다).

---

## 6. 이 저장소가 이미 해 둔 것

손댈 필요 없다. 다만 왜 있는지는 알아 둘 것.

### `PrivacyInfo.xcprivacy` — **이게 없으면 업로드가 거부된다**

2024년 5월부터 "필수 이유 API"를 안 밝힌 빌드는 업로드 자체가 튕긴다
(ITMS-91053: Missing API declaration). 이 코드베이스가 건드리는 것은 둘이다.

| API | 어디서 | 이유 코드 |
|---|---|---|
| `UserDefaults` | 열 개 파일(설정·백업 폴더·API 사용량·묘비 장부). 전부 제 앱 것 | `CA92.1` |
| 파일 수정 시각 | `CloudBackupService.modificationDate(of:)` 한 군데 — iCloud 컨테이너의 백업을 오래된 것부터 세운다 | `C617.1` |

안 쓰는 것도 확인했다: 디스크 용량, 시스템 부팅 시각, 활성 키보드.
`UserDefaults(suiteName:)`는 한 군데도 없다 — 앱 그룹은 공유 **폴더**로만 쓴다.

> **첫 업로드 전에 이유 코드 두 개를 Apple 문서와 맞춰 볼 것.** Xcode에서
> `PrivacyInfo.xcprivacy`를 열면 이유를 고르는 목록이 나오고, 그것이 지금 시점의
> 정답이다. 코드가 틀리면 업로드가 같은 이유로 튕긴다.

### `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`

이게 없으면 올릴 때마다 App Store Connect가 수출 규정 질문을 띄우고, 답하기
전까지 빌드가 **"준수 정보 누락"으로 멈춰 있다.** 이 앱은 HTTPS만 쓰므로
답은 "아니오"다.

> 첫 아카이브에서 **실제로 들어갔는지 확인할 것.** Organizer에서 아카이브를
> 우클릭 → Show in Finder → 패키지 내용 보기 →
> `Products/Applications/PlaceCards.app/Info.plist`에
> `ITSAppUsesNonExemptEncryption`이 있어야 한다. 이 프로젝트는 Info.plist를
> 빌드 설정에서 **생성**하므로(`GENERATE_INFOPLIST_FILE = YES`) 눈으로 볼 수
> 없고, CI는 아카이브를 만들지 않아 검증해 주지 못한다.

### 아이콘

`Assets.xcassets/AppIcon.appiconset/AppIcon.png` — 1024×1024, RGB,
**알파 채널 없음**. 알파가 있으면 App Store가 거부하는데, 이건 깨끗하다.

### 그 밖에 맞춰져 있는 것

`MARKETING_VERSION = 1.0`, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`(테스터 기기가
iOS 17 이상이어야 한다), `TARGETED_DEVICE_FAMILY = "1,2"`(iPhone·iPad 둘 다),
사진·위치 사용 설명 문구 셋.

---

## 7. 테스터에게 알려 줄 것

- **AI 기능은 제 OpenAI 키를 넣어야 돈다.** 설정에서 넣는다. 키가 없으면 사진
  읽기와 장소 보완이 안 되고, 나머지는 다 된다. 이걸 안 알려 주면 "기능이
  고장났다"는 보고가 온다.
- **Naver 지도 말풍선은 이 앱 안에 없다.** 웹 페이지를 불러온다(CLAUDE.md §5).
  거기 문제는 이 빌드로 못 고친다.
- 크래시를 보고받을 때 **화면 맨 아래 크레딧 줄의 빌드 번호**를 함께 받는다.
  그 번호가 사용자와 나눌 수 있는 유일한 신원이다(CLAUDE.md §4).
- 크래시 리포트를 찾을 때 이름은 **`PlaceCards`**다. `PinSpots`가 아니다 —
  표시 이름만 PinSpots고 실행 파일은 그대로다. 이것 때문에 실제로 리포트를
  한참 못 찾았다.

---

## 8. 올릴 때마다 되풀이되는 것

1. 빌드 번호를 올린다 — `project.pbxproj`의 `CURRENT_PROJECT_VERSION` **네 줄**.
2. CI가 초록인지 본다(CLAUDE.md §1·§2). **컴파일 검증은 CI뿐이다.**
3. Archive → Distribute → Upload.
4. TestFlight 탭에서 처리가 끝나면 테스터에게 푼다.

CI를 아카이브까지 가게 만들 수도 있지만, 그러려면 배포 인증서와 프로파일을
GitHub Secrets에 넣어야 한다. 지금 CI는 서명을 끈 채 **빌드만** 한다
(`CODE_SIGNING_ALLOWED=NO`) — 그것이 컴파일 검증에는 충분하고, 서명 자료를
저장소 근처에 두지 않는 편이 안전하다.

---

## 9. 이 문서가 검증하지 못한 것

정직하게 적어 둔다. 개발 환경에는 Xcode도 Swift 툴체인도 없고, CI는 **빌드만**
하고 아카이브를 만들지 않는다. 그래서 확인된 것과 안 된 것이 갈린다.

**확인됨** — `PrivacyInfo.xcprivacy`가 plist로 파싱되고 앱 타깃의 Resources에
들어갔다, 아이콘이 1024×1024 RGB에 알파가 없다, 식별자 넷이 entitlements와
일치한다, 필수 이유 API가 저 둘뿐이다.

**확인 안 됨** — 아카이브가 실제로 만들어지는지, 생성된 Info.plist에 수출 규정
키가 들어가는지, 이유 코드 두 개가 지금 Apple이 받는 값인지, 서명이 통과하는지.
전부 첫 아카이브에서 드러난다.
