# 3. 지도 API 비교 분석

기획 문서에서 상세히 논의된 Google Places, Naver Map, Kakao Local API의 비교 분석입니다.

---

## 3.1 API 데이터 풍부도 비교

| 항목 | Google Places API | Naver 지역검색 API | Kakao 로컬 API |
|------|------|------|------|
| 이름/주소/좌표 | ✅ | ✅ | ✅ |
| 평점 (별점) | ✅ | ❌ | ❌ |
| 리뷰 수 / 원문 | ✅ (텍스트도 가능) | ❌ | ❌ |
| 요일별 영업시간 | ✅ (Monday-Sunday) | ❌ | ❌ |
| 인기시간대 (Popular Times) | ✅ | ❌ | ❌ |
| 전화번호 | ✅ (있으면) | ✅ (있으면) | ✅ (있으면) |
| 웹사이트/SNS링크 | ✅ | ✅ | ❌ |
| 세부 속성 (amenities) | ✅ (주차, 반려동물 등) | ❌ | ❌ |
| 사진 / 썸네일 | ✅ | ✅ | ✅ |

**결론**: **Google Places API가 압도적으로 풍부한 데이터 제공**

---

## 3.2 인증 방식 및 클라이언트 호출 가능성

| 항목 | Google | Naver | Kakao |
|------|--------|-------|-------|
| 인증 방식 | API 키 1개 | Client ID + **Client Secret** | REST API 키 1개 |
| 클라이언트(iOS)에서 직접 호출 | ✅ 가능 | ❌ **불가** | ❌ **불가** |
| 이유 | 번들ID로 제한 가능 (상대적 안전) | Secret 노출 → 인증 전체 뚫림 | Secret 불필요하나 정책상 권장 안 함 |
| 필요 아키텍처 | 클라이언트 직접 호출 | **백엔드 프록시 필수** | **백엔드 프록시 필수** |

**결론**: Naver/Kakao는 반드시 **백엔드 프록시** 필요

---

## 3.3 한국 지도 앱 사용자 규모 (2026년 3월 기준)

| 순위 | 앱 | 월간 활성 사용자 | 성격 | 사용 목적 |
|------|-----|---------|------|---------|
| 1 | **네이버 지도** | ~2,952만 명 | 종합 지도 | 장소 검색/발견, 내비게이션 |
| 2 | 티맵 | ~1,562만 명 | 내비게이션 전용 | 경로안내 (PlaceCards 비교 대상 제외) |
| 3 | **카카오맵** | ~1,282만 명 | 종합 지도 | 장소 검색/발견, 내비게이션 |
| - | **구글 지도** | 상대적으로 낮음 | 전 세계 지도 | 국제 여행, 상세 정보 |

**결론**: 한국 사용자 기준 발견 행동은 **네이버 >> 카카오 >> 구글** 순이나, 데이터 풍부도는 **구글 >> 네이버 > 카카오** 순.
→ **하이브리드 전략 필수** (발견은 네이버/카카오, 상세정보는 구글)

---

## 3.4 Kakao의 결정적 제약 사항

### ⚠️ 카카오 로컬 API 공식 정책

**출처**: devtalk.kakao.com 공식 답변 (확인됨)

#### 문제점
1. **구조화된 정보의 영구 저장 금지**
   - 로컬 API 응답 결과 (이름, 주소, 평점 등)를 DB에 저장하는 것이 원칙적으로 금지됨
   - 이는 플레이스카드의 핵심 설계(데이터 통합 저장)와 충돌

2. **캐싱도 제약**
   - 응답 속도 개선을 위한 1시간 캐싱도 \"임시 DB\" 간주
   - 따라서 운영정책 위반 소지 있음

#### 허용되는 사항 (제한적)
- ✅ `place_id` + `place_url` 저장 (기본키 수준만 OK)
- ✅ 사용자가 직접 입력/확정한 텍스트를 게시물 콘텐츠로 저장

#### PlaceCards 적용 불가 케이스
```
❌ 불가: PlaceCard {
    name: "카페A",              // ← Kakao API에서 가져온 것 저장 불가
    address: "서울시 강남구",   // ← Kakao API에서 가져온 것 저장 불가
    rating: 4.5                 // ← Kakao API에서 가져온 것 저장 불가
}
```

