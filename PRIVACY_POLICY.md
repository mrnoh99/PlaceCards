# PinSpots 개인정보 처리방침

최종 수정: 2026년 9월 16일

> 이 문서는 앱 안(설정 → 개인정보 및 약관 → 개인정보 처리방침)에서 보이는 내용과
> 동일합니다. 원본은 `PlaceCards/PlaceCards/Services/LegalDocuments.swift`이며,
> **한쪽을 고치면 다른 쪽도 함께 고쳐야 합니다.**
>
> App Store Connect는 접근 가능한 방침 URL을 요구합니다. 이 파일을 GitHub Pages
> 등으로 게시하고 그 주소를 등록하세요.

## 요약

PinSpots는 계정이 없고, 개발자가 운영하는 서버도 없습니다. 저장한 장소와 사진은 이 기기 안에 있습니다.

다만 앱이 하는 일 중 일부는 외부 서비스를 부릅니다. 무엇이 언제 어디로 나가는지 아래에 전부 적었습니다. 그중 가장 중요한 것은 이것입니다 — AI로 사진을 스캔하면 그 사진이 사용자가 설정한 AI 제공자에게 업로드됩니다.

## 기기에 저장되는 정보

아래 정보는 이 앱의 저장 공간 안에만 있으며, 개발자는 볼 수 없습니다.

- **게시판과 장소 카드** — 이름, 주소, 좌표, 카테고리, 평점, 연락처, 웹사이트, 영업시간, 메모, 태그, 방문 기록 등 사용자가 저장하거나 앱이 채운 모든 항목
- **사진** — 사용자가 추가한 사진과 Google Places에서 받아온 장소 사진
- **API 키** — iOS 키체인에 저장되며 iCloud로 동기화되지 않습니다
- **앱 설정** — 언어, AI 제공자 순서, 백업 폴더 위치, 사용량 카운터

## 외부로 전송되는 정보

아래는 이 앱이 연결하는 곳 전부입니다. 모두 사용자가 직접 등록한 API 키로, 사용자 본인의 계정으로 호출됩니다.

### 1. Google Places API (`places.googleapis.com`)

장소를 확인하거나 평점·사진·영업시간을 채울 때. 검색어(장소 이름과 주소)와 앱의 번들 식별자가 전송되며, 현재 위치를 사용할 수 있는 경우 검색 기준점으로 좌표가 함께 전송됩니다.

### 2. Google Maps JavaScript API (`maps.googleapis.com`)

"지도" 탭에서 Google 지도를 선택했을 때. 저장한 장소의 좌표가 지도에 표시됩니다.

### 3. AI 제공자 — 사용자가 설정한 곳

사진 스캔을 실행할 때 **선택한 이미지가 업로드됩니다.** 설정에 등록한 제공자에 따라 아래 중 한 곳입니다.

- Anthropic (`api.anthropic.com`)
- OpenAI (`api.openai.com`)
- Google (`generativelanguage.googleapis.com`)
- `factchat-cloud.mindlogic.ai` — **제3자가 운영하는 게이트웨이입니다.** 이 앱이나 개발자가 운영하지 않으며, 선택한 경우에만 사용됩니다.

업로드된 이미지가 그곳에서 어떻게 처리·보관되는지는 각 제공자의 정책을 따릅니다. 사진 스캔을 실행하지 않으면 사진은 기기를 떠나지 않습니다.

### 4. Naver 검색 API (`naverapihub.apigw.ntruss.com`) — 선택

Naver 자격 정보를 등록한 경우, 장소 이름이 검색어로 전송됩니다.

### 5. Naver 지도 표시 페이지 (`mrnoh99.github.io`)

"지도" 탭에서 Naver 지도를 선택하면 GitHub Pages에 호스팅된 지도 페이지를 불러옵니다. 표시할 좌표가 그 페이지로 전달됩니다.

## 위치 정보

위치 권한은 "앱 사용 중"만 사용하며, 두 가지에만 쓰입니다.

- 저장한 장소를 현재 위치에서 가까운 순으로 정렬
- Google 장소 검색 시 검색 기준점으로 사용 — **이 경우 좌표가 Google로 전송됩니다**

위치 기록을 남기거나 이동 경로를 저장하지 않습니다. 권한을 거부해도 정렬 기능만 사용할 수 없고 나머지는 정상 동작합니다.

## iCloud 보관

"iCloud에 자동 보관"이 켜져 있으면, 앱을 열고 닫을 때마다 게시판·장소·사진 전체의 사본이 사용자 본인의 iCloud 계정 안, 이 앱 전용 공간에 저장됩니다. 기기를 바꾸거나 앱을 다시 설치했을 때 복구하기 위한 것입니다.

이 사본은 사용자의 iCloud에 있으며 개발자는 접근할 수 없습니다. 설정에서 끌 수 있고, 끄면 이미 저장된 사본도 함께 삭제됩니다.

