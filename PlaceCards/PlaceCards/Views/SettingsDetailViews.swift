import SwiftUI
// For `UTType.folder` in `FolderBackupSettingsView`'s folder picker — the
// kind of import the local checks here cannot catch a missing one of.
import UniformTypeIdentifiers

/// The screens `SettingsView` pushes to.
///
/// Settings used to be one `Form` holding eleven sections: four AI
/// provider key fields with a priority list and a model picker, three
/// Naver credential fields across two sections, a folder-backup schedule,
/// and forty-odd lines of Cloud Console instructions — all at the same
/// level as "앱 언어", with nothing marking what a new user actually has
/// to fill in. Everything that is optional, or that is configured once and
/// then never touched again, lives on one of these screens instead, so the
/// first screen can be short enough to read.

// MARK: - Shared

extension View {
    /// The "저장했습니다" / error alert. Lives on every screen that can
    /// trigger a save rather than only on the root: an alert attached to a
    /// parent doesn't reliably present over a pushed child, so a key saved
    /// on a detail screen would otherwise confirm nothing.
    func settingsStatusAlert(viewModel: SettingsViewModel) -> some View {
        alert(
            "알림".localized,
            isPresented: Binding(
                get: { viewModel.statusMessage != nil },
                set: { if !$0 { viewModel.statusMessage = nil } }
            )
        ) {
            Button("확인".localized, role: .cancel) { viewModel.statusMessage = nil }
        } message: {
            Text(viewModel.statusMessage ?? "")
        }
    }
}

// MARK: - Google key help

/// The Cloud Console walkthrough, off the main screen.
///
/// This text is load-bearing — the two traps in it (enabling only one of
/// the two APIs, and restricting the key to "iOS apps") each produce a
/// silent, hard-to-diagnose failure — but it is read once, while setting
/// the key up, and never again. On the main screen it was forty lines of
/// caption text under a field.
struct GoogleAPIHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                helpBlock(
                    title: "두 개의 API를 모두 켜야 합니다".localized,
                    body: "장소 검색·상세·사진은 Places API (New)를 호출하고, \"지도\" 탭의 Google 지도는 Maps JavaScript API를 웹뷰에 띄워 그립니다. 같은 키를 쓰지만 서로 다른 API라서, 하나만 켜면 다른 쪽이 조용히 동작하지 않습니다.".localized
                )
                helpBlock(
                    title: "애플리케이션 제한은 \"없음\"으로 두세요".localized,
                    body: "REST 호출은 번들 ID로, 웹뷰의 지도는 리퍼러로 확인되는데 키 하나에는 제한을 한 종류만 걸 수 있습니다. \"iOS 앱\"을 고르면 지도 탭이 백지가 됩니다. 대신 아래 할당량으로 사용량을 막는 것을 권합니다.".localized
                )
                helpBlock(
                    title: "API별 일일 할당량을 직접 거세요".localized,
                    body: "Cloud Console → APIs & Services → Places API (New) → Quotas & System Limits에서 메서드별로 설정합니다. 기본값이 수십만 회라 그대로 두면 노출 금액이 큽니다.\n\n• SearchTextRequest — 200 (장소 검색과 주소 변환이 함께 소비)\n• GetPlaceRequest — 50\n• GetPhotoMediaRequest — 200\n• AutocompletePlacesRequest — 0 (미사용)\n• SearchNearbyRequest — 0 (미사용)\n• SearchMediaRequest — 0 (미사용)\n• SearchReviewPostsRequest — 0 (미사용)\n• Maps JavaScript API → Map loads per day — 200".localized
                )
                helpBlock(
                    title: "예산 알림을 함께 걸어두세요".localized,
                    body: "키 유출에 대한 방어가 제한이 아니라 할당량이므로, 결제 계정의 예산 알림(예: $5에 50/90/100%)이 사실상 마지막 안전망입니다.".localized
                )
                helpBlock(
                    title: "Geocoding API는 켜지 않아도 됩니다".localized,
                    body: "주소를 좌표로 바꾸는 것도 Places의 searchText가 처리합니다. 별도로 켜면 할당량 없는 표면만 하나 늘어납니다.".localized
                )
            }
            .padding()
        }
        .navigationTitle("Google 키 설정 방법".localized)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - AI providers

