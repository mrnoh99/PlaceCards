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

    @StateObject private var viewModel: PlaceCardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var pickedImages: [UIImage] = []
    /// The original, unmodified bytes for each of `pickedImages` (same
    /// index) — kept alongside since EXIF (used for `photoLocationHint`)
    /// doesn't survive being decoded into a `UIImage`.
    @State private var pickedImageDatas: [Data] = []
    @State private var isLoadingPhotos = false
    @State private var sourceType: SourceType = .instagramScreenshot
    @State private var didCreateCards = false

    init(viewModel: PlaceCardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
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
                }
            }
            .navigationTitle("장소 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("추가 (\(viewModel.selectedRowCount))") {
                            Task {
                                _ = await viewModel.createCards(source: sourceType)
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
        }
    }

    private var photosSection: some View {
        Section("사진 선택") {
            if pickedImages.count < Self.maxPhotos {
                PhotosPicker(
                    selection: $photoPickerItems,
                    maxSelectionCount: Self.maxPhotos - pickedImages.count,
                    matching: .images
                ) {
                    if isLoadingPhotos {
                        ProgressView()
                    } else {
                        Text(pickedImages.isEmpty ? "갤러리에서 사진 선택 (여러 장 가능)" : "사진 더 추가")
                    }
                }
                .disabled(isLoadingPhotos)
            }

            Picker("출처", selection: $sourceType) {
                Text("인스타그램 스크린샷").tag(SourceType.instagramScreenshot)
                Text("구글 지도 스크린샷").tag(SourceType.googleMapScreenshot)
                Text("네이버 지도 스크린샷").tag(SourceType.naverMapScreenshot)
                Text("현장 촬영").tag(SourceType.onsitePhoto)
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
                    Task { await viewModel.analyzeImages(pickedImages, rawImageDatas: pickedImageDatas, source: sourceType) }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("AI로 장소 분석하기 (\(pickedImages.count)장)")
                    }
                }
                .disabled(viewModel.isLoading)
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

            Button("+ 장소 추가") { viewModel.addBlankRow() }
        } header: {
            Text("추가할 장소 (\(viewModel.selectedRowCount)개 선택)")
        } footer: {
            Text("AI가 찾은 장소를 검토·수정하거나 직접 추가하세요. \"Google에서 검색\"으로 정확한 주소·평점·연락처를 채울 수 있습니다.")
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
                TextField("장소명", text: row.name)
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
                TextField("주소", text: row.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if row.wrappedValue.chosenResult != nil {
                    Label("Google 지도에서 확인됨", systemImage: "checkmark.seal")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                Button {
                    Task { await viewModel.search(rowID: row.wrappedValue.id) }
                } label: {
                    if row.wrappedValue.isSearching {
                        ProgressView()
                    } else {
                        Text("Google에서 검색")
                    }
                }
                .font(.caption)
                .disabled(row.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty || row.wrappedValue.isSearching)

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
}
