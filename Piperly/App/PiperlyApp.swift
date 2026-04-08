import SwiftUI

@main
struct PiperlyApp: App {
    @StateObject private var bookStore = BookStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bookStore)
        }
    }
}
