# 3. 지도 API 전략 (수정판) - Google + Naver Only

## 개요

PlaceCards에서는 **Google Places API**와 **Naver Map API** 2개만 사용합니다.
Kakao는 제외하여 저장 정책 제약과 복잡성을 완전히 제거합니다.

---

## 1. Google Places API vs Naver Map API 비교

### 1.1 데이터 풍부도

| 항목 | Google Places API | Naver 지역검색 API |
|------|------|------|
| 이름/주소/좌표 | ✅ | ✅ |
| 평점 (별점) | ✅ | ❌ |
| 리뷰 수 | ✅ | ❌ |
| 요일별 영업시간 | ✅ | ❌ |
| 전화번호 | ✅ | ✅ |
| 웹사이트 | ✅ | ❌ |
| 세부 속성 (주차, 반려동물 등) | ✅ | ❌ |
| 인기시간대 | ✅ | ❌ |
| 사진 | ✅ | ✅ |

**결론**: **Google이 데이터 풍부도에서 압도적**

---

### 1.2 인증 방식 & 클라이언트 호출 가능성

| 항목 | Google | Naver |
|------|--------|-------|
| 인증 방식 | API 키 1개 | Client ID + Client Secret |
| iOS에서 직접 호출 | ✅ 가능 (번들ID 제한) | ❌ **불가** |
| 보안 위험도 | 낮음 (번들ID로 보호) | 높음 (Secret 노출) |
| 필요한 아키텍처 | 클라이언트 직접 호출 | **백엔드 프록시 필수** |

**결론**: Naver는 **반드시 백엔드 프록시**가 필요함

---

## 2. 한국 지도 앱 사용자 규모 (2026년 3월 기준)

| 순위 | 앱 | 월간 활성 사용자 |
|------|-----|---------|
| 1 | **네이버 지도** | ~2,952만 명 |
| 2 | 티맵 | ~1,562만 명 (내비게이션 전용, 제외) |
| 3 | 카카오맵 | ~1,282만 명 (제외) |
| - | **구글 지도** | 상대적으로 낮음 |

**한국 사용자 발견 행동**:
- **Naver**: 59% (가장 높음)
- **Google**: 28%
- **Kakao**: 13% (제외됨)

---

## 3. 채택 전략: Google + Naver 하이브리드

### 3.1 역할 분담

```
사용자가 장소 발견
  ↓
┌──────────────────────────┐
│ 1. Naver API (발견)      │
│   - 한국 사용자 주력     │
│   - 장소 검색 (이름)     │
│   - 좌표, 주소 획득      │
└────────────┬─────────────┘
             ↓
    ✓ Naver 결과 있으면 OK
    ✗ 없으면 → Google로 재검색
             ↓
┌──────────────────────────┐
│ 2. Google API (상세정보) │
│   - 평점, 리뷰, 영업시간 │
│   - 편의시설, 웹사이트   │
│   - 상세 정보 보강       │
└────────────┬─────────────┘
             ↓
    PlaceCard 생성
    ✓ Naver의 기본 정보
    ✓ Google의 상세 정보
```

### 3.2 사용 흐름

#### 케이스 1: 지도 스크린샷 (주로 Naver)
```
사용자: Naver Map 스크린샷 추가
  ↓
[AI API로 위치명 추출 (사용자의 Claude/GPT)]
  ↓
[Naver API로 검색]
  ↓
✓ 결과 있음 → Naver 기본정보 획득
  ↓
[Google API로 상세정보 획득]
  ↓
[PlaceCard 생성]
```

#### 케이스 2: Google Map 스크린샷
```
사용자: Google Map 스크린샷 추가
  ↓
[AI API로 위치명 추출]
  ↓
[Google API로 직접 검색]
  ↓
✓ 상세정보 모두 획득
  ↓
[PlaceCard 생성]
```

#### 케이스 3: 로컬 소규모 가게 (Google에만 없음)
```
사용자: 카페꼰대 (용인 로컬 카페) 추가
  ↓
[AI API로 위치명 추출]
  ↓
[Naver API로 검색]
  ✓ 결과 있음
  ↓
[Google API로 재검색]
  ✗ 결과 없음 (로컬 소규모점)
  ↓
[Naver 정보만으로 PlaceCard 생성]
  (평점/리뷰/영업시간은 미기입)
```

---

## 4. 아키텍처 단순화

### 4.1 이전 (Google + Naver + Kakao)
```
PlaceCards App
├─ GooglePlacesService (직접 호출)
├─ NaverMapService (백엔드 프록시)
├─ KakaoLocalService (백엔드 프록시 + 저장 제약)
└─ Backend Proxy
   ├─ /api/naver/search
   └─ /api/kakao/search
```

