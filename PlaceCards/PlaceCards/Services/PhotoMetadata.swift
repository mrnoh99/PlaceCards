import Foundation
import ImageIO
import CoreLocation

/// Best-effort extraction of a photo's own embedded GPS coordinate (EXIF)
/// — used to narrow ("locationBias") the Google Places search when adding
/// a place from an on-site photo that has one, instead of a blind text
/// search. Ported from Peragra's `PhotoMetadata` (there also reads capture
/// time/accuracy for its own on-site GPS-capture flow, which PlaceCards
/// doesn't have, so only the coordinate is extracted here).
enum PhotoMetadata {
    /// 사진 한 장에서 읽어 낸 것. 찍힌 자리와 찍힌 때 — 둘 다 없을 수
    /// 있다.
    ///
    /// `MediaItem`에 그대로 얹어 둔다(`capturedAt`·`capturedCoordinates`).
    /// 저장할 때 읽어 두지 않으면 나중에 읽을 길이 없기 때문이다:
    /// 사용자가 고른 사진은 `MediaStore.saveImage(_ image:)`가 `UIImage`로
    /// 다시 인코딩해서 넣으므로 **디스크에 남는 파일에는 EXIF가 없다.**
    struct Capture: Equatable {
        var takenAt: Date? = nil
        var coordinates: Coordinates? = nil

        var isEmpty: Bool { takenAt == nil && coordinates == nil }
    }

    /// 자리와 때를 한 번에. `data`에 대한 조건은 `extractLocation`과 같다.
    static func extractCapture(from data: Data) -> Capture {
        Capture(takenAt: extractCaptureDate(from: data), coordinates: extractLocation(from: data))
    }

    /// 찍힌 때. EXIF의 `DateTimeOriginal`을 먼저 보고, 없으면
    /// `DateTimeDigitized`를 본다 — 앞의 것이 셔터가 눌린 순간이고, 뒤의
    /// 것은 파일이 만들어진 때라 스캔·복사본에서만 다르다.
    ///
    /// EXIF의 날짜는 시간대 없이 `"2026:09:21 20:06:11"` 꼴이라, 찍은
    /// 기기의 현지 시각 그대로 읽는다(`Calendar.current`의 시간대). 방문
    /// **날짜**만 쓰는 용도라 이게 맞다 — UTC로 읽으면 저녁에 찍은 한국
    /// 사진이 하루 전으로 밀린다.
    static func extractCaptureDate(from data: Data) -> Date? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        else {
            return nil
        }
        let raw = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String)
        guard let raw else { return nil }
        return exifDateFormatter.date(from: raw)
    }

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        // 기기 설정과 무관하게 같은 문자열을 같게 읽는다. 시간대는
        // 일부러 건드리지 않는다 — 위 주석 참고.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// `data` must be the original, unmodified bytes as picked — EXIF
    /// doesn't survive being decoded into a `UIImage` and re-encoded
    /// (e.g. via `UIImage.jpegData(compressionQuality:)`).
    static func extractLocation(from data: Data) -> Coordinates? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
            let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
            let longitude = gps[kCGImagePropertyGPSLongitude] as? Double,
            let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        else {
            return nil
        }
        let coordinate = Coordinates(
            latitude: latitudeRef == "S" ? -latitude : latitude,
            longitude: longitudeRef == "W" ? -longitude : longitude
        )
        // Some photo export/edit pipelines keep the GPS IFD structure but
        // write 0 for both latitude and longitude instead of omitting the
        // block entirely when there's no real location fix — no genuine
        // photo is actually taken at 0°N, 0°E (open ocean off the coast
        // of Africa, nicknamed "Null Island"), so this is treated the
        // same as no GPS data at all rather than a real coordinate that
        // would otherwise enable "GPS로 촬영위치찾기"/location-hint
        // features on a photo with no actual location in it.
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else {
            return nil
        }
        return coordinate
    }
}

