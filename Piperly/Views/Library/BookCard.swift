import SwiftUI

struct BookCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Piperly.Colors.surfaceElevated)
                .aspectRatio(0.65, contentMode: .fit)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 36))
                            .foregroundStyle(Piperly.Colors.textTertiary)
                        Text(book.title)
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                    }
                }

            // Title
            Text(book.title)
                .font(Piperly.Typography.caption)
                .foregroundStyle(Piperly.Colors.textPrimary)
                .lineLimit(1)

            // Author
            Text(book.author)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Piperly.Colors.textSecondary)
                .lineLimit(1)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Piperly.Colors.border)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Piperly.Colors.accent)
                        .frame(width: geo.size.width * book.lastReadProgression, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .background(Piperly.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Piperly.Colors.border, lineWidth: 1)
        )
    }
}
