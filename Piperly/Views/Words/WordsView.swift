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

struct WordsView: View {
    @EnvironmentObject var bookStore: BookStore
    let ttsEngine: TTSEngine
    @State private var viewMode: ViewMode = .all

    enum ViewMode: String, CaseIterable {
        case all = "All Words"
        case byBook = "By Book"
    }

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)
    ]

    var body: some View {
        ZStack {
            Piperly.Colors.background.ignoresSafeArea()

            if activeWords.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    statsHeader
                    ScrollView {
                        switch viewMode {
                        case .all:
                            allWordsGrid
                        case .byBook:
                            byBookSections
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(Piperly.Colors.textTertiary)
            Text("No words yet")
                .font(Piperly.Typography.title)
                .foregroundStyle(Piperly.Colors.textPrimary)
            Text("Tap any word while reading to start collecting!")
                .font(Piperly.Typography.body)
                .foregroundStyle(Piperly.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var statsHeader: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Piperly.Colors.accent)
                    Text("\(activeWords.count) words collected")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Piperly.Colors.textPrimary)
                }
                Spacer()
            }

            Picker("", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var allWordsGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(sortedWords) { word in
                WordChip(savedWord: word, onTap: { speakWord(word) }, onRemove: {
                    bookStore.removeWord(word.id)
                })
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var byBookSections: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(groupedByBook, id: \.bookID) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(group.bookTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Piperly.Colors.textSecondary)
                        .padding(.horizontal, 24)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.words) { word in
                            WordChip(savedWord: word, onTap: { speakWord(word) }, onRemove: {
                                bookStore.removeWord(word.id)
                            })
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func speakWord(_ word: SavedWord) {
        ttsEngine.speak(
            word: word.displayWord,
            voiceIdentifier: bookStore.activeVoiceIdentifier,
            rate: Float(bookStore.activeSpeechRate)
        )
    }

    private var sortedWords: [SavedWord] {
        activeWords.sorted { $0.lastTappedAt > $1.lastTappedAt }
    }

    private var groupedByBook: [(bookTitle: String, bookID: UUID, words: [SavedWord])] {
        Dictionary(grouping: activeWords, by: \.bookID)
            .map { bookID, words in
                (bookTitle: words.first?.bookTitle ?? "Unknown",
                 bookID: bookID,
                 words: words.sorted { $0.lastTappedAt > $1.lastTappedAt })
            }
            .sorted { ($0.words.first?.lastTappedAt ?? .distantPast) > ($1.words.first?.lastTappedAt ?? .distantPast) }
    }

    private var activeWords: [SavedWord] {
        bookStore.wordsForActiveProfile
    }
}
