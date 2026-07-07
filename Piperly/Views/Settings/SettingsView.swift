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

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("readerFontSize") private var fontSize: Double = 22
    @AppStorage("readerTheme") private var selectedTheme: String = ReaderTheme.piperly.rawValue
    @AppStorage("speechRate") private var speechRate: Double = 0.45
    @AppStorage("selectedVoiceIdentifier") private var selectedVoiceIdentifier: String = ""
    @State private var showingVoicePicker = false
    @State private var voices: [Voice] = []

    let ttsEngine: TTSEngine

    private var theme: ReaderTheme {
        ReaderTheme(rawValue: selectedTheme) ?? .piperly
    }

    private var selectedVoiceName: String {
        if let voice = voices.first(where: { $0.id == selectedVoiceIdentifier }) {
            return voice.name
        }
        return voices.first?.name ?? "Choose Voice"
    }

    var body: some View {
        NavigationStack {
            List {
                readingSection
                voicesSection
            }
            .scrollContentBackground(.hidden)
            .background(Piperly.Colors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Piperly.Colors.accent)
                }
            }
            .toolbarBackground(Piperly.Colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showingVoicePicker, onDismiss: refreshVoices) {
            VoicePickerSheet(ttsEngine: ttsEngine)
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
        .presentationDetents([.large])
        .presentationBackground(Piperly.Colors.background)
    }

    private var readingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Font Size")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                HStack {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                    Slider(value: $fontSize, in: 18...30, step: 1) {
                        Text("Font Size")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .labelsHidden()
                    .tint(Piperly.Colors.accent)
                    Image(systemName: "textformat.size.larger")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 12) {
                Text("Reader Theme")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(ReaderTheme.allCases) { readerTheme in
                            Button {
                                selectedTheme = readerTheme.rawValue
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: readerTheme.backgroundColor))
                                        .frame(width: 52, height: 52)
                                        .overlay {
                                            Text("Aa")
                                                .font(readerTheme.fontFamily == .serif
                                                    ? .system(size: 16, weight: .medium, design: .serif)
                                                    : .system(size: 16, weight: .medium, design: .default))
                                                .foregroundStyle(Color(hex: readerTheme.textColor))
                                        }
                                        .overlay {
                                            Circle()
                                                .stroke(Piperly.Colors.accent, lineWidth: 3)
                                                .opacity(theme == readerTheme ? 1 : 0)
                                        }
                                    Text(readerTheme.displayName)
                                        .font(.system(
                                            size: 11,
                                            weight: theme == readerTheme ? .semibold : .regular,
                                            design: .rounded
                                        ))
                                        .foregroundStyle(theme == readerTheme ? Piperly.Colors.accent : Piperly.Colors.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(readerTheme.displayName)
                            .accessibilityAddTraits(theme == readerTheme ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Reading")
                .foregroundStyle(Piperly.Colors.textSecondary)
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    private var voicesSection: some View {
        Section {
            Button {
                showingVoicePicker = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Piperly.Colors.accent)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Voice")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Piperly.Colors.textPrimary)
                        Text(selectedVoiceName)
                            .font(Piperly.Typography.caption)
                            .foregroundStyle(Piperly.Colors.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Piperly.Colors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice")
            .accessibilityValue(selectedVoiceName)

            VStack(alignment: .leading, spacing: 8) {
                Text("Voice Speed")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Piperly.Colors.textSecondary)
                HStack {
                    Image(systemName: "tortoise")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                    Slider(value: $speechRate, in: 0.30...0.60, step: 0.05) {
                        Text("Voice Speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                    .labelsHidden()
                    .tint(Piperly.Colors.accent)
                    Image(systemName: "hare")
                        .foregroundStyle(Piperly.Colors.textTertiary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Voices")
                .foregroundStyle(Piperly.Colors.textSecondary)
        }
        .listRowBackground(Piperly.Colors.surface)
    }

    private func refreshVoices() {
        voices = Voice.availableVoices()
    }
}