### 4.2 변경 후 (Google + Naver Only)
```
PlaceCards App
├─ GooglePlacesService (직접 호출)
├─ NaverProxyService (백엔드 프록시)
└─ Backend Proxy
   └─ /api/naver/search  (Naver만!)
```

**제거된 복잡성**:
- ✂️ Kakao 저장 정책 검토 불필요
- ✂️ Kakao 백엔드 프록시 구현 불필요
- ✂️ 3가지 API 응답 형식 처리 복잡성 감소

---

## 5. API 호출 전략

### 5.1 Google Places API (iOS에서 직접)

```swift
class GooglePlacesService {
    let apiKey: String  // Info.plist 또는 환경 변수
    
    func search(query: String, location: CLLocationCoordinate2D? = nil) async throws -> [PlaceSearchResult] {
        let url = URL(string: "https://places.googleapis.com/v1/places:searchText")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        
        let body = [
            "textQuery": query
        ]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GooglePlacesResponse.self, from: data)
        
        return response.places.map { place in
            PlaceSearchResult(
                id: place.id,
                name: place.displayName.text,
                address: place.formattedAddress,
                coordinates: (place.location.latitude, place.location.longitude),
                rating: place.rating,
                reviewCount: place.userRatingCount,
                // ... 기타 필드
            )
        }
    }
    
    func getDetails(placeId: String) async throws -> PlaceDetails {
        // Google Places Details API
        // 평점, 리뷰, 영업시간, 사진 등 상세 정보
    }
}
```

### 5.2 Naver Map API (백엔드 프록시 경유)

```swift
class NaverProxyService {
    let proxyBaseURL: URL  // https://my-naver-proxy.com
    
    func search(query: String, display: Int = 10) async throws -> [PlaceSearchResult] {
        let url = proxyBaseURL.appendingPathComponent("api/naver/search")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["query": query, "display": display]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(NaverSearchResponse.self, from: data)
        
        return response.items.map { item in
            PlaceSearchResult(
                id: item.mapx + "," + item.mapy,
                name: item.title,
                address: item.roadAddress ?? item.address,
                coordinates: (CLLocationDegrees(item.mapy)!, CLLocationDegrees(item.mapx)!),
                rating: nil,  // Naver는 평점 미제공
                reviewCount: nil,
                // ... 기타 필드
            )
        }
    }
}
```

### 5.3 백엔드 프록시 (Node.js)

```javascript
// routes/naver.js
app.post('/api/naver/search', async (req, res) => {
    const { query, display } = req.body;
    
    try {
        const naverResponse = await axios.get(
            'https://openapi.naver.com/v1/search/local.json',
            {
                headers: {
                    'X-Naver-Client-Id': process.env.NAVER_CLIENT_ID,
                    'X-Naver-Client-Secret': process.env.NAVER_CLIENT_SECRET
                },
                params: {
                    query,
                    display: display || 10,
                    sort: 'comment'
                }
            }
        );
        
        res.json(naverResponse.data);
    } catch (error) {
        res.status(error.response?.status || 500).json({
            error: error.message
        });
    }
});
```

---

## 6. 데이터 우선순위

PlaceCard를 생성할 때 필드 우선순위:

```
필수 필드 (모두 채우기):
  ✓ name (위치명)
  ✓ address (주소)
  ✓ coordinates (좌표)

Google에서 획득 (높은 우선순위):
  ✓ rating (평점)
  ✓ reviewCount (리뷰 수)
  ✓ hoursDetail (요일별 영업시간)
  ✓ amenities (편의시설)
  ✓ website (웹사이트)

Naver에서 획득 (기본정보):
  ✓ name
  ✓ address
  ✓ coordinates
  ✓ phone (전화번호)

선택 필드:
  ? closingTime (대표 마감시간)
  ? holidays (휴무일)
```

### 필드 채우는 순서

```swift
func createPlaceCard(from aiExtractedName: String) async throws -> PlaceCard {
    // 1단계: Naver로 기본 정보 획득
    let naverResult = try await naverService.search(query: aiExtractedName)
    guard !naverResult.isEmpty else {
        // Naver에 없으면 Google로 재검색
        let googleResult = try await googleService.search(query: aiExtractedName)
        return try createFromGoogle(googleResult[0])
    }
    
    // 2단계: Google로 상세정보 보강
    let googleResult = try await googleService.search(
        query: aiExtractedName,
        location: naverResult[0].coordinates
    )
    
    // 3단계: PlaceCard 생성 (Naver 기본 + Google 상세)
    let placeCard = PlaceCard(
        id: UUID().uuidString,
        name: naverResult[0].name,
        address: naverResult[0].address,
        coordinates: naverResult[0].coordinates,
        rating: googleResult[0].rating,          // ← Google
        reviewCount: googleResult[0].reviewCount, // ← Google
        hoursDetail: googleResult[0].hoursDetail, // ← Google
        amenities: googleResult[0].amenities,     // ← Google
        website: googleResult[0].website,         // ← Google
        phone: naverResult[0].phone,             // ← Naver
        // ... 기타
    )
    
    return placeCard
}
```

