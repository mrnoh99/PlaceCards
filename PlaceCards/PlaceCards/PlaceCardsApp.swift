import SwiftUI

@main
struct PlaceCardsApp: App {
    @StateObject private var storageService = StorageService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storageService)
                // Lightroom을 본뜨는 개편이라 화면은 항상 어둡다. 기기
                // 설정을 따라가면 밝은 모드에서 `Theme`의 검정 배경 위에
                // 시스템 기본 검정 글씨가 얹혀 글자가 사라진다.
                .preferredColorScheme(.dark)
        }
        // Saves are written on a background actor now
        // (`StorageService.persistNow()`'s own comment explains why), which
        // leaves one gap the old synchronous write didn't have: a queued
        // write may not get to run before the process is suspended. Leaving
        // the foreground is exactly when that happens, so the current state
        // is written straight through here.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { storageService.persistNow() }
        }
    }
}
