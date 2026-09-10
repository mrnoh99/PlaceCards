import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var step = 0

    private let steps: [(systemImage: String, title: String, description: String)] = [
        ("mappin.and.ellipse", "PlaceCards",
         "지도 앱, SNS, 직접 찍은 사진에서 발견한 장소를 하나의 카드로 모아보세요.".localized),
        ("photo.on.rectangle.angled", "사진으로 바로 추가".localized,
         "스크린샷이나 사진을 넣으면 AI가 장소명을 찾아주고, Google 지도 정보로 자동 보강됩니다.".localized),
        ("key", "API 키는 내 것만".localized,
         "Google, Claude/ChatGPT/Gemini API 키를 설정에서 등록하세요. 키는 이 기기의 키체인에만 저장됩니다.".localized)
    ]

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

            Button(step < steps.count - 1 ? "다음".localized : "시작하기".localized) {
                if step < steps.count - 1 {
                    step += 1
                } else {
                    hasCompletedOnboarding = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 40)
        }
        .padding()
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
