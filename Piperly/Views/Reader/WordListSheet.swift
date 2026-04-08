import SwiftUI

struct WordListSheet: View {
    @EnvironmentObject var bookStore: BookStore
    let bookID: UUID
    let ttsEngine: TTSEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedVoiceIdentifier") private var selectedVoiceIdentifier: String = ""
    @AppStorage("speechRate") private var speechRate: Double = 0.45

    private var words: [SavedWord] {
        bookStore.words(for: bookID)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Piperly.Colors.background.ignoresSafeArea()

                if words.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "character.book.closed")
                            .font(.system(size: 48))
                            .foregroundStyle(Piperly.Colors.textTertiary)
                        Text("No words collected yet")
                            .font(Piperly.Typography.title)
                            .foregroundStyle(Piperly.Colors.textPrimary)
                        Text("Tap any word to hear it and add it here!")
                            .font(Piperly.Typography.body)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                    }
                } else {
                    List {
                        ForEach(words) { word in
                            Button {
                                ttsEngine.speak(
                                    word: word.displayWord,
                                    voiceIdentifier: selectedVoiceIdentifier,
                                    rate: Float(speechRate)
                                )
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(word.displayWord)
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundStyle(Piperly.Colors.textPrimary)
                                        if word.tapCount > 1 {
                                            Text("tapped \(word.tapCount)x")
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundStyle(Piperly.Colors.textTertiary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "speaker.wave.2")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Piperly.Colors.accent)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Piperly.Colors.surface)
                        }
                        .onDelete { indexSet in
                            let wordsToDelete = indexSet.map { words[$0] }
                            for word in wordsToDelete {
                                bookStore.removeWord(word.id)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("My Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Piperly.Colors.accent)
                }
            }
            .toolbarBackground(Piperly.Colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Piperly.Colors.background)
    }
}
