# 5. AI(Claude API) 사용 정책 — BYOK 모델

PlaceCards 앱의 Claude API 활용 정책과 Bring Your Own Key(BYOK) 모델에 대한 상세 설명입니다.

---

## 5.1 핵심 원칙

### \"API 이용은 사용자가 결정한다\"

앱 운영자가 API 비용을 부담하지 않으며, 사용자가 **투명하게 비용을 제어**할 수 있는 모델을 지향합니다.

---

## 5.2 사용자 정책 옵션

```swift
enum AIAnalysisPolicy: String, Codable {
    case always         // 스크린샷 추가 시 자동 분석 (추천 안 함)
    case askEachTime    // 매번 확인 다이얼로그 (기본값, 권장)
    case manualOnly     // AI 미사용, 수동 입력만
}
```

### Option 1: `always` (자동 분석)

```
사용자가 스크린샷 추가
  ↓
자동으로 Claude API 호출 (사용자 확인 없음)
  ↓
결과를 바로 PlaceCard에 반영
```

**장점**: 편리함
**단점**: 사용자가 비용 예측 불가, 투명성 떨어짐
**권장 대상**: 고급 사용자, 무제한 할당량

---

### Option 2: `askEachTime` (매번 확인, 기본값, 권장)

```
사용자가 스크린샷 추가
  ↓
다이얼로그:
┌──────────────────────────────────┐
│ 💬 위치 분석                      │
├──────────────────────────────────┤
│                                   │
│ 이 스크린샷의 위치명을 Claude AI  │
│ 로 분석하시겠어요?                │
│                                   │
│ 예상 비용: ~$0.010                │
│ (사용자의 Anthropic 계정으로 청구) │
│                                   │
│ [취소]        [분석하기]          │
└──────────────────────────────────┘
  ↓ (사용자가 \"분석하기\" 클릭)
Claude API 호출
  ↓
결과 제시 + 사용자 확인
```

**장점**: 완전 투명성, 비용 제어, 신뢰도 높음
**단점**: 약간의 추가 탭 필요
**권장 대상**: 일반 사용자, 이 프로젝트 **기본값**

---

### Option 3: `manualOnly` (AI 미사용)

```
사용자가 스크린샷 추가
  ↓
Claude API 호출 안 함
  ↓
사용자가 수동으로 위치명/주소 입력
  ↓
Google Places API로 검증
```

**장점**: Claude API 비용 0원, 완전 제어
**단점**: 사용자 입력 번거로움, AI 편의성 포기
**권장 대상**: 가벼운 사용, 비용 최소화 원하는 사용자

---

## 5.3 BYOK (Bring Your Own Key) 모델

### 개념

사용자가 **자신의 Anthropic API 키를 앱에 등록**하여, Claude API 호출 시 사용자 계정으로 청구하는 방식입니다.

### 아키텍처

```
사용자
  ↓ 1. Anthropic 계정 생성
Anthropic 콘솔 (console.anthropic.com)
  ↓ 2. API 키 발급
사용자 API 키 복사
  ↓ 3. PlaceCards 앱의 설정에 입력
┌─────────────────────────────────┐
│   PlaceCards 앱 (iOS)           │
│ ├─ [설정] > [Claude API 키]     │
│ │  └─ 입력 필드 + \"검증\" 버튼  │
│ │                              │
│ └─ Keychain에 안전히 저장      │
└────────────┬────────────────────┘
             ↓ 4. 이미지 분석 시 사용
        Claude API 호출
             ↓
        비용: 사용자 계정에서 청구
             ↓
        사용자가 Anthropic 콘솔에서 확인
```

### 장점

| 항목 | 설명 |
|------|------|
| **앱 비용** | 0원 (API 인프라 비용 부담 없음) |
| **사용자 투명성** | Anthropic 계정에서 직접 사용량 및 청구 내역 확인 |
| **개인정보 보호** | 이미지가 사용자의 API 키로만 Anthropic 전송 (중간 서버 경유 안 함) |
| **확장성** | 사용자 수 증가 시에도 앱 비용 증가 없음 |
| **사용자 제어** | 언제든 API 키를 비활성화하거나 교체 가능 |

### 단점

| 항목 | 설명 | 대응 |
|------|------|------|
| **사용자 번거로움** | Anthropic 계정 생성/키 발급 필요 | 온보딩 화면에서 단계별 가이드 제공 |
| **초기 비용** | 사용자가 Claude API 비용 직접 부담 | 월 $5-20 정도면 충분한 비용 설명 |
| **기술 장벽** | API 키 개념이 낯설 수 있음 | \"설명\" 버튼, \"자주 묻는 질문\" 제공 |

---

## 5.4 BYOK 구현 흐름

