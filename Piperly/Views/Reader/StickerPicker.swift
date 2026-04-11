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

struct StickerPicker: View {
    let onSelect: (BookmarkSticker) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(BookmarkSticker.allCases, id: \.self) { sticker in
                Button {
                    onSelect(sticker)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: sticker.symbol)
                            .font(.title2)
                            .foregroundStyle(sticker.color)
                        Text(sticker.label)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Piperly.Colors.textSecondary)
                    }
                    .frame(minWidth: 56, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Piperly.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Piperly.Colors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}
