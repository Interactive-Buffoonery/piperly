import SwiftUI
import ReadiumShared
import ReadiumNavigator

struct ReaderView: View {
    @EnvironmentObject var bookStore: BookStore
    @Environment(\.dismiss) private var dismiss

    let book: Book
    let ttsEngine: TTSEngine

    @State private var publication: Publication?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingVoicePicker = false
    @State private var tappedWord: String?
    @State private var showWordBubble = false
    @AppStorage("selectedVoiceID") private var selectedVoiceID: Int = 3
    @AppStorage("ttsSpeed") private var ttsSpeed: Double = 0.9
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

            // Word tap bubble overlay
            if showWordBubble, let word = tappedWord {
                VStack {
                    Spacer()
                    Text(word)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Piperly.Colors.textPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Piperly.Colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Piperly.Colors.accent.opacity(0.5), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                        .transition(.scale.combined(with: .opacity))
                        .padding(.bottom, 40)
                }
                .animation(.spring(duration: 0.3), value: showWordBubble)
            }
        }
        .task {
            await loadPublication()
        }
        .onAppear {
            wordTapCoordinator.onWordTapped = { word in
                tappedWord = word
                showWordBubble = true

                Task {
                    try? await ttsEngine.speak(
                        word: word,
                        voiceID: selectedVoiceID,
                        speed: Float(ttsSpeed)
                    )
                }

                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    showWordBubble = false
                }
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