### Step 1: 온보딩 (첫 실행)

```
[PlaceCards 앱 첫 실행]
  ↓
[온보딩 화면 1/3]
┌────────────────────────────────┐
│ 📍 PlaceCards에 오신 것을 환영합니다 │
├────────────────────────────────┤
│                                 │
│ 여행 장소를 한 곳에서 관리하세요 │
│                                 │
│ [다음]                          │
└────────────────────────────────┘
  ↓
[온보딩 화면 2/3 - 필수 기능]
┌────────────────────────────────┐
│ 🤖 AI 기반 위치 인식            │
├────────────────────────────────┤
│                                 │
│ 스크린샷에서 자동으로 위치명을  │
│ 추출합니다 (Claude AI 기반)     │
│                                 │
│ ⓘ 비용은 사용자님이 부담합니다  │
│    (월 ~$5-20 추정)             │
│                                 │
│ [다음]                          │
└────────────────────────────────┘
  ↓
[온보딩 화면 3/3 - API 키 설정]
┌────────────────────────────────┐
│ 🔑 Claude API 키 등록          │
├────────────────────────────────┤
│                                 │
│ 1. Anthropic 방문하기           │
│    console.anthropic.com        │
│ 2. \"API 키\" 복사하기           │
│ 3. 아래 붙여넣기                │
│                                 │
│ [입력 필드]                     │
│ [검증]                          │
│                                 │
│ [건너뛰기]  [완료]              │
└────────────────────────────────┘
```

---

### Step 2: API 키 검증

```swift
// iOS 앱 코드
class ClaudeAPIService {
    func verifyAPIKey(_ key: String) async throws -> Bool {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let payload = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 10,
            "messages": [
                [
                    "role": "user",
                    "content": "Say 'ok'"
                ]
            ]
        ] as [String : Any]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 200 {
            return true
        }
        return false
    }
}
```

**성공 시**:
```
✅ API 키가 유효합니다!

이제 인스타그램 스크린샷을 추가할 때
Claude AI가 위치명을 자동으로 분석해줍니다.

[완료]
```

**실패 시**:
```
❌ API 키가 유효하지 않습니다.

확인 사항:
• Anthropic 계정에서 키를 복사했나요?
• 전체 키를 붙여넣었나요? (공백 없이)
• 키가 비활성화되지 않았나요?

[도움말 보기]  [다시 시도]
```

---

### Step 3: Keychain 저장

```swift
import Security

class KeychainService {
    static let service = "com.placecards.app"
    static let account = "anthropic_api_key"
    
    static func saveAPIKey(_ key: String) throws {
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecService as String: service,
            kSecAccount as String: account,
            kSecValue as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // 기존 항목이 있으면 삭제
        SecItemDelete(query as CFDictionary)
        
        // 새로 저장
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }
    
    static func getAPIKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecService as String: service,
            kSecAccount as String: account,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }
        
        return key
    }
    
    static func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecService as String: service,
            kSecAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainError.deleteFailed
        }
    }
}
```

**Keychain 설정의 핵심**:
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 
  → 기기 잠금 해제 시에만 접근 가능
  → iCloud 동기화 안 함 (보안성 최고)

---

### Step 4: 이미지 분석 시 사용

```swift
class PlaceCardService {
    async func analyzeScreenshot(
        _ uiImage: UIImage,
        policy: AIAnalysisPolicy
    ) async throws -> AnalysisResult {
        // 정책에 따라 사용자 확인
        if policy == .askEachTime {
            let userConfirmed = await showAnalysisConfirmationDialog()
            guard userConfirmed else {
                throw UserCancelledError()
            }
        }
        
        // Keychain에서 API 키 로드
        let apiKey = try KeychainService.getAPIKey()
        
        // 이미지를 base64로 인코딩
        guard let imageData = uiImage.jpegData(compressionQuality: 0.8) else {
            throw ImageConversionError()
        }
        let base64Image = imageData.base64EncodedString()
        
        // Claude API 호출
        let result = try await claudeService.analyzeImage(
            base64Image: base64Image,
            apiKey: apiKey
        )
        
        return result
    }
}
```

---

## 5.5 비용 추정 및 사용자 안내

### 월별 비용 시뮬레이션

| 사용 패턴 | 월 분석 건수 | 월 비용 | 연간 비용 |
|---------|--------|--------|---------|
| **라이트** (주 1-2회) | ~10건 | ~$0.06 | ~$0.72 |
| **노멀** (주 3-5회) | ~50건 | ~$0.30 | ~$3.60 |
| **헤비** (매일) | ~100건 | ~$0.60 | ~$7.20 |
| **파워** (하루 10회) | ~300건 | ~$1.80 | ~$21.60 |

