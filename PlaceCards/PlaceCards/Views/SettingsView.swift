import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

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
                Section("Google Places API") {
                    SecureField("API 키", text: $viewModel.googleAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("저장") { viewModel.saveGoogleAPIKey() }
                }

                Section("Unsplash 이미지 검색 (선택)") {
                    SecureField("Access Key", text: $viewModel.unsplashAccessKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("저장") { viewModel.saveUnsplashAccessKey() }
                    Text("장소에 사용자가 올린 사진도, Google에서 찾은 사진도 없을 때만 이 장소명으로 Unsplash를 검색해 대신 썸네일로 사용합니다. unsplash.com/oauth/applications에서 발급받은 Access Key입니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Naver 지도 표시 (선택)") {
                    SecureField("NCP Client ID", text: $viewModel.naverMapClientId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("저장") { viewModel.saveNaverMapClientId() }
                    Text("\"지도\" 탭에서 Naver 지도를 선택했을 때만 사용됩니다. NAVER Cloud Platform Maps 애플리케이션의 Client ID이며, Secret은 필요 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("AI 이미지 분석 (BYOK)") {
                    Picker("제공자", selection: $viewModel.aiProviderType) {
                        ForEach(AIProviderType.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: viewModel.aiProviderType) { _, newValue in
                        viewModel.loadAIKey(for: newValue)
                    }

                    SecureField("API 키", text: $viewModel.aiAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if viewModel.aiProviderType == .gateway {
                        Picker("모델", selection: $gatewayModelSelection) {
                            ForEach(GatewayModels.all) { model in
                                Text(model.label).tag(model.id)
                            }
                            Text("직접 입력…").tag(Self.customModelTag)
                        }
                        if gatewayModelSelection == Self.customModelTag {
                            TextField("model-id", text: $gatewayCustomModelInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }

                    Button("저장") {
                        if viewModel.aiProviderType == .gateway {
                            viewModel.gatewayModel = gatewayModelSelection == Self.customModelTag
                                ? gatewayCustomModelInput
                                : gatewayModelSelection
                        }
                        viewModel.saveAIProviderSettings()
                    }
                }

                Section("정보") {
                    LabeledContent("API 키 저장 방식", value: "iOS 키체인 (기기 내)")
                    Text("PlaceCards는 사용자가 등록한 API 키로 직접 Google/Naver/AI 서비스를 호출합니다(BYOK). 키는 iCloud와 동기화되지 않으며 이 기기에만 저장됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("공유로 사진 가져오기") {
                        Label(
                            SharedImportStore.isAppGroupAvailable ? "연결됨" : "연결 안 됨",
                            systemImage: SharedImportStore.isAppGroupAvailable
                                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(SharedImportStore.isAppGroupAvailable ? .green : .orange)
                    }
                    if !SharedImportStore.isAppGroupAvailable {
                        Text("다른 앱에서 공유한 사진을 못 받아오는 상태입니다. Xcode에서 PlaceCards와 PlaceCardsShare 두 타겟 모두 Signing & Capabilities에 팀을 지정하고 \"App Groups\" 항목에 group.com.mrnoh99.PlaceCards가 켜져 있는지 확인해주세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let lastShareStatus = SharedImportStore.lastDebugStatus() {
                        LabeledContent("마지막 공유 시도") {
                            Text(lastShareStatus)
                        }
                        .font(.caption)
                    } else {
                        Text("아직 공유 시도 기록이 없습니다. 사진 공유 시트에서 PlaceCards를 선택하면 여기에 결과가 표시됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("설정")
            .alert(
                "알림",
                isPresented: Binding(
                    get: { viewModel.statusMessage != nil },
                    set: { isPresented in
                        if !isPresented { viewModel.statusMessage = nil }
                    }
                )
            ) {
                Button("확인", role: .cancel) { viewModel.statusMessage = nil }
            } message: {
                Text(viewModel.statusMessage ?? "")
            }
        }
    }
}

#Preview {
    SettingsView()
}
