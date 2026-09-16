import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    /// Read by `MainTabView` right after onboarding finishes, to open the
    /// Settings tab when the user chose "지금 설정하기". A stored flag
    /// rather than a direct call because `AppNavigation` doesn't exist yet
    /// while this screen is up — it's created by `MainTabView`, which only
    /// appears once `hasCompletedOnboarding` flips.
    @AppStorage("pendingOpenAIKeySetup") private var pendingOpenAIKeySetup = false
    @State private var step = 0

    private let steps: [(systemImage: String, title: String, description: String)] = [
        ("mappin.and.ellipse", "PinSpots",
         "지도 앱, SNS, 직접 찍은 사진에서 발견한 장소를 하나의 카드로 모아보세요.".localized),
        ("square.and.arrow.down", "공유로 바로 담기".localized,
         "Google 지도나 네이버 지도에서 장소를 공유하면 바로 카드가 됩니다. 별도 설정 없이 지금 바로 쓸 수 있어요.".localized),
        ("photo.on.rectangle.angled", "사진에서 찾기".localized,
         "AI 키를 등록하면 인스타그램 게시물처럼 주소가 없는 사진에서도 장소를 읽고 전화번호·영업시간까지 채웁니다. 등록하지 않으면 가게 이름과 주소가 함께 보이는 사진만 읽을 수 있습니다. 키는 이 기기의 키체인에만 저장됩니다.".localized)
    ]

    /// The AI-key step is the last one, and the only one that ends in a
    /// choice rather than "다음" — see `finalStepActions`.
    private var isFinalStep: Bool { step == steps.count - 1 }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            let current = steps[step]
            VStack(spacing: 16) {
                Image(systemName: current.systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text(current.title)
                    .font(.title.bold())
                Text(current.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            if isFinalStep {
                finalStepActions
            } else {
                Button("다음".localized) { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 40)
            }
        }
        .padding()
    }

    /// Two ways out, not one — the AI key is genuinely optional (sharing a
    /// place in from a map app needs nothing), and sending everyone to a
    /// settings screen to paste an API key before they have seen a single
    /// screen of the app is how a first run gets abandoned. "나중에" is
    /// the plain-text option so it reads as a real choice rather than a
    /// thing to feel bad about.
    @ViewBuilder
    private var finalStepActions: some View {
        VStack(spacing: 12) {
            Button("지금 설정하기".localized) {
                pendingOpenAIKeySetup = true
                hasCompletedOnboarding = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("나중에".localized) {
                pendingOpenAIKeySetup = false
                hasCompletedOnboarding = true
            }
            .controlSize(.large)

            Text("나중에 설정 탭에서 언제든 등록할 수 있습니다.".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 40)
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
