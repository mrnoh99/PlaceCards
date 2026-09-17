import SwiftUI
import MapKit

/// Which map renders the "지도" tab's pins — chosen right there in the
/// tab (a segmented picker in the nav bar), not buried in Settings.
/// Google/Naver need their own BYOK key/Client ID (see `SettingsView`);
/// Apple's needs nothing and is the default.
private enum MapDisplayProvider: String, CaseIterable, Identifiable {
    case apple, google, naver

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        case .naver: return "Naver"
        }
    }
}

struct PlacesMapView: View {
    @StateObject private var viewModel: MapViewModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var storageService: StorageService
    @State private var selectedCard: PlaceCard?
    @State private var searchQuery = ""
    /// The Apple map's own marker-tap callout, keyed by card id — mirrors
    /// the info popup Google/Naver's web-based maps already show on a
    /// marker tap (name, address, a "카드 보기" button) instead of the
    /// old behavior of jumping straight to the full card. Tapping the
    /// same marker again collapses it back down.
    @State private var calloutCardID: String?
    @AppStorage("mapDisplayProvider") private var displayProviderRaw: String = MapDisplayProvider.apple.rawValue

    private var displayProvider: MapDisplayProvider {
        MapDisplayProvider(rawValue: displayProviderRaw) ?? .apple
    }

