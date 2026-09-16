import SwiftUI

@main
struct PlaceCardsApp: App {
    @StateObject private var storageService = StorageService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storageService)
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
