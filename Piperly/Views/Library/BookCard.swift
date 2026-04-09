import SwiftUI

struct BookCard: View {
    let book: Book
    var onDelete: (() -> Void)?
    @State private var showingMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover placeholder
            ZStack(alignment: .topTrailing) {
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

                if onDelete != nil {
                    Button { showingMenu.toggle() } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Piperly.Colors.textSecondary, Piperly.Colors.surface.opacity(0.8))
                    }
                    .padding(6)
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
        .overlay(alignment: .topTrailing) {
            if showingMenu {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        showingMenu = false
                        onDelete?()
                    } label: {
                        Label("Remove Book", systemImage: "trash")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Piperly.Colors.error)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Piperly.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Piperly.Colors.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                .frame(width: 180)
                .padding(.top, 40)
                .padding(.trailing, 4)
                .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.2), value: showingMenu)
        .zIndex(showingMenu ? 1 : 0)
    }
}
