import SwiftUI
import UniformTypeIdentifiers

/// Receives a board exported by "내보내기" (`ExportBoardSheet`/
/// `BackupService.writeBundle`) and adds it to this device's data —
/// ported from Peragra's `ImportBoardSheet`: paste the JSON text, or
/// pick the **folder** (or an older single file), preview how many
/// places it holds, then confirm.
/// Purely additive (`BackupService.importBoard`) — never touches
/// anything already saved, unlike "백업에서 복원" (Settings), which
/// replaces everything.
struct ImportBoardSheet: View {
    @EnvironmentObject private var storageService: StorageService
    @Environment(\.dismiss) private var dismiss

    @State private var pastedText = ""
    @State private var showingFileImporter = false
    @State private var preview: BackupService.BackupData?
    /// 폴더 형식으로 고른 경우 그 폴더. 사진이 **거기** 있으므로 가져올 때까지
    /// 들고 있어야 한다. 옛 단일 파일은 사진이 payload에 박혀 있어 nil이다.
    @State private var previewBundleURL: URL?
    /// 그중 **이 화면이 직접 만든** 임시 폴더(옛 단일 파일을 풀어 놓은 것).
    /// 사용자가 고른 폴더와 달리 다 쓰면 치워야 한다.
    @State private var stagedBundleURL: URL?
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
                    Button("닫기".localized) {
                        discardStagedBundleIfNeeded()
                        dismiss()
                    }
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
                // `.folder`도 받는다. 게시판 내보내기가 이제 폴더 한 벌을
                // 내놓기 때문이다(`BackupService.writeBundle`). 옛 단일 파일과
                // Google Takeout CSV는 그대로 받는다.
                allowedContentTypes: [.json, .commaSeparatedText, .folder],
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
        guard case .success(let url) = result else {
            errorMessage = "파일을 읽지 못했습니다.".localized
            return
        }
        discardStagedBundleIfNeeded()
        Task { await load(from: url) }
    }

    /// 파일을 읽는 일은 전부 메인 액터 **밖에서** 한다.
    ///
    /// 옛 단일 파일은 사진이 base64로 박혀 있어 읽는 것만으로 수백 MB가
    /// 오간다. 예전에는 그걸 이 함수 자리에서 그대로 했고, 사진이 쌓인
    /// 백업을 고르면 **앱이 죽었다**(사용자 신고). 이제
    /// `BackupService.stageLegacyBackup`이 백그라운드에서 읽어 사진을 임시
    /// 폴더로 내려놓고, 화면은 메타데이터만 들고 있는다.
    private func load(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        // 폴더 형식이면 메타데이터만 읽는다. 사진은 가져오기를 누를 때
        // 그 폴더에서 한 장씩 옮긴다 — 임시 폴더로 옮길 것도 없다.
        if BackupService.isBundle(at: url) {
            guard let backup = try? BackupService.decodeBundle(at: url) else {
                errorMessage = "파일을 읽지 못했습니다.".localized
                return
            }
            preview = backup
            previewBundleURL = url
            stagedBundleURL = nil
            isTakeout = false
            errorMessage = nil
            return
        }

        // 이 앱의 옛 백업이면 임시 폴더로 옮겨 놓는다.
        if let staged = try? await BackupService.stageLegacyBackup(at: url) {
            preview = staged.backup
            previewBundleURL = staged.bundleURL
            stagedBundleURL = staged.bundleURL
            isTakeout = false
            errorMessage = nil
            return
        }

        // 남은 것은 Google Takeout이다. 사진이 없으므로 가볍다.
        // A Takeout CSV is named after the list it came from, which is
        // the board name the user is expecting.
        let listName = url.deletingPathExtension().lastPathComponent
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "파일을 읽지 못했습니다.".localized
            return
        }
        applyDecoded(data, listName: listName)
    }

    /// 임시로 풀어 둔 폴더가 있으면 치운다. 사진 수백 장이 남을 수 있다.
    private func discardStagedBundleIfNeeded() {
        guard let stagedBundleURL else { return }
        BackupService.discardStagedBundle(at: stagedBundleURL)
        self.stagedBundleURL = nil
    }

    /// This app's own backup first, then a Google Takeout export. Takeout
    /// is converted to the same `BackupData` the backup path produces, so
    /// the preview and the import below work on it unchanged — the only
    /// difference is where the rows came from.
    private func applyDecoded(_ data: Data, listName: String? = nil) {
        // 붙여넣은 텍스트이거나 Takeout이므로 폴더가 없다.
        previewBundleURL = nil
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

    /// 폴더에서 고른 경우 사진을 옮기는 내내 보안 스코프가 열려 있어야 한다 —
    /// `handleFilePicked`에서 잡은 것은 그 함수가 끝나며 풀렸다.
    private func performImport() {
        guard let preview else { return }
        if let previewBundleURL {
            let accessed = previewBundleURL.startAccessingSecurityScopedResource()
            defer { if accessed { previewBundleURL.stopAccessingSecurityScopedResource() } }
            BackupService.importBoard(
                preview, photosFrom: previewBundleURL, storageService: storageService
            )
        } else {
            BackupService.importBoard(preview, storageService: storageService)
        }
        discardStagedBundleIfNeeded()
        didImport = true
    }
}

#Preview {
    ImportBoardSheet()
        .environmentObject(StorageService())
}
