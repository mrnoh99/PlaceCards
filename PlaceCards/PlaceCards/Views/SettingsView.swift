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
    @ObservedObject private var usage = APIUsageCounter.shared

    @State private var showingBackupFolderPicker = false
    @State private var showingRestoreImporter = false
    @State private var showingCSVExporter = false
    @State private var csvDocument: CSVDocument?
    @State private var showingRestoreConfirm = false
    @State private var restorePendingURL: URL?
    @State private var backupMessage: String?

    /// Mirrors `CloudBackupService.isEnabled`, read once — nothing outside
    /// this screen changes it.
    @State private var isCloudBackupEnabled = CloudBackupService.isEnabled
    /// 앱이 하나 만들어 내려보낸다(`PlaceCardsApp`). 갤러리 툴바의 동기화
    /// 단추와 같은 것을 눌러야 하므로 여기서 새로 만들지 않는다.
    @EnvironmentObject private var cloudSync: CloudSyncService

    /// Filled in once by a background task — `MediaStore.usage()` walks the
    /// whole photo directory, which has no business running on every render.
    @State private var mediaUsage: (fileCount: Int, totalBytes: Int64)?

    private var cloudSyncStatusText: String {
        switch cloudSync.status {
        case .notChecked: return "확인 안 함".localized
        case .checking: return "확인 중…".localized
        case .ready(let accountTag): return "연결됨 (".localized + accountTag + ")"
        case .noAccount: return "iCloud에 로그인되어 있지 않습니다.".localized
        case .restricted: return "이 기기에서 iCloud가 제한되어 있습니다.".localized
        case .unavailable(let reason): return reason
        }
    }

    /// 연결 확인(`cloudSyncStatusText`)과 한 줄로 합치지 않는다. 연결됐다는
    /// 말과 주고받았다는 말은 다른 사실이고, 실패했을 때 어느 쪽이 실패한
    /// 것인지 구별되지 않으면 사용자가 할 일을 못 고른다.
    ///
    /// 문장 자체는 `SyncState`가 만든다 — 갤러리 툴바의 단추도 같은 것을 쓴다.
    private var cloudSyncProgressText: String {
        cloudSync.syncState.progressText
    }

    private var storageUsageText: String {
        guard let mediaUsage else { return "계산 중…".localized }
        let places = "\(storageService.activePlaceCards.count)" + "개 장소".localized
        let photos = "\(mediaUsage.fileCount)" + "장의 사진".localized
        let size = ByteCountFormatter.string(fromByteCount: mediaUsage.totalBytes, countStyle: .file)
        return places + " · " + photos + " · " + size
    }

    var body: some View {
        NavigationStack {
            // Ordered by what a new person should deal with first, not by
            // how the app is built. Language, then the key that decides
            // how much of this app works at all, then the map keys —
            // Naver last, and only where it can be used.
            // Each section below is a computed property rather than an
            // inline `Section` here, because the compiler couldn't
            // type-check this body as one expression once nearly every
            // literal in it became a non-literal `String` via `.localized`
            // ("unable to type-check this expression in reasonable time").
            // Same fix as `EditPlaceCardSheet`.
            Form {
                languageSection
                aiKeySection
                googlePlacesAPISection
                naverSection
                usageSection
                dataSection
                legalSection
                infoSection
                creditFooter
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("설정".localized)
            .settingsStatusAlert(viewModel: viewModel)
            .task {
                mediaUsage = await Task.detached(priority: .utility) { MediaStore.usage() }.value
            }
        }
    }

    /// Only one language choice is the user's to make here. The app's own
    /// screens follow iOS, because the person already told iOS what they
    /// read; what this app can't know is what language they want the
    /// *place information* it reads back in, which is a different question
    /// — someone reading a Korean UI may well want notes about a Tokyo
    /// trip written in Japanese.
    @ViewBuilder
    private var languageSection: some View {
        Section {
            Picker("읽어오는 언어".localized, selection: $viewModel.scanResultLanguage) {
                ForEach(ScanResultLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        } header: {
            Text("언어".localized)
        } footer: {
            Text("사진 스캔으로 채워지는 카테고리·메모 같은 정보를 어떤 언어로 가져올지 정합니다. 앱 화면 자체의 언어는 iOS 설정의 언어를 따릅니다.".localized)
        }
    }

    /// First, and said plainly: without this key most of what this app is
    /// for doesn't happen. The field for the provider that would actually
    /// be used is right here rather than a screen away — registering one
    /// key is the whole setup for most people, and the other three
    /// providers, their order and the gateway's model are a row down.
    @ViewBuilder
    private var aiKeySection: some View {
        Section {
            if !hasAnyAIKey {
                Label(
                    "키를 등록하지 않으면 기능이 크게 제한됩니다.".localized,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.orange)
            }
            LabeledContent("제공자".localized, value: primaryAIProvider.displayName)
            SecureField("API 키".localized, text: providerKeyBinding(primaryAIProvider))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("저장".localized) { viewModel.saveProviderAPIKey(primaryAIProvider) }
            NavigationLink {
                AIProviderSettingsView(viewModel: viewModel)
            } label: {
                LabeledContent("다른 제공자와 우선순위".localized) {
                    Text(registeredProviderSummary)
                }
            }
        } header: {
            Text("AI 사진 읽기 — 가장 먼저 설정하세요".localized)
        } footer: {
            Text("이 앱의 핵심은 사진에서 장소를 찾아내는 것이고, 그 일을 하는 것이 이 키입니다. 등록하면 인스타그램 게시물처럼 주소가 없는 사진에서도 장소를 읽고 전화번호·영업시간까지 채웁니다. 등록하지 않으면 가게 이름과 주소가 함께 보이는 사진만 기기에서 읽을 수 있고, 그 외의 사진에서는 아무것도 얻지 못합니다.".localized)
        }
    }

    private var hasAnyAIKey: Bool {
        AIProviderType.allCases.contains { !(viewModel.providerAPIKeys[$0] ?? "").isEmpty }
    }

    /// Whichever provider a scan would actually reach first: the
    /// highest-priority one that has a key, or — when none does yet — the
    /// highest-priority one, which is the provider the key typed in above
    /// would be saved for.
    private var primaryAIProvider: AIProviderType {
        viewModel.providerPriority.first { !(viewModel.providerAPIKeys[$0] ?? "").isEmpty }
            ?? viewModel.providerPriority.first
            ?? .claude
    }

    private func providerKeyBinding(_ provider: AIProviderType) -> Binding<String> {
        Binding(
            get: { viewModel.providerAPIKeys[provider] ?? "" },
            set: { viewModel.providerAPIKeys[provider] = $0 }
        )
    }

    /// Naver is a Korean service, its consoles are Korean-only, and its
    /// local search covers Korean places — offering it on a device that
    /// has nothing to do with Korea is three credential fields of pure
    /// noise. Shown for a Korean region *or* a Korean reader, since either
    /// one alone would miss someone (a Korean speaker abroad; a resident
    /// whose phone is in English).
    private var isKoreaRelevant: Bool {
        if Locale.current.region?.identifier == "KR" { return true }
        return Locale.preferredLanguages.contains { $0.hasPrefix("ko") }
    }

    @ViewBuilder
    private var naverSection: some View {
        if isKoreaRelevant {
            Section {
                NavigationLink {
                    NaverSettingsView(viewModel: viewModel)
                } label: {
                    LabeledContent("Naver 연동".localized) {
                        Text(naverSummary)
                    }
                }
            } header: {
                Text("Naver — 한국 장소 (선택)".localized)
            } footer: {
                Text("네이버 지도에서 공유받은 장소를 Google 대신 Naver로 검증하고, \"지도\" 탭에 네이버 지도를 띄울 수 있습니다. 설정하지 않아도 모든 장소는 Google로 검증됩니다.".localized)
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
            Text("Google — 지도와 장소 정보".localized)
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
            // Photos are kept forever and nothing prunes them, so this is
            // the one number worth showing before any of the backup/export
            // actions below — until now it was only visible from iOS's own
            // Settings app, never from here.
            LabeledContent("저장 공간".localized) {
                Text(storageUsageText)
            }
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
            LabeledContent("기기 간 동기화".localized) {
                HStack(spacing: 6) {
                    Text(cloudSyncStatusText)
                        .foregroundStyle(cloudSync.status.isReady ? .green : .secondary)
                    if case .checking = cloudSync.status {
                        ProgressView()
                    } else {
                        Button("확인".localized) { Task { await cloudSync.check() } }
                            .buttonStyle(.borderless)
                    }
                }
                .font(.subheadline)
            }
            LabeledContent("iCloud와 맞추기".localized) {
                HStack(spacing: 6) {
                    Text(cloudSyncProgressText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    if cloudSync.syncState.isBusy {
                        ProgressView()
                    } else {
                        Button("지금 맞추기".localized) {
                            Task { await cloudSync.syncNow(storageService: storageService) }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .font(.subheadline)
            }
            Button("전체 백업".localized) { showingBackupFolderPicker = true }
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
            Text("\"iCloud에 자동 보관\"은 게시판·장소·사진 전체의 사본을 본인의 iCloud 계정 안 이 앱 전용 공간에 저장해, 기기를 바꾸거나 앱을 다시 설치했을 때 복구할 수 있게 합니다. 끄면 이미 저장된 사본도 삭제됩니다. \"전체 백업\"은 같은 내용을 직접 고른 폴더 안에 백업 폴더 하나로 저장합니다. 복원할 때는 그 폴더를 고르면 되고, 이 기기에 없는 장소는 추가하고 백업 쪽이 더 나중에 수정된 장소는 그 내용으로 바꿉니다. 백업에 없는 장소는 그대로 둡니다.".localized)
            Text("지금 맞추기는 다른 기기에서 올린 게시판과 장소를 먼저 받아 합친 뒤, 합친 결과를 본인 iCloud에 올립니다. 이 기기에 없던 장소는 추가하고, 다른 기기에서 더 나중에 고친 장소는 그 내용으로 바꾸며, iCloud에 없는 장소는 그대로 둡니다. 한 기기에서 아주 지운 장소는 다른 기기에서도 지워지고 다시 살아나지 않습니다. 사진은 장소가 가리키는 것만, 아직 없는 쪽으로만 오갑니다.".localized)
        }
        // 파일을 내보내는 대신 **저장할 폴더를 고르게 한다.** 백업 한 벌이
        // 이제 폴더 하나이기 때문이다(`BackupService`의 폴더 형식).
        //
        // `.fileExporter`로 폴더를 내보내려면 패키지 UTType을 따로 선언해야
        // 하는데, 이 앱은 Info.plist를 빌드 설정에서 만들어 내므로
        // (`GENERATE_INFOPLIST_FILE = YES`) 그 선언을 넣으려면 프로젝트
        // 구조부터 바꿔야 한다. 폴더를 고르게 하면 그게 통째로 필요 없고,
        // **폴더 자동 백업이 이미 쓰고 있는 길**과 같은 길이 된다.
        .fileImporter(isPresented: $showingBackupFolderPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await writeBackup(into: url) }
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
        // `.folder`도 고를 수 있어야 한다. 자동 백업은 이제 **폴더**로
        // 쓰므로(`BackupService`의 폴더 형식), `.json`만 받으면 제 백업을
        // 손으로 되돌릴 길이 없다. 옛 단일 파일 백업도 그대로 받는다.
        .fileImporter(isPresented: $showingRestoreImporter, allowedContentTypes: [.json, .folder]) { result in
            switch result {
            case .success(let url):
                restorePendingURL = url
                showingRestoreConfirm = true
            case .failure:
                backupMessage = "파일을 읽지 못했습니다.".localized
            }
        }
        // No longer `role: .destructive`, and no longer warns that it
        // can't be undone: a restore now only adds what is missing, so
        // there is nothing here to lose. The dialog stays because the
        // user still picked a file and deserves to see what it will do.
        .confirmationDialog(
            "이 백업을 가져올까요?".localized,
            isPresented: $showingRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("가져오기".localized) { Task { await performRestore() } }
            Button("취소".localized, role: .cancel) { restorePendingURL = nil }
        } message: {
            Text("이 기기에 없는 장소는 추가하고, 백업 쪽이 더 나중에 수정된 장소는 그 내용으로 바꿉니다. 백업에 없는 장소는 그대로 둡니다.".localized)
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
            CreditFooter()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// Synchronous, unlike `writeBackup(into:)`: a CSV is text with no
    /// photo bytes in it, so there is nothing here worth an async hop.
    private func startCSVExport() {
        csvDocument = CSVDocument(
            data: CSVExport.csv(boards: storageService.boards, placeCards: storageService.activePlaceCards)
        )
        showingCSVExporter = true
    }

    /// 고른 폴더 안에 백업 폴더 한 벌을 쓴다.
    ///
    /// 예전에는 `BackupService.exportData`로 통째로 인코딩한 `Data`를
    /// `.fileExporter`에 넘겼다. 그 인코딩이 사진 전체를 두 벌로 메모리에
    /// 올려, 사진이 쌓인 기기에서 이 단추가 앱을 죽였다 — `writeBundle`은
    /// 사진을 한 장씩 파일로 옮기므로 그런 일이 없다.
    ///
    /// 보안 스코프는 쓰는 내내 열려 있어야 한다. 사진을 한 장씩 그 폴더
    /// 안으로 복사하는 것이 오래 걸리는 부분이다(`AutoBackupService`와
    /// 같은 이유).
    private func writeBackup(into folderURL: URL) async {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }
        do {
            try await BackupService.writeBundle(
                to: folderURL.appendingPathComponent(BackupService.filename()),
                storageService: storageService
            )
            backupMessage = "백업을 저장했습니다.".localized
        } catch {
            backupMessage = "백업을 저장하지 못했습니다.".localized
        }
    }

    /// One line for what a restore did. Built in separate statements
    /// rather than one `+` chain — a long chain of `.localized`
    /// concatenations is what trips "unable to type-check this expression
    /// in reasonable time" elsewhere in this app.
    private func restoreSummary(_ result: (boards: Int, added: Int, updated: Int)) -> String {
        if result.added == 0 && result.updated == 0 {
            return "이 백업에서 바뀐 것이 없습니다.".localized
        }
        var parts: [String] = []
        if result.added > 0 {
            parts.append("\(result.added)" + "곳 추가".localized)
        }
        if result.updated > 0 {
            parts.append("\(result.updated)" + "곳 갱신".localized)
        }
        return parts.joined(separator: ", ")
    }

    /// 고른 것이 **폴더 형식 백업이면** 그쪽으로, 아니면 옛 단일 파일로
    /// 다룬다.
    ///
    /// 보안 스코프를 붙잡고 있는 범위가 둘에서 다르다. 파일 쪽은 바이트를
    /// 다 읽고 나면 더 볼 일이 없어 읽는 동안만 잡으면 되지만, 폴더 쪽은
    /// **사진을 한 장씩 그 폴더에서 복사해 오는 내내** 열려 있어야 한다.
    private func performRestore() async {
        guard let url = restorePendingURL else { return }
        restorePendingURL = nil

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        // 읽기 전에 내려받는다 — 아직 안 내려온 iCloud 파일을 그대로 읽으면
        // Foundation이 블록해서 화면이 선 채로 멎는다(`ensureDownloaded`).
        backupMessage = "파일을 읽는 중…".localized
        // 다 왔는지 **묻고 답을 본다.** 예전에는 부르고 지나갔고, 시간이
        // 다해도 그 사실을 모른 채 반쯤 온 백업으로 복원했다.
        let arrived = await BackupService.ensureDownloaded(at: url)
        guard arrived, FileManager.default.fileExists(atPath: url.path) else {
            backupMessage = "아직 iCloud에서 내려받지 못했습니다. 파일 앱에서 받아 둔 뒤 다시 골라주세요.".localized
            return
        }

        do {
            let result: (boards: Int, added: Int, updated: Int)
            if BackupService.isBundle(at: url) {
                result = try await BackupService.restore(bundleAt: url, storageService: storageService)
            } else {
                // 옛 단일 파일도 **임시 폴더로 옮겨 놓고** 폴더 쪽 길을 탄다.
                // 그쪽에서 읽기와 디코딩이 전부 메인 액터 밖에서 일어나고,
                // 사진을 든 사전이 곧바로 풀린다 — 여기서 `Data(contentsOf:)`로
                // 통째로 읽으면 그 수백 MB가 메인 액터에 얹힌다.
                let staged = try await BackupService.stageLegacyBackup(at: url)
                defer { BackupService.discardStagedBundle(at: staged.bundleURL) }
                result = try await BackupService.restore(
                    bundleAt: staged.bundleURL, storageService: storageService
                )
            }
            // Says what actually happened, and counts replacements
            // separately — overwriting a card the user already had is the
            // one part of this worth never glossing over.
            backupMessage = restoreSummary(result)
        } catch {
            backupMessage = (error as? BackupService.BackupError)?.errorDescription ?? "그 파일에서 복원하지 못했습니다.".localized
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(StorageService())
        .environmentObject(CloudSyncService())
}
