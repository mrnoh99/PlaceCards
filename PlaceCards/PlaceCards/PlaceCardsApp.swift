import SwiftUI

@main
struct PlaceCardsApp: App {
    @StateObject private var storageService = StorageService()
    /// 동기화는 화면 하나의 일이 아니다. 설정의 "지금 맞추기"와 갤러리
    /// 툴바의 단추가 **같은 하나**를 눌러야 한다 — 화면마다 따로 만들면
    /// 진행 상태가 갈라지고, 한쪽이 도는 중에 다른 쪽이 또 시작한다
    /// (`syncNow`의 `isBusy` 빗장은 같은 인스턴스 안에서만 듣는다).
    @StateObject private var cloudSync = CloudSyncService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storageService)
                .environmentObject(cloudSync)
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
