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

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return scoped }
        return scoped.filter { card in
            card.name.localizedCaseInsensitiveContains(trimmedQuery)
                || card.address.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var mapNavigationTitle: String {
        if navigation.mapFilterIDs != nil { return "선택한 장소" }
        if let scopedBoard { return scopedBoard.name }
        return "지도"
    }

    var body: some View {
        NavigationStack {
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
            .navigationTitle(mapNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("지도", selection: $displayProviderRaw) {
                        ForEach(MapDisplayProvider.allCases) { provider in
                            Text(provider.label).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                if navigation.mapFilterIDs != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("전체 보기") { navigation.mapFilterIDs = nil }
                    }
                }
            }
            .sheet(item: $selectedCard) { card in
                NavigationStack {
                    PlaceCardDetailView(card: card)
                }
            }
            .searchable(text: $searchQuery, prompt: "장소 검색")
            // Only the Apple map has a SwiftUI-owned camera
            // (`viewModel.region`) this can recenter directly — the
            // Google/Naver maps are WKWebViews with no such hook from
            // here, so for those, matching pins simply being the only
            // ones left on the map (via `visibleCards` above) is the
            // whole effect of a search there.
            .onChange(of: searchQuery) { _, newValue in
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty,
                      let firstMatch = visibleCards.first else { return }
                withAnimation {
                    viewModel.region.center = viewModel.coordinate(for: firstMatch)
                }
            }
        }
    }

    private var appleMap: some View {
        Map(
            coordinateRegion: $viewModel.region,
            annotationItems: visibleCards
        ) { card in
            MapAnnotation(coordinate: viewModel.coordinate(for: card)) {
                Button {
                    selectedCard = card
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
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
                title: "Google API 키가 필요합니다",
                message: "설정에서 Google Places API 키를 등록해주세요."
            )
        }
    }

    @ViewBuilder
    private var naverMap: some View {
        if let clientId = SettingsViewModel.currentNaverMapClientId() {
            NaverMapWebView(
                clientId: clientId,
                places: visibleCards.map(naverMarker),
                onSelectPlace: selectCard(byID:)
            )
        } else {
            missingKeyState(
                title: "Naver Client ID가 필요합니다",
                message: "설정에서 Naver 지도 표시용 NCP Client ID를 등록해주세요."
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
            emoji: PlaceCategoryIcon.markerGlyphHTML(for: card.category),
            visited: card.isVisited,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            kakaoMapUrlString: KakaoMapOpener.url(for: card)?.absoluteString,
            naverMapUrlString: NaverMapOpener.url(for: card)?.absoluteString,
            tmapUrlString: TmapOpener.url(for: card)?.absoluteString
        )
    }
}

#Preview {
    PlacesMapView(viewModel: MapViewModel(storageService: StorageService()))
        .environmentObject(AppNavigation())
        .environmentObject(StorageService())
}
