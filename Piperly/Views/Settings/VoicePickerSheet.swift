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
import AVFoundation

struct VoicePickerSheet: View {
    let ttsEngine: TTSEngine

    var body: some View {
        NavigationStack {
            VoicePickerList(ttsEngine: ttsEngine, showsDoneButton: true)
        }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}

struct VoicePickerList: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedVoiceIdentifier") private var selectedVoiceIdentifier: String = ""
    @State private var voices: [Voice] = []

    let ttsEngine: TTSEngine
    let showsDoneButton: Bool

    var body: some View {
        ZStack {
            Piperly.Colors.background.ignoresSafeArea()

            if voices.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "speaker.wave.3")
                        .font(.system(size: 40))
                        .foregroundStyle(Piperly.Colors.textTertiary)
                    Text("No voices available")
                        .font(Piperly.Typography.body)
                        .foregroundStyle(Piperly.Colors.textSecondary)
                    Text("Download Premium or Enhanced voices in the iOS Settings app under Accessibility > Read & Speak or Spoken Content > Voices.")
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
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Piperly.Colors.accent)
                }
            }
        }
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
