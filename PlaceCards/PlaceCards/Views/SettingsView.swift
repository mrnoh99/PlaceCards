import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Google Places API") {
                    SecureField("API 키", text: $viewModel.googleAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("저장") { viewModel.saveGoogleAPIKey() }
                }

                Section("Naver 검색 프록시") {
                    TextField("프록시 서버 URL (예: https://proxy.example.com)", text: $viewModel.naverProxyURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("저장") { viewModel.saveNaverProxyURL() }
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
                    Button("저장") { viewModel.saveAIProviderSettings() }
                }

                Section("정보") {
                    LabeledContent("API 키 저장 방식", value: "iOS 키체인 (기기 내)")
                    Text("PlaceCards는 사용자가 등록한 API 키로 직접 Google/Naver/AI 서비스를 호출합니다(BYOK). 키는 iCloud와 동기화되지 않으며 이 기기에만 저장됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
