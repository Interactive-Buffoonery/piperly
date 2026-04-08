import SwiftUI

struct VoicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedVoiceID") private var selectedVoiceID: Int = 3

    var body: some View {
        NavigationStack {
            ZStack {
                Piperly.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Voice.curated) { voice in
                            VoiceCard(
                                voice: voice,
                                isSelected: voice.id == selectedVoiceID,
                                onSelect: { selectedVoiceID = voice.id }
                            )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Choose Voice")
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct VoiceCard: View {
    let voice: Voice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Circle()
                    .fill(voice.color)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(String(voice.name.prefix(1)))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(voice.name)
                        .font(Piperly.Typography.body)
                        .foregroundStyle(Piperly.Colors.textPrimary)
                    Text("\(voice.language) \(voice.gender == .female ? "Female" : "Male")")
                        .font(Piperly.Typography.caption)
                        .foregroundStyle(Piperly.Colors.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Piperly.Colors.accent)
                }
            }
            .padding(16)
            .background(isSelected ? Piperly.Colors.surfaceElevated : Piperly.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Piperly.Colors.accent : Piperly.Colors.border, lineWidth: 1)
            )
        }
    }
}