/// 카드에 붙은 사진 중 **그 장소에서 찍힌 것**의 촬영 날짜를 방문 날짜
/// 후보로 내놓는다.
///
/// **꼭 있어야 하는 것은 촬영 날짜 하나다.** 날짜가 없으면 언제 갔는지를
/// 모르므로 아무것도 할 수 없다.
///
/// 위치는 **있으면 견주고, 없으면 넘어간다.** 예전에는 둘 다 있어야만
/// 받아들였는데, 그 탓에 위치 정보가 꺼진 채로 찍은 사진은 날짜가 뻔히
/// 있어도 전부 버려졌다 — 사용자에게는 "날짜가 적혀 있는데 못 찾는다"로
/// 보인다. 위치는 **반증하는 데** 쓰는 것이지 입증에 필요한 것이 아니다:
/// 다른 동네에서 찍힌 것이 드러나면 떨어뜨리고, 아무 말이 없으면 사용자가
/// 제 현장 사진으로 붙였다는 사실을 믿는다.
///
/// 그 믿음이 성립하는 것은 **`onsitePhotos`만 보기 때문**이다. 지도
/// 스크린샷은 `mapScreenshots`로, 남이 보내 준 사진은 `receivedPhotos`로,
/// Google이 준 사진은 `officialPhotos`로 따로 들어간다 — 위치 없이 믿었다가
/// 엉뚱한 날짜가 들어올 만한 것들은 애초에 이 배열에 없다.
enum PhotoVisitDates {
    /// 이 안에서 찍혔으면 "그 장소에서"로 친다.
    ///
    /// `PlaceCardViewModel.maxAddressMatchDistanceMeters`(100m)보다 넉넉하다.
    /// 저쪽은 두 좌표가 같은 곳을 가리키는지를 따지는 자리지만, 여기서는
    /// 가게 안이 아니라 **길 건너에서, 주차장에서, 건물 밖에서** 찍은 사진도
    /// 다 그 방문의 사진이다. 반대로 너무 넓히면 같은 날 옆 동네에서 찍은
    /// 사진이 남의 카드에 방문 기록을 남긴다.
    static let maxOnsiteDistanceMeters: CLLocationDistance = 200

    /// 아직 기록되지 않은 날짜만, 이른 것부터. 같은 날 여러 장을 찍었으면
    /// 하루로 묶는다.
    ///
    /// **현장 사진(`onsitePhotos`)만 본다.** 지도 스크린샷은 그 장소가 아니라
    /// 스크린샷을 찍은 자리에서 만들어지고, Google이 준 공식 사진과 전달받은
    /// 사진은 애초에 사용자가 찍은 것이 아니다 — 셋 다 "내가 거기 있었다"의
    /// 근거가 못 된다.
    static func candidates(for card: PlaceCard) -> [Date] {
        // 기준점이 없어도 **멈추지 않는다.** 견줄 것이 없다는 뜻이지,
        // 날짜를 못 쓴다는 뜻이 아니다.
        let place = reference(for: card)
        let calendar = Calendar.current

        var found: [Date] = []
        for item in card.media.onsitePhotos {
            let capture = capture(of: item)
            guard let takenAt = capture.takenAt else { continue }
            if let place, let taken = capture.coordinates,
               place.distance(from: CLLocation(latitude: taken.latitude, longitude: taken.longitude))
                > maxOnsiteDistanceMeters {
                // 다른 데서 찍힌 것이 **드러난** 사진만 떨어뜨린다.
                continue
            }
            let alreadyKnown = card.visitDates.contains { calendar.isDate($0, inSameDayAs: takenAt) }
                || found.contains { calendar.isDate($0, inSameDayAs: takenAt) }
            guard !alreadyKnown else { continue }
            found.append(takenAt)
        }
        return found.sorted()
    }

