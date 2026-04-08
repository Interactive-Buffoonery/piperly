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
                        .foregroundStyle(.white)
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
