import SwiftUI
import ReadiumShared
import ReadiumNavigator

struct ReaderView: View {
    @EnvironmentObject var bookStore: BookStore
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var publication: Publication?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingVoicePicker = false
    @State private var tappedWord: String?
    @StateObject private var wordTapCoordinator = WordTapCoordinator()

    var body: some View {
        ZStack {
            Piperly.Colors.background.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(Piperly.Colors.accent)
            } else if let publication {
                VStack(spacing: 0) {
                    ReaderToolbar(
                        title: book.title,
                        onBack: { dismiss() },
                        onVoice: { showingVoicePicker = true }
                    )

                    ReaderNavigator(
                        publication: publication,
                        initialLocator: nil,
                        wordTapCoordinator: wordTapCoordinator,
                        onProgressChanged: { progress in
                            bookStore.updateProgress(for: book.id, progression: progress)
                        }
                    )
                }
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(Piperly.Colors.error)
                    Text(errorMessage)
                        .font(Piperly.Typography.body)
                        .foregroundStyle(Piperly.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .task {
            await loadPublication()
        }
        .onAppear {
            wordTapCoordinator.onWordTapped = { word in
                tappedWord = word
            }
        }
        .sheet(isPresented: $showingVoicePicker) {
            VoicePickerSheet()
        }
    }

    private func loadPublication() async {
        let url = bookStore.bookURL(for: book)

        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Book file not found."
            isLoading = false
            return
        }

        do {
            publication = try await bookStore.openPublication(at: url)
        } catch {
            errorMessage = "Could not open book: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