    init(viewModel: MapViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    /// The board Home is currently showing, if any — used for the
    /// navigation title, and to look up its name.
    private var scopedBoard: Board? {
        guard let boardID = navigation.currentHomeBoardID else { return nil }
        return storageService.boards.first { $0.id == boardID }
    }

    /// Narrowed to `navigation.mapFilterIDs` when a board's "지도에서
    /// 보기" bulk action set it (an explicit one-shot pick, so it wins);
    /// otherwise to the board Home is currently showing, if any; otherwise
    /// every card, as usual — then further narrowed by `searchQuery`, so
    /// searching always searches *within* whatever's already showing.
    private var visibleCards: [PlaceCard] {
        let scoped: [PlaceCard]
        if let filterIDs = navigation.mapFilterIDs {
            scoped = viewModel.annotatedPlaceCards.filter { filterIDs.contains($0.id) }
        } else if let boardID = navigation.currentHomeBoardID {
            scoped = viewModel.annotatedPlaceCards.filter { $0.boardId == boardID }
        } else {
            scoped = viewModel.annotatedPlaceCards
        }

        return scoped.filter { $0.matchesSearch(searchQuery) }
    }

    /// `visibleCards` narrowed to places actually in Korea — Naver Maps has
    /// essentially no useful data outside Korea (same reasoning as
    /// `KoreaRegion`'s own doc comment), and worse, the embed page's own
    /// `map.fitBounds(bounds)` computes one bounding box across *every*
    /// marker it's handed: a single far-outside-Korea card in the mix (a
    /// trip abroad saved to the same board) was enough to zoom the whole
    /// map out to fit it, landing on some unrelated country/continent
    /// instead of Korea — reported as "지도가 안 움직인다"/"엉뚱한 곳이
    /// 뜬다" when it was actually correctly fitting bounds around a
    /// marker that shouldn't have been there at all.
    private var naverEligibleCards: [PlaceCard] {
        visibleCards.filter { card in
            guard let coordinates = card.coordinates else { return false }
            return KoreaRegion.contains(latitude: coordinates.latitude, longitude: coordinates.longitude)
        }
    }

    private var mapNavigationTitle: String {
        if navigation.mapFilterIDs != nil { return "선택한 장소".localized }
        if let scopedBoard { return scopedBoard.name }
        return "지도".localized
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasNothingToShow {
                    nothingToShowState
                } else {
                    Group {
                        switch displayProvider {
                        case .apple:
                            appleMap
                        case .google:
                            googleMap
                        case .naver:
                            naverMap
                        }
                    }
                    .overlay(alignment: .top) { excludedPlacesBanner }
                }
            }
            .navigationTitle(mapNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("지도".localized, selection: $displayProviderRaw) {
                        ForEach(MapDisplayProvider.allCases) { provider in
                            Text(provider.label).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                if navigation.mapFilterIDs != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("전체 보기".localized) { navigation.mapFilterIDs = nil }
                    }
                }
            }
            .fullScreenCover(item: $selectedCard) { card in
                NavigationStack {
                    PlaceCardDetailView(card: card)
                        .toolbar {
                            // `fullScreenCover` has no swipe-to-dismiss
                            // (unlike `.sheet`, which this replaced), so
                            // this is the only way back out.
                            ToolbarItem(placement: .cancellationAction) {
                                Button("닫기".localized) { selectedCard = nil }
                            }
                        }
                }
            }
            // `.always` so search stays visible without a pull-down/
            // scroll — matches Home/Gallery/BoardDetailView.
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "장소 검색".localized)
            // Only the Apple map has a SwiftUI-owned camera
            // (`viewModel.cameraPosition`) this can recenter directly — the
            // Google/Naver maps are WKWebViews with no such hook from
            // here, so for those, matching pins simply being the only
            // ones left on the map (via `visibleCards` above) is the
            // whole effect of a search there.
            .onChange(of: searchQuery) { _, newValue in
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty,
                      let firstMatch = visibleCards.first else { return }
                withAnimation {
                    viewModel.recenter(on: viewModel.coordinate(for: firstMatch))
                }
            }
            // Google/Naver each fit their own web map to every marker via
            // `map.fitBounds` on load — Apple's `cameraPosition` has no
            // such built-in behavior and otherwise just sits on Seoul
            // (`MapViewModel.defaultRegion`) forever, so this fits it to
            // the actual pins whenever Apple becomes the active provider
            // (picking it in the segmented control, or it already being
            // selected when this screen first appears).
            .onAppear { fitAppleMapIfNeeded() }
            .onChange(of: displayProviderRaw) { _, _ in fitAppleMapIfNeeded() }
        }
    }

    private func fitAppleMapIfNeeded() {
        guard displayProvider == .apple else { return }
        viewModel.fitToVisiblePlaces(visibleCards)
    }

    /// Whether this provider has any pin at all to draw right now.
    private var hasNothingToShow: Bool {
        visibleCards.isEmpty || (displayProvider == .naver && naverEligibleCards.isEmpty)
    }

    /// Why the map has no pins, when it has none. Every provider used to
    /// just draw an empty default view of Seoul in this case, which reads
    /// the same whether there are no cards at all, no card has coordinates
    /// yet, or a search simply matched nothing — three very different
    /// situations, none of them explained.
    @ViewBuilder
    private var nothingToShowState: some View {
        if visibleCards.isEmpty {
            ContentUnavailableView {
                Label("지도에 표시할 장소가 없습니다".localized, systemImage: "mappin.slash")
            } description: {
                Text(nothingToShowReason)
            }
        } else {
            ContentUnavailableView {
                Label("Naver 지도에 표시할 한국 장소가 없습니다".localized, systemImage: "mappin.slash")
            } description: {
                Text("Naver 지도는 한국 내 장소만 표시합니다. 한국 밖 장소는 Apple이나 Google 지도로 보실 수 있습니다.".localized)
            }
        }
    }

    private var nothingToShowReason: String {
        if storageService.placeCards.isEmpty {
            return "아직 저장된 장소가 없습니다. 갤러리 탭의 \"장소 추가\"로 첫 장소를 담아보세요.".localized
        }
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return "검색어와 일치하는 장소가 없습니다.".localized
        }
        return "저장된 장소에 아직 좌표가 없습니다. 카드 편집의 \"주소로 좌표 확인\"으로 좌표를 채우면 지도에 표시됩니다.".localized
    }

    /// Naver's map only ever gets the Korean subset (`naverEligibleCards`)
    /// — without this, the places it left out simply weren't there, with
    /// no way to tell that from them having been lost.
    @ViewBuilder
    private var excludedPlacesBanner: some View {
        let excluded = visibleCards.count - naverEligibleCards.count
        if displayProvider == .naver, excluded > 0 {
            Text("한국 밖 ".localized + "\(excluded)" + "곳은 Naver 지도에 표시되지 않습니다.".localized)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
        }
    }

    private var appleMap: some View {
        Map(position: $viewModel.cameraPosition) {
            // "내 위치에서 이 장소들이 어디쯤인가"는 지도를 여는 가장 흔한
            // 이유인데, 이 앱은 거리 정렬(`PlaceStatusFilterBar`의 "현재
            // 위치")에 이미 위치 권한을 쓰면서도 정작 지도에는 내 위치를
            // 한 번도 그려주지 않았다. 권한이 없으면 점은 그냥 안 나오고,
            // 아래 버튼을 누르면 그때 시스템이 권한을 묻는다.
            UserAnnotation()

            ForEach(visibleCards) { card in
                Annotation(card.name, coordinate: viewModel.coordinate(for: card)) {
                    appleMapAnnotation(for: card)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    /// A tap toggles a small callout above the pin (name/address/"카드
    /// 보기") instead of jumping straight into the full card — the same
    /// two-step "tap marker, then tap to open the card" flow Google/Naver
    /// already offer via their own web page's marker info window.
    @ViewBuilder
    private func appleMapAnnotation(for card: PlaceCard) -> some View {
        VStack(spacing: 6) {
            if calloutCardID == card.id {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if !card.address.isEmpty {
                        Text(card.address)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Button("카드 보기".localized) {
                            selectedCard = card
                        }
                        .buttonStyle(.borderedProminent)

                        // Google/Naver's own map tabs show these same
                        // "Open in ..." links right in their marker popup
                        // (`naver-map-embed.html`'s `makeMapLink` calls) —
                        // Apple's callout had only "카드 보기", with no way
                        // to jump to Kakao Map or any other provider from
                        // here. Apple's own entry is left out: this is
                        // already the Apple map.
                        if card.hasAnyMapLink {
                            MapOpenMenu(card: card, includesApple: false) {
                                Image(systemName: "map")
                                    .accessibilityLabel("지도에서 열기".localized)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .font(.caption)
                    .controlSize(.mini)
                }
                .padding(8)
                .frame(maxWidth: 220, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 2)
            }

            Button {
                calloutCardID = (calloutCardID == card.id) ? nil : card.id
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "mappin.circle.fill")
                        .accessibilityHidden(true)
                        .font(.title)
                        .foregroundStyle(.red)
                    if calloutCardID != card.id {
                        Text(card.name)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var googleMap: some View {
        if let apiKey = KeychainService.load(.googlePlacesAPIKey), !apiKey.isEmpty {
            GoogleMapWebView(
                apiKey: apiKey,
                places: visibleCards.map(googleMarker),
                onSelectPlace: selectCard(byID:)
            )
        } else {
            missingKeyState(
                title: "Google API 키가 필요합니다".localized,
                message: "설정에서 Google Places API 키를 등록해주세요.".localized
            )
        }
    }

    @ViewBuilder
    private var naverMap: some View {
        if let clientId = SettingsViewModel.currentNaverMapClientId() {
            NaverMapWebView(
                clientId: clientId,
                places: naverEligibleCards.map(naverMarker),
                onSelectPlace: selectCard(byID:)
            )
        } else {
            missingKeyState(
                title: "Naver Client ID가 필요합니다".localized,
                message: "설정에서 Naver 지도 표시용 NCP Client ID를 등록해주세요.".localized
            )
        }
    }

    private func missingKeyState(title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "key")
        } description: {
            Text(message)
        }
    }

    private func selectCard(byID id: String) {
        selectedCard = visibleCards.first { $0.id == id }
    }

    private func googleMarker(for card: PlaceCard) -> GoogleMapWebView.MarkerPlace {
        let coordinate = viewModel.coordinate(for: card)
        return GoogleMapWebView.MarkerPlace(
            id: card.id,
            name: card.name,
            address: card.address,
            visited: card.isVisited,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            kakaoMapUrlString: KakaoMapOpener.url(for: card)?.absoluteString,
            naverMapUrlString: NaverMapOpener.url(for: card)?.absoluteString,
            tmapUrlString: TmapOpener.url(for: card)?.absoluteString
        )
    }

    private func naverMarker(for card: PlaceCard) -> NaverMapWebView.MarkerPlace {
        let coordinate = viewModel.coordinate(for: card)
        return NaverMapWebView.MarkerPlace(
            id: card.id,
            name: card.name,
            address: card.address,
            emoji: naverMarkerContentHTML(for: card),
            visited: card.isVisited,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            kakaoMapUrlString: KakaoMapOpener.url(for: card)?.absoluteString,
            naverMapUrlString: NaverMapOpener.url(for: card)?.absoluteString,
            tmapUrlString: TmapOpener.url(for: card)?.absoluteString
        )
    }

    /// The category badge (`PlaceCategoryIcon.markerGlyphHTML`) with the
    /// place's name added as a label underneath — matching Apple/Google's
    /// "name below the pin" look. Plugged into `MarkerPlace.emoji`, which
    /// the *shared* Naver embed page (not this app's own — see that
    /// page's own doc comment; not editable from here) concatenates
    /// directly as raw HTML into a fixed 24×24 container. Rather than
    /// depending on that fixed box (whose exact overflow/centering
    /// behavior for taller content isn't something this app controls or
    /// can verify without the page itself), the badge sits in its own
    /// `position: relative` 24×24 wrapper — identical in size to the
    /// plain badge this replaces, so the page's own anchor math is
    /// unaffected — and the label is `position: absolute; top: 100%`
    /// under it, which lays out purely relative to that wrapper and
    /// isn't constrained by the page's outer box at all.
    private func naverMarkerContentHTML(for card: PlaceCard) -> String {
        let escapedName = card.name
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <div style="position:relative;width:24px;height:24px;">\
        \(PlaceCategoryIcon.markerGlyphHTML(for: card.category))\
        <div style="position:absolute;top:100%;left:50%;transform:translateX(-50%);margin-top:2px;font:11px -apple-system,sans-serif;padding:2px 6px;background:rgba(255,255,255,0.9);border-radius:10px;max-width:96px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">\(escapedName)</div>\
        </div>
        """
    }
}

#Preview {
    PlacesMapView(viewModel: MapViewModel(storageService: StorageService()))
        .environmentObject(AppNavigation())
        .environmentObject(StorageService())
}