#### 대안 설계
```
✅ 가능: PlaceCard {
    kakaoPlaceId: "ABC123",         // Place ID만 저장
    kakaoMapUrl: "https://place.kakao.com/...",
    
    // 필요시 아래와 같이 런타임에 재조회:
    async refreshFromKakaoIfNeeded() {
        let freshData = try await kakaoAPI.getPlaceDetails(placeId)
        // 표시는 하되, 저장하지 않음
    }
}
```

또는

```
✅ 가능: PlaceCard {
    // 다른 API(Google)에서 얻은 정보로 PlaceCard 채우기
    name: "카페A",    // ← Google Places API에서 가져온 것
    
    // Kakao는 발견 출처로만 기록
    sources: [
        SourceRecord(sourceType: .kakaoDirectLookup, ...)
    ]
}
```

### 결론

**Kakao를 PlaceCard 데이터 소스로 쓰려면:**

1. **\"매번 실시간 조회 후 표시\"** 전략
   - 사용자가 PlaceCard를 열 때마다 Kakao API 재호출
   - 응답을 임시로 UI에만 표시, 저장 안 함

2. **\"place_url 저장 후 필요시 링크로 redirect\"** 전략
   - 카카오맵 URL만 저장
   - 사용자가 필요 시 링크 클릭해서 카카오맵 앱으로 이동

3. **\"Google 중심, Kakao는 발견 출처용\"** 전략 (권장)
   - Kakao로 사용자가 장소 발견 (스크린샷 스캔 등)
   - 실제 PlaceCard 데이터는 Google에서 채우기
   - 보안/준법성 최고

**실제 구현 전 카카오 개발자센터에 서면 문의 필수**

---

## 3.5 아키텍처별 구현 방식

### Case 1: Google Only (가장 간단)

```
iOS 앱
  ↓ (API 키 + 번들ID)
Google Places API
  ↓
PlaceCard 저장
```

**장점**: 구현 간단, 백엔드 불필요
**단점**: 한국 사용자 발견 커버리지 낮음

---

### Case 2: 하이브리드 (권장)

```
iOS 앱
  ├─ (API 키)─→ Google Places API
  │             ↓
  │        PlaceCard 채우기 (상세정보)
  │
  ├─ (Client ID)─→ 백엔드 프록시 (Node.js)
  │                ├─ Naver API (Client ID + Secret)
  │                └─ Kakao API (REST API 키)
  │                ↓
  │          발견 + 기본정보
  │
  └─ Claude API (BYOK) → Instagram 인식
                        ↓
                    Google 검증
```

**흐름**:
1. 사용자가 네이버/카카오 스크린샷 스캔 → 위치명 추출
2. Google Places API로 검증 및 상세정보 채우기
3. PlaceCard 저장 (Google 중심)
4. 필요시 Naver 평가, Kakao 링크 보강

**장점**: 한국 발견 커버리지 + 상세 데이터, 최적 균형
**단점**: 백엔드 프록시 필요, 복잡도 증가

---

### Case 3: 멀티 프록시 (고급)

```
iOS 앱
  ├─ Google Places API (직접)
  ├─ Naver Proxy
  ├─ Kakao Proxy
  └─ Claude API (BYOK)
     ↓
  PlaceCard (Google 중심 + Naver/Kakao 보강)
```

**장점**: 각 API별 최적 활용
**단점**: 복잡도 최고, 관리 부담

---

## 3.6 권장 전략 요약

| 조건 | 권장 방식 | 이유 |
|------|---------|------|
| 글로벌 서비스 | Case 1 (Google Only) | 복잡도 낮음, 확장성 높음 |
| 한국 중심 서비스 (이 프로젝트) | Case 2 (하이브리드) | 발견 + 상세정보 모두 확보 |
| 한국 전문 서비스 | Case 3 (멀티 프록시) | 한국 API 최대 활용 |

**이 프로젝트 최종 결론**: **Case 2 (하이브리드)** 추진