**결론**: 거의 모든 사용자가 월 $1-5 범위 내

### 앱 내 표시 방식

```
[설정] > [Claude AI]

┌────────────────────────────────┐
│ 🤖 Claude AI 분석 기능         │
├────────────────────────────────┤
│                                 │
│ ✅ 활성화됨                     │
│                                 │
│ API 키: ***...***               │
│ [변경하기]  [삭제하기]          │
│                                 │
│ 비용 정보                        │
│ ├─ 예상 월간 비용: ~$5-20      │
│ ├─ Anthropic 계정에서 청구됨  │
│ └─ 청구 내역 보기              │
│    (console.anthropic.com)     │
│                                 │
│ 분석 정책                        │
│ ○ 매번 확인하기 (권장)         │
│ ○ 자동 분석                    │
│ ○ 사용 안 함                   │
│                                 │
└────────────────────────────────┘
```

---

## 5.6 오류 처리

### API 키 만료/무효화

```
사용자가 인스타그램 스크린샷 분석 시도
  ↓
Claude API 401 Unauthorized
  ↓
앱에서 감지
  ↓
다이얼로그:
┌──────────────────────────────────┐
│ ⚠️ API 키 문제 발생              │
├──────────────────────────────────┤
│                                   │
│ Claude API 키가 더 이상 유효하지 │
│ 않습니다.                         │
│                                   │
│ Anthropic 콘솔에서 새 키를        │
│ 발급받아 다시 입력해주세요.       │
│                                   │
│ [설정으로 가기]  [닫기]          │
└──────────────────────────────────┘
```

### 할당량 초과

```
Claude API 응답: \"Too Many Requests\"
  ↓
다이얼로그:
┌──────────────────────────────────┐
│ ℹ️ 일시적 오류                   │
├──────────────────────────────────┤
│                                   │
│ Claude AI 분석이 일시적으로      │
│ 불가능합니다.                    │
│                                   │
│ (할당량 초과 또는 일시적 오류)   │
│                                   │
│ 잠시 후 다시 시도해주세요.       │
│                                   │
│ [닫기]  [나중에 시도]            │
└──────────────────────────────────┘
```

---

## 5.7 사용자 교육 자료

### FAQ 섹션

```
Q1: Claude API 키란 무엇인가요?
A: API 키는 PlaceCards가 Claude AI 서비스를 사용할 수 있도록 
   Anthropic이 발급하는 인증 코드입니다. 
   비밀번호와 같이 안전히 보관해야 합니다.

Q2: 정말로 비용이 청구되나요?
A: 네, 이미지 분석 시 Anthropic 계정으로 청구됩니다. 
   하지만 대부분의 사용자는 월 $1-5 범위 내입니다.
   (100건 분석 = 약 $0.60)

Q3: Anthropic 계정은 어떻게 만드나요?
A: console.anthropic.com을 방문하고 \"Sign Up\" 클릭 후,
   이메일로 계정을 생성하세요.
   가입 후 Credit $5를 받을 수 있습니다. (최신 정보 확인 필요)

Q4: API 키가 노출되면 어떻게 하나요?
A: 즉시 Anthropic 콘솔에서 해당 키를 비활성화하고 새 키를 
   발급받으세요. 그 후 앱에서 새 키로 업데이트하면 됩니다.

Q5: Claude 분석을 사용하지 않고도 앱을 쓸 수 있나요?
A: 네, [설정]에서 \"분석 정책\"을 \"사용 안 함\"으로 변경하면
   수동 입력만 사용할 수 있습니다.
```

---

## 5.8 Privacy Policy 명시 사항

```
## Claude API (인스타그램 분석)

PlaceCards는 Anthropic의 Claude API를 사용하여 
인스타그램 스크린샷에서 위치명을 자동으로 분석합니다.

- 이미지는 사용자의 Anthropic API 키를 통해 
  직접 Anthropic으로 전송됩니다.
  
- 이미지는 앱 운영자의 서버를 거치지 않습니다.
  
- 처리는 Anthropic의 Privacy Policy에 따릅니다:
  https://www.anthropic.com/privacy
  
- 사용자는 언제든 Anthropic 계정에서 API 키를 
  비활성화하거나 교체할 수 있습니다.
```

---

## 5.9 다음 단계

- [ ] Anthropic 계정 생성 및 API 테스트
- [ ] Claude API 가격 모니터링
- [ ] Keychain 저장 코드 구현 및 테스트
- [ ] 온보딩 UI/UX 설계
- [ ] 에러 처리 및 재시도 로직 구현
- [ ] Privacy Policy 작성 및 검토

---

*작성: 2026-09-09 | 상태: 완료*
