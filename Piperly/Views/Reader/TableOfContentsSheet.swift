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

struct TableOfContentsSheet: View {
    let publication: Publication
    let navigator: EPUBNavigatorViewController?
    let currentLocator: Locator?
    @Environment(\.dismiss) private var dismiss

    private var flatItems: [TOCItem] {
        var items: [TOCItem] = []
        func flatten(_ links: [ReadiumShared.Link], depth: Int, counter: inout Int) {
            for link in links {
                counter += 1
                items.append(TOCItem(link: link, index: counter, depth: depth))
                flatten(link.children, depth: depth + 1, counter: &counter)
            }
        }
        var counter = 0
        flatten(publication.manifest.tableOfContents, depth: 0, counter: &counter)
        return items
    }

    var body: some View {
        NavigationStack {
            Group {
                let items = flatItems
                if items.isEmpty {
                    emptyState
                } else {
                    tocList(items)
                }
            }
            .navigationTitle("Contents")
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
            Image(systemName: "text.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(Piperly.Colors.textTertiary)
            Text("No table of contents")
                .font(Piperly.Typography.body)
                .foregroundStyle(Piperly.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tocList(_ items: [TOCItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    tocRow(item)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func tocRow(_ item: TOCItem) -> some View {
        let isCurrent = isCurrentChapter(item.link)

        return Button {
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                await navigator?.go(to: item.link)
            }
        } label: {
            HStack(spacing: 12) {
                if item.depth > 0 {
                    Rectangle()
                        .fill(Piperly.Colors.accent.opacity(0.3))
                        .frame(width: 3)
                        .padding(.leading, CGFloat(item.depth - 1) * 20)
                }

                Text("\(item.index)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(isCurrent ? Piperly.Colors.accent : Piperly.Colors.textTertiary)
                    .frame(width: 28)

                Text(item.link.title ?? "Untitled")
                    .font(Piperly.Typography.body)
                    .foregroundStyle(isCurrent ? Piperly.Colors.accent : Piperly.Colors.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isCurrent {
                    Image(systemName: "book.fill")
                        .font(.caption)
                        .foregroundStyle(Piperly.Colors.accent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(isCurrent ? Piperly.Colors.accent.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func isCurrentChapter(_ link: ReadiumShared.Link) -> Bool {
        guard let locatorHref = currentLocator?.href else { return false }
        return locatorHref.string.contains(link.url().string)
    }
}

private struct TOCItem: Identifiable {
    let id = UUID()
    let link: ReadiumShared.Link
    let index: Int
    let depth: Int
}
