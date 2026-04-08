import SwiftUI

@main
struct PiperlyApp: App {
    @StateObject private var bookStore = BookStore()
    private let ttsEngine = TTSEngine()

    var body: some Scene {
        WindowGroup {
            ContentView(ttsEngine: ttsEngine)
                .environmentObject(bookStore)
                .task {
                    await initializeTTS()
                }
        }
    }

    private func initializeTTS() async {
        // Look for Kokoro model files in the app bundle first,
        // then fall back to Documents directory
        let modelDir: String
        if let bundledDir = Bundle.main.path(forResource: "kokoro-v1.0", ofType: nil) {
            modelDir = bundledDir
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            modelDir = docs.appendingPathComponent("Models/kokoro-v1.0").path
        }

        do {
            try await ttsEngine.initialize(modelDir: modelDir)
        } catch {
            print("TTS initialization failed: \(error). Word tap will show text only.")
        }
    }
}
