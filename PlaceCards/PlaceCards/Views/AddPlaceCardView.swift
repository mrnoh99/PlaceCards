import SwiftUI
import PhotosUI

/// Add-place flow: pick one or more screenshots, run them through AI in a
/// single request, and review the resulting list of places — a screenshot
/// naming several places, or several screenshots handed over together,
/// ends up as several rows here instead of just one. Each row can be
/// verified against Google Places, edited by hand, or added blank, and
/// every selected row becomes its own card on save. Mirrors Peragra's
/// `AddPlaceSheet` (its multi-row review list, "+ Add Place", and "Add N"
/// confirmation), simplified to this app's own single AI-extraction step
/// (no on-site GPS capture or nearby-places lookup, which PlaceCards
/// doesn't have).
struct AddPlaceCardView: View {
    private static let maxPhotos = 10
    /// The "출처" picker this screen used to show had no effect on
    /// anything visible: `PlaceCardViewModel.analyzeImages` ignores its
    /// `source` argument entirely (the AI prompt is fixed regardless of
    /// source), and the only other thing it drove — which of
    /// `MediaBundle`'s four photo buckets a saved photo lands in — is
    /// never shown back to the user anywhere in the app. Asking the user
    /// to pick a bucket nobody ever sees again wasn't worth the extra
    /// step, so this just picks one value for every save instead.
    private static let defaultSource: SourceType = .onsitePhoto

    @StateObject private var viewModel: PlaceCardViewModel
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var pickedImages: [UIImage] = []
    /// The original, unmodified bytes for each of `pickedImages` (same
    /// index) — kept alongside since EXIF (used for `photoLocationHint`)
    /// doesn't survive being decoded into a `UIImage`.
    @State private var pickedImageDatas: [Data] = []
    @State private var isLoadingPhotos = false
    @State private var didCreateCards = false
    /// The seeded row's ID when opened from a shared link, so `.task` can
    /// run its search automatically exactly once — see
    /// `autoResolveInitialLinkIfNeeded()`. `nil` for every other way this
    /// view opens (photo scan, "+ 장소 추가", blank row).
    @State private var initialLinkRowID: UUID?
    /// Whether this screen was opened with something already handed over
    /// from outside the app (a Share Extension link or photo) rather than
    /// started blank from inside — set once in `init`, from the same two
    /// parameters that seed `initialLinkRowID`/`pickedImages`. Drives
    /// whether saving jumps straight to the resulting card afterward (see
    /// the "추가" button action) — makes sense for a place the user just
    /// shared in from outside, not for an ordinary in-app add where they're
    /// already looking at wherever they'll expect the new card to show up.
    private let cameFromSharedInfo: Bool