---

## 3.7 백엔드 프록시 구현 개요

### Naver Map Proxy (Node.js)

```javascript
// POST /api/naver/search
app.post('/api/naver/search', async (req, res) => {
  const { query, coords } = req.body;
  
  const naverResponse = await axios.get(
    'https://openapi.naver.com/v1/search/local.json',
    {
      headers: {
        'X-Naver-Client-Id': process.env.NAVER_CLIENT_ID,
        'X-Naver-Client-Secret': process.env.NAVER_CLIENT_SECRET
      },
      params: { query, sort: 'comment', display: 10 }
    }
  );
  
  res.json(naverResponse.data);
});
```

**배포 옵션**:
- Heroku Free Tier (주의: 2024년 11월부터 무료 지원 종료)
- Railway
- Render
- AWS Lightsail
- 자체 VPS (Linode, DigitalOcean)

### Kakao Local Proxy (Node.js)

```javascript
// POST /api/kakao/search
app.post('/api/kakao/search', async (req, res) => {
  const { query, coords } = req.body;
  
  const kakaoResponse = await axios.get(
    'https://dapi.kakao.com/v2/local/search/keyword.json',
    {
      headers: {
        'Authorization': `KakaoAK ${process.env.KAKAO_API_KEY}`
      },
      params: { query, size: 15 }
    }
  );
  
  res.json(kakaoResponse.data);
});
```

---

## 3.8 실제 조회 테스트 결과

기획 단계에서 실제 Google Places API로 조회한 용인시 카페 6곳 사례:

| 상호명 | Google 매칭 | 평점 | 리뷰수 | 비고 |
|-------|------|------|--------|------|
| 달애울 | ✅ | 4.2 | 5 | 첫 테스트 성공 |
| 마지모우 | ✅ | 4.2 | 46 | polle.com에서 전화 추가 확보 |
| 카페꼰대 | ❌ | - | - | Google DB 미등록, 로컬 소규모점의 한계 |
| 도나스데이 본점 | ✅ | 4.1 | 188 | - |
| 카페스트리트36 | ✅ (이름 불일치) | 4.6 | 212 | Google 등록명: \"Bean to Bar\" → 검증 필요 |
| 언덕 | ✅ | 4.6 | 33 | - |
| 스테이어도러블 | ✅ | 4.3 | 12 | 주차 없음 등 후기 정보 풍부 |

**시사점**:
- 로컬 소규모 카페는 Google DB 미등록 가능성 (→ Naver/Kakao 보강 필수)
- 이름 불일치 사례 존재 (→ 사용자 검증 절차 필요)
- Google이 평점/리뷰는 가장 풍부

---

## 3.9 비용 추정

### Per-Request 기준 (2026년)

| API | 가격 | 월 만 건 기준 | 월 십만 건 기준 |
|-----|------|---------|---------|
| Google Places | $0.017/query | $170 | $1,700 |
| Naver Search | 무료 (1일 25,000건) | 무료* | 유료** |
| Kakao Local | 무료 (1일 100,000건) | 무료 | 무료 |

*Naver: 월 75만 건까지 무료, 초과 시 협상
**Kakao: 공식 정책상 일일 100,000건이 상한

### 백엔드 호스팅

| 플랫폼 | 비용 | 비고 |
|--------|------|------|
| Heroku | 무료 (종료) → $7/월 이상 | 2024년 11월 이후 유료화 |
| Railway | $5/월 | 시작 크레딧 제공 |
| Render | $7/월 | Free Tier 지원 |
| AWS Lightsail | $3.50/월 | 안정성 높음 |

---

## 3.10 다음 단계

- [ ] Google Cloud Console에서 Google Places API 프로젝트 생성
- [ ] Naver Cloud Platform에서 API 키 발급
- [ ] Kakao Developers에서 API 키 발급
- [ ] 백엔드 프록시 테스트 (로컬 개발 환경)
- [ ] 각 API 응답 데이터 형식 분석 및 매핑
- [ ] Rate Limiting, Error Handling 전략 수립

---

*작성: 2026-09-09 | 상태: 완료*
