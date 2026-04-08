import SwiftUI

struct ReaderToolbar: View {
    let title: String
    let onBack: () -> Void
    let onVoice: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Piperly.Colors.accent)
            }

            Spacer()

            Text(title)
                .font(Piperly.Typography.caption)
                .foregroundStyle(Piperly.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            Button(action: onVoice) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(Piperly.Colors.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Piperly.Colors.surface.opacity(0.95))
    }
}
