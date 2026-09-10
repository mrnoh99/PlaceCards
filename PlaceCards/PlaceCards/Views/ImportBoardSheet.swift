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
                            let count = preview.placeCards.filter { $0.boardId == board.id }.count
                            LabeledContent(board.name, value: "장소 \(count)개")
                        }
                    } header: {
                        Text("가져올 내용")
                    } footer: {
                        Text("기존 게시판·장소는 그대로 두고, 새 게시판으로 추가됩니다.")
                    }
                } else {
                    Section {
                        TextEditor(text: $pastedText)
                            .frame(minHeight: 160)
                        Button("붙여넣은 텍스트 확인") { parse(pastedText) }
                            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: {
                        Text("텍스트 붙여넣기")
                    }

                    Section {
                        Button("파일 선택…") { showingFileImporter = true }
                    } header: {
                        Text("또는 파일에서")
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("게시판 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                if preview != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("가져오기") { performImport() }
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                onCompletion: handleFilePicked
            )
            .onChange(of: didImport) { _, imported in
                if imported { dismiss() }
            }
        }
    }

    private func parse(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            errorMessage = "읽을 수 없는 텍스트입니다."
            return
        }
        applyDecoded(data)
    }

    private func handleFilePicked(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "파일을 읽지 못했습니다."
                return
            }
            applyDecoded(data)
        case .failure:
            errorMessage = "파일을 읽지 못했습니다."
        }
    }

    private func applyDecoded(_ data: Data) {
        do {
            preview = try BackupService.decode(data)
            errorMessage = nil
        } catch {
            errorMessage = (error as? BackupService.BackupError)?.errorDescription ?? "게시판 파일이 아닙니다."
        }
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
