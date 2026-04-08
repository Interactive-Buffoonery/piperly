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
                            Text(bookmark.title ?? "Untitled")
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
        Task {
            await navigator?.go(to: locator)
        }
        dismiss()
    }
}
