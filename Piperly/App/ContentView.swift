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

struct ContentView: View {
    @EnvironmentObject var bookStore: BookStore
    @State private var selectedBook: Book?
    @State private var selectedTab: ContentTab = .library
    @State private var showingSettings = false
    @State private var showingImporter = false

    let ttsEngine: TTSEngine

    enum ContentTab: String, CaseIterable {
        case library = "My Books"
        case words = "Words"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom header
                HStack {
                    Text("Piperly")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Piperly.Colors.accent)

                    Spacer()

                    Picker("", selection: $selectedTab) {
                        ForEach(ContentTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .colorScheme(.dark)
                    .frame(width: 340)

                    Spacer()

                    Menu {
                        ForEach(bookStore.profiles) { profile in
                            Button {
                                bookStore.selectProfile(profile.id)
                            } label: {
                                Label(
                                    profile.name,
                                    systemImage: profile.id == bookStore.activeProfile.id ? "checkmark" : profile.avatarSymbol
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Label(bookStore.activeProfile.name, systemImage: bookStore.activeProfile.avatarSymbol)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(Piperly.Colors.accent)
                    .buttonStyle(.bordered)
                    .tint(Piperly.Colors.accent)
                    .accessibilityLabel("Reader Profile")
                    .accessibilityValue(bookStore.activeProfile.name)

                    HStack(spacing: 12) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundStyle(Piperly.Colors.accent)
                        }
                        .accessibilityLabel("Settings")

                        if selectedTab == .library {
                            Button {
                                showingImporter = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Piperly.Colors.accent)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                switch selectedTab {
                case .library:
                    LibraryView(
                        selectedBook: $selectedBook,
                        showingImporter: $showingImporter
                    )
                case .words:
                    WordsView(ttsEngine: ttsEngine)
                }
            }
            .background(Piperly.Colors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $selectedBook) { book in
                ReaderView(book: book, ttsEngine: ttsEngine)
                    .environmentObject(bookStore)
            }
            .fullScreenCover(isPresented: $showingSettings) {
                SettingsView(ttsEngine: ttsEngine)
            }
        }
    }
}
