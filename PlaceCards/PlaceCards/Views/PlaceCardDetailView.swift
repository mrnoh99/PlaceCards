import SwiftUI
import MapKit
import UIKit

/// Shows every field a `PlaceCard` carries, not just the handful the list
/// row/grid cell have room for — and the same action set Peragra's
/// `PlaceRowView` offers (favorite/visited toggle, call, a map-provider
/// menu, Instagram, website, edit), which this screen didn't have before.
struct PlaceCardDetailView: View {
    @State private var card: PlaceCard

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.openURL) private var openURL
    @State private var isPresentingEdit = false
    @State private var isPresentingPhotoViewer = false
    @State private var photoViewerStartIndex = 0
    @FocusState private var isMemoFieldFocused: Bool
    /// Guards `heroPhotoSection`'s tap for a moment after this screen
    /// appears. Every card list/grid navigates here via
    /// `.contentShape(Rectangle()).onTapGesture { selectedCard = card }`
    /// (not `NavigationLink`, which swallows a row's own inner buttons —
    /// see those views' own comments) — a plain `onTapGesture` doesn't
    /// participate in the same touch-cancellation UIKit gives a real
    /// control, so the same touch-up that opened this screen can, during
    /// the push transition, also land on whatever's sitting at that same
    /// screen position once this view appears — here, the hero photo
    /// banner, being the first and largest thing in the layout. Without
    /// this guard that stray touch fires the photo viewer immediately on
    /// open; a few hundred milliseconds is well past any transition but
    /// unnoticeable for a real, deliberate tap.
    @State private var isHeroPhotoTappable = false
    /// A working copy of `card.tags`, edited freely (add/remove) and only
    /// written back to `card`/disk when "저장" is tapped — unlike the memo
    /// field's autosave-on-blur, a tag list has no single natural "done
    /// editing" moment (adding several, then removing one you just added,
    /// is a normal way to use it), so committing explicitly avoids writing
    /// to disk after every single add/remove.
    @State private var tagsDraft: [String]
    @State private var newTagInput = ""

    private var isTagsDirty: Bool { tagsDraft != card.tags }

    init(card: PlaceCard) {
        _card = State(initialValue: card)
        _tagsDraft = State(initialValue: card.tags)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroPhotoSection

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
                            Text("리뷰 ".localized + "\(reviewCount)" + "개".localized)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal)

                if !card.media.allItems.isEmpty {
                    photosSection
                        .padding(.horizontal)
                }

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
                        Text("편의시설".localized)
                            .font(.headline)
                        WrapTagsView(tags: card.amenities)
                    }

                    tagsSection

                    memoSection
                }
                .padding(.horizontal)

                if let coordinates = card.coordinates {
                    // `Map(coordinateRegion:)` (the pre-iOS 17 API, driven by
                    // a `.constant()` binding) is prone to a well-known
                    // MapKit bug: inside a plain `ScrollView` (not `List`),
                    // its tiles can fail to finish loading and are left
                    // permanently blank — with `allowsHitTesting(false)`
                    // below (this is a static preview, not a real
                    // interactive map) there's no gesture to ever retrigger
                    // a retry, so a tile stuck blank stays that way. The
                    // newer `Map(initialPosition:)` composable API uses a
                    // different, more reliable rendering path that doesn't
                    // exhibit this.
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))) {
                        Marker(card.name, coordinate: CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude))
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
                    Label("공유".localized, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                metaFooter
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingEdit = true
                } label: {
                    Label("편집".localized, systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $isPresentingEdit) {
            EditPlaceCardSheet(card: card) { updated in
                card = updated
                // `tagsDraft` is a separate working copy (see its own
                // comment) that only ever changes through this screen's
                // own add/remove/저장 — without this, editing tags via
                // "편집" (`EditPlaceCardSheet` has its own, separate tags
                // field) would leave the stale draft in place, and tapping
                // "저장" here next would silently overwrite the edit
                // sheet's change right back to the old tags.
                tagsDraft = updated.tags
            }
        }
        .sheet(isPresented: $isPresentingPhotoViewer) {
            PhotoViewerSheet(
                images: card.media.allItems.compactMap { MediaStore.loadImage(fileName: $0.localPath) },
                selection: photoViewerStartIndex
            )
        }
        // Safety net alongside the memo field's own save-on-blur: in case
        // this screen goes away (back navigation, tab switch) without the
        // field ever losing focus first, this still persists whatever was
        // typed rather than silently discarding it.
        .onDisappear {
            if isMemoFieldFocused { storageService.save(card) }
            isHeroPhotoTappable = false
        }
        .task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            isHeroPhotoTappable = true
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
                    Label("전화".localized, systemImage: "phone")
                }
            }
            if let website = card.website, let url = URL(string: website) {
                Button {
                    openURL(url)
                } label: {
                    Label("웹사이트".localized, systemImage: "link")
                }
            }
            if let instagramURL = card.instagramURL, let url = URL(string: instagramURL) {
                Button {
                    openURL(url)
                } label: {
                    Label("인스타그램".localized, systemImage: "camera")
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
                Button("Apple 지도".localized) {
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
            Label("지도에서 열기".localized, systemImage: "map")
        }
        .buttonStyle(.bordered)
    }

    private var hasHoursInfo: Bool {
        card.hoursDetail?.isEmpty == false || card.closingTime?.isEmpty == false || card.holidays?.isEmpty == false
    }

    @ViewBuilder
    private var hoursSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("영업 정보".localized)
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
                Label("마감 ".localized + closingTime, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let holidays = card.holidays, !holidays.isEmpty {
                Label("휴무일 ".localized + holidays, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The same photo `PlaceCardGridCell`/`PlaceCardListRow` lead with
    /// (an official Google photo if there is one, else whatever's first)
    /// — its position within `photosSection`'s own `allItems` ordering,
    /// so tapping the hero opens the photo viewer already on the right
    /// one instead of always resetting to index 0.
    private var heroPhotoItem: MediaItem? {
        card.media.officialPhotos.first ?? card.media.allItems.first
    }

    private var heroPhotoIndex: Int {
        guard let heroPhotoItem else { return 0 }
        return card.media.allItems.firstIndex(of: heroPhotoItem) ?? 0
    }

    /// A full-width banner at the very top of the screen — separate from
    /// `photosSection`'s own horizontal thumbnail strip further down
    /// (which still lists every photo), this just gives the card an
    /// immediate visual identity the moment the screen opens, the way
    /// the grid/list cells already do.
    @ViewBuilder
    private var heroPhotoSection: some View {
        if let heroPhotoItem, let image = MediaStore.loadImage(fileName: heroPhotoItem.localPath) {
            Button {
                guard isHeroPhotoTappable else { return }
                photoViewerStartIndex = heroPhotoIndex
                isPresentingPhotoViewer = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            .buttonStyle(.plain)
        }
    }

    /// Every photo attached to this card, across all four media
    /// categories (`MediaBundle.allItems`) — tapping one opens
    /// `PhotoViewerSheet` for a full-screen, swipeable look, starting on
    /// whichever thumbnail was tapped.
    @ViewBuilder
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("사진".localized)
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(card.media.allItems.enumerated()), id: \.element.id) { index, item in
                        if let image = MediaStore.loadImage(fileName: item.localPath) {
                            Button {
                                photoViewerStartIndex = index
                                isPresentingPhotoViewer = true
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Directly editable right here, like `memoSection` below — no
    /// separate edit mode/sheet to step into first (unlike amenities
    /// above it, or every other field on this screen, which route through
    /// `EditPlaceCardSheet`). Always shown (not hidden when empty) since
    /// this is also how a tag gets *added* in the first place. Unlike the
    /// memo field's autosave-on-blur, edits here only commit to `card`
    /// (and disk) once "저장" is tapped — see `tagsDraft`'s own comment.
    @ViewBuilder
    private var tagsSection: some View {
        Text("태그".localized)
            .font(.headline)
        if !tagsDraft.isEmpty {
            WrapTagsView(tags: tagsDraft) { tag in
                tagsDraft.removeAll { $0 == tag }
            }
        }
        HStack {
            TextField("태그 추가".localized, text: $newTagInput)
                .font(.subheadline)
                .onSubmit(addTag)
            Button("추가".localized, action: addTag)
                .disabled(newTagInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        if isTagsDirty {
            Button("저장".localized) {
                card.tags = tagsDraft
                storageService.save(card)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func addTag() {
        let trimmed = newTagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tagsDraft.contains(trimmed) else { return }
        tagsDraft.append(trimmed)
        newTagInput = ""
    }

    /// Directly typable right here — no separate edit mode/sheet to step
    /// into first, unlike every other field on this screen (which route
    /// through `EditPlaceCardSheet`). Always shown (unlike amenities
    /// above it, which hides entirely when empty) since this field itself
    /// is how a memo gets *added* in the first place, not just changed.
    /// Saved once the field loses focus rather than on every keystroke —
    /// `storageService.save(card)` writes the whole JSON store back to
    /// disk, so doing that per-character while typing would be wasteful.
    @ViewBuilder
    private var memoSection: some View {
        Text("메모".localized)
            .font(.headline)
        TextField("메모 없음".localized, text: memoBinding, axis: .vertical)
            .font(.body)
            .focused($isMemoFieldFocused)
            .onChange(of: isMemoFieldFocused) { wasFocused, isFocused in
                if wasFocused, !isFocused { storageService.save(card) }
            }
    }

    private var memoBinding: Binding<String> {
        Binding(
            get: { card.memo ?? "" },
            set: { newValue in
                card.memo = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private var metaFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            if card.updatedAt != card.createdAt {
                Text("수정한 날짜: ".localized + card.updatedAt.formatted(date: .abbreviated, time: .omitted))
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

/// Full-screen, swipeable photo viewer — opened from `photosSection`,
/// starting on whichever thumbnail was tapped (`selection`).
private struct PhotoViewerSheet: View {
    let images: [UIImage]
    @State var selection: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기".localized) { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct WrapTagsView: View {
    let tags: [String]
    /// Adds an "x" to each capsule when set — `tagsSection` uses this to
    /// remove a tag from its draft; every other caller (read-only
    /// displays like amenities) leaves it `nil` and gets plain capsules.
    var onRemove: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                        if let onRemove {
                            Button {
                                onRemove(tag)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
        PlaceCardDetailView(card: PlaceCard(boardId: "preview", name: "샘플 카페".localized, address: "서울시 강남구".localized))
    }
    .environmentObject(StorageService())
}
