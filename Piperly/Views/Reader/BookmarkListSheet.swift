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

struct BookmarkListSheet: View {
    @EnvironmentObject var bookStore: BookStore
    let bookID: UUID
    let navigator: EPUBNavigatorViewController?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                let items = bookStore.bookmarks(for: bookID)
                if items.isEmpty {
                    emptyState
                } else {
                    bookmarkList(items)
                }
            }
            .navigationTitle("Bookmarks")
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundStyle(Piperly.Colors.textTertiary)
            Text("No bookmarks yet")
                .font(Piperly.Typography.body)
                .foregroundStyle(Piperly.Colors.textSecondary)
            Text("Tap the bookmark icon to save your favorite pages")
                .font(Piperly.Typography.caption)
                .foregroundStyle(Piperly.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bookmarkList(_ items: [Bookmark]) -> some View {
        List {
            ForEach(items) { bookmark in
                Button {
                    navigateTo(bookmark)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: bookmark.sticker.symbol)
                            .font(.title3)
                            .foregroundStyle(bookmark.sticker.color)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.title ?? "Page at \(Int(bookmark.progression * 100))%")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(Piperly.Colors.textPrimary)
                            HStack(spacing: 8) {
                                Text("\(Int(bookmark.progression * 100))% through")
                                    .font(Piperly.Typography.caption)
                                    .foregroundStyle(Piperly.Colors.textTertiary)
                                Text(bookmark.createdAt, style: .relative)
                                    .font(Piperly.Typography.caption)
                                    .foregroundStyle(Piperly.Colors.textTertiary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Piperly.Colors.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Piperly.Colors.surface)
            }
            .onDelete { offsets in
                let items = bookStore.bookmarks(for: bookID)
                for offset in offsets {
                    bookStore.removeBookmark(items[offset].id)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func navigateTo(_ bookmark: Bookmark) {
        guard let locator = try? Locator(jsonString: bookmark.locatorJSON) else { return }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            await navigator?.go(to: locator)
        }
    }
}
