import SwiftUI
import UniformTypeIdentifiers

/// The Settings tab's first screen.
///
/// Kept deliberately short. What a person has to deal with here is the one
/// required key, what this app has spent on their behalf, and their data;
/// everything optional or set-once lives behind a row (see
/// `SettingsDetailViews.swift`). Nothing on this screen tells the user to
/// open Xcode.
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var storageService: StorageService
    @ObservedObject private var localization = LocalizationObserver.shared
    @ObservedObject private var usage = APIUsageCounter.shared

    @State private var showingBackupExporter = false
    @State private var backupDocument: BackupDocument?
    @State private var showingRestoreImporter = false
    @State private var showingCSVExporter = false
    @State private var csvDocument: CSVDocument?
    @State private var showingRestoreConfirm = false
    @State private var restorePendingURL: URL?
    @State private var backupMessage: String?

    /// Mirrors `CloudBackupService.isEnabled`, read once — nothing outside
    /// this screen changes it.
    @State private var isCloudBackupEnabled = CloudBackupService.isEnabled

    var body: some View {
        NavigationStack {
            Form {
                appLanguageSection
                googlePlacesAPISection
                usageSection
                integrationsSection
                dataSection
                legalSection
                infoSection
                creditFooter
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("설정".localized)
            .settingsStatusAlert(viewModel: viewModel)
        }
    }

    /// Each of these is a computed property rather than an inline
    /// `Section` in `body` because the compiler couldn't type-check `body`
    /// as one expression once nearly every literal in it became a
    /// non-literal `String` via `.localized` ("unable to type-check this
    /// expression in reasonable time"). Same fix as `EditPlaceCardSheet`.
    @ViewBuilder
    private var appLanguageSection: some View {
        Section {
            Picker(
                "앱 언어".localized,
                selection: Binding(
                    get: { localization.language },
                    set: { localization.setLanguage($0) }
                )
            ) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        }
    }

    /// The one key the app genuinely leans on, so it stays on this screen
    /// with the field right there. The Cloud Console walkthrough that used
    /// to sit under it as forty lines of caption text is a row now
    /// (`GoogleAPIHelpView`) — the same information, read at the one
    /// moment it's needed.
    @ViewBuilder
    private var googlePlacesAPISection: some View {
        Section {
            SecureField("API 키".localized, text: $viewModel.googleAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("저장".localized) { viewModel.saveGoogleAPIKey() }
            NavigationLink("키 발급과 설정 방법".localized) { GoogleAPIHelpView() }
        } header: {
            Text("Google Places API")
        } footer: {
            Text("장소 확인과 평점·사진·영업시간 채우기, 그리고 \"지도\" 탭의 Google 지도에 사용됩니다. 키가 없어도 공유로 장소를 담고 기기 내 사진 읽기를 쓸 수 있지만, 그 정보들은 비어 있게 됩니다.".localized)
        }
    }

    /// Hidden until something has actually been counted — a user who has
    /// never made a request doesn't need a screenful of zeroes.
    @ViewBuilder
    private var usageSection: some View {
        if usage.hasAnyUsage {
            Section {
                ForEach(APIUsageCounter.Call.allCases) { call in
                    LabeledContent(call.displayName) {
                        Text(usageDetail(for: call))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                Button("기록 지우기".localized, role: .destructive) { usage.clear() }
            } header: {
                Text("사용량".localized)
            } footer: {
                Text("이 기기가 보낸 Google Places와 AI 요청 수입니다. 오늘 수치 뒤의 숫자는 이 앱이 권장하는 일일 할당량이며, 실제로 설정된 할당량이 아닙니다. 요금은 각 제공자가 사용자 계정에 직접 청구하므로 실제 금액은 해당 콘솔에서 확인하세요.".localized)
            }
        }
    }

    /// Both optional integrations, as one row each. A registered-key count
    /// rather than a bare chevron, so the state is readable without
    /// opening it.
    @ViewBuilder
    private var integrationsSection: some View {
        Section {
            NavigationLink {
                AIProviderSettingsView(viewModel: viewModel)
            } label: {
                LabeledContent("AI 이미지 분석".localized) {
                    Text(registeredProviderSummary)
                }
            }
            NavigationLink {
                NaverSettingsView(viewModel: viewModel)
            } label: {
                LabeledContent("Naver 연동".localized) {
                    Text(naverSummary)
                }
            }
        } header: {
            Text("선택 기능".localized)
        } footer: {
            Text("AI 키를 등록하면 인스타그램 게시물처럼 주소가 없는 사진도 읽을 수 있습니다. 등록하지 않아도 주소가 함께 보이는 사진은 기기에서 바로 읽습니다.".localized)
        }
    }

    /// "오늘 12/200 · 이번 달 148". The limit shown after today's count is
    /// the value README asks the user to set in their own Cloud console —
    /// nothing here can read what they actually set, which is why the
    /// footer says so rather than letting the slash imply otherwise.
    private func usageDetail(for call: APIUsageCounter.Call) -> String {
        let todayCount = usage.today[call] ?? 0
        let today: String
        if let limit = call.recommendedDailyLimit {
            today = "오늘 ".localized + "\(todayCount)/\(limit)"
        } else {
            today = "오늘 ".localized + "\(todayCount)"
        }
        return today + " · ".localized + "이번 달 ".localized + "\(usage.month[call] ?? 0)"
    }

    private var registeredProviderSummary: String {
        let count = AIProviderType.allCases.filter { !(viewModel.providerAPIKeys[$0] ?? "").isEmpty }.count
        return count == 0 ? "미설정".localized : "\(count)" + "개 등록됨".localized
    }

    private var naverSummary: String {
        let hasMap = !viewModel.naverMapClientId.isEmpty
        let hasSearch = !viewModel.naverSearchClientId.isEmpty && !viewModel.naverSearchClientSecret.isEmpty
        if hasMap && hasSearch { return "지도 · 검색".localized }
        if hasMap { return "지도".localized }
        if hasSearch { return "검색".localized }
        return "미설정".localized
    }

    @ViewBuilder
    private var dataSection: some View {
        Section {
            Toggle(
                "iCloud에 자동 보관".localized,
                isOn: Binding(
                    get: { isCloudBackupEnabled },
                    set: { newValue in
                        isCloudBackupEnabled = newValue
                        Task {
                            await CloudBackupService.setEnabled(newValue)
                            backupMessage = newValue
                                ? nil
                                : "iCloud에 보관된 사본을 삭제했습니다.".localized
                        }
                    }
                )
            )
            Button("전체 백업".localized) { Task { await startBackup() } }
            // A different job from the backup above, not a variant of it:
            // that file exists to restore this app, embeds every photo as
            // base64, and no spreadsheet will open it.
            Button("CSV로 내보내기".localized) { startCSVExport() }
            NavigationLink("폴더 자동 백업".localized) { FolderBackupSettingsView() }
            Button("백업에서 복원".localized, role: .destructive) { showingRestoreImporter = true }
            if let backupMessage {
                Text(backupMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("데이터".localized)
        } footer: {
            Text("\"iCloud에 자동 보관\"은 게시판·장소·사진 전체의 사본을 본인의 iCloud 계정 안 이 앱 전용 공간에 저장해, 기기를 바꾸거나 앱을 다시 설치했을 때 복구할 수 있게 합니다. 끄면 이미 저장된 사본도 삭제됩니다. \"전체 백업\"은 같은 내용을 직접 고른 파일로 저장하며, 복원하면 지금 앱에 있는 모든 데이터가 그 파일 내용으로 교체됩니다.".localized)
        }
        .fileExporter(
            isPresented: $showingBackupExporter,
            document: backupDocument,
            contentType: .json,
            defaultFilename: BackupService.filename()
        ) { result in
            switch result {
            case .success: backupMessage = "백업을 저장했습니다.".localized
            case .failure: backupMessage = "백업을 저장하지 못했습니다.".localized
            }
        }
        .fileExporter(
            isPresented: $showingCSVExporter,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: CSVExport.filename()
        ) { result in
            switch result {
            case .success: backupMessage = "CSV를 저장했습니다.".localized
            case .failure: backupMessage = "CSV를 저장하지 못했습니다.".localized
            }
        }
        .fileImporter(isPresented: $showingRestoreImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                restorePendingURL = url
                showingRestoreConfirm = true
            case .failure:
                backupMessage = "파일을 읽지 못했습니다.".localized
            }
        }
        .confirmationDialog(
            "이 백업으로 모든 게시판·장소를 교체할까요?".localized,
            isPresented: $showingRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("복원".localized, role: .destructive) { Task { await performRestore() } }
            Button("취소".localized, role: .cancel) { restorePendingURL = nil }
        } message: {
            Text("되돌릴 수 없습니다.".localized)
        }
    }

    /// Carried in the app rather than linked out — see `LegalDocuments`.
    @ViewBuilder
    private var legalSection: some View {
        Section {
            NavigationLink("개인정보 처리방침".localized) {
                LegalDocumentView(kind: .privacyPolicy)
            }
            NavigationLink("이용약관".localized) {
                LegalDocumentView(kind: .termsOfService)
            }
        } header: {
            Text("개인정보 및 약관".localized)
        }
    }

    @ViewBuilder
    private var infoSection: some View {
        Section {
            LabeledContent("API 키 저장 방식".localized, value: "iOS 키체인 (기기 내)".localized)
            Text("PinSpots는 사용자가 등록한 API 키로 직접 Google/Naver/AI 서비스를 호출합니다(BYOK). 키는 iCloud와 동기화되지 않으며 이 기기에만 저장됩니다.".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Kept because it answers a question a user really can have
            // ("I shared a photo and nothing happened"). What it no longer
            // does is hand them Xcode instructions they can't act on — in
            // a correctly built release this never reads "연결 안 됨", so
            // the text now points at the one step that is theirs.
            if !SharedImportStore.isAppGroupAvailable {
                LabeledContent("공유로 사진 가져오기".localized) {
                    Label("연결 안 됨".localized, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text("다른 앱에서 공유한 사진을 받아올 수 없는 상태입니다. 앱을 다시 설치해도 계속되면 알려주세요.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("정보".localized)
        }
    }

    /// The build's own credit line, at the very bottom of the last screen
    /// — the conventional place for one, and the only screen a person
    /// goes looking for a version number.
    @ViewBuilder
    private var creditFooter: some View {
        Section {
            Text(Self.creditLine)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// Read from the bundle rather than written out here, so the numbers
    /// can never drift from the build they are printed on. Not localized:
    /// a name and two version numbers read the same in either language.
    private static var creditLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "Developed by JaiSung NOH MD 2026, Ver(\(version)) Build(\(build))"
    }

    /// Synchronous, unlike `startBackup()`: a CSV is text with no photo
    /// bytes in it, so there is nothing here worth an async hop.
    private func startCSVExport() {
        csvDocument = CSVDocument(
            data: CSVExport.csv(boards: storageService.boards, placeCards: storageService.placeCards)
        )
        showingCSVExporter = true
    }

    private func startBackup() async {
        do {
            backupDocument = BackupDocument(data: try await BackupService.exportData(storageService: storageService))
            showingBackupExporter = true
        } catch {
            backupMessage = "백업을 준비하지 못했습니다.".localized
        }
    }

    /// The file's own bytes are read while the security-scoped access is
    /// still held; applying it (`BackupService.restore`, which decodes and
    /// writes every embedded photo off the main actor) happens after,
    /// since it only ever touches this app's own container.
    private func performRestore() async {
        guard let url = restorePendingURL else { return }
        restorePendingURL = nil
        let data: Data
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            data = try Data(contentsOf: url)
        } catch {
            backupMessage = "그 파일에서 복원하지 못했습니다.".localized
            return
        }
        do {
            try await BackupService.restore(from: data, storageService: storageService)
            backupMessage = "백업에서 복원했습니다.".localized
        } catch {
            backupMessage = (error as? BackupService.BackupError)?.errorDescription ?? "그 파일에서 복원하지 못했습니다.".localized
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(StorageService())
}
