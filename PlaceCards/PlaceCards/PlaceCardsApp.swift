import SwiftUI

@main
struct PlaceCardsApp: App {
    @StateObject private var store = PlaceCardStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
