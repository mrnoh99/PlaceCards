import SwiftUI
import UniformTypeIdentifiers

/// Receives a board exported by "내보내기" (`ExportBoardMenu`/
/// `BackupService.exportBoard`) and adds it to this device's data —
/// ported from Peragra's `ImportBoardSheet`: paste the JSON text, or
/// pick the file, preview how many places it holds, then confirm.
/// Purely additive (`BackupService.importBoard`) — never touches
/// anything already saved, unlike "백업에서 복원" (Settings), which
/// replaces everything.
struct ImportBoardSheet: View {
    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var pastedText = ""
    @State private var showingFileImporter = false
    @State private var preview: BackupService.BackupData?
    @State private var errorMessage: String?
    @State private var didImport = false

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    Section {
                        ForEach(preview.boards) { board in
                            let count = preview.placeCards.filter { $0.boardIDs.contains(board.id) }.count
                            LabeledContent(board.name, value: "장소 ".localized + "\(count)" + "개".localized)
                        }
                    } header: {
                        Text("가져올 내용".localized)
                    } footer: {
                        Text(isTakeout
                             ? "Google Takeout에서 읽었습니다. 이름·주소(있으면 좌표)만 담기며, 평점·사진·영업시간은 조회하지 않습니다 — 나중에 카드를 열어 채울 수 있습니다. 기존 게시판·장소는 그대로 둡니다.".localized
                             : "기존 게시판·장소는 그대로 두고, 새 게시판으로 추가됩니다.".localized)
                    }
                } else {
                    Section {
                        TextEditor(text: $pastedText)
                            .frame(minHeight: 160)
                        Button("붙여넣은 텍스트 확인".localized) { parse(pastedText) }
                            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: {
                        Text("텍스트 붙여넣기".localized)
                    }

                    Section {
                        Button("파일 선택…".localized) { showingFileImporter = true }
                    } header: {
                        Text("또는 파일에서".localized)
                    } footer: {
                        Text("PinSpots 백업 파일과 Google Takeout의 저장한 장소(Saved Places.json, 목록별 CSV)를 모두 읽습니다.".localized)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            // The one text-entry screen that was missing these. It also
            // has the app's only multi-line `TextEditor`, where they
            // matter most: a return key inserts a newline there rather
            // than dismissing, so without a 완료 button there was no way
            // to put the keyboard away — and it covers the "붙여넣은
            // 텍스트 확인" button sitting right under the editor.
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("게시판 가져오기".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기".localized) { dismiss() }
                }
                if preview != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("가져오기".localized) { performImport() }
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                // Takeout hands out `Saved Places.json` and one CSV per
                // saved list, so both types are pickable here.
                allowedContentTypes: [.json, .commaSeparatedText],
                onCompletion: handleFilePicked
            )
            .onChange(of: didImport) { _, imported in
                if imported { dismiss() }
            }
        }
    }

    private func parse(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            errorMessage = "읽을 수 없는 텍스트입니다.".localized
            return
        }
        applyDecoded(data)
    }

    /// Whether the preview came from Takeout, which changes what the
    /// footer can honestly promise: those cards carry a name, an address
    /// and (from the GeoJSON form) a coordinate, and nothing else — no
    /// rating, no photo, no hours, because nothing was looked up.
    @State private var isTakeout = false

    private func handleFilePicked(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "파일을 읽지 못했습니다.".localized
                return
            }
            // A Takeout CSV is named after the list it came from, which is
            // the board name the user is expecting.
            applyDecoded(data, listName: url.deletingPathExtension().lastPathComponent)
        case .failure:
            errorMessage = "파일을 읽지 못했습니다.".localized
        }
    }

    /// This app's own backup first, then a Google Takeout export. Takeout
    /// is converted to the same `BackupData` the backup path produces, so
    /// the preview and the import below work on it unchanged — the only
    /// difference is where the rows came from.
    private func applyDecoded(_ data: Data, listName: String? = nil) {
        if let backup = try? BackupService.decode(data) {
            preview = backup
            isTakeout = false
            errorMessage = nil
            return
        }
        if let takeout = TakeoutImport.parse(data, listName: listName) {
            preview = takeout
            isTakeout = true
            errorMessage = nil
            return
        }
        errorMessage = "PinSpots 백업 파일도, Google Takeout 파일도 아닙니다.".localized
    }

    private func performImport() {
        guard let preview else { return }
        BackupService.importBoard(preview, storageService: storageService)
        didImport = true
    }
}

#Preview {
    ImportBoardSheet()
        .environmentObject(StorageService())
}
