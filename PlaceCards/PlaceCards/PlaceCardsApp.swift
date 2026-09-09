import SwiftUI

@main
struct PlaceCardsApp: App {
    @StateObject private var storageService = StorageService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storageService)
        }
    }
}
