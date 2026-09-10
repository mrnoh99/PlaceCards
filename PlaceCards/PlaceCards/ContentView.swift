import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @ObservedObject private var localization = LocalizationObserver.shared

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
        // Changing the app language (Settings → "앱 언어") has no other
        // hook into already-rendered `"...".localized` text — remounting
        // everything below here on a language change is what makes it
        // take effect immediately instead of needing a relaunch.
        .id(localization.language)
    }
}

#Preview {
    ContentView()
        .environmentObject(StorageService())
}
