import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var storageService: StorageService
    @ObservedObject private var backupFolderSettings = BackupFolderSettings.shared
    @ObservedObject private var localization = LocalizationObserver.shared

    @State private var showingBackupExporter = false
    @State private var backupDocument: BackupDocument?
    @State private var showingRestoreImporter = false
    @State private var showingRestoreConfirm = false
    @State private var restorePendingURL: URL?
    @State private var backupMessage: String?

    @State private var showingBackupFolderPicker = false
    @State private var autoBackupMessage: String?

    /// Sentinel tag for "Custom…" in the gateway model picker below,
    /// mirroring Peragra's own `SettingsSheet.customModelTag`.
    private static let customModelTag = "__custom__"

    private static func initialModelSelection(current: String, known: [GatewayModels.Model]) -> String {
        known.contains(where: { $0.id == current }) ? current : customModelTag
    }

    private static func initialCustomModelInput(current: String, known: [GatewayModels.Model]) -> String {
        known.contains(where: { $0.id == current }) ? "" : current
    }

    @State private var gatewayModelSelection: String = SettingsView.initialModelSelection(
        current: SettingsViewModel.currentGatewayModel(), known: GatewayModels.all
    )
    @State private var gatewayCustomModelInput: String = SettingsView.initialCustomModelInput(
        current: SettingsViewModel.currentGatewayModel(), known: GatewayModels.all
    )

    var body: some View {
        NavigationStack {
            Form {
                appLanguageSection
                googlePlacesAPISection
                naverMapSection
                naverSearchAPISection
                aiImageAnalysisSection
                scanResponseLanguageSection
                backupSection
                autoBackupSection
                infoSection
            }
            .navigationTitle("설정".localized)
            .alert(
                "알림".localized,
                isPresented: Binding(
                    get: { viewModel.statusMessage != nil },
                    set: { isPresented in
                        if !isPresented { viewModel.statusMessage = nil }
                    }
                )
            ) {
                Button("확인".localized, role: .cancel) { viewModel.statusMessage = nil }
            } message: {
                Text(viewModel.statusMessage ?? "")
            }
        }
    }

    /// Each of these used to be an inline `Section` in `body`'s `Form {
    /// ... }` — split out (same fix as `EditPlaceCardSheet`/
    /// `BoardDetailView`) because the compiler couldn't type-check `body`
    /// as one expression once nearly every literal in it became a
    /// non-literal `String` via `.localized` ("unable to type-check this
    /// expression in reasonable time").
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
        } footer: {
            Text("앱 화면 전체에서 사용하는 언어입니다. 사진 스캔·웹 검색 결과의 언어는 아래 \"AI 응답 언어\"에서 따로 정합니다.".localized)
        }
    }

    @ViewBuilder
    private var googlePlacesAPISection: some View {
        Section("Google Places API") {
            SecureField("API 키".localized, text: $viewModel.googleAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("저장".localized) { viewModel.saveGoogleAPIKey() }
        }
    }

    @ViewBuilder
    private var naverMapSection: some View {
        Section("Naver 지도 표시 (선택)".localized) {
            SecureField("NCP Client ID", text: $viewModel.naverMapClientId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("저장".localized) { viewModel.saveNaverMapClientId() }
            Text("\"지도\" 탭에서 Naver 지도를 선택했을 때만 사용됩니다. NAVER Cloud Platform Maps 애플리케이션의 Client ID이며, Secret은 필요 없습니다.".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var naverSearchAPISection: some View {
        Section("Naver 검색 API (선택)".localized) {
            SecureField("Client ID", text: $viewModel.naverSearchClientId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Client Secret", text: $viewModel.naverSearchClientSecret)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("저장".localized) { viewModel.saveNaverSearchCredentials() }
            Text("네이버 지도에서 공유받은 장소는 Google 대신 이 API로 검증합니다. 위 \"Naver 지도 표시\"와는 별개로, Naver Developers(developers.naver.com/apps)에서 발급받는 검색 API 애플리케이션의 Client ID/Secret입니다. 설정하지 않으면 지금처럼 Google로 검증합니다.".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var aiImageAnalysisSection: some View {
        Section("AI 이미지 분석 (BYOK)".localized) {
            Picker("제공자".localized, selection: $viewModel.aiProviderType) {
                ForEach(AIProviderType.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: viewModel.aiProviderType) { _, newValue in
                viewModel.loadAIKey(for: newValue)
            }

            SecureField("API 키".localized, text: $viewModel.aiAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if viewModel.aiProviderType == .gateway {
                Picker("모델".localized, selection: $gatewayModelSelection) {
                    ForEach(GatewayModels.all) { model in
                        Text(model.label).tag(model.id)
                    }
                    Text("직접 입력…".localized).tag(Self.customModelTag)
                }
                if gatewayModelSelection == Self.customModelTag {
                    TextField("model-id", text: $gatewayCustomModelInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Button("저장".localized) {
                if viewModel.aiProviderType == .gateway {
                    viewModel.gatewayModel = gatewayModelSelection == Self.customModelTag
                        ? gatewayCustomModelInput
                        : gatewayModelSelection
                }
                viewModel.saveAIProviderSettings()
            }
        }
    }

    @ViewBuilder
    private var scanResponseLanguageSection: some View {
        Section {
            Picker("AI 응답 언어".localized, selection: $viewModel.scanResultLanguage) {
                ForEach(ScanResultLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        } footer: {
            Text("사진 스캔·웹 검색으로 채워지는 카테고리·메모 같은 텍스트를 어떤 언어로 작성할지 정합니다. 앱 화면 자체의 언어(한국어)에는 영향을 주지 않습니다.".localized)
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        Section {
            Button("전체 백업".localized) { startBackup() }
            Button("백업에서 복원".localized, role: .destructive) { showingRestoreImporter = true }
            if let backupMessage {
                Text(backupMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("데이터".localized)
        } footer: {
            Text("모든 게시판·장소를 직접 고른 파일로 백업하거나, 백업 파일에서 복원합니다 — 복원하면 지금 앱에 있는 모든 데이터가 그 파일 내용으로 교체됩니다. 사진 자체는 백업에 포함되지 않고, 같은 기기에서 복원할 때만 정상적으로 보입니다.".localized)
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
            Button("복원".localized, role: .destructive) { performRestore() }
            Button("취소".localized, role: .cancel) { restorePendingURL = nil }
        } message: {
            Text("되돌릴 수 없습니다.".localized)
        }
    }

    @ViewBuilder
    private var autoBackupSection: some View {
        Section {
            if backupFolderSettings.folderDisplayName == nil {
                Button("백업 폴더 선택…".localized) { showingBackupFolderPicker = true }
            } else {
                LabeledContent("폴더".localized, value: backupFolderSettings.folderDisplayName ?? "")
                Toggle(
                    "자동으로 백업".localized,
                    isOn: Binding(
                        get: { backupFolderSettings.autoBackupEnabled },
                        set: { backupFolderSettings.setAutoBackupEnabled($0) }
                    )
                )
                Picker(
                    "주기".localized,
                    selection: Binding(
                        get: { backupFolderSettings.autoBackupIntervalDays },
                        set: { backupFolderSettings.setAutoBackupIntervalDays($0) }
                    )
                ) {
                    Text("매일".localized).tag(1)
                    Text("매주".localized).tag(7)
                }
                .pickerStyle(.segmented)

                if let lastAutoBackupAt = backupFolderSettings.lastAutoBackupAt {
                    Text("마지막 백업: ".localized + lastAutoBackupAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if backupFolderSettings.needsReauthorization {
                    Text("이 폴더에 대한 접근 권한이 끊어졌습니다. 아래에서 폴더를 다시 선택해주세요.".localized)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button("지금 백업".localized) {
                    autoBackupMessage = AutoBackupService.runNow(storageService: storageService)
                        ? "선택한 폴더에 백업했습니다.".localized
                        : "폴더에 쓰지 못했습니다 — 아래에서 폴더를 다시 선택해주세요.".localized
                }
                Button("폴더 변경…".localized) { showingBackupFolderPicker = true }
                Button("자동 백업 끄기".localized, role: .destructive) { backupFolderSettings.clearFolder() }
            }
            if let autoBackupMessage {
                Text(autoBackupMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("자동 백업".localized)
        } footer: {
            Text("폴더를 한 번 선택해두면, 앱을 열 때마다(위 주기당 최대 한 번) PlaceCards가 그 폴더에 새 백업을 저장합니다.".localized)
        }
        .fileImporter(
            isPresented: $showingBackupFolderPicker,
            allowedContentTypes: [.folder],
            onCompletion: handleBackupFolderPicked
        )
    }

    @ViewBuilder
    private var infoSection: some View {
        Section("정보".localized) {
            LabeledContent("API 키 저장 방식".localized, value: "iOS 키체인 (기기 내)".localized)
            Text("PlaceCards는 사용자가 등록한 API 키로 직접 Google/Naver/AI 서비스를 호출합니다(BYOK). 키는 iCloud와 동기화되지 않으며 이 기기에만 저장됩니다.".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("공유로 사진 가져오기".localized) {
                Label(
                    SharedImportStore.isAppGroupAvailable ? "연결됨".localized : "연결 안 됨".localized,
                    systemImage: SharedImportStore.isAppGroupAvailable
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(SharedImportStore.isAppGroupAvailable ? .green : .orange)
            }
            if !SharedImportStore.isAppGroupAvailable {
                Text("다른 앱에서 공유한 사진을 못 받아오는 상태입니다. Xcode에서 PlaceCards와 PlaceCardsShare 두 타겟 모두 Signing & Capabilities에 팀을 지정하고 \"App Groups\" 항목에 group.com.mrnoh99.PlaceCards가 켜져 있는지 확인해주세요.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastShareStatus = SharedImportStore.lastDebugStatus() {
                LabeledContent("마지막 공유 시도".localized) {
                    Text(lastShareStatus)
                }
                .font(.caption)
            } else {
                Text("아직 공유 시도 기록이 없습니다. 사진 공유 시트에서 PlaceCards를 선택하면 여기에 결과가 표시됩니다.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startBackup() {
        do {
            backupDocument = BackupDocument(data: try BackupService.exportData(storageService: storageService))
            showingBackupExporter = true
        } catch {
            backupMessage = "백업을 준비하지 못했습니다.".localized
        }
    }

    private func performRestore() {
        guard let url = restorePendingURL else { return }
        restorePendingURL = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try BackupService.restore(from: data, storageService: storageService)
            backupMessage = "백업에서 복원했습니다.".localized
        } catch {
            backupMessage = (error as? BackupService.BackupError)?.errorDescription ?? "그 파일에서 복원하지 못했습니다.".localized
        }
    }

    private func handleBackupFolderPicked(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let bookmark = try? url.bookmarkData() else {
                autoBackupMessage = "백업 폴더를 설정하지 못했습니다.".localized
                return
            }
            backupFolderSettings.setFolder(bookmark: bookmark, displayName: url.lastPathComponent)
            backupFolderSettings.setAutoBackupEnabled(true)
            autoBackupMessage = nil
        case .failure:
            autoBackupMessage = "백업 폴더를 설정하지 못했습니다.".localized
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(StorageService())
}
