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

                Section("Naver 검색 (Local Search API)") {
                    SecureField("Client ID", text: $viewModel.naverClientId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Client Secret", text: $viewModel.naverClientSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("저장") { viewModel.saveNaverLocalSearchCredentials() }
                    Text("openapi.naver.com에서 발급받은 키입니다. 앱이 기기에서 Naver API를 직접 호출하므로 별도 서버가 필요 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Naver 좌표 보강 (Geocoding API, 선택)") {
                    SecureField("NCP Client ID", text: $viewModel.naverGeocodingClientId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("NCP Client Secret", text: $viewModel.naverGeocodingClientSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("저장") { viewModel.saveNaverGeocodingCredentials() }
                    Text("NAVER Cloud Platform(NCP)에서 발급받은, 위 검색 키와는 별도의 키입니다. 주소만 있고 좌표가 없는 장소의 좌표를 보강할 때 사용됩니다.")
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
