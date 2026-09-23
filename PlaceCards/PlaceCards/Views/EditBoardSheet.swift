import PhotosUI
import SwiftUI
import UIKit

/// Mirrors Peragra's `EditTripSheet`: same name/subtitle/cover-icon form
/// as `AddBoardSheet`, pre-filled with the board's current values.
struct EditBoardSheet: View {
    let board: Board

    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var subtitle: String
    @State private var coverIcon: String
    @State private var coverPhotoPath: String?

    init(board: Board) {
        self.board = board
        _name = State(initialValue: board.name)
        _subtitle = State(initialValue: board.subtitle)
        _coverIcon = State(initialValue: board.coverIcon)
        _coverPhotoPath = State(initialValue: board.coverPhotoPath)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("게시판".localized) {
                    TextField("이름 (예: 도쿄 봄 여행)".localized, text: $name)
                    TextField("부제목 (예: 2026년 4월 · 도쿄)".localized, text: $subtitle)
                }

                Section("표지".localized) {
                    BoardCoverPicker(coverIcon: $coverIcon, coverPhotoPath: $coverPhotoPath)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("게시판 수정".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장".localized) { save() }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func save() {
        var updated = board
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.subtitle = subtitle.trimmingCharacters(in: .whitespaces)
        updated.coverIcon = coverIcon
        updated.coverPhotoPath = coverPhotoPath
        storageService.saveBoard(updated)
        dismiss()
    }
}

#Preview {
    EditBoardSheet(board: Board(name: "도쿄 봄 여행".localized, subtitle: "2026년 4월".localized, coverIcon: "airplane"))
        .environmentObject(StorageService())
}

/// 게시판 표지 고르기 — **기호로도, 사진으로도.** `AddBoardSheet`도 이것을 쓴다.
///
/// 사진이 있으면 사진이 표지다(`BoardRow`). 사진을 빼면 기호로 돌아가므로
/// `coverIcon`은 사진이 있어도 그대로 들고 있는다 — 메뉴 줄·칩·배지는
/// `Label(_:systemImage:)`이라 기호가 늘 있어야 하기도 하다.
///
/// `Section`을 제 안에서 만들지 않는다. 쓰는 쪽이 감싸고, 여기서는 줄만
/// 내놓는다 — 그래야 `.onChange`가 평범한 뷰에 붙는다.
struct BoardCoverPicker: View {
    @Binding var coverIcon: String
    @Binding var coverPhotoPath: String?

    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoading = false

    var body: some View {
        Group {
            HStack(spacing: 12) {
                preview
                if isLoading {
                    ProgressView()
                } else if coverPhotoPath != nil {
                    Button("사진 빼기".localized) { coverPhotoPath = nil }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                }
                Spacer()
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("사진에서 고르기".localized, systemImage: "photo")
            }

            iconGrid
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    /// 지금 표지. 사진이면 사진, 아니면 고른 기호.
    private var preview: some View {
        Group {
            if let coverPhotoPath,
               let image = MediaStore.loadThumbnail(fileName: coverPhotoPath, maxPixelSize: 192) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: coverIcon)
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("표지".localized)
    }

    /// 기호 격자. 사진이 걸려 있어도 고를 수 있다 — 고르면 사진을 뺀다.
    /// 기호를 눌렀는데 아무 일도 안 일어나는 것이 더 이상하다.
    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
            ForEach(Board.coverIconChoices, id: \.self) { icon in
                Button {
                    coverIcon = icon
                    coverPhotoPath = nil
                } label: {
                    let chosen = coverPhotoPath == nil && coverIcon == icon
                    Image(systemName: icon)
                        .accessibilityLabel("표지 아이콘".localized)
                        .accessibilityAddTraits(chosen ? [.isSelected] : [])
                        .font(.system(size: 22))
                        .foregroundStyle(chosen ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(chosen ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    /// `saveImage(data:)`가 아니라 `saveImage(_:)`를 쓴다 — 그쪽이 줄여
    /// 저장한다. 표지는 48pt 칸에 그려지므로 원본 해상도를 들고 있을 이유가
    /// 없고, 이 사진은 백업과 기기 간 동기화에도 실린다.
    private func load(_ item: PhotosPickerItem) async {
        isLoading = true
        defer {
            isLoading = false
            pickerItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let saved = try? MediaStore.saveImage(image) else { return }
        coverPhotoPath = saved
    }
}
