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
            .onLongPressGesture {
                onBookmarkList()
            }

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
