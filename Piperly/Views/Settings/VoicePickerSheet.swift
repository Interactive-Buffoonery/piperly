import SwiftUI
import AVFoundation

struct VoicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedVoiceIdentifier") private var selectedVoiceIdentifier: String = ""
    @State private var voices: [Voice] = []

    let ttsEngine: TTSEngine

    var body: some View {
        NavigationStack {
            ZStack {
                Piperly.Colors.background.ignoresSafeArea()

                if voices.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "speaker.wave.3")
                            .font(.system(size: 40))
                            .foregroundStyle(Piperly.Colors.textTertiary)
                        Text("No enhanced voices found")
                            .font(Piperly.Typography.body)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                        Text("Download Premium or Enhanced voices in\nSettings > Accessibility > Spoken Content > Voices")
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(voices) { voice in
                                VoiceCard(
                                    voice: voice,
                                    isSelected: voice.id == selectedVoiceIdentifier,
                                    onSelect: { selectedVoiceIdentifier = voice.id },
                                    onPreview: {
                                        ttsEngine.speak(
                                            word: "Hi, I'm \(voice.name)!",
                                            voiceIdentifier: voice.id,
                                            rate: 0.45
                                        )
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Voices")
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
        .onAppear {
            refreshVoices()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVSpeechSynthesizer.availableVoicesDidChangeNotification
            )
        ) { _ in
            refreshVoices()
        }
    }

    private func refreshVoices() {
        voices = Voice.availableVoices()
        if !voices.contains(where: { $0.id == selectedVoiceIdentifier }),
           let first = voices.first {
            selectedVoiceIdentifier = first.id
        }
    }
}

private struct VoiceCard: View {
    let voice: Voice
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(voice.color)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(voice.name.prefix(1)))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(Piperly.Typography.body)
                    .foregroundStyle(Piperly.Colors.textPrimary)
                Text("\(voice.language) \u{2022} \(voice.quality.rawValue)")
                    .font(Piperly.Typography.caption)
                    .foregroundStyle(Piperly.Colors.textTertiary)
            }

            Spacer()

            Button(action: onPreview) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Piperly.Colors.accent.opacity(0.7))
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Piperly.Colors.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? Piperly.Colors.surfaceElevated : Piperly.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
