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

struct VoiceSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedVoiceSetup") private var hasCompletedVoiceSetup = false
    @AppStorage("selectedVoiceIdentifier") private var selectedVoiceIdentifier: String = ""
    @State private var voices: [Voice] = []

    let ttsEngine: TTSEngine

    private var hasHighQualityVoices: Bool {
        voices.contains { $0.quality == .premium || $0.quality == .enhanced }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Piperly.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Piperly.Colors.accent)
                            .padding(.top, 4)

                        Text("Pick a Voice")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Piperly.Colors.textPrimary)

                        Text("Tap a voice to hear it. Then choose your favorite to read words aloud.")
                            .font(Piperly.Typography.body)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        LazyVStack(spacing: 10) {
                            ForEach(voices) { voice in
                                VoiceRow(
                                    voice: voice,
                                    isSelected: voice.id == selectedVoiceIdentifier,
                                    onTap: {
                                        selectedVoiceIdentifier = voice.id
                                        ttsEngine.speak(
                                            word: previewPhrase,
                                            voiceIdentifier: voice.id,
                                            rate: 0.45
                                        )
                                    }
                                )
                            }
                        }

                        if !hasHighQualityVoices {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Want better voices?", systemImage: "sparkles")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Piperly.Colors.textPrimary)
                                Text(voiceSettingsPath)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Piperly.Colors.accent)
                                Text("Download a Premium or Enhanced voice, then tap Refresh.")
                                    .font(Piperly.Typography.caption)
                                    .foregroundStyle(Piperly.Colors.textTertiary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Piperly.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 12) {
                        Button {
                            refreshVoices()
                        } label: {
                            Label("Refresh Voices", systemImage: "arrow.clockwise")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Piperly.Colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            if let first = voices.first, selectedVoiceIdentifier.isEmpty {
                                selectedVoiceIdentifier = first.id
                            }
                            ttsEngine.stop()
                            hasCompletedVoiceSetup = true
                            dismiss()
                        } label: {
                            Text("Continue")
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(Piperly.Colors.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Piperly.Colors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(Piperly.Colors.background.opacity(0.96))
                }
            }
            .navigationTitle("Set Up Voices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Piperly.Colors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
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

    private let previewPhrase = "Hello. Welcome to Piperly."

    private func refreshVoices() {
        voices = Voice.availableVoices()
        if !voices.contains(where: { $0.id == selectedVoiceIdentifier }),
           let first = voices.first {
            selectedVoiceIdentifier = first.id
        }
    }

    private var voiceSettingsPath: String {
        if #available(iOS 26, *) {
            return "Settings  >  Accessibility  >  Read & Speak  >  Voices  >  English"
        } else {
            return "Settings  >  Accessibility  >  Spoken Content  >  Voices  >  English"
        }
    }
}

private struct VoiceRow: View {
    let voice: Voice
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Circle()
                    .fill(voice.color)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name)
                        .font(Piperly.Typography.body)
                        .foregroundStyle(Piperly.Colors.textPrimary)
                    Text(voice.quality.rawValue)
                        .font(Piperly.Typography.caption)
                        .foregroundStyle(Piperly.Colors.textTertiary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(isSelected
                        ? AnyShapeStyle(Piperly.Colors.accent)
                        : AnyShapeStyle(Piperly.Colors.textTertiary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Piperly.Colors.surfaceElevated : Piperly.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Piperly.Colors.accent, lineWidth: isSelected ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(voice.name), \(voice.quality.rawValue) voice")
        .accessibilityHint("Tap to hear this voice and choose it")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
