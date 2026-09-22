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
/// 판단 기준은 사진의 EXIF 두 가지가 **둘 다** 있을 때뿐이다 — 찍힌 자리가
/// 카드의 좌표와 가깝고(`maxOnsiteDistanceMeters`), 찍힌 때가 있을 것.
/// 하나라도 없으면 그 사진은 아무것도 말해 주지 않는 것으로 친다. 날짜만
/// 있고 자리가 없으면 남이 보내 준 사진인지 현장 사진인지 구별할 수 없고,
/// 자리만 있고 날짜가 없으면 언제 갔는지를 모른다.
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
        guard let place = reference(for: card) else { return [] }
        let calendar = Calendar.current

        var found: [Date] = []
        for item in card.media.onsitePhotos {
            let capture = capture(of: item)
            guard let takenAt = capture.takenAt, let taken = capture.coordinates else { continue }
            let distance = place.distance(
                from: CLLocation(latitude: taken.latitude, longitude: taken.longitude)
            )
            guard distance <= maxOnsiteDistanceMeters else { continue }
            let alreadyKnown = card.visitDates.contains { calendar.isDate($0, inSameDayAs: takenAt) }
                || found.contains { calendar.isDate($0, inSameDayAs: takenAt) }
            guard !alreadyKnown else { continue }
            found.append(takenAt)
        }
        return found.sorted()
    }

    /// 사진이 "그 장소에서" 찍혔는지 견줄 기준점.
    ///
    /// 카드 좌표가 있으면 그것이다. **없으면 현장 사진 중 GPS가 있는 첫 장의
    /// 위치를 쓴다.**
    ///
    /// 왜 그냥 포기하지 않는가. 예전에는 좌표가 없으면 바로 빈 손으로
    /// 돌아왔는데, 사진을 공유해 만든 카드에는 좌표가 **아직** 없다 —
    /// 지도에서 장소를 확정해야 비로소 생긴다. 그래서 "사진 날짜가 구글에서
    /// 확정한 뒤에야 나타난다"가 됐다. 단추(`PlaceCardDetailView`)까지 그때는
    /// 비활성이라 손으로 부를 수도 없었다.
    ///
    /// 왜 이래도 안전한가. 견주는 일 자체를 없앤 것이 아니라 **기준점을 사진
    /// 쪽에서 세울 뿐**이다. GPS가 없는 사진은 여전히 한 장도 통과하지 못하고
    /// (지도 스크린샷·웹에서 받은 사진이 대개 그렇다), 200m 검사도 그대로
    /// 남아 첫 장에서 멀리 떨어진 사진은 떨어진다. 즉 "한 자리에서 찍힌
    /// 사진 묶음"이라는 조건은 그대로고, 그 자리가 어디인지를 구글에게 묻지
    /// 않을 뿐이다.
    ///
    /// 첫 장을 쓰는 것은 정하기 나름이지만 배열 차례가 곧 붙인 차례라
    /// 결과가 늘 같다. 좌표가 나중에 생기면 그다음부터는 카드 좌표가 기준이
    /// 된다 — 이미 적힌 날짜를 되돌리지는 않는다.
    private static func reference(for card: PlaceCard) -> CLLocation? {
        if let coordinates = card.coordinates {
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
