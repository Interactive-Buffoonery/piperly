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
