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

struct ReaderToolbar: View {
    let title: String
    let isBookmarked: Bool
    let onBack: () -> Void
    let onBookmarkToggle: () -> Void
    let onBookmarkList: () -> Void
    let onTableOfContents: () -> Void
    let onWordList: () -> Void
    let onSettings: () -> Void
    let onVoice: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Piperly.Colors.accent)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())

            Button(action: onBookmarkToggle) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.title3)
                    .foregroundStyle(isBookmarked ? Piperly.Colors.warning : Piperly.Colors.accent)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Add bookmark")

            Button(action: onBookmarkList) {
                Image(systemName: "bookmark.square")
                    .font(.title3)
                    .foregroundStyle(Piperly.Colors.accent)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("View bookmarks")

            Button(action: onTableOfContents) {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(Piperly.Colors.accent)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())

            Button(action: onWordList) {
                Image(systemName: "character.book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(Piperly.Colors.accent)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())

            Spacer()

            Text(title)
                .font(Piperly.Typography.caption)
                .foregroundStyle(Piperly.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Piperly.Colors.accent)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())

            Button(action: onVoice) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(Piperly.Colors.accent)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Piperly.Colors.surface.opacity(0.95))
    }
}
