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

struct WordChip: View {
    let savedWord: SavedWord
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(savedWord.displayWord)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textPrimary)

                Text(savedWord.bookTitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Piperly.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Piperly.Colors.border, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if savedWord.tapCount > 1 {
                    Text("\(savedWord.tapCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Piperly.Colors.background)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Piperly.Colors.accent)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("I know this one!", systemImage: "checkmark.circle")
            }
        }
    }
}
