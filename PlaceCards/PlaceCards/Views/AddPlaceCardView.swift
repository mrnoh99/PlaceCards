import SwiftUI
import PhotosUI

struct AddPlaceCardView: View {
    @StateObject private var viewModel: PlaceCardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var sourceType: SourceType = .instagramScreenshot
    @State private var manualName = ""
    @State private var manualAddress = ""
    @State private var didCreateCard = false

    init(viewModel: PlaceCardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("사진 선택") {
                    PhotosPicker("갤러리에서 사진 선택", selection: $photoPickerItem, matching: .images)

                    Picker("출처", selection: $sourceType) {
                        Text("인스타그램 스크린샷").tag(SourceType.instagramScreenshot)
                        Text("구글 지도 스크린샷").tag(SourceType.googleMapScreenshot)
                        Text("네이버 지도 스크린샷").tag(SourceType.naverMapScreenshot)
                        Text("현장 촬영").tag(SourceType.onsitePhoto)
                    }

                    if let image = viewModel.selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            Task { await viewModel.analyzeImage(image, source: sourceType) }
                        } label: {
                            if viewModel.isLoading {
                                ProgressView()
                            } else {
                                Text("AI로 장소명 분석하기")
                            }
                        }
                        .disabled(viewModel.isLoading)
                    }
                }

                Section("장소 검색") {
                    TextField("장소명", text: $viewModel.extractedPlaceName)
                    Button("Google에서 검색") {
                        Task { await viewModel.search(placeName: viewModel.extractedPlaceName) }
                    }
                    .disabled(viewModel.extractedPlaceName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading)

                    ForEach(viewModel.candidateResults) { result in
                        Button {
                            createCard(from: result)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(result.name).font(.headline)
                                Text(result.address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("직접 입력") {
                    TextField("장소명", text: $manualName)
                    TextField("주소", text: $manualAddress)
                    Button("직접 입력으로 저장") {
                        Task {
                            _ = await viewModel.createManualPlaceCard(name: manualName, address: manualAddress)
                            didCreateCard = true
                        }
                    }
                    .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

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
            }
            .onChange(of: photoPickerItem) { _, newItem in
                Task { await loadPhoto(from: newItem) }
            }
            .onChange(of: didCreateCard) { _, created in
                if created { dismiss() }
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await viewModel.analyzeImage(image, source: sourceType)
        }
    }

    private func createCard(from result: PlaceSearchResult) {
        do {
            _ = try viewModel.createPlaceCard(from: result, image: viewModel.selectedImage, source: sourceType)
            didCreateCard = true
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddPlaceCardView(viewModel: PlaceCardViewModel(storageService: StorageService()))
}
