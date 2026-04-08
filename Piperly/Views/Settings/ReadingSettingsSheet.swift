import SwiftUI

struct ReadingSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readerFontSize") private var fontSize: Double = 22
    @AppStorage("readerUseSerif") private var useSerif: Bool = false
    @AppStorage("speechRate") private var speechRate: Double = 0.45

    var body: some View {
        NavigationStack {
            ZStack {
                Piperly.Colors.background.ignoresSafeArea()

                VStack(spacing: 32) {
                    // Font size
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Font Size")
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                        HStack {
                            Text("A")
                                .font(.system(size: 14))
                                .foregroundStyle(Piperly.Colors.textTertiary)
                            Slider(value: $fontSize, in: 18...30, step: 1)
                                .tint(Piperly.Colors.accent)
                            Text("A")
                                .font(.system(size: 24))
                                .foregroundStyle(Piperly.Colors.textPrimary)
                        }
                    }

                    // Font style
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Font Style")
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                        Picker("Font", selection: $useSerif) {
                            Text("Sans-serif").tag(false)
                            Text("Serif").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }

                    // TTS Speed
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Voice Speed")
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                        HStack {
                            Image(systemName: "tortoise")
                                .foregroundStyle(Piperly.Colors.textTertiary)
                            Slider(value: $speechRate, in: 0.30...0.60, step: 0.05)
                                .tint(Piperly.Colors.accent)
                            Image(systemName: "hare")
                                .foregroundStyle(Piperly.Colors.textPrimary)
                        }
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Piperly.Colors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Piperly.Colors.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
