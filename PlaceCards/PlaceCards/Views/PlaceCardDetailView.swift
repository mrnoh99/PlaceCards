import SwiftUI
import MapKit

/// Shows every field a `PlaceCard` carries, not just the handful the list
/// row/grid cell have room for — and the same action set Peragra's
/// `PlaceRowView` offers (favorite/visited toggle, call, a map-provider
/// menu, Instagram, website, edit), which this screen didn't have before.
/// Also offers filling in whatever Google's own lookup left blank
/// (address/phone/category/coordinates) from Naver Local Search — see
/// `naverRefineSection`.
struct PlaceCardDetailView: View {
    @State private var card: PlaceCard

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.openURL) private var openURL
    @State private var isPresentingEdit = false
    @State private var isRefiningWithNaver = false
    @State private var naverStatusMessage: String?

    init(card: PlaceCard) {
        _card = State(initialValue: card)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !card.media.allItems.isEmpty {
                    TabView {
                        ForEach(card.media.allItems) { item in
                            if let image = MediaStore.loadImage(fileName: item.localPath) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 240)
                }

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

                if missingNaverFillableFields || naverStatusMessage != nil {
                    naverRefineSection
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

                    Button {
                        openInPreferredMap(coordinates: coordinates)
                    } label: {
                        Label("지도에서 열기", systemImage: "map")
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
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

    /// Call / map-provider menu / website / Instagram, in one row — the
    /// same set of actions Peragra's `PlaceRowView` offers, which this
    /// screen previously had none of at all (only a single "open in the
    /// default map app" button below).
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
            if card.hasAnyMapLink {
                Menu {
                    if let url = GoogleMapsOpener.url(for: card) {
                        Button("Google Maps") { openURL(url) }
                    }
                    if let url = NaverMapOpener.url(for: card) {
                        Button("Naver Map") { openURL(url) }
                    }
                    if let url = KakaoMapOpener.url(for: card) {
                        Button("Kakao Map") { openURL(url) }
                    }
                    if let url = TmapOpener.url(for: card) {
                        Button("Tmap") { openURL(url) }
                    }
                } label: {
                    Label("길찾기", systemImage: "map")
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

    /// Whether Naver Local Search could plausibly still add something here
    /// — address/phone/category/coordinates are the only fields it returns
    /// (see `NaverSearchResult`), so this only checks those, not every
    /// field Google leaves blank.
    private var missingNaverFillableFields: Bool {
        card.address.trimmingCharacters(in: .whitespaces).isEmpty
            || (card.phone?.isEmpty ?? true)
            || (card.category?.isEmpty ?? true)
            || card.coordinates == nil
    }

    /// Looks this place up on Naver Local Search and fills in whatever of
    /// address/phone/category/coordinates is still blank — the remaining
    /// fields Google's own lookup didn't provide (see `PlaceSearchService`)
    /// can often still be found there, since Naver's Korean place data is
    /// generally better than Google's. Mirrors
    /// `PlaceCardViewModel.refineWithNaver` (used when adding a place) but
    /// applied here to an already-saved card, and — like everywhere else in
    /// this app that "fills in" data — only ever adds to a blank field,
    /// never overwrites one that's already set.
    @ViewBuilder
    private var naverRefineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await refineWithNaver() }
            } label: {
                if isRefiningWithNaver {
                    ProgressView()
                } else {
                    Label("Naver 지도에서 정보 보완", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefiningWithNaver)

            if let naverStatusMessage {
                Text(naverStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    /// Opens the map app chosen in Settings — Apple Maps directly via
    /// `MKMapItem`, or Google/Naver Maps via their own "open in..." link.
    /// Naver has no useful data outside Korea, so falls back to Google
    /// Maps there instead of silently doing nothing.
    private func openInPreferredMap(coordinates: Coordinates) {
        let provider = SettingsViewModel.currentMapProvider()
        guard provider != .apple else {
            openInAppleMaps(coordinates: coordinates, name: card.name)
            return
        }
        if let url = provider.url(for: card) {
            openURL(url)
        } else if let url = GoogleMapsOpener.url(for: card) {
            openURL(url)
        }
    }

    private func openInAppleMaps(coordinates: Coordinates, name: String) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps()
    }

    private func refineWithNaver() async {
        guard let credentials = SettingsViewModel.currentNaverLocalSearchCredentials() else {
            naverStatusMessage = PlaceCardsError.apiKeyMissing.localizedDescription
            return
        }

        isRefiningWithNaver = true
        defer { isRefiningWithNaver = false }

        let naverService = NaverLocalSearchService(clientId: credentials.clientId, clientSecret: credentials.clientSecret)
        do {
            guard let result = try await naverService.search(query: card.name, display: 1).first else {
                naverStatusMessage = PlaceCardsError.noResults.localizedDescription
                return
            }
            applyNaverResult(result)
        } catch {
            naverStatusMessage = error.localizedDescription
        }
    }

    private func applyNaverResult(_ result: NaverSearchResult) {
        var filledLabels: [String] = []
        var dataProvided: [String] = []

        if card.address.trimmingCharacters(in: .whitespaces).isEmpty, !result.address.isEmpty {
            card.address = result.address
            filledLabels.append("주소")
            dataProvided.append("address")
        }
        if (card.phone?.isEmpty ?? true), let phone = result.phone, !phone.isEmpty {
            card.phone = phone
            filledLabels.append("전화번호")
            dataProvided.append("phone")
        }
        if (card.category?.isEmpty ?? true), let category = result.category, !category.isEmpty {
            card.category = category
            filledLabels.append("카테고리")
            dataProvided.append("category")
        }
        if card.coordinates == nil, let coordinates = result.coordinates {
            card.coordinates = coordinates
            filledLabels.append("좌표")
            dataProvided.append("coordinates")
        }

        guard !filledLabels.isEmpty else {
            naverStatusMessage = "Naver 지도에서 이미 채워진 정보 외에 추가로 찾은 게 없습니다."
            return
        }

        card.sources.append(SourceRecord(sourceType: .naverDirectLookup, dataProvided: dataProvided))
        storageService.save(card)
        naverStatusMessage = "\(filledLabels.joined(separator: ", "))를 채웠습니다."
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
