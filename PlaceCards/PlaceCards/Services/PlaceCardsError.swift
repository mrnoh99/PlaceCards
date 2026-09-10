import Foundation

enum PlaceCardsError: LocalizedError {
    case networkError(String)
    case apiError(String, statusCode: Int)
    case timeout
    case validationError(String)
    case decodingError(String)
    case saveFailed(String)
    case keychainError(String)
    case apiKeyMissing
    case apiKeyInvalid
    case rateLimited(String)
    case userCancelled
    case noResults
    case notImplemented(String)
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "네트워크 오류: ".localized + message
        case .apiError(let message, let statusCode):
            return "API 오류 (".localized + "\(statusCode)): " + message
        case .timeout:
            return "요청 시간이 초과되었습니다.".localized
        case .validationError(let message):
            return "입력 오류: ".localized + message
        case .decodingError(let message):
            return "데이터 처리 오류: ".localized + message
        case .saveFailed(let message):
            return "저장 실패: ".localized + message
        case .keychainError(let message):
            return "키체인 오류: ".localized + message
        case .apiKeyMissing:
            return "설정에서 API 키를 먼저 등록해주세요.".localized
        case .apiKeyInvalid:
            return "유효하지 않은 API 키입니다.".localized
        case .rateLimited(let service):
            return service + "의 호출 한도를 초과했습니다. 잠시 후 다시 시도해주세요.".localized
        case .userCancelled:
            return "사용자가 취소했습니다.".localized
        case .noResults:
            return "검색 결과가 없습니다.".localized
        case .notImplemented(let message):
            return "아직 지원하지 않는 기능입니다: ".localized + message
        case .invalidImage:
            return "이미지를 처리할 수 없습니다.".localized
        }
    }
}
