import SwiftUI
import MapKit

/// Shows every field a `PlaceCard` carries, not just the handful the list
/// row/grid cell have room for — and the same action set Peragra's
/// `PlaceRowView` offers (favorite/visited toggle, call, a map-provider
/// menu, Instagram, website, edit), which this screen didn't have before.
struct PlaceCardDetailView: View {
    @State private var card: PlaceCard

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.openURL) private var openURL
    @State private var isPresentingEdit = false

    init(card: PlaceCard) {
        _card = State(initialValue: card)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(card.name)
                            .font(.title.bold())
                        Spacer()
                        HStack(spacing: 12) {
                            Button(action: toggleVisited) {
                                Image(systemName: card.isVisited ? "checkmark.circle.fill" : "checkmark.circle")
                                    .foregroundStyle(card.isVisited ? .green : .secondary)
                            }
                            Button(action: toggleFavorite) {
                                Image(systemName: card.isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(card.isFavorite ? .yellow : .secondary)
                            }
                        }
                        .font(.title3)
                        .buttonStyle(.plain)
                    }
                    if let category = card.category, !category.isEmpty {
                        Label(PlaceCategoryIcon.normalizedLabel(for: category), systemImage: PlaceCategoryIcon.symbolName(for: category))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !card.address.isEmpty {
                        Text(card.address)
                            .font(.body)
                    }

                    HStack(spacing: 16) {
                        if let rating = card.rating {
                            Label(String(format: "%.1f", rating), systemImage: "star")
                                .foregroundStyle(.orange)
                        }
                        if let reviewCount = card.reviewCount {
                            Text("리뷰 \(reviewCount)개")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal)

                if card.hasAnyAction {
                    actionRow
                        .padding(.horizontal)
                }

                if hasHoursInfo {
                    hoursSection
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !card.amenities.isEmpty {
                        Text("편의시설")
                            .font(.headline)
                        WrapTagsView(tags: card.amenities)
                    }

                    if !card.tags.isEmpty {
                        Text("태그")
                            .font(.headline)
                        WrapTagsView(tags: card.tags)
                    }
                }
                .padding(.horizontal)

                if let coordinates = card.coordinates {
                    Map(
                        coordinateRegion: .constant(
                            MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude),
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )
                        ),
                        annotationItems: [card]
                    ) { item in
                        MapMarker(coordinate: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude))
                    }
                    .frame(height: 180)
                    .padding(.horizontal)
                    .allowsHitTesting(false)

                    if card.hasAnyMapLink {
                        mapMenu
                            .padding(.horizontal)
                    }
                }

                ShareLink(item: shareText) {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                if !card.sources.isEmpty || card.discoverySource != nil {
                    sourcesSection
                        .padding(.horizontal)
                }

                metaFooter
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingEdit = true
                } label: {
                    Label("편집", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $isPresentingEdit) {
            EditPlaceCardSheet(card: card) { updated in
                card = updated
            }
        }
    }

    /// Call / website / Instagram, in one row — mirrors Peragra's
    /// `PlaceRowView` action set, minus the map action (`mapMenu` below,
    /// shown alongside the map preview instead of duplicating it here).
    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 20) {
            if let callURL = card.callURL {
                Button {
                    openURL(callURL)
                } label: {
                    Label("전화", systemImage: "phone")
                }
            }
            if let website = card.website, let url = URL(string: website) {
                Button {
                    openURL(url)
                } label: {
                    Label("웹사이트", systemImage: "link")
                }
            }
            if let instagramURL = card.instagramURL, let url = URL(string: instagramURL) {
                Button {
                    openURL(url)
                } label: {
                    Label("인스타그램", systemImage: "camera")
                }
                .tint(.pink)
            }
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    /// "지도에서 열기" — Google Maps와 Apple 지도는 항상, Naver/Kakao
    /// Map·Tmap은 한국 내 장소일 때만 제공(각 opener가 좌표로 직접
    /// 판단, `KoreaRegion` 참고). 탭하는 순간 `MapOpenContext`에 이
    /// 카드를 기록해서, 지도 앱에서 스크린샷을 찍어 공유로 돌아왔을 때
    /// 새 카드가 아니라 이 카드에 바로 반영할 수 있게 함.
    @ViewBuilder
    private var mapMenu: some View {
        Menu {
            if GoogleMapsOpener.url(for: card) != nil {
                Button("Google Maps") {
                    MapOpenContext.recordMapOpen(cardID: card.id)
                    GoogleMapsOpener.open(for: card, using: openURL)
                }
            }
            if card.coordinates != nil {
                Button("Apple 지도") {
                    MapOpenContext.recordMapOpen(cardID: card.id)
                    AppleMapsOpener.open(for: card)
                }
            }
            if let url = NaverMapOpener.url(for: card) {
                Button("Naver Map") {
                    MapOpenContext.recordMapOpen(cardID: card.id)
                    openURL(url)
                }
            }
            if let url = KakaoMapOpener.url(for: card) {
                Button("Kakao Map") {
                    MapOpenContext.recordMapOpen(cardID: card.id)
                    openURL(url)
                }
            }
            if let url = TmapOpener.url(for: card) {
                Button("Tmap") {
                    MapOpenContext.recordMapOpen(cardID: card.id)
                    openURL(url)
                }
            }
        } label: {
            Label("지도에서 열기", systemImage: "map")
        }
        .buttonStyle(.bordered)
    }

    private var hasHoursInfo: Bool {
        card.hoursDetail?.isEmpty == false || card.closingTime?.isEmpty == false || card.holidays?.isEmpty == false
    }

    @ViewBuilder
    private var hoursSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("영업 정보")
                .font(.headline)
            if let hoursDetail = card.hoursDetail, !hoursDetail.isEmpty {
                ForEach(hoursDetail.sorted(by: { $0.key < $1.key }), id: \.key) { day, hours in
                    HStack {
                        Text(day).foregroundStyle(.secondary)
                        Spacer()
                        Text(hours)
                    }
                    .font(.subheadline)
                }
            }
            if let closingTime = card.closingTime, !closingTime.isEmpty {
                Label("마감 \(closingTime)", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let holidays = card.holidays, !holidays.isEmpty {
                Label("휴무일 \(holidays)", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// How this card's data was populated/verified over time
    /// (`PlaceCard.sources`) and, when it was first found on social media
    /// before being verified against a map API (`discoverySource`) —
    /// neither was surfaced anywhere in the UI before.
    @ViewBuilder
    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("정보 출처")
                .font(.headline)
            if let discoverySource = card.discoverySource {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(discoverySource.platform)에서 발견")
                        .font(.subheadline)
                    if let originalPostUrl = discoverySource.originalPostUrl, let url = URL(string: originalPostUrl) {
                        Link("원본 게시물 보기", destination: url)
                            .font(.caption)
                    }
                }
            }
            ForEach(card.sources) { source in
                HStack {
                    Text(source.sourceType.displayName)
                        .font(.caption)
                    Spacer()
                    Text(source.timestamp.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metaFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("추가한 날짜: \(card.createdAt.formatted(date: .abbreviated, time: .omitted))")
            if card.updatedAt != card.createdAt {
                Text("수정한 날짜: \(card.updatedAt.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var shareText: String {
        "\(card.name)\n\(card.address)"
    }

    private func toggleFavorite() {
        card.isFavorite.toggle()
        storageService.save(card)
    }

    private func toggleVisited() {
        card.isVisited.toggle()
        storageService.save(card)
    }
}

private struct WrapTagsView: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlaceCardDetailView(card: PlaceCard(boardId: "preview", name: "샘플 카페", address: "서울시 강남구"))
    }
    .environmentObject(StorageService())
}