/// Every AI provider key, their fallback order, the gateway's model, and
/// the language scan results come back in.
struct AIProviderSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    /// Sentinel tag for "직접 입력…" in the gateway model picker,
    /// mirroring Peragra's own `SettingsSheet.customModelTag`.
    private static let customModelTag = "__custom__"

    @State private var gatewayModelSelection: String
    @State private var gatewayCustomModelInput: String

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        let current = SettingsViewModel.currentGatewayModel()
        let isKnown = GatewayModels.all.contains { $0.id == current }
        _gatewayModelSelection = State(initialValue: isKnown ? current : Self.customModelTag)
        _gatewayCustomModelInput = State(initialValue: isKnown ? "" : current)
    }

    var body: some View {
        Form {
            uploadNoticeSection
            keysSection
            prioritySection
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle("AI 제공자".localized)
        .navigationBarTitleDisplayMode(.inline)
        .settingsStatusAlert(viewModel: viewModel)
    }

    /// Stated on the screen that registers the key, not only in the
    /// privacy policy. Uploading the picked photo to a third party is the
    /// single most consequential thing this app does, and the moment
    /// someone is deciding whether to enable it is the moment they should
    /// be told.
    @ViewBuilder
    private var uploadNoticeSection: some View {
        Section {
            Text("사진 스캔을 실행하면 선택한 이미지가 아래에서 등록한 제공자에게 업로드됩니다. 업로드된 이미지의 처리·보관은 각 제공자의 정책을 따릅니다. 스캔을 실행하지 않으면 사진은 기기를 떠나지 않습니다.".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Every provider gets its own row (not one Picker swapping a single
    /// shared field) — `AIProviderChain.run(_:)` falls back through more
    /// than one, so all four need to be registerable at once.
    @ViewBuilder
    private var keysSection: some View {
        Section {
            ForEach(AIProviderType.allCases) { provider in
                // "저장" deliberately sits in its own Form row rather than
                // inside the VStack below. Sharing a row with a `.menu`
                // Picker made it un-tappable — that Picker's interaction
                // region inside a List row can exceed its visual bounds,
                // and no combination of `.borderless`/`.pickerStyle` fixed
                // it. `ForEach`'s closure is a `@ViewBuilder`, so
                // returning the button as a sibling is enough to split
                // them into two independent rows.
                VStack(alignment: .leading, spacing: 6) {
                    Text(provider.displayName)
                        .font(.subheadline.bold())
                    SecureField("API 키".localized, text: providerKeyBinding(provider))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if provider == .gateway {
                        Text("제3자가 운영하는 게이트웨이입니다.".localized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("모델".localized, selection: $gatewayModelSelection) {
                            ForEach(GatewayModels.all) { model in
                                Text(model.label).tag(model.id)
                            }
                            Text("직접 입력…".localized).tag(Self.customModelTag)
                        }
                        .pickerStyle(.menu)
                        if gatewayModelSelection == Self.customModelTag {
                            TextField("model-id", text: $gatewayCustomModelInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                }
                .padding(.vertical, 4)

                Button("저장".localized) {
                    if provider == .gateway {
                        viewModel.gatewayModel = gatewayModelSelection == Self.customModelTag
                            ? gatewayCustomModelInput
                            : gatewayModelSelection
                    }
                    viewModel.saveProviderAPIKey(provider)
                }
            }
        } header: {
            Text("제공자 키 (BYOK)".localized)
        } footer: {
            Text("여러 제공자의 키를 등록해두면, 아래 순서대로 시도하다가 하나가 실패(호출 한도 초과, 오류 등)해도 자동으로 다음 제공자로 넘어갑니다.".localized)
        }
    }

    /// Up/down buttons rather than native drag-to-reorder — simpler and
    /// more reliable inside a `Form` than `.onMove`/`EditMode`, and this
    /// list only ever has as many rows as `AIProviderType` has cases.
    @ViewBuilder
    private var prioritySection: some View {
        Section {
            ForEach(Array(viewModel.providerPriority.enumerated()), id: \.element) { index, provider in
                HStack {
                    Text(provider.displayName)
                    if (viewModel.providerAPIKeys[provider] ?? "").isEmpty {
                        Text("(키 없음)".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.moveProviderUp(provider)
                    } label: {
                        Image(systemName: "chevron.up")
                            .accessibilityLabel("위로 이동".localized)
                    }
                    .disabled(index == 0)
                    Button {
                        viewModel.moveProviderDown(provider)
                    } label: {
                        Image(systemName: "chevron.down")
                            .accessibilityLabel("아래로 이동".localized)
                    }
                    .disabled(index == viewModel.providerPriority.count - 1)
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("우선순위".localized)
        } footer: {
            Text("사진 스캔 시 이 순서대로 시도합니다. 키가 등록되지 않은 제공자는 건너뜁니다.".localized)
        }
    }

    private func providerKeyBinding(_ provider: AIProviderType) -> Binding<String> {
        Binding(
            get: { viewModel.providerAPIKeys[provider] ?? "" },
            set: { viewModel.providerAPIKeys[provider] = $0 }
        )
    }
}

// MARK: - Naver

/// Both Naver integrations, which are separate applications registered in
/// separate consoles and were two same-level sections on the main screen
/// for it.
struct NaverSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            mapSection
            searchSection
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle("Naver 연동".localized)
        .navigationBarTitleDisplayMode(.inline)
        .settingsStatusAlert(viewModel: viewModel)
    }

    @ViewBuilder
    private var mapSection: some View {
        Section {
            SecureField("NCP Client ID", text: $viewModel.naverMapClientId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("저장".localized) { viewModel.saveNaverMapClientId() }
        } header: {
            Text("지도 표시".localized)
        } footer: {
            Text("\"지도\" 탭에서 Naver 지도를 선택했을 때만 사용됩니다. NAVER Cloud Platform Maps 애플리케이션의 Client ID이며, Secret은 필요 없습니다. 지도가 뜨는 페이지는 이 앱이 아니라 mrnoh99.github.io에서 불러오므로, 콘솔의 해당 Application 설정에서 Web 서비스 URL에 반드시 \"mrnoh99.github.io\"를 등록해야 합니다 — 등록하지 않으면 Client ID는 통과해도 지도 타일이 전부 실패합니다.".localized)
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        Section {
            SecureField("Client ID", text: $viewModel.naverSearchClientId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Client Secret", text: $viewModel.naverSearchClientSecret)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("저장".localized) { viewModel.saveNaverSearchCredentials() }
        } header: {
            Text("장소 검증".localized)
        } footer: {
            Text("네이버 지도에서 공유받은 장소는 Google 대신 이 API로 검증합니다. 위 \"지도 표시\"와는 별개의 애플리케이션입니다 — NAVER Cloud Platform 콘솔에서 Menu → All Services → Application Services → NAVER API HUB로 들어가 Application을 등록할 때 \"검색\" API를 선택하고, 등록된 Application의 \"인증 정보\"에서 Client ID/Secret을 확인해 입력하세요. 설정하지 않으면 지금처럼 Google로 검증합니다.".localized)
        }
    }
}

// MARK: - Folder backup

/// The scheduled "write a backup into a folder I picked" feature. Off the
/// main screen because it is configured once and then runs by itself.
struct FolderBackupSettingsView: View {
    @EnvironmentObject private var storageService: StorageService
    @ObservedObject private var settings = BackupFolderSettings.shared

    @State private var showingFolderPicker = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if settings.folderDisplayName == nil {
                    Button("백업 폴더 선택…".localized) { showingFolderPicker = true }
                } else {
                    configuredFolderRows
                }
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("폴더를 한 번 선택해두면, 앱을 열 때마다(위 주기당 최대 한 번) PinSpots가 그 폴더에 새 백업을 저장합니다.".localized)
            }
        }
        .navigationTitle("폴더 자동 백업".localized)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            onCompletion: handleFolderPicked
        )
    }

    @ViewBuilder
    private var configuredFolderRows: some View {
        LabeledContent("폴더".localized, value: settings.folderDisplayName ?? "")
        Toggle(
            "자동으로 백업".localized,
            isOn: Binding(
                get: { settings.autoBackupEnabled },
                set: { settings.setAutoBackupEnabled($0) }
            )
        )
        Picker(
            "주기".localized,
            selection: Binding(
                get: { settings.autoBackupIntervalDays },
                set: { settings.setAutoBackupIntervalDays($0) }
            )
        ) {
            Text("매일".localized).tag(1)
            Text("매주".localized).tag(7)
        }
        .pickerStyle(.segmented)

        if let lastAutoBackupAt = settings.lastAutoBackupAt {
            Text("마지막 백업: ".localized + lastAutoBackupAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if settings.needsReauthorization {
            Text("이 폴더에 대한 접근 권한이 끊어졌습니다. 아래에서 폴더를 다시 선택해주세요.".localized)
                .font(.caption)
                .foregroundStyle(.orange)
        }

        Button("지금 백업".localized) {
            Task {
                message = await AutoBackupService.runNow(storageService: storageService)
                    ? "선택한 폴더에 백업했습니다.".localized
                    : "폴더에 쓰지 못했습니다 — 아래에서 폴더를 다시 선택해주세요.".localized
            }
        }
        Button("폴더 변경…".localized) { showingFolderPicker = true }
        Button("자동 백업 끄기".localized, role: .destructive) { settings.clearFolder() }
    }

    private func handleFolderPicked(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let bookmark = try? url.bookmarkData() else {
                message = "백업 폴더를 설정하지 못했습니다.".localized
                return
            }
            settings.setFolder(bookmark: bookmark, displayName: url.lastPathComponent)
            settings.setAutoBackupEnabled(true)
            message = nil
        case .failure:
            message = "백업 폴더를 설정하지 못했습니다.".localized
        }
    }
}
