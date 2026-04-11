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
                    VStack(spacing: 24) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Piperly.Colors.accent)
                            .padding(.top, 8)

                        Text("Set Up Voices")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Piperly.Colors.textPrimary)

                        // swiftlint:disable:next line_length
                        Text("Piperly uses high-quality on-device voices to read words aloud. For the best experience, download Premium or Enhanced voices.")
                            .font(Piperly.Typography.body)
                            .foregroundStyle(Piperly.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("How to download:")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Piperly.Colors.textPrimary)
                            Text(voiceSettingsPath)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(Piperly.Colors.accent)
                            Text("Tap a voice, then tap download for Premium or Enhanced quality.")
                                .font(Piperly.Typography.caption)
                                .foregroundStyle(Piperly.Colors.textTertiary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Piperly.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: hasHighQualityVoices
                                    ? "checkmark.circle.fill" : "info.circle.fill")
                                    .foregroundStyle(hasHighQualityVoices
                                        ? Piperly.Colors.success : Piperly.Colors.warning)
                                Text(hasHighQualityVoices
                                    ? "\(voices.count) voice\(voices.count == 1 ? "" : "s") available"
                                    : "Using built-in voices (download Premium for better quality)")
                                    .font(Piperly.Typography.body)
                                    .foregroundStyle(Piperly.Colors.textPrimary)
                            }

                            ForEach(voices.prefix(5)) { voice in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(voice.color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Text(String(voice.name.prefix(1)))
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                        )
                                    Text(voice.name)
                                        .font(Piperly.Typography.body)
                                        .foregroundStyle(Piperly.Colors.textPrimary)
                                    Spacer()
                                    Text(voice.quality.rawValue)
                                        .font(Piperly.Typography.caption)
                                        .foregroundStyle(Piperly.Colors.textTertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Piperly.Colors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 8)

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
                        .padding(.horizontal, 16)

                        Button {
                            if let first = voices.first, selectedVoiceIdentifier.isEmpty {
                                selectedVoiceIdentifier = first.id
                            }
                            hasCompletedVoiceSetup = true
                            dismiss()
                        } label: {
                            Text("Continue")
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(Piperly.Colors.accent)
                        }
                        .padding(.bottom, 24)
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Piperly.Colors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
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

    private func refreshVoices() {
        voices = Voice.availableVoices()
    }

    private var voiceSettingsPath: String {
        if #available(iOS 26, *) {
            return "Settings  >  Accessibility  >  Read & Speak  >  Voices  >  English"
        } else {
            return "Settings  >  Accessibility  >  Spoken Content  >  Voices  >  English"
        }
    }
}
