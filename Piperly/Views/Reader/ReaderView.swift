// Piperly - iPad ebook reader for kids
// Copyright (C) 2026 Interactive Buffoonery
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

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
    @State private var showingStickerPicker = false
    @State private var showingBookmarks = false
    @State private var showingTOC = false
    @State private var showingSettings = false
    @State private var tappedWord: String?
    @State private var showWordBubble = false
    @State private var isNewWord = false
    @State private var showingWordList = false
    @AppStorage("selectedVoiceIdentifier") private var selectedVoiceIdentifier: String = ""
    @AppStorage("speechRate") private var speechRate: Double = 0.45
    @AppStorage("readerFontSize") private var fontSize: Double = 22
    @AppStorage("readerTheme") private var selectedTheme: String = ReaderTheme.piperly.rawValue
    @StateObject private var wordTapCoordinator = WordTapCoordinator()
    @State private var navigator: EPUBNavigatorViewController?
    @State private var currentLocator: Locator?

    var body: some View {
        ZStack {
            Piperly.Colors.background.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(Piperly.Colors.accent)
            } else if let publication {
                VStack(spacing: 0) {
                    ReaderToolbar(
                        title: currentLocator?.title ?? book.title,
                        isBookmarked: isCurrentPageBookmarked,
                        onBack: { dismiss() },
                        onBookmarkToggle: { toggleBookmark() },
                        onBookmarkList: { showingBookmarks = true },
                        onTableOfContents: { showingTOC = true },
                        onWordList: { showingWordList = true },
                        onSettings: { showingSettings = true },
                        onVoice: { showingVoicePicker = true }
                    )

                    ReaderNavigator(
                        publication: publication,
                        initialLocator: restoredLocator,
                        wordTapCoordinator: wordTapCoordinator,
                        preferences: readerPreferences,
                        readerTheme: theme,
                        onProgressChanged: { progress in
                            bookStore.updateProgress(for: book.id, progression: progress)
                        },
                        onNavigatorReady: { nav in
                            navigator = nav
                        },
                        onLocationChanged: { locator in
                            currentLocator = locator
                            if let json = locator.jsonString {
                                bookStore.updateLocator(for: book.id, locatorJSON: json)
                            }
                        },
                        onCreationFailed: { error in
                            self.publication = nil
                            errorMessage = "Could not open book: \(error.localizedDescription)"
                        }
                    )

                    // Progress bar
                    HStack(spacing: 8) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Piperly.Colors.border)
                                Rectangle()
                                    .fill(Piperly.Colors.accent)
                                    .frame(width: geometry.size.width * currentProgression)
                            }
                        }
                        .frame(height: 4)
                        .clipShape(Capsule())

                        Text("\(Int(currentProgression * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Piperly.Colors.textTertiary)
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(Piperly.Colors.surface.opacity(0.95))
                }
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(Piperly.Colors.error)
                    Text(errorMessage)
                        .font(Piperly.Typography.body)
                        .foregroundStyle(Piperly.Colors.textSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task { await loadPublication() }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .font(Piperly.Typography.body)
                            .foregroundStyle(Piperly.Colors.accent)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Piperly.Colors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button("Go Back") { dismiss() }
                        .font(Piperly.Typography.body)
                        .foregroundStyle(Piperly.Colors.textTertiary)
                }
                .padding()
            }

            // Sticker picker overlay
            if showingStickerPicker {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showingStickerPicker = false }

                VStack {
                    StickerPicker { sticker in
                        addBookmark(sticker: sticker)
                        showingStickerPicker = false
                    }
                    .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.spring(duration: 0.25), value: showingStickerPicker)
            }

            // Word tap bubble overlay
            if showWordBubble, let word = tappedWord {
                VStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text(word)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Piperly.Colors.textPrimary)

                        if isNewWord {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13))
                                Text("Collected!")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Piperly.Colors.accent)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Piperly.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isNewWord ? Piperly.Colors.accent : Piperly.Colors.accent.opacity(0.5), lineWidth: isNewWord ? 2 : 1)
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
        .onChange(of: wordTapCoordinator.lastTap) { _, tap in
            guard let tap else { return }
            handleWordTap(tap.word)
        }
        .sheet(isPresented: $showingVoicePicker) {
            VoicePickerSheet(ttsEngine: ttsEngine)
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarkListSheet(bookID: book.id, navigator: navigator)
        }
        .sheet(isPresented: $showingTOC) {
            if let publication {
                TableOfContentsSheet(
                    publication: publication,
                    navigator: navigator,
                    currentLocator: currentLocator
                )
            }
        }
        .sheet(isPresented: $showingSettings) {
            ReadingSettingsSheet()
        }
        .sheet(isPresented: $showingWordList) {
            WordListSheet(bookID: book.id, ttsEngine: ttsEngine)
        }
    }

    private var currentProgression: Double {
        currentLocator?.locations.totalProgression ?? book.lastReadProgression
    }

    private var isCurrentPageBookmarked: Bool {
        guard let locator = currentLocator else { return false }
        let progression = locator.locations.totalProgression ?? 0
        return bookStore.isBookmarked(bookID: book.id, progression: progression)
    }

    private func toggleBookmark() {
        guard let locator = currentLocator else { return }
        let progression = locator.locations.totalProgression ?? 0
        if let existing = bookStore.findBookmark(bookID: book.id, progression: progression) {
            bookStore.removeBookmark(existing.id)
        } else {
            showingStickerPicker = true
        }
    }

    private func addBookmark(sticker: BookmarkSticker) {
        guard let locator = currentLocator,
              let json = locator.jsonString else { return }
        let progression = locator.locations.totalProgression ?? 0
        bookStore.addBookmark(
            for: book.id,
            locatorJSON: json,
            title: locator.title,
            progression: progression,
            sticker: sticker
        )
    }

    private var theme: ReaderTheme {
        ReaderTheme(rawValue: selectedTheme) ?? .piperly
    }

    private var readerPreferences: EPUBPreferences {
        theme.epubPreferences(fontSize: fontSize)
    }

    private var restoredLocator: Locator? {
        guard let json = book.lastReadLocatorJSON else { return nil }
        return try? Locator(jsonString: json)
    }

    private func handleWordTap(_ word: String) {
        let newWord = bookStore.saveWordReturningIsNew(word, bookID: book.id, bookTitle: book.title)
        tappedWord = word
        isNewWord = newWord
        showWordBubble = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(newWord ? 1.8 : 1.5))
            showWordBubble = false
        }
        ttsEngine.speak(
            word: word,
            voiceIdentifier: selectedVoiceIdentifier,
            rate: Float(speechRate)
        )
    }

    private func loadPublication() async {
        errorMessage = nil
        isLoading = true

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
