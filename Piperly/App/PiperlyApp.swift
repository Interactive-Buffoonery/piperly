import SwiftUI

@main
struct PiperlyApp: App {
    @StateObject private var bookStore = BookStore()
    private let ttsEngine = TTSEngine()
    @AppStorage("hasCompletedVoiceSetup") private var hasCompletedVoiceSetup = false
    @State private var showVoiceSetup = false

    var body: some Scene {
        WindowGroup {
            ContentView(ttsEngine: ttsEngine)
                .environmentObject(bookStore)
                .task {
                    await bookStore.importSampleBooksIfNeeded()
                }
                .onAppear {
                    if !hasCompletedVoiceSetup {
                        showVoiceSetup = true
                    }
                }
                .sheet(isPresented: $showVoiceSetup) {
                    VoiceSetupSheet(ttsEngine: ttsEngine)
                }
        }
    }
}