    /// `initialImageData` seeds the picker with a photo handed over from
    /// outside the normal PhotosPicker flow — namely a photo shared into
    /// the app through the Share Extension (see `SharedPhotoBoardPickerSheet`).
    /// `initialLinkText` does the same for a shared link/text (see
    /// `SharedLinkBoardPickerSheet`) — dropped straight into a blank row's
    /// name field exactly as if the user had pasted it there by hand, so
    /// it goes through the same `PlaceCardViewModel.search(rowID:)` →
    /// `SharedLinkParser` resolution already used for manual paste, with
    /// no separate code path of its own. `initialLinkRowID` then lets
    /// `.task` run that same search on its own right away — a shared link
    /// already named one specific, already-confirmed place (the user
    /// picked and confirmed it in Google/Naver Maps before sharing), so
    /// making them also tap "Google에서 검색" here would just be re-doing
    /// a confirmation that already happened.
    init(viewModel: PlaceCardViewModel, initialImageData: Data? = nil, initialLinkText: String? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        cameFromSharedInfo = initialImageData != nil
            || (initialLinkText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        if let initialImageData, let image = UIImage(data: initialImageData) {
            _pickedImages = State(initialValue: [image])
            _pickedImageDatas = State(initialValue: [initialImageData])
        }
        if let initialLinkText, !initialLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let row = PlaceCandidateRow(name: initialLinkText, address: "")
            viewModel.candidateRows = [row]
            _initialLinkRowID = State(initialValue: row.id)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                photosSection
                candidatesSection

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let infoMessage = viewModel.infoMessage {
                    Text(infoMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("장소 추가".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("추가 (".localized + "\(viewModel.selectedRowCount)" + ")") {
                            Task {
                                let created = await viewModel.createCards(source: Self.defaultSource)
                                // Only when it resolves to exactly one card —
                                // several rows (a screenshot naming multiple
                                // places) has no single "the" card to jump to.
                                if cameFromSharedInfo, created.count == 1 {
                                    navigation.showCardDetail(created[0].id)
                                }
                                didCreateCards = true
                            }
                        }
                        .disabled(viewModel.selectedRowCount == 0)
                    }
                }
            }
            .onChange(of: photoPickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await loadPhotos(newItems)
                    photoPickerItems = []
                }
            }
            .onChange(of: didCreateCards) { _, created in
                if created { dismiss() }
            }
            .task {
                await autoResolveInitialLinkIfNeeded()
            }
        }
    }

    /// Runs the same lookup a manual "Google에서 검색" tap would, right
    /// away, for the row seeded from a shared link — see `init`. Only ever
    /// runs once (`initialLinkRowID` is cleared immediately), and only
    /// auto-picks a result when the search comes back with exactly one:
    /// several results means the shared page's title alone wasn't a
    /// precise enough query to trust picking blind, so — same as a manual
    /// search with more than one hit — it's left for the user to choose.
    private func autoResolveInitialLinkIfNeeded() async {
        guard let rowID = initialLinkRowID else { return }
        initialLinkRowID = nil
        await viewModel.search(rowID: rowID)
        guard
            let row = viewModel.candidateRows.first(where: { $0.id == rowID }),
            row.searchResults.count == 1,
            let onlyResult = row.searchResults.first
        else { return }
        viewModel.chooseResult(onlyResult, forRowID: rowID)
    }

    private var photosSection: some View {
        Section("사진 선택".localized) {
            if pickedImages.count < Self.maxPhotos {
                PhotosPicker(
                    selection: $photoPickerItems,
                    maxSelectionCount: Self.maxPhotos - pickedImages.count,
                    matching: .images
                ) {
                    if isLoadingPhotos {
                        ProgressView()
                    } else {
                        Text(pickedImages.isEmpty ? "갤러리에서 사진 선택 (여러 장 가능)".localized : "사진 더 추가".localized)
                    }
                }
                .disabled(isLoadingPhotos)
            }

            if !pickedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pickedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Button {
                                    pickedImages.remove(at: index)
                                    pickedImageDatas.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(4)
                            }
                        }
                    }
                }

                Button {
                    Task { await viewModel.analyzeImages(pickedImages, rawImageDatas: pickedImageDatas, source: Self.defaultSource) }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("AI로 장소 분석하기 (".localized + "\(pickedImages.count)" + "장)".localized)
                    }
                }
                .disabled(viewModel.isLoading || !AIProviderChain.hasAnyConfiguredProvider())

                if !AIProviderChain.hasAnyConfiguredProvider() {
                    Text(AIProviderChain.unconfiguredHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var candidatesSection: some View {
        Section {
            ForEach($viewModel.candidateRows) { $row in
                candidateRowView($row)
            }
            .onDelete { indices in
                for index in indices {
                    viewModel.removeRow(id: viewModel.candidateRows[index].id)
                }
            }

            Button("+ 장소 추가".localized) { viewModel.addBlankRow() }
        } header: {
            Text("추가할 장소 (".localized + "\(viewModel.selectedRowCount)" + "개 선택)".localized)
        } footer: {
            Text("AI가 찾은 장소를 검토·수정하거나 직접 추가하세요. \"Google에서 검색\"으로 정확한 주소·평점·연락처를 채울 수 있습니다.".localized)
        }
    }

    @ViewBuilder
    private func candidateRowView(_ row: Binding<PlaceCandidateRow>) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                viewModel.toggleSelected(id: row.wrappedValue.id)
            } label: {
                Image(systemName: row.wrappedValue.selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.wrappedValue.selected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                TextField("장소명".localized, text: row.name)
                    .font(.subheadline.weight(.medium))
                    .onChange(of: row.wrappedValue.name) { _, newValue in
                        // `chooseResult` itself writes its result's name onto
                        // this same field, which would otherwise immediately
                        // trigger this onChange and undo what it just set —
                        // only clear when the name no longer matches the
                        // currently chosen result, i.e. an actual manual edit.
                        if row.wrappedValue.chosenResult?.name != newValue {
                            viewModel.clearChosenResult(id: row.wrappedValue.id)
                        }
                    }
                TextField("주소".localized, text: row.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Whatever the AI scan found beyond name/address (a
                // hashtag, a one-line impression) — editable here since
                // it's still just a draft, and folded into the saved
                // card's memo field at `createCards()` either way.
                TextField(
                    "메모 (선택)".localized,
                    text: Binding(
                        get: { row.wrappedValue.scannedNote ?? "" },
                        set: { row.wrappedValue.scannedNote = $0.isEmpty ? nil : $0 }
                    ),
                    axis: .vertical
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                if !row.wrappedValue.tags.isEmpty {
                    Text("태그: ".localized + row.wrappedValue.tags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // AI-suggested tags aren't added to the row on their own —
                // see `PlaceWebDetails.tags`'s own doc comment for why —
                // so this offers them for a deliberate "추가" tap instead,
                // the same confirm-before-applying shape
                // `EditPlaceCardSheet`'s own tag suggestions use.
                if let suggested = suggestedTags(for: row.wrappedValue), !suggested.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text("제안된 태그: ".localized + suggested.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("추가".localized) {
                            viewModel.acceptSuggestedTags(suggested, forRowID: row.wrappedValue.id)
                        }
                        .font(.caption2)
                    }
                }

                if row.wrappedValue.chosenResult != nil {
                    Label(
                        row.wrappedValue.originSource == .naverMapShare
                            ? "Naver 지도에서 확인됨".localized
                            : "Google 지도에서 확인됨".localized,
                        systemImage: "checkmark.seal"
                    )
                    .font(.caption2)
                    .foregroundStyle(.green)
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.search(rowID: row.wrappedValue.id) }
                    } label: {
                        if row.wrappedValue.isSearching {
                            ProgressView()
                        } else {
                            // Which backend this actually verifies against
                            // isn't up to the user's choice here — a Naver
                            // Map share always checks against Naver's own
                            // listings (see `PlaceCardViewModel.search(rowID:)`)
                            // — so the button's own label should say which
                            // one it's really about to call rather than always
                            // claiming Google, which was actively misleading
                            // once this button could mean either.
                            Text(
                                row.wrappedValue.originSource == .naverMapShare
                                    ? "Naver에서 검색".localized
                                    : "Google에서 검색".localized
                            )
                        }
                    }
                    .disabled(row.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty || row.wrappedValue.isSearching)

                    // A read-only detour to the real map app for this row's
                    // current name/address, entirely separate from
                    // "Google/Naver에서 검색" above — that verifies against
                    // the search API and fills the row's own fields; this
                    // just opens the actual app so the user can eyeball the
                    // place themselves (useful when the API search above
                    // comes back empty/wrong, or before ever trying it).
                    // Doesn't feed anything back into the row on its own —
                    // see this app's own design notes on why capturing a
                    // screenshot back into one specific still-unsaved row
                    // isn't attempted automatically.
                    Menu {
                        if !row.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Google Maps") {
                                GoogleMapsOpener.open(name: row.wrappedValue.name, address: row.wrappedValue.address, using: openURL)
                            }
                            if let url = NaverMapOpener.searchURL(name: row.wrappedValue.name, address: row.wrappedValue.address) {
                                Button("Naver Map") {
                                    openURL(url)
                                }
                            }
                        }
                        // Opens at the exact spot the photo was taken
                        // (`viewModel.photoLocationHint`) rather than
                        // searching by the name AI guessed — real evidence
                        // of where the place is, worth offering even when
                        // a name search above already exists, and the only
                        // option here at all when the row has no name yet.
                        if let photoLocationHint = viewModel.photoLocationHint {
                            Button("사진 위치로 보기 (Google)".localized) {
                                GoogleMapsOpener.open(coordinates: photoLocationHint, using: openURL)
                            }
                            if let url = NaverMapOpener.mapURL(coordinates: photoLocationHint) {
                                Button("사진 위치로 보기 (Naver)".localized) {
                                    openURL(url)
                                }
                            }
                        }
                    } label: {
                        Label("지도에서 찾기".localized, systemImage: "map")
                    }
                    .disabled(
                        row.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty
                            && viewModel.photoLocationHint == nil
                    )
                }
                .font(.caption)

                ForEach(row.wrappedValue.searchResults) { result in
                    Button {
                        viewModel.chooseResult(result, forRowID: row.wrappedValue.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name).font(.subheadline)
                            Text(result.address).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// AI-suggested tags for `row` not already accepted onto it — `nil`
    /// (rather than an empty array) when there's nothing new to show, so
    /// callers can use it directly as an `if let` guard.
    private func suggestedTags(for row: PlaceCandidateRow) -> [String]? {
        guard let suggested = row.scannedDetails?.tags, !suggested.isEmpty else { return nil }
        let newTags = suggested.filter { !row.tags.contains($0) }
        return newTags.isEmpty ? nil : newTags
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        for item in items {
            guard pickedImages.count < Self.maxPhotos else { break }
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                pickedImages.append(image)
                pickedImageDatas.append(data)
            }
        }
    }
}

#Preview {
    AddPlaceCardView(viewModel: PlaceCardViewModel(storageService: StorageService(), boardId: "preview"))
        .environmentObject(AppNavigation())
}