    /// `candidates`가 빈 손으로 돌아왔을 때 **왜 그런지** 한 줄로 답한다.
    ///
    /// 이게 없던 동안 화면에는 "촬영 날짜를 찾지 못했습니다" 하나뿐이었고,
    /// 그 한 줄이 서로 아주 다른 상황을 전부 덮었다 — 사진에 위치 정보가
    /// 없는 것, 날짜가 없는 것, 다른 데서 찍힌 것, 이미 다 적혀 있는 것.
    /// 사용자가 할 수 있는 일이 각각 다른데 구별이 안 되니 "기능이 안 된다"로
    /// 보인다. 특히 **위치 정보가 꺼진 채로 찍은 사진**이 제일 흔한데, 그건
    /// 앱이 고칠 수 있는 것이 아니라 사용자가 카메라 설정에서 켜야 하는
    /// 것이다.
    ///
    /// 검사 순서는 `candidates`가 걸러 내는 순서와 같게 둔다. 그래야 여기서
    /// 하는 말과 저기서 하는 일이 어긋나지 않는다.
    static func reasonNothingFound(for card: PlaceCard) -> String {
        let photos = card.media.onsitePhotos
        guard !photos.isEmpty else {
            return "현장에서 찍은 사진이 없습니다. 사진을 먼저 추가해주세요.".localized
        }

        let captures = photos.map { capture(of: $0) }
        let dated = captures.filter { $0.takenAt != nil }
        guard !dated.isEmpty else {
            return "사진에 촬영 날짜가 없습니다.".localized
        }

        // 날짜는 있는데 아무것도 안 나왔다면 남은 이유는 둘뿐이다.
        // 거리 계산은 다시 쓰지 않는다 — 두 벌로 갈라지면 한쪽만 고치게 된다.
        let calendar = Calendar.current
        let allKnown = dated.allSatisfy { capture in
            guard let takenAt = capture.takenAt else { return true }
            return card.visitDates.contains { calendar.isDate($0, inSameDayAs: takenAt) }
        }
        if allKnown {
            return "사진의 촬영 날짜는 이미 모두 기록돼 있습니다.".localized
        }
        // 여기까지 오는 것은 확정된 좌표가 실제로 사진을 물리쳤을 때뿐이다.
        // 확정 전에는 사진들끼리 견주므로 첫 장이 늘 통과한다.
        return "사진이 이 장소에서 멀리 떨어진 곳에서 찍혔습니다.".localized
    }

    /// 사진이 "그 장소에서" 찍혔는지 견줄 기준점. **없을 수 있고, 없어도
    /// 된다** — 견줄 것이 없다는 뜻이지 날짜를 못 쓴다는 뜻이 아니다
    /// (`candidates` 참고).
    ///
    /// **확정된 좌표만 기준으로 삼는다**(`isPlaceConfirmed` — Google이나
    /// Naver의 실제 등록 정보와 맞춰진 것). 확정 전 좌표는 AI가 사진에서
    /// 읽은 주소를 지오코딩한 **추정치**라 실제 장소에서 수백 미터씩 어긋날
    /// 수 있는데, 사진의 GPS는 기기가 그 자리에서 잰 **실측**이다. 추정치로
    /// 실측을 반증하면 앞뒤가 바뀐다 — 실제로 그 탓에 "구글에서 검색해
    /// 저장하면 그때서야 날짜가 들어온다"가 됐다. 확정하는 순간 좌표가
    /// 진짜 값으로 바뀌면서 같은 사진이 200m 안으로 들어왔던 것이다.
    ///
    /// 확정 전에는 **현장 사진 중 GPS가 있는 첫 장**을 기준으로 삼아 사진들끼리
    /// 견준다. 그러면 "한 자리에서 찍힌 사진 묶음"이라는 조건은 그대로 살아
    /// 있으면서, 그 자리가 어디인지를 추정치에게 묻지 않는다. 첫 장을 쓰는
    /// 것은 정하기 나름이지만 배열 차례가 곧 붙인 차례라 결과가 늘 같다.
    ///
    /// 나중에 확정되면 그다음부터는 카드 좌표가 기준이 된다 — 이미 적힌
    /// 날짜를 되돌리지는 않는다.
    private static func reference(for card: PlaceCard) -> CLLocation? {
        if card.isPlaceConfirmed, let coordinates = card.coordinates {
            return CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
        }
        for item in card.media.onsitePhotos {
            guard let taken = capture(of: item).coordinates else { continue }
            return CLLocation(latitude: taken.latitude, longitude: taken.longitude)
        }
        return nil
    }

    /// 저장해 둔 값이 있으면 그것을, 없으면 파일에서 읽는다.
    ///
    /// 뒤쪽이 있어야 하는 이유: `capturedAt`/`capturedCoordinates`가 생기기
    /// **전에** 저장된 사진에는 그 값이 없다. 그런 사진도 원본 바이트 그대로
    /// 저장된 것(공유로 들어온 사진)이면 파일에서 아직 읽어 낼 수 있다.
    private static func capture(of item: MediaItem) -> PhotoMetadata.Capture {
        let stored = PhotoMetadata.Capture(
            takenAt: item.capturedAt, coordinates: item.capturedCoordinates
        )
        guard stored.isEmpty else { return stored }
        guard let data = MediaStore.loadData(fileName: item.localPath) else { return stored }
        return PhotoMetadata.extractCapture(from: data)
    }
}
