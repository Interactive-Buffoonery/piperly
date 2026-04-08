import SwiftUI

@main
struct PiperlyApp: App {
    @StateObject private var bookStore = BookStore()
    @StateObject private var pinManager = PINManager()
    @StateObject private var opdsService = OPDSService()
    private let ttsEngine = TTSEngine()
    @AppStorage("hasCompletedVoiceSetup") private var hasCompletedVoiceSetup = false
    @State private var showVoiceSetup = false

    var body: some Scene {
        WindowGroup {
            ContentView(ttsEngine: ttsEngine)
                .environmentObject(bookStore)
                .environmentObject(pinManager)
                .environmentObject(opdsService)
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