## 수집하지 않는 것

- 분석 도구, 광고, 추적 SDK를 일절 사용하지 않습니다
- 개발자가 운영하는 서버가 없으므로 사용 기록이 전송되는 곳도 없습니다
- 계정이 없고 이메일·이름·전화번호를 요구하지 않습니다
- 설정 화면의 사용량 카운터는 이 기기 안에서만 계산되며 어디로도 전송되지 않습니다

## 데이터 삭제

앱을 삭제하면 기기에 저장된 장소·사진·설정·API 키가 함께 삭제됩니다.

iCloud 사본은 설정에서 "iCloud에 자동 보관"을 끄면 삭제됩니다. 앱을 먼저 삭제한 경우에는 iOS 설정 앱의 iCloud 저장공간 관리에서 지울 수 있습니다.

외부 서비스로 이미 전송된 내용(예: AI 제공자에 업로드된 이미지)의 삭제는 각 제공자에게 요청해야 합니다.

## 아동의 개인정보

이 앱은 아동을 대상으로 하지 않으며, 연령 정보를 포함해 어떤 개인정보도 수집하지 않습니다.

## 변경 및 문의

이 방침이 바뀌면 앱 업데이트와 함께 이 화면의 내용이 갱신되고 상단 날짜가 바뀝니다.

문의: jsnoh2010@gmail.com

---

# PinSpots Privacy Policy

Last updated: 16 September 2026

## Summary

PinSpots has no accounts and no server run by its developer. The places and photos you save stay on this device.

Some of what the app does calls external services, though. Everything that leaves the device is listed below. The most important one: running an AI scan uploads that photo to whichever AI provider you configured.

## Stored on this device

The following lives only inside this app's own storage. The developer cannot see any of it.

- **Boards and place cards** — name, address, coordinates, category, rating, contacts, website, opening hours, notes, tags, visit history, and everything else you save or the app fills in
- **Photos** — the ones you add, and place photos fetched from Google Places
- **API keys** — kept in the iOS Keychain and never synced to iCloud
- **App settings** — language, AI provider order, backup folder location, usage counters

## What leaves the device

This is every destination the app connects to. All of them are called with the API key you registered yourself, on your own account.

### 1. Google Places API (`places.googleapis.com`)

When confirming a place or filling in its rating, photo or hours. Sends the search text (place name and address) and the app's bundle identifier, plus your coordinates as a search bias when a current location is available.

### 2. Google Maps JavaScript API (`maps.googleapis.com`)

When you pick the Google map in the "Map" tab. Your saved places' coordinates are drawn on it.

### 3. Your configured AI provider

When you run a photo scan, **the selected image is uploaded.** Depending on which provider you registered, that is one of:

- Anthropic (`api.anthropic.com`)
- OpenAI (`api.openai.com`)
- Google (`generativelanguage.googleapis.com`)
- `factchat-cloud.mindlogic.ai` — **a gateway operated by a third party.** Neither this app nor its developer runs it, and it is used only if you select it.

How an uploaded image is handled and retained there is governed by that provider's own policy. If you never run a photo scan, your photos never leave the device.

### 4. Naver Search API (`naverapihub.apigw.ntruss.com`) — optional

If you registered Naver credentials, a place name is sent as the search query.

### 5. Naver map page (`mrnoh99.github.io`)

Picking the Naver map in the "Map" tab loads a map page hosted on GitHub Pages. The coordinates to display are passed to it.

## Location

Location access is "while using the app" only, and is used for exactly two things:

- Sorting your saved places by distance from where you are
- Biasing a Google place search toward you — **in this case your coordinates are sent to Google**

No location history or movement track is kept. Denying the permission disables only the distance sort; everything else works as normal.

## iCloud copy

While "Keep a copy in iCloud" is on, a copy of all your boards, places and photos is written into this app's own area of your personal iCloud account each time you open and leave the app. It exists so you can recover after changing phones or reinstalling.

That copy lives in your iCloud, and the developer cannot reach it. You can turn it off in Settings, and doing so also deletes the copy already stored.

## What is never collected

- No analytics, advertising or tracking SDK of any kind
- No developer-run server exists, so there is nowhere for usage data to be sent
- No account, and no request for your email, name or phone number
- The usage counter in Settings is computed on this device only and is never transmitted

## Deleting your data

Deleting the app removes the places, photos, settings and API keys stored on the device with it.

The iCloud copy is deleted when you turn "Keep a copy in iCloud" off in Settings. If you removed the app first, you can delete it from iCloud storage management in the iOS Settings app.

Anything already sent to an external service — an image uploaded to an AI provider, for instance — has to be deleted by asking that provider.

## Children's privacy

This app is not directed at children and collects no personal information at all, age included.

## Changes and contact

If this policy changes, this screen is updated along with the app and the date at the top changes with it.

Contact: jsnoh2010@gmail.com