---

## 7. 비용 추정

### 7.1 Google Places API

**가격** (2026년):
- Text Search: $0.017/query
- Details: $0.017/query
- 월 사용량 한계: 월 10만 건까지 $1,700

**예상 사용량**:
- 사용자 1000명
- 1인당 월 5건 검색 = 5000건
- 월 비용: 5000 × $0.017 = $85

### 7.2 Naver API

**가격**: 무료
- 일일 25,000건까지 무료
- 초과 시 협상

**예상 사용량**: 완전 무료

### 7.3 백엔드 호스팅

**옵션**:
| 플랫폼 | 월 비용 | 특징 |
|--------|--------|------|
| Railway | $5/월 | 시작 크레딧 제공 |
| Render | $7/월 | Free Tier 제공 |
| AWS Lightsail | $3.50/월 | 안정성 높음 |
| Heroku | $7/월+ | 2024년 11월부터 유료화 |

**추천**: Railway 또는 Render ($5-7/월)

### 7.4 총 월 비용 (추정)

```
Google Places API:  $85/월
백엔드 호스팅:      $5/월
클라우드 저장:      $0/월 (로컬 저장)
─────────────────────────
합계:              ~$90/월
```

**사용자당 비용** (1000명 기준):
- $90 ÷ 1000 = $0.09/월/사용자 (매우 저렴!)

---

## 8. 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────┐
│          PlaceCards iOS App                     │
│          (Swift + SwiftUI)                      │
├──────────────────┬──────────────────────────────┤
│   UI Layer       │ Home | Gallery | Map | Settings │
├──────────────────┼──────────────────────────────┤
│   ViewModel      │ PlaceCardVM | GalleryVM      │
├──────────────────┼──────────────────────────────┤
│   Service Layer  │                              │
│                  ├─ GooglePlacesService (직접)  │
│                  ├─ NaverProxyService (프록시)  │
│                  ├─ AIProviderService (사용자 AI) │
│                  └─ StorageService (SwiftData)  │
├──────────────────┼──────────────────────────────┤
│   Security       │ KeychainService              │
│                  │ (Google API 키, AI API 키)   │
└──────────────────┴──────────────────────────────┘

외부 서비스:

        ┌─────────────────────────────────────┐
        │    사용자의 AI API                   │
        │ (Claude/GPT/Gemini - BYOK)          │
        │ 이미지 분석 → 위치명 추출           │
        └────────────────┬────────────────────┘
                         │
        ┌────────────────┴────────────────────┐
        │                                     │
   ┌────▼─────────────────┐    ┌────────────────┐
   │ Google Places API    │    │ Backend Proxy  │
   │ (직접 호출)          │    │ (Naver)        │
   │                      │    │                │
   │ • Text Search        │    │ /api/naver/... │
   │ • Details            │    │                │
   │ • 평점/리뷰/영업시간 │    └─────┬──────────┘
   │ • 편의시설           │          │
   └──────────────────────┘      ┌───▼──────────┐
                                 │ Naver API    │
                                 │              │
                                 │ • 검색       │
                                 │ • 좌표/주소  │
                                 └──────────────┘
```

---

## 9. 마이그레이션 전략 (기존 앱에서)

기존 3개 API를 사용하던 코드 → Google + Naver로:

```swift
// ❌ 이전
class PlaceService {
    var googleService: GooglePlacesService
    var naverService: NaverMapService
    var kakaoService: KakaoLocalService
}

// ✅ 변경
class PlaceService {
    var googleService: GooglePlacesService
    var naverService: NaverProxyService
    // kakaoService 제거
}
```

**변경 작업량**:
- Kakao 관련 코드 제거: ~10%
- 데이터 모델 단순화: ~5%
- 테스트 코드 감소: ~15%

---

## 10. 다음 단계

- [ ] Google Cloud Console에서 Places API 활성화
- [ ] Naver Cloud Platform에서 API 키 발급
- [ ] 백엔드 프록시 서버 선택 (Railway/Render)
- [ ] 실제 API 호출 테스트
- [ ] 응답 데이터 형식 분석 및 Adapter 작성
- [ ] 프로젝트 문서 최종 업데이트

---

*작성: 2026-09-09 | 최종 업데이트: 2026-09-09*
